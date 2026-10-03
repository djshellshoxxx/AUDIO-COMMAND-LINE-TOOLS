import json, pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]; BASH=ROOT/'bash'; POWERSHELL=ROOT/'powershell'
TOOLS=['formattruth','transcodeaudit','batchsilence','albumcontract','loudwalk','stereotruth','phasewatch']
class T(unittest.TestCase):
 @classmethod
 def setUpClass(c):
  if not shutil.which('ffmpeg') or not shutil.which('ffprobe'): raise unittest.SkipTest('ffmpeg/ffprobe required')
  c.t=tempfile.TemporaryDirectory(); c.d=pathlib.Path(c.t.name)/'fixtures with spaces'; c.d.mkdir()
  c.stereo=c.d/'stereo test.wav'; c.mono=c.d/'mono.wav'; c.pad=c.d/'silence padded.wav'
  subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','sine=frequency=440:duration=1','-filter_complex','[0:a]asplit=2[l][r];[l][r]amerge=inputs=2[out]','-map','[out]','-ar','48000',str(c.stereo)],check=True)
  subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','sine=frequency=220:duration=1','-ac','1','-ar','44100',str(c.mono)],check=True)
  subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','anullsrc=r=48000:cl=stereo:d=0.25','-f','lavfi','-i','sine=frequency=330:duration=0.5','-f','lavfi','-i','anullsrc=r=48000:cl=stereo:d=0.35','-filter_complex','[1:a]pan=stereo|c0=c0|c1=c0[mid];[0:a][mid][2:a]concat=n=3:v=0:a=1[out]','-map','[out]',str(c.pad)],check=True)
 @classmethod
 def tearDownClass(c): c.t.cleanup()
 def run_tool(self,tool,*args,exp=(0,1)):
  p=BASH/(tool+'.sh'); self.assertTrue(p.exists(),f'missing {p}'); before={x:(x.stat().st_mtime_ns,x.read_bytes()) for x in self.d.glob('*.wav')}; cp=subprocess.run(['bash',str(p),*map(str,args)],text=True,capture_output=True); self.assertIn(cp.returncode,exp,cp.stderr); after={x:(x.stat().st_mtime_ns,x.read_bytes()) for x in self.d.glob('*.wav')}; self.assertEqual(before,after); return cp

 def run_ps(self,tool,*args,exp=(0,1)):
  if not shutil.which('pwsh'): self.skipTest('pwsh not installed')
  p=POWERSHELL/(tool+'.ps1'); self.assertTrue(p.exists(),f'missing {p}'); before={x:(x.stat().st_mtime_ns,x.read_bytes()) for x in self.d.glob('*.wav')}; cp=subprocess.run(['pwsh','-NoProfile','-File',str(p),*map(str,args)],text=True,capture_output=True); self.assertIn(cp.returncode,exp,cp.stderr); after={x:(x.stat().st_mtime_ns,x.read_bytes()) for x in self.d.glob('*.wav')}; self.assertEqual(before,after); return cp
 def js(self,cp):
  try:return json.loads(cp.stdout)
  except Exception as e:self.fail(f'{e}\n{cp.stdout}\n{cp.stderr}')
 def test_help(self):
  for t in TOOLS:self.run_tool(t,'--help',exp=(0,))
 def test_formattruth(self):
  d=self.js(self.run_tool('formattruth',self.stereo,'--json')); self.assertEqual(d['measurements']['channels'],2); self.assertEqual(d['tool'],'formattruth')
 def test_transcodeaudit_order(self):
  d=self.js(self.run_tool('transcodeaudit',self.d,'--json')); paths=[x['path'] for x in d['measurements']['files']]; self.assertEqual(paths,sorted(paths))
 def test_batchsilence(self):
  d=self.js(self.run_tool('batchsilence',self.d,'--json')); r=next(x for x in d['measurements']['files'] if x['path'].endswith('silence padded.wav')); self.assertGreater(r['leading_silence_seconds'],.15); self.assertGreater(r['trailing_silence_seconds'],.2)
 def test_albumcontract(self):
  d=self.js(self.run_tool('albumcontract',self.d,'--json')); self.assertIn('channel_count_outlier',{x['category'] for x in d['findings']})
 def test_loudwalk(self):
  d=self.js(self.run_tool('loudwalk',self.stereo,'--json')); self.assertIn('timeline',d['measurements'])
 def test_stereotruth(self):
  d=self.js(self.run_tool('stereotruth',self.stereo,'--json')); self.assertIn('dual_mono_candidate',{x['category'] for x in d['findings']})
 def test_phasewatch(self):
  d=self.js(self.run_tool('phasewatch',self.stereo,'--json')); self.assertIn('windows',d['measurements'])

 def test_powershell_help(self):
  for t in TOOLS:self.run_ps(t,'-Help',exp=(0,))
 def test_powershell_formattruth_parity(self):
  b=self.js(self.run_tool('formattruth',self.stereo,'--json')); p=self.js(self.run_ps('formattruth',self.stereo,'-Json')); self.assertEqual(b['measurements']['channels'],p['measurements']['channels']); self.assertEqual(b['measurements']['sample_rate'],p['measurements']['sample_rate'])
 def test_powershell_stereotruth_category_parity(self):
  b=self.js(self.run_tool('stereotruth',self.stereo,'--json')); p=self.js(self.run_ps('stereotruth',self.stereo,'-Json')); self.assertEqual({x['category'] for x in b['findings']},{x['category'] for x in p['findings']})
 def test_powershell_albumcontract_category_parity(self):
  b=self.js(self.run_tool('albumcontract',self.d,'--json')); p=self.js(self.run_ps('albumcontract',self.d,'-Json')); self.assertEqual({x['category'] for x in b['findings']},{x['category'] for x in p['findings']})
 def test_powershell_batchsilence_measurement(self):
  p=self.js(self.run_ps('batchsilence',self.d,'-Json')); r=next(x for x in p['measurements']['files'] if x['path'].endswith('silence padded.wav')); self.assertGreater(r['leading_silence_seconds'],.15); self.assertGreater(r['trailing_silence_seconds'],.2)
if __name__=='__main__':unittest.main()
