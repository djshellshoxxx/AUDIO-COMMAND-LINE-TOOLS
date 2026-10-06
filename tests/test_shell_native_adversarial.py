import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASH = ROOT / 'bash'
POWERSHELL = ROOT / 'powershell'
SINGLE = ['formattruth', 'loudwalk', 'stereotruth', 'phasewatch']
DIRECTORY = ['transcodeaudit', 'batchsilence', 'albumcontract']


class ShellNativeAdversarialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
            raise unittest.SkipTest('ffmpeg/ffprobe required')
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = pathlib.Path(cls.tmp.name) / 'audio set'
        cls.root.mkdir()
        cls.source = cls.root / 'source.wav'
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.4',
            '-filter_complex', '[0:a]asplit=2[l][r];[l][r]amerge=inputs=2[out]',
            '-map', '[out]', '-ar', '48000', str(cls.source)
        ], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def snapshot(self):
        return self.source.read_bytes(), self.source.stat().st_mtime_ns

    def assert_unchanged(self, before):
        self.assertEqual(before[0], self.source.read_bytes())
        self.assertEqual(before[1], self.source.stat().st_mtime_ns)

    def run_bash(self, tool, target):
        return subprocess.run(
            ['bash', str(BASH / f'{tool}.sh'), str(target), '--json', '--output', str(self.source)],
            text=True, capture_output=True
        )

    def run_ps(self, tool, target):
        return subprocess.run(
            ['pwsh', '-NoProfile', '-File', str(POWERSHELL / f'{tool}.ps1'), str(target), '-Json', '-Output', str(self.source)],
            text=True, capture_output=True
        )

    @unittest.skipIf(os.name == 'nt', 'Bash regression tests run on Linux')
    def test_bash_report_output_cannot_alias_analyzed_source(self):
        for tool in SINGLE + DIRECTORY:
            with self.subTest(tool=tool):
                # Restore the fixture before each subtest so one vulnerable tool cannot
                # prevent the remaining tools from being exercised.
                subprocess.run([
                    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.4',
                    '-filter_complex', '[0:a]asplit=2[l][r];[l][r]amerge=inputs=2[out]',
                    '-map', '[out]', '-ar', '48000', str(self.source)
                ], check=True)
                before = self.snapshot()
                target = self.source if tool in SINGLE else self.root
                cp = self.run_bash(tool, target)
                self.assertEqual(cp.returncode, 2, cp.stderr)
                self.assert_unchanged(before)

    def test_powershell_report_output_cannot_alias_analyzed_source(self):
        if not shutil.which('pwsh'):
            self.skipTest('pwsh not installed')
        for tool in SINGLE + DIRECTORY:
            with self.subTest(tool=tool):
                subprocess.run([
                    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.4',
                    '-filter_complex', '[0:a]asplit=2[l][r];[l][r]amerge=inputs=2[out]',
                    '-map', '[out]', '-ar', '48000', str(self.source)
                ], check=True)
                before = self.snapshot()
                target = self.source if tool in SINGLE else self.root
                cp = self.run_ps(tool, target)
                self.assertEqual(cp.returncode, 2, cp.stderr)
                self.assert_unchanged(before)


if __name__ == '__main__':
    unittest.main()
