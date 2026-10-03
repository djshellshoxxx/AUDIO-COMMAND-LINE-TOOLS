from pathlib import Path
import tempfile
import unittest
import zipfile
import subprocess

ROOT=Path(__file__).resolve().parents[1]
TOOLS=('edgeguard','subphase','banddrift','repeataudit','samplefreeze','transientledger')

class BashSiteTest(unittest.TestCase):
    def test_sources_specs_readme_and_site_reference_every_tool(self):
        readme=(ROOT/'README.md').read_text(encoding='utf-8')
        page=(ROOT/'site'/'index.html').read_text(encoding='utf-8')
        for name in TOOLS:
            with self.subTest(name=name):
                self.assertTrue((ROOT/'bash'/f'{name}.sh').is_file())
                self.assertTrue((ROOT/'spec'/f'{name}.md').is_file())
                self.assertIn(name,readme)
                self.assertIn(name,page)
                self.assertIn(f'spec/{name}.md',page)
                self.assertIn(f'bash/{name}.sh',page)
        self.assertGreaterEqual(page.lower().count('beta'),6)
        self.assertIn('Bash pipeline',page)
        self.assertIn('FFmpeg',page)

    def test_bash_bundle_contains_runtime_and_specs(self):
        subprocess.run(['python',str(ROOT/'scripts'/'package.py')],check=True,cwd=ROOT)
        bundle=ROOT/'site'/'downloads'/'cdl-audio-bash.zip'
        self.assertTrue(bundle.is_file())
        with zipfile.ZipFile(bundle) as z:
            names=set(z.namelist())
        for name in TOOLS:
            self.assertIn(f'bash/{name}.sh',names)
            self.assertIn(f'spec/{name}.md',names)
        for helper in ('audio-common.sh','output.sh','pcm.sh'):
            self.assertIn(f'bash/lib/{helper}',names)

    def test_novelty_copy_is_evidence_based(self):
        combined='\n'.join((ROOT/'README.md').read_text(encoding='utf-8'),(ROOT/'site'/'index.html').read_text(encoding='utf-8'))
        self.assertNotIn('no other tool exists',combined.lower())
        self.assertNotIn('first ever',combined.lower())
        self.assertIn('well-established standalone',combined)

if __name__=='__main__':unittest.main()
