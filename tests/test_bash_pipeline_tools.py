import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ["edgeguard", "subphase", "banddrift", "repeataudit", "samplefreeze", "transientledger"]


class BashPipelineToolsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            raise unittest.SkipTest("ffmpeg/ffprobe required")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.p = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_tool(self, name, *args, env=None):
        cmd = ["bash", str(ROOT / "bash" / f"{name}.sh"), *map(str, args)]
        e = os.environ.copy()
        if env:
            e.update(env)
        return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", env=e)

    def ffmpeg(self, *args):
        r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *map(str, args)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def tone(self, path, freq=440, duration=1.0, channels=1, volume=0.5):
        if channels == 1:
            self.ffmpeg("-f", "lavfi", "-i", f"sine=frequency={freq}:sample_rate=48000:duration={duration}", "-filter:a", f"volume={volume}", path)
        else:
            self.ffmpeg("-f", "lavfi", "-i", f"sine=frequency={freq}:sample_rate=48000:duration={duration}", "-filter_complex", f"[0:a]volume={volume},pan=stereo|c0=c0|c1=c0[out]", "-map", "[out]", path)
        return path

    def jsonl(self, result):
        rows = []
        for line in result.stdout.splitlines():
            if line.strip():
                rows.append(json.loads(line))
        return rows

    def events(self, result):
        return [row.get("event") for row in self.jsonl(result)]

    def test_scripts_exist_and_help_version(self):
        for tool in TOOLS:
            with self.subTest(tool=tool):
                path = ROOT / "bash" / f"{tool}.sh"
                self.assertTrue(path.exists(), path)
                h = self.run_tool(tool, "--help")
                self.assertEqual(h.returncode, 0, h.stderr)
                self.assertIn(tool, h.stdout.lower())
                v = self.run_tool(tool, "--version")
                self.assertEqual(v.returncode, 0, v.stderr)
                self.assertIn("beta", v.stdout.lower())

    def test_common_error_and_output_contract(self):
        source = self.tone(self.p / "a file.wav", channels=2)
        for tool in TOOLS:
            with self.subTest(tool=tool):
                missing = self.run_tool(tool)
                self.assertEqual(missing.returncode, 2)
                bad = self.run_tool(tool, self.p / "missing.wav")
                self.assertEqual(bad.returncode, 2)
                r = self.run_tool(tool, source, "--format", "jsonl")
                self.assertIn(r.returncode, (0, 1), r.stderr)
                rows = self.jsonl(r)
                self.assertTrue(rows)
                self.assertEqual(rows[-1]["tool"], tool)
                self.assertEqual(rows[-1]["event"], "summary")
                tsv = self.run_tool(tool, source, "--format", "tsv")
                self.assertIn(tsv.returncode, (0, 1), tsv.stderr)
                lines = [x for x in tsv.stdout.splitlines() if x]
                self.assertGreaterEqual(len(lines), 1)
                nohead = self.run_tool(tool, source, "--format", "tsv", "--no-header")
                self.assertIn(nohead.returncode, (0, 1), nohead.stderr)
                self.assertNotEqual(lines[0], nohead.stdout.splitlines()[0] if nohead.stdout.splitlines() else "")

    def test_output_file_is_atomic_and_source_unchanged(self):
        source = self.tone(self.p / "source.wav", channels=2)
        before = source.read_bytes()
        stamp = source.stat().st_mtime_ns
        for tool in TOOLS:
            report = self.p / f"{tool}.jsonl"
            r = self.run_tool(tool, source, "--format", "jsonl", "--output", report)
            self.assertIn(r.returncode, (0, 1), r.stderr)
            self.assertEqual(r.stdout, "")
            self.assertTrue(report.exists())
            for line in report.read_text(encoding="utf-8").splitlines():
                if line.strip():
                    json.loads(line)
        self.assertEqual(source.read_bytes(), before)
        self.assertEqual(source.stat().st_mtime_ns, stamp)

    def test_edgeguard_hard_boundary_vs_fade(self):
        abrupt = self.tone(self.p / "abrupt.wav", duration=1.0, volume=0.8)
        faded = self.p / "faded.wav"
        self.ffmpeg("-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1", "-af", "volume=0.8,afade=t=in:d=0.1,afade=t=out:st=0.9:d=0.1", faded)
        r = self.run_tool("edgeguard", abrupt, "--format", "jsonl")
        self.assertEqual(r.returncode, 1, r.stderr)
        ev = self.events(r)
        self.assertTrue("possible_truncated_start" in ev or "possible_truncated_end" in ev)
        clean = self.run_tool("edgeguard", faded, "--format", "jsonl")
        self.assertEqual(clean.returncode, 0, clean.stderr)
        self.assertNotIn("possible_truncated_start", self.events(clean))
        self.assertNotIn("possible_truncated_end", self.events(clean))

    def test_subphase_inverted_low_band(self):
        source = self.p / "inverted-sub.wav"
        self.ffmpeg("-f", "lavfi", "-i", "aevalsrc=0.5*sin(2*PI*60*t)|-0.5*sin(2*PI*60*t):s=48000:d=1", source)
        r = self.run_tool("subphase", source, "--format", "jsonl")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertTrue(any(x in self.events(r) for x in ("negative_sub_correlation", "critical_sub_correlation")))
        mono = self.tone(self.p / "mono.wav", freq=60)
        self.assertEqual(self.run_tool("subphase", mono).returncode, 2)
        self.assertIn(self.run_tool("subphase", mono, "--allow-mono").returncode, (0, 1))

    def test_banddrift_detects_tonal_shift(self):
        source = self.p / "bands.wav"
        self.ffmpeg(
            "-f", "lavfi", "-i", "sine=frequency=60:sample_rate=48000:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=3000:sample_rate=48000:duration=2",
            "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1[out]", "-map", "[out]", source,
        )
        r = self.run_tool("banddrift", source, "--format", "jsonl", "--window-ms", "500", "--min-run-windows", "1")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertTrue(any(x in self.events(r) for x in ("band_share_high", "band_share_low", "broad_tonal_shift")))
        invalid = self.run_tool("banddrift", source, "--band", "a:20:200", "--band", "b:100:300")
        self.assertEqual(invalid.returncode, 2)

    def test_repeataudit_finds_exact_adjacent_repeat_and_ignores_silence(self):
        block = self.p / "block.wav"
        self.ffmpeg("-f", "lavfi", "-i", "sine=frequency=731:sample_rate=48000:duration=0.1", block)
        repeated = self.p / "repeated.wav"
        self.ffmpeg("-i", block, "-filter_complex", "[0:a]asplit=4[a][b][c][d];[a][b][c][d]concat=n=4:v=0:a=1[out]", "-map", "[out]", repeated)
        r = self.run_tool("repeataudit", repeated, "--format", "jsonl", "--block-ms", "100", "--min-adjacent-ms", "200")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("adjacent_exact_repeat", self.events(r))
        silence = self.p / "silence.wav"
        self.ffmpeg("-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono:d=1", silence)
        clean = self.run_tool("repeataudit", silence, "--format", "jsonl")
        self.assertEqual(clean.returncode, 0, clean.stderr)

    def test_samplefreeze_exact_and_channel_aware(self):
        source = self.p / "freeze.wav"
        self.ffmpeg("-f", "lavfi", "-i", "aevalsrc=if(between(t\,0.25\,0.55)\,0.25\,0.25*sin(2*PI*440*t))|0.25*sin(2*PI*440*t):s=48000:d=1", source)
        r = self.run_tool("samplefreeze", source, "--format", "jsonl", "--min-run-ms", "50")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("exact_sample_freeze", self.events(r))
        sine = self.tone(self.p / "sine.wav", channels=2)
        clean = self.run_tool("samplefreeze", sine, "--format", "jsonl")
        self.assertEqual(clean.returncode, 0, clean.stderr)

    def test_transientledger_relative_regime(self):
        source = self.p / "transients.wav"
        self.ffmpeg(
            "-f", "lavfi", "-i", "sine=frequency=220:sample_rate=48000:duration=2",
            "-f", "lavfi", "-i", "aevalsrc=if(lt(mod(t\,0.1)\,0.005)\,0.9\,0):s=48000:d=2",
            "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1[out]", "-map", "[out]", source,
        )
        r = self.run_tool("transientledger", source, "--format", "jsonl", "--window-ms", "1000")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertTrue(any(x in self.events(r) for x in ("transient_density_low", "transient_density_high", "transient_regime_change", "crest_factor_high")))

    def test_leading_dash_filename_after_terminator(self):
        source = self.tone(self.p / "--source.wav", channels=2)
        for tool in TOOLS:
            r = subprocess.run(["bash", str(ROOT / "bash" / f"{tool}.sh"), "--format", "jsonl", "--", source.name], cwd=self.p, capture_output=True, text=True)
            self.assertIn(r.returncode, (0, 1), (tool, r.stderr))

    def test_invalid_numbers_rejected(self):
        source = self.tone(self.p / "a.wav", channels=2)
        cases = [
            ("edgeguard", "--window-ms", "0"),
            ("subphase", "--crossover-hz", "0"),
            ("banddrift", "--deviation-pct", "-1"),
            ("repeataudit", "--block-ms", "0"),
            ("samplefreeze", "--min-run-ms", "0"),
            ("transientledger", "--envelope-ms", "0"),
        ]
        for tool, flag, value in cases:
            with self.subTest(tool=tool):
                self.assertEqual(self.run_tool(tool, source, flag, value).returncode, 2)


if __name__ == "__main__":
    unittest.main()
