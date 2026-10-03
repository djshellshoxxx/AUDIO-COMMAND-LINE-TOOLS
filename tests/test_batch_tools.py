import tempfile
import unittest
import wave
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
import batch_audio


def write_wav(path, data, rate=8000):
    x = np.asarray(data, dtype=float)
    if x.ndim == 1:
        x = x[:, None]
    q = np.clip(np.rint(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(q.tobytes())


class BatchAudioTests(unittest.TestCase):
    def test_onsetpack_finds_transient_and_preroll(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "hit.wav"
            x = np.zeros(8000)
            x[2400:2600] = 0.8
            write_wav(p, x)
            r = batch_audio.analyze_onset(p, threshold_db=-20, preroll_ms=25)
            self.assertAlmostEqual(r["onset_seconds"], 0.3, places=3)
            self.assertEqual(r["trim_start_frame"], 2200)

    def test_onsetpack_does_not_modify_source(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            src, out = td / "src", td / "out"
            src.mkdir()
            p = src / "hit.wav"
            x = np.zeros(8000)
            x[2000:] = 0.5
            write_wav(p, x)
            before = p.read_bytes()
            batch_audio.onsetpack(src, out, threshold_db=-20, preroll_ms=10)
            self.assertEqual(p.read_bytes(), before)
            self.assertTrue((out / "hit.wav").exists())

    def test_phasebatch_detects_delay_and_polarity(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            rate = 8000
            base = np.zeros(rate)
            base[1000:1100] = np.hanning(100)
            delayed = np.zeros_like(base)
            delayed[1012:1112] = -base[1000:1100]
            a, b = td / "ref.wav", td / "mic.wav"
            write_wav(a, base, rate)
            write_wav(b, delayed, rate)
            r = batch_audio.compare_phase(a, b, max_shift_ms=5)
            self.assertEqual(r["delay_frames"], 12)
            self.assertTrue(r["polarity_inverted"])
            self.assertLess(r["correlation"], -0.95)

    def test_packdelta_detects_rename_modify_add_remove_and_duplicates(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            old, new = td / "old", td / "new"
            old.mkdir()
            new.mkdir()
            tone = np.sin(2 * np.pi * 440 * np.arange(800) / 8000) * 0.5
            tone2 = np.sin(2 * np.pi * 220 * np.arange(800) / 8000) * 0.5
            write_wav(old / "same.wav", tone)
            write_wav(new / "same.wav", tone)
            write_wav(old / "rename_me.wav", tone2)
            write_wav(new / "renamed.wav", tone2)
            write_wav(old / "removed.wav", tone * 0.2)
            write_wav(new / "added.wav", tone * 0.3)
            write_wav(old / "modified.wav", tone * 0.1)
            write_wav(new / "modified.wav", tone * 0.4)
            write_wav(new / "dup1.wav", tone2)
            r = batch_audio.diff_packs(old, new)
            self.assertIn("same.wav", r["unchanged"])
            self.assertIn({"from": "rename_me.wav", "to": "renamed.wav"}, r["renamed"])
            self.assertIn("modified.wav", r["modified"])
            self.assertIn("removed.wav", r["removed"])
            self.assertIn("added.wav", r["added"])
            self.assertTrue(any(len(g["files"]) >= 2 for g in r["duplicates_new"]))

    def test_edgeguard_detects_and_repairs_hot_edges(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            p, out = td / "edge.wav", td / "fixed.wav"
            x = np.ones(800) * 0.8
            write_wav(p, x)
            r = batch_audio.analyze_edges(p, threshold_db=-30)
            self.assertTrue(r["start_risk"])
            self.assertTrue(r["end_risk"])
            batch_audio.repair_edges(p, out, fade_ms=10)
            y, _ = batch_audio.read_wav(out)
            self.assertLess(abs(y[0, 0]), 0.01)
            self.assertLess(abs(y[-1, 0]), 0.01)
            self.assertGreater(abs(y[len(y) // 2, 0]), 0.7)

    def test_output_refuses_overwrite_by_default(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            p = td / "src.wav"
            out = td / "out.wav"
            write_wav(p, np.ones(100) * 0.2)
            write_wav(out, np.zeros(100))
            with self.assertRaises(FileExistsError):
                batch_audio.repair_edges(p, out, fade_ms=2)

    def test_scan_is_recursive_and_case_insensitive(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            (td / "sub").mkdir()
            write_wav(td / "A.WAV", np.zeros(100))
            write_wav(td / "sub" / "b.wav", np.zeros(100))
            found = batch_audio.scan_wavs(td)
            self.assertEqual([p.name for p in found], ["A.WAV", "b.wav"])


if __name__ == "__main__":
    unittest.main()
