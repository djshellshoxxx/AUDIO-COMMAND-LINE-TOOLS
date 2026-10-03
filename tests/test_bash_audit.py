from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class BashAuditRegressionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
            raise unittest.SkipTest('ffmpeg/ffprobe required')
    def setUp(self):
        self.t=tempfile.TemporaryDirectory(); self.p=Path(self.t.name)
    def tearDown(self): self.t.cleanup()
    def ff(self,*args):
        r=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',*map(str,args)],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
    def run(self,name,*args):
        return subprocess.run(['bash',str(ROOT/'bash'/f'{name}.sh'),*map(str,args)],capture_output=True,text=True)
    def events(self,r):
        return [json.loads(x)['event'] for x in r.stdout.splitlines() if x.strip()]

    def test_edgeguard_emits_explicit_no_fade_evidence(self):
        p=self.p/'hard.wav'; self.ff('-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=1','-af','volume=.8',p)
        r=self.run('edgeguard',p,'--format','jsonl')
        self.assertEqual(r.returncode,1,r.stderr)
        ev=self.events(r)
        self.assertIn('no_start_fade_evidence',ev)
        self.assertIn('no_end_fade_evidence',ev)

    def test_subphase_min_run_suppresses_single_bad_window_and_reports_regime_change(self):
        p=self.p/'phase.wav'
        self.ff('-f','lavfi','-i','aevalsrc=0.5*sin(2*PI*60*t)|0.5*sin(2*PI*60*t):s=48000:d=.5',
                '-f','lavfi','-i','aevalsrc=0.5*sin(2*PI*60*t)|-0.5*sin(2*PI*60*t):s=48000:d=.25',
                '-f','lavfi','-i','aevalsrc=0.5*sin(2*PI*60*t)|0.5*sin(2*PI*60*t):s=48000:d=.5',
                '-filter_complex','[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]','-map','[out]',p)
        suppressed=self.run('subphase',p,'--format','jsonl','--window-ms','250','--min-run-ms','500')
        self.assertNotIn('critical_sub_correlation',self.events(suppressed))
        reported=self.run('subphase',p,'--format','jsonl','--window-ms','250','--min-run-ms','250')
        self.assertIn('critical_sub_correlation',self.events(reported))
        self.assertIn('sub_phase_regime_change',self.events(reported))

    def test_banddrift_min_run_windows_is_enforced(self):
        p=self.p/'bands.wav'
        self.ff('-f','lavfi','-i','sine=frequency=60:sample_rate=48000:duration=2',
                '-f','lavfi','-i','sine=frequency=3000:sample_rate=48000:duration=.5',
                '-f','lavfi','-i','sine=frequency=60:sample_rate=48000:duration=2',
                '-filter_complex','[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]','-map','[out]',p)
        suppressed=self.run('banddrift',p,'--format','jsonl','--window-ms','500','--min-run-windows','2')
        self.assertNotIn('broad_tonal_shift',self.events(suppressed))
        reported=self.run('banddrift',p,'--format','jsonl','--window-ms','500','--min-run-windows','1')
        self.assertIn('broad_tonal_shift',self.events(reported))

    def test_repeataudit_nonadjacent_run_respects_duration_threshold(self):
        p=self.p/'nonadjacent.wav'
        self.ff('-f','lavfi','-i','sine=frequency=731:sample_rate=48000:duration=.6',
                '-f','lavfi','-i','sine=frequency=997:sample_rate=48000:duration=.3',
                '-filter_complex','[0:a]asplit=2[a][c];[a][1:a][c]concat=n=3:v=0:a=1[out]','-map','[out]',p)
        r=self.run('repeataudit',p,'--format','jsonl','--block-ms','100','--min-adjacent-ms','1000','--min-nonadjacent-ms','500')
        self.assertEqual(r.returncode,1,r.stderr)
        self.assertIn('nonadjacent_exact_repeat',self.events(r))

    def test_samplefreeze_reports_multichannel_overlap(self):
        p=self.p/'bothfreeze.wav'
        self.ff('-f','lavfi','-i','aevalsrc=if(between(t\,0.2\,0.5)\,.25\,.2*sin(2*PI*440*t))|if(between(t\,0.2\,0.5)\,-.25\,.2*sin(2*PI*330*t)):s=48000:d=1',p)
        r=self.run('samplefreeze',p,'--format','jsonl','--min-run-ms','50')
        self.assertEqual(r.returncode,1,r.stderr)
        self.assertIn('multichannel_freeze',self.events(r))

    def test_transientledger_reports_regime_change(self):
        p=self.p/'regime.wav'
        self.ff('-f','lavfi','-i','sine=frequency=220:sample_rate=48000:duration=2',
                '-f','lavfi','-i','aevalsrc=if(lt(mod(t\,.1)\,.005)\,.9\,0):s=48000:d=2',
                '-filter_complex','[0:a][1:a]concat=n=2:v=0:a=1[out]','-map','[out]',p)
        r=self.run('transientledger',p,'--format','jsonl','--window-ms','1000')
        self.assertEqual(r.returncode,1,r.stderr)
        self.assertIn('transient_regime_change',self.events(r))

if __name__=='__main__':unittest.main()
