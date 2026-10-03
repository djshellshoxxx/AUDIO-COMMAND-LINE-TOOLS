import os
import tempfile
import unittest
import warnings
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
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(q.tobytes())


class BatchToolsAuditTests(unittest.TestCase):
    def test_phase_search_larger_than_audio_has_no_runtime_warnings(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            x = np.zeros(1000)
            x[500:510] = 0.7
            a, b = td / "a.wav", td / "b.wav"
            write_wav(a, x)
            write_wav(b, x)
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                result = batch_audio.compare_phase(a, b, max_shift_ms=1000)
            self.assertEqual(caught, [])
            self.assertEqual(result["delay_frames"], 0)
            self.assertGreater(result["correlation"], 0.99)

    def test_nonfinite_numeric_options_are_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            p, q = td / "a.wav", td / "b.wav"
            write_wav(p, np.ones(100) * 0.2)
            write_wav(q, np.ones(100) * 0.2)
            with self.assertRaises(ValueError):
                batch_audio.analyze_onset(p, threshold_db=float("nan"))
            with self.assertRaises(ValueError):
                batch_audio.analyze_edges(p, threshold_db=float("inf"))
            with self.assertRaises(ValueError):
                batch_audio.compare_phase(p, q, max_shift_ms=float("inf"))
            with self.assertRaises(ValueError):
                batch_audio.repair_edges(p, td / "out.wav", fade_ms=float("inf"))

    def test_zero_fade_is_rejected_instead_of_mutating_edge_samples(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            p, out = td / "a.wav", td / "out.wav"
            write_wav(p, np.ones(100) * 0.5)
            with self.assertRaises(ValueError):
                batch_audio.repair_edges(p, out, fade_ms=0)
            self.assertFalse(out.exists())

    def test_json_and_csv_cannot_share_same_output_path(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "report.out"
            with self.assertRaises(ValueError):
                batch_audio.write_report({"files": [{"a": 1}]}, p, p, overwrite=True)
            self.assertFalse(p.exists())

    def test_symlinked_output_directory_cannot_redirect_into_source(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            src, out = td / "src", td / "out"
            src.mkdir()
            out.mkdir()
            write_wav(src / "sub" / "hit.wav", np.ones(100) * 0.5)
            try:
                os.symlink(src / "sub", out / "sub", target_is_directory=True)
            except OSError as exc:
                self.skipTest(f"symlink unavailable: {exc}")
            before = (src / "sub" / "hit.wav").read_bytes()
            with self.assertRaises(ValueError):
                batch_audio.edgeguard(src, out, repair=True, overwrite=True)
            self.assertEqual((src / "sub" / "hit.wav").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
