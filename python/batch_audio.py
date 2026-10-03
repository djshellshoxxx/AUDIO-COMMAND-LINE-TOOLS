#!/usr/bin/env python3
"""Circuit Drift Labs batch audio tools (beta)."""
from __future__ import annotations
import argparse, csv, difflib, hashlib, json, math, struct, sys, wave
from pathlib import Path
import numpy as np

AUDIO_EXTS = {".wav"}


def scan_wavs(root: str | Path) -> list[Path]:
    root = Path(root)
    if not root.exists():
        raise ValueError(f"Input does not exist: {root}")
    files = [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in AUDIO_EXTS]
    return sorted(files, key=lambda p: str(p.relative_to(root)).lower())


def read_wav(path: str | Path) -> tuple[np.ndarray, int]:
    path = Path(path)
    with wave.open(str(path), "rb") as w:
        channels = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        frames = w.getnframes()
        comptype = w.getcomptype()
        if comptype != "NONE":
            raise ValueError(f"Compressed WAV unsupported: {path}")
        raw = w.readframes(frames)
    if channels < 1 or channels > 32 or rate < 1 or frames < 1:
        raise ValueError(f"Invalid WAV geometry: {path}")
    if width == 1:
        x = (np.frombuffer(raw, np.uint8).astype(np.float64) - 128.0) / 128.0
    elif width == 2:
        x = np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0
    elif width == 3:
        u = np.frombuffer(raw, np.uint8).reshape(-1, 3).astype(np.int32)
        v = u[:, 0] | (u[:, 1] << 8) | (u[:, 2] << 16)
        v = np.where(v & 0x800000, v - 0x1000000, v)
        x = v.astype(np.float64) / 8388608.0
    elif width == 4:
        x = np.frombuffer(raw, "<i4").astype(np.float64) / 2147483648.0
    else:
        raise ValueError(f"Unsupported PCM width ({width * 8}-bit): {path}")
    if x.size % channels:
        raise ValueError(f"Misaligned WAV frames: {path}")
    x = x.reshape(-1, channels)
    if not np.isfinite(x).all():
        raise ValueError(f"Nonfinite audio: {path}")
    return x, rate


def write_wav(path: str | Path, x: np.ndarray, rate: int, overwrite: bool = False) -> None:
    path = Path(path)
    if path.exists() and not overwrite:
        raise FileExistsError(f"Output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    if not len(x) or not np.isfinite(x).all():
        raise ValueError("Cannot write empty/nonfinite audio")
    q = np.clip(np.rint(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(q.tobytes())


def db_to_amp(db: float) -> float:
    return 10.0 ** (float(db) / 20.0)


def analyze_onset(path: str | Path, threshold_db: float = -30.0, preroll_ms: float = 10.0) -> dict:
    x, rate = read_wav(path)
    env = np.max(np.abs(x), axis=1)
    hits = np.flatnonzero(env >= db_to_amp(threshold_db))
    onset = int(hits[0]) if hits.size else None
    preroll = max(0, int(round(preroll_ms * rate / 1000.0)))
    start = max(0, onset - preroll) if onset is not None else 0
    return {
        "file": str(path), "sample_rate": rate, "frames": len(x),
        "threshold_db": threshold_db, "onset_frame": onset,
        "onset_seconds": None if onset is None else onset / rate,
        "trim_start_frame": start, "trim_start_seconds": start / rate,
        "all_below_threshold": onset is None,
    }


def onsetpack(root: str | Path, output_dir: str | Path | None = None, threshold_db: float = -30.0,
              preroll_ms: float = 10.0, overwrite: bool = False) -> dict:
    root = Path(root)
    files = scan_wavs(root)
    rows = []
    out_root = Path(output_dir) if output_dir else None
    for p in files:
        r = analyze_onset(p, threshold_db, preroll_ms)
        rows.append(r)
        if out_root is not None:
            x, rate = read_wav(p)
            rel = p.relative_to(root)
            write_wav(out_root / rel, x[r["trim_start_frame"]:], rate, overwrite)
    return {"tool": "onsetpack", "beta": True, "root": str(root), "files": rows}


def _mono(x: np.ndarray) -> np.ndarray:
    return np.mean(x, axis=1)


def compare_phase(reference: str | Path, target: str | Path, max_shift_ms: float = 10.0) -> dict:
    a, ra = read_wav(reference)
    b, rb = read_wav(target)
    if ra != rb:
        raise ValueError("Sample rates must match")
    am, bm = _mono(a), _mono(b)
    max_shift = max(0, int(round(max_shift_ms * ra / 1000.0)))
    best = None
    for delay in range(-max_shift, max_shift + 1):
        # Positive delay means target occurs later than reference.
        if delay >= 0:
            count = min(len(am), len(bm) - delay)
            aa, bb = am[:count], bm[delay:delay + count]
        else:
            d = -delay
            count = min(len(am) - d, len(bm))
            aa, bb = am[d:d + count], bm[:count]
        if len(aa) < 2:
            continue
        aa = aa - np.mean(aa)
        bb = bb - np.mean(bb)
        denom = math.sqrt(float(np.dot(aa, aa) * np.dot(bb, bb)))
        corr = float(np.dot(aa, bb) / denom) if denom else 0.0
        score = abs(corr)
        if best is None or score > best[0]:
            best = (score, delay, corr)
    if best is None:
        raise ValueError("Not enough overlap for phase comparison")
    _, delay, corr = best
    return {
        "reference": str(reference), "target": str(target), "sample_rate": ra,
        "delay_frames": int(delay), "delay_ms": delay * 1000.0 / ra,
        "correlation": corr, "polarity_inverted": corr < 0,
    }


def _align_target(x: np.ndarray, delay: int, invert: bool, length: int) -> np.ndarray:
    y = -x if invert else x.copy()
    out = np.zeros((length, y.shape[1]), dtype=np.float64)
    if delay >= 0:
        src_start = delay
        count = min(length, len(y) - src_start)
        if count > 0:
            out[:count] = y[src_start:src_start + count]
    else:
        dst_start = -delay
        count = min(length - dst_start, len(y))
        if count > 0:
            out[dst_start:dst_start + count] = y[:count]
    return out


def phasebatch(root: str | Path, reference: str | Path, output_dir: str | Path | None = None,
               max_shift_ms: float = 10.0, correct: bool = False, overwrite: bool = False) -> dict:
    root = Path(root)
    ref = Path(reference)
    if not ref.is_absolute():
        ref = root / ref
    files = scan_wavs(root)
    if ref not in files:
        raise ValueError("Reference must be a WAV inside the input tree")
    ref_x, ref_rate = read_wav(ref)
    rows = []
    for p in files:
        if p == ref:
            continue
        r = compare_phase(ref, p, max_shift_ms)
        rows.append(r)
        if correct:
            if output_dir is None:
                raise ValueError("--correct requires --output-dir")
            x, rate = read_wav(p)
            if rate != ref_rate:
                raise ValueError("Sample rates must match")
            fixed = _align_target(x, r["delay_frames"], r["polarity_inverted"], len(ref_x))
            write_wav(Path(output_dir) / p.relative_to(root), fixed, rate, overwrite)
    return {"tool": "phasebatch", "beta": True, "reference": str(ref), "comparisons": rows}


def decoded_hash(path: str | Path) -> str:
    x, rate = read_wav(path)
    h = hashlib.sha256()
    h.update(struct.pack("<II", rate, x.shape[1]))
    # Stable decoded identity across container bit-depth differences where samples coincide.
    q = np.rint(np.clip(x, -1, 1) * (2 ** 23 - 1)).astype("<i4")
    h.update(q.tobytes())
    return h.hexdigest()


def _tree_inventory(root: Path) -> dict[str, dict]:
    inv = {}
    for p in scan_wavs(root):
        rel = p.relative_to(root).as_posix()
        x, rate = read_wav(p)
        inv[rel] = {"hash": decoded_hash(p), "frames": len(x), "rate": rate, "channels": x.shape[1]}
    return inv


def _duplicates(inv: dict[str, dict]) -> list[dict]:
    by = {}
    for name, meta in inv.items():
        by.setdefault(meta["hash"], []).append(name)
    return [{"hash": h, "files": sorted(v)} for h, v in sorted(by.items()) if len(v) > 1]


def diff_packs(old_root: str | Path, new_root: str | Path) -> dict:
    old_root, new_root = Path(old_root), Path(new_root)
    old, new = _tree_inventory(old_root), _tree_inventory(new_root)
    unchanged, modified, removed, added = [], [], [], []
    for name in sorted(set(old) | set(new)):
        if name in old and name in new:
            (unchanged if old[name]["hash"] == new[name]["hash"] else modified).append(name)
        elif name in old:
            removed.append(name)
        else:
            added.append(name)
    old_by_hash, new_by_hash = {}, {}
    for n, m in old.items():
        old_by_hash.setdefault(m["hash"], []).append(n)
    for n, m in new.items():
        new_by_hash.setdefault(m["hash"], []).append(n)
    renamed, used_old, used_new = [], set(), set()
    for h in sorted(set(old_by_hash) & set(new_by_hash)):
        os = [n for n in sorted(old_by_hash[h]) if n in removed]
        ns = [n for n in sorted(new_by_hash[h]) if n in added]
        candidates = []
        for a in os:
            for b in ns:
                score = difflib.SequenceMatcher(None, Path(a).stem.lower(), Path(b).stem.lower()).ratio()
                candidates.append((-score, a, b))
        for _, a, b in sorted(candidates):
            if a in used_old or b in used_new:
                continue
            renamed.append({"from": a, "to": b})
            used_old.add(a)
            used_new.add(b)
    removed = [n for n in removed if n not in used_old]
    added = [n for n in added if n not in used_new]
    return {
        "tool": "packdelta", "beta": True, "unchanged": unchanged, "renamed": renamed,
        "modified": modified, "added": added, "removed": removed,
        "duplicates_old": _duplicates(old), "duplicates_new": _duplicates(new),
    }


def analyze_edges(path: str | Path, threshold_db: float = -45.0) -> dict:
    x, rate = read_wav(path)
    threshold = db_to_amp(threshold_db)
    start_peak = float(np.max(np.abs(x[0])))
    end_peak = float(np.max(np.abs(x[-1])))
    start_slope = float(np.max(np.abs(x[min(1, len(x) - 1)] - x[0]))) if len(x) > 1 else 0.0
    end_slope = float(np.max(np.abs(x[-1] - x[-2]))) if len(x) > 1 else 0.0
    return {
        "file": str(path), "sample_rate": rate, "frames": len(x),
        "start_peak": start_peak, "end_peak": end_peak,
        "start_slope": start_slope, "end_slope": end_slope,
        "start_risk": max(start_peak, start_slope) >= threshold,
        "end_risk": max(end_peak, end_slope) >= threshold,
        "threshold_db": threshold_db,
    }


def repair_edges(path: str | Path, output: str | Path, fade_ms: float = 5.0, overwrite: bool = False) -> dict:
    x, rate = read_wav(path)
    y = x.copy()
    n = max(1, int(round(fade_ms * rate / 1000.0)))
    n = min(n, len(y))
    ramp = np.linspace(0.0, 1.0, n, endpoint=True)
    y[:n] *= ramp[:, None]
    y[-n:] *= ramp[::-1, None]
    write_wav(output, y, rate, overwrite)
    return {"input": str(path), "output": str(output), "fade_ms": fade_ms}


def edgeguard(root: str | Path, output_dir: str | Path | None = None, threshold_db: float = -45.0,
              fade_ms: float = 5.0, repair: bool = False, overwrite: bool = False) -> dict:
    root = Path(root)
    rows = []
    for p in scan_wavs(root):
        r = analyze_edges(p, threshold_db)
        rows.append(r)
        if repair and (r["start_risk"] or r["end_risk"]):
            if output_dir is None:
                raise ValueError("--repair requires --output-dir")
            repair_edges(p, Path(output_dir) / p.relative_to(root), fade_ms, overwrite)
    return {"tool": "edgeguard", "beta": True, "root": str(root), "files": rows}


def write_report(report: dict, output: str | Path | None, csv_output: str | Path | None = None) -> None:
    text = json.dumps(report, indent=2, sort_keys=True)
    if output:
        p = Path(output)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text + "\n", encoding="utf-8")
    else:
        print(text)
    if csv_output:
        rows = report.get("files") or report.get("comparisons") or []
        if rows:
            keys = sorted({k for row in rows for k in row.keys()})
            p = Path(csv_output)
            p.parent.mkdir(parents=True, exist_ok=True)
            with p.open("w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=keys)
                w.writeheader()
                w.writerows(rows)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Circuit Drift Labs batch audio tools (BETA)")
    s = p.add_subparsers(dest="tool", required=True)
    q = s.add_parser("onsetpack")
    q.add_argument("root")
    q.add_argument("--output-dir")
    q.add_argument("--threshold-db", type=float, default=-30)
    q.add_argument("--preroll-ms", type=float, default=10)
    q = s.add_parser("phasebatch")
    q.add_argument("root")
    q.add_argument("--reference", required=True)
    q.add_argument("--output-dir")
    q.add_argument("--max-shift-ms", type=float, default=10)
    q.add_argument("--correct", action="store_true")
    q = s.add_parser("packdelta")
    q.add_argument("old_root")
    q.add_argument("new_root")
    q = s.add_parser("edgeguard")
    q.add_argument("root")
    q.add_argument("--output-dir")
    q.add_argument("--threshold-db", type=float, default=-45)
    q.add_argument("--fade-ms", type=float, default=5)
    q.add_argument("--repair", action="store_true")
    for q in s.choices.values():
        q.add_argument("--output")
        q.add_argument("--csv")
        q.add_argument("--overwrite", action="store_true")
    return p


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    try:
        if a.tool == "onsetpack":
            r = onsetpack(a.root, a.output_dir, a.threshold_db, a.preroll_ms, a.overwrite)
        elif a.tool == "phasebatch":
            r = phasebatch(a.root, a.reference, a.output_dir, a.max_shift_ms, a.correct, a.overwrite)
        elif a.tool == "packdelta":
            r = diff_packs(a.old_root, a.new_root)
        else:
            r = edgeguard(a.root, a.output_dir, a.threshold_db, a.fade_ms, a.repair, a.overwrite)
        write_report(r, a.output, a.csv)
        return 0
    except (OSError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


def main_for(tool: str) -> int:
    return main([tool, *sys.argv[1:]])


if __name__ == "__main__":
    raise SystemExit(main())
