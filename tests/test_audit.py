"""Regression cases found during the per-program audit."""
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
from drift_audio import read_wav, write_wav, analyze, DEFAULTS, FLAGS

class AuditTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.p=Path(self.temp.name)
        self.source=self.p/'a.wav';write_wav(self.source,np.full((100,2),.25),1000)
    def tearDown(self):self.temp.cleanup()
    def cli(self,tool,*args,js=False):
        exe=['node',str(ROOT/'site/js'/f'{tool}.mjs')] if js else [sys.executable,str(ROOT/'python'/f'{tool}.py')]
        return subprocess.run(exe+list(map(str,args)),cwd=self.p,capture_output=True,text=True,encoding='utf-8')
    def floating(self,name,x,rate=1000):
        x=np.asarray(x,dtype='<f8');channels=x.shape[1];align=channels*8;payload=x.tobytes()
        body=b'WAVEfmt '+struct.pack('<IHHIIHH',16,3,channels,rate,rate*align,align,64)+b'data'+struct.pack('<I',len(payload))+payload
        p=self.p/name;p.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body);return p
    def test_empty_output_flags_are_errors(self):
        for js in (False,True):
            for flag in ('--output=','--audio-out='):
                with self.subTest(js=js,flag=flag):self.assertEqual(self.cli('gainbudget',self.source,flag,js=js).returncode,2)
    def test_missing_output_value_does_not_consume_next_flag(self):
        for js in (False,True):
            for args in [('--output','--overwrite'),('--output','--help'),('--audio-out','--overwrite')]:
                with self.subTest(js=js,args=args):
                    r=self.cli('gainbudget',self.source,*args,js=js)
                    self.assertEqual(r.returncode,2,r.stdout)
                    self.assertFalse((self.p/'--overwrite').exists())
    def test_boolean_equals_is_rejected(self):
        for js in (False,True):self.assertEqual(self.cli('gainbudget',self.source,'--overwrite=true',js=js).returncode,2)
    def test_terminator_preserves_dash_and_equals_filenames(self):
        for name in ('--help','--source=take.wav'):
            (self.p/name).write_bytes(self.source.read_bytes())
            for js in (False,True):
                r=self.cli('loopbudget','--',name,js=js);self.assertEqual(r.returncode,0,r.stderr)
                self.assertEqual(json.loads(r.stdout)['inputs'],[name])
    def test_help_string_as_expect_value(self):
        for js in (False,True):
            r=self.cli('stemcontract',self.source,'--expect=--help',js=js)
            self.assertEqual(r.returncode,1);self.assertEqual(json.loads(r.stdout)['missing'],['--help'])
    def test_numeric_tokens_use_decimal_syntax(self):
        for js in (False,True):
            for tool,flag,value in [('loopbudget','--bpm','0x80'),('loopbudget','--bars','1e2')]:
                self.assertEqual(self.cli(tool,self.source,flag,value,js=js).returncode,2)
    def test_output_aliases_through_symlink_parent(self):
        real=self.p/'real';real.mkdir();alias=self.p/'alias'
        try:alias.symlink_to(real,target_is_directory=True)
        except OSError:self.skipTest('Symlink creation unavailable')
        for js in (False,True):
            r=self.cli('gainbudget',self.source,'--audio-out',real/'same','--output',alias/'same','--overwrite',js=js)
            self.assertEqual(r.returncode,2);self.assertFalse((real/'same').exists())
    def test_invalid_report_destination_does_not_leave_audio(self):
        for js in (False,True):
            dest=self.p/f'out-{js}.wav'
            r=self.cli('gainbudget',self.source,'--audio-out',dest,'--output',self.p,'--overwrite',js=js)
            self.assertEqual(r.returncode,2);self.assertFalse(dest.exists())
    def test_gain_ceiling_after_quantization(self):
        source=self.floating('tiny.wav',np.full((10,2),.001))
        outputs=[]
        for js in (False,True):
            dest=self.p/f'tiny-{js}.wav';r=self.cli('gainbudget',source,'--ceiling-db','-60','--audio-out',dest,js=js)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertLessEqual(float(np.max(np.abs(read_wav(dest)['samples']))),.001)
            outputs.append(dest.read_bytes())
        self.assertEqual(outputs[0],outputs[1])
    def test_gain_budget_below_display_floor(self):
        source=self.floating('tiny.wav',np.full((10,1),1e-15))
        for js in (False,True):
            r=self.cli('gainbudget',source,js=js);self.assertEqual(r.returncode,0,r.stderr)
            self.assertAlmostEqual(json.loads(r.stdout)['safe_gain_db'],299)
    def test_constant_stereo_correlation_is_null(self):
        source=self.floating('constant.wav',np.tile([.1,-.1],(100,1)))
        for js in (False,True):
            r=self.cli('monoledger',source,js=js);self.assertEqual(r.returncode,0,r.stderr)
            self.assertIsNone(json.loads(r.stdout)['risky_windows'][0]['correlation'])
    def test_cue_limit_accounts_for_origin(self):
        source=self.p/'long.wav';write_wav(source,np.zeros((200001,1)),1)
        for js in (False,True):
            for offset,expected in [(200000,[200000]),(200002,[])]:
                r=self.cli('cueclock',source,'--bpm','240','--offset-seconds',offset,js=js)
                self.assertEqual(r.returncode,0,r.stderr)
                self.assertEqual([c['frame'] for c in json.loads(r.stdout)['cues']],expected)
    def test_unicode_expected_names_have_portable_order(self):
        for js in (False,True):
            r=self.cli('stemcontract',self.source,'--expect','\U00010000.wav','--expect','\ue000.wav',js=js)
            self.assertEqual(r.returncode,1);self.assertEqual(json.loads(r.stdout)['missing'],['\ue000.wav','\U00010000.wav'])
    def test_large_window_report_is_rejected(self):
        source=self.p/'dense.wav';write_wav(source,np.full((100001,1),.25),1000)
        for js in (False,True):
            r=self.cli('dcjourney',source,'--window-ms','1',js=js)
            self.assertEqual(r.returncode,2);self.assertIn('100000',r.stderr)
    def test_event_limits_cover_all_ledgers(self):
        for tool in ('monoledger','gapcontext','railruns','renderdelta'):
            if tool=='monoledger':x=np.tile([.25,-.25],(100001,1));opts=['--window-ms','1']
            elif tool=='gapcontext':x=np.tile([[.25],[0.]],(100002,1));opts=['--min-ms','.5','--flank-ms','1']
            elif tool=='railruns':x=np.tile([[1.],[0.]],(100001,1));opts=['--min-run','1']
            else:x=np.full((100001,1),.25);opts=['--window-ms','1']
            source=self.p/f'{tool}.wav';write_wav(source,x,1000)
            inputs=[source]
            if tool=='renderdelta':
                other=self.p/'zeros.wav';write_wav(other,np.zeros_like(x),1000);inputs.append(other)
            for js in (False,True):
                with self.subTest(tool=tool,js=js):
                    r=self.cli(tool,*inputs,*opts,js=js)
                    self.assertEqual(r.returncode,2);self.assertIn('100000',r.stderr)
    def test_active_threshold_range(self):
        for js in (False,True):
            for value in ('1','-241'):
                self.assertEqual(self.cli('gapcontext',self.source,'--active-db',value,js=js).returncode,2)
    def test_fmt_extension_size_is_validated(self):
        b=self.source.read_bytes();body=b[8:16]+struct.pack('<I',18)+b[20:36]+struct.pack('<H',100)+b[36:]
        source=self.p/'invalid-fmt.wav';source.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
        for js in (False,True):self.assertEqual(self.cli('gainbudget',source,js=js).returncode,2)
    def test_dangling_symlink_output_alias_is_rejected(self):
        report=self.p/'result.json';alias=self.p/'alias.wav'
        try:alias.symlink_to(report)
        except OSError:self.skipTest('Symlinks unavailable')
        for js in (False,True):
            r=self.cli('gainbudget',self.source,'--audio-out',alias,'--output',report,'--overwrite',js=js)
            self.assertEqual(r.returncode,2,r.stderr);self.assertFalse(report.exists())
    def test_cli_batch_size_budget(self):
        files=[]
        for i in range(3):
            p=self.p/f'large-{i}.wav'
            with p.open('wb') as f:f.truncate(50*1024*1024)
            files.append(p)
        for js in (False,True):
            r=self.cli('stemcontract',*files,js=js);self.assertEqual(r.returncode,2);self.assertIn('128 MiB',r.stderr)
    def test_lazy_spans_cross_chunk_boundaries(self):
        from drift_audio import spans
        mask=np.zeros(131074,dtype=bool);mask[65534:65538]=True;mask[131072:]=True
        self.assertEqual(list(spans(mask)),[(65534,65538),(131072,131074)])
    def test_gap_quiet_context_after_loud_audio(self):
        x=np.full((1000,1),1e-5);x[0]=1e6;x[400:410]=0
        source=self.floating('dynamic.wav',x)
        for js in (False,True):
            r=self.cli('gapcontext',source,'--threshold-db','-120','--active-db','-110',js=js)
            self.assertEqual(r.returncode,0,r.stderr);rows=json.loads(r.stdout)['candidates']
            self.assertEqual(len(rows),1);self.assertAlmostEqual(rows[0]['before_rms_dbfs'],-100,places=8)
    def test_empty_expected_basename_is_rejected(self):
        for js in (False,True):self.assertEqual(self.cli('stemcontract',self.source,'--expect=',js=js).returncode,2)
    def test_active_threshold_endpoints_are_accepted(self):
        for js in (False,True):
            for value in ('0','-240'):
                self.assertEqual(self.cli('gapcontext',self.source,'--active-db',value,js=js).returncode,0)
    def test_fmt_single_extension_byte_is_rejected(self):
        b=self.source.read_bytes();body=b[8:16]+struct.pack('<I',17)+b[20:36]+b'\x00\x00'+b[36:]
        source=self.p/'invalid-fmt.wav';source.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
        for js in (False,True):self.assertEqual(self.cli('gainbudget',source,js=js).returncode,2)
    def test_all_documented_flags_are_wired(self):
        for tool,keys in FLAGS.items():
            spec=(ROOT/'spec'/f'{tool}.md').read_text()
            for js in (False,True):
                r=self.cli(tool,'--help',js=js);self.assertEqual(r.returncode,0)
                for key in keys:
                    name='--'+key.replace('_','-');self.assertIn(name,spec);self.assertIn(name,r.stdout)
    def test_help_describes_defaults(self):
        for js in (False,True):
            r=self.cli('railruns','--help',js=js)
            self.assertIn('default',r.stdout.lower());self.assertIn('-0.1',r.stdout)
    def test_gap_prefix_rms_matches_direct_measurement(self):
        rng=np.random.default_rng(107);x=rng.uniform(.1,.4,(10000,3));x[333:343]=0;x[8000:8020]=0
        source=self.floating('gaps.wav',x)
        for js in (False,True):
            r=self.cli('gapcontext',source,'--flank-ms','2000',js=js);self.assertEqual(r.returncode,0,r.stderr)
            rows=json.loads(r.stdout)['candidates'];self.assertEqual(len(rows),2)
            for row,(start,end) in zip(rows,[(333,343),(8000,8020)]):
                before=20*math.log10(np.sqrt(np.mean(x[max(0,start-2000):start]**2)))
                after=20*math.log10(np.sqrt(np.mean(x[end:min(len(x),end+2000)]**2)))
                self.assertAlmostEqual(row['before_rms_dbfs'],before,places=8);self.assertAlmostEqual(row['after_rms_dbfs'],after,places=8)
if __name__=='__main__':unittest.main()
