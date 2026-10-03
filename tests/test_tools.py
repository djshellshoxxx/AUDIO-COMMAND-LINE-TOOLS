"""Synthetic regression tests and cross-language parity, no external audio fixtures."""
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
from drift_audio import analyze, decode_wav, read_wav, write_wav, DEFAULTS, TOOLS, validate

class ToolsTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.p=Path(self.temp.name)
        self.rate=1000
        self.x=np.column_stack([np.sin(np.arange(2000)*2*np.pi/100)*.3]*2)
        write_wav(self.p/'a.wav',self.x,self.rate)
        self.a=read_wav(self.p/'a.wav')
    def tearDown(self): self.temp.cleanup()
    def run_tool(self,name,x=None,**options):
        o={**DEFAULTS,**options};return analyze(name,[self.a if x is None else {'samples':x,'rate':self.rate}],o)[0]
    def cli(self,name,*args,js=False):
        cmd=['node',str(ROOT/'site/js'/f'{name}.mjs')] if js else [sys.executable,str(ROOT/'python'/f'{name}.py')]
        return subprocess.run(cmd+list(map(str,args)),capture_output=True,text=True)
    def test_loop_length_and_jump(self):
        r=self.run_tool('loopbudget',np.zeros((2000,2)),bpm=120)
        self.assertEqual(r['frame_error'],0);self.assertEqual(r['seam_jump_dbfs'],[-240]*2)
        y=np.zeros((1999,1));y[-1]=.5;r=self.run_tool('loopbudget',y)
        self.assertEqual(r['frame_error'],-1);self.assertAlmostEqual(r['seam_jump_dbfs'][0],-6.020599913)
    def test_single_frame_loop(self):
        r=self.run_tool('loopbudget',np.ones((1,1))*.2)
        self.assertEqual(r['slope_mismatch_dbfs'],[-240])
    def test_tail_budget(self):
        y=np.zeros((1000,2));y[0:400]=.2
        r=self.run_tool('tailbudget',y,pad_ms=100)
        self.assertEqual(r['kept_frames'],500);self.assertEqual(r['removable_frames'],500)
    def test_silent_tail(self):
        r=self.run_tool('tailbudget',np.zeros((1000,1)),pad_ms=0)
        self.assertTrue(r['all_quiet']);self.assertEqual(r['kept_frames'],1)
    def test_tail_uses_any_channel(self):
        y=np.zeros((1000,2));y[900,1]=.2
        self.assertEqual(self.run_tool('tailbudget',y,pad_ms=0)['kept_frames'],901)
    def test_mono_inverse_and_same(self):
        y=np.column_stack([self.x[:,0],-self.x[:,0]])
        r=self.run_tool('monoledger',y);self.assertEqual(len(r['risky_windows']),20)
        self.assertAlmostEqual(r['risky_windows'][0]['correlation'],-1)
        self.assertEqual(self.run_tool('monoledger')['risky_windows'],[])
    def test_mono_rejects_other_channels(self):
        with self.assertRaises(ValueError):self.run_tool('monoledger',np.zeros((20,1)))
    def test_mono_silence_ignored(self):
        self.assertEqual(self.run_tool('monoledger',np.zeros((20,2)))['risky_windows'],[])
    def test_gap_context(self):
        y=np.ones((1000,2))*.2;y[400:410]=0
        r=self.run_tool('gapcontext',y)
        self.assertEqual(r['candidates'][0]['frames'],10)
        self.assertEqual(r['candidates'][0]['start_seconds'],.4)
    def test_gap_excludes_edges_and_inactive_flanks(self):
        y=np.ones((1000,2))*.002;y[400:410]=0;y[:10]=0;y[-10:]=0
        self.assertEqual(self.run_tool('gapcontext',y)['candidates'],[])
    def test_gap_requires_all_channels_quiet(self):
        y=np.ones((1000,2))*.2;y[400:410,0]=0
        self.assertEqual(self.run_tool('gapcontext',y)['candidates'],[])
    def test_rail_runs(self):
        y=np.zeros((1000,2));y[50:54,0]=1;y[100,1]=-1
        r=self.run_tool('railruns',y,threshold_db=-.1)
        self.assertEqual(len(r['events']),1);self.assertEqual(r['events'][0]['frames'],4)
        self.assertEqual(r['events'][0]['channel'],1)
    def test_dc_global_vs_local(self):
        y=np.zeros((1000,2));y[:500]=.1;y[500:]=-.1
        r=self.run_tool('dcjourney',y,window_ms=500,threshold_db=-40)
        np.testing.assert_allclose(r['channel_mean'],[0,0],atol=1e-15)
        self.assertAlmostEqual(r['max_window_offset'],.1);self.assertTrue(r['windows'][1]['flagged'])
    def test_gain_budget(self):
        r=self.run_tool('gainbudget',np.ones((10,2))*.5,gain_db=3,ceiling_db=-1)
        self.assertTrue(r['fits_ceiling']);self.assertAlmostEqual(r['safe_gain_db'],5.020599913)
        self.assertFalse(self.run_tool('gainbudget',np.ones((10,2))*.5,gain_db=6)['fits_ceiling'])
    def test_silence_gain(self):
        self.assertIsNone(self.run_tool('gainbudget',np.zeros((10,1)))['safe_gain_db'])
    def test_stem_contract(self):
        r,_=analyze('stemcontract',[self.a,{'samples':np.zeros((10,1)),'rate':2000}],{**DEFAULTS,'require_active':True,'expect':['missing.wav']},['a.wav','b.wav'])
        self.assertFalse(r['passed']);self.assertEqual(r['missing'],['missing.wav'])
        self.assertEqual(r['files'][1]['mismatches'],['rate','channels','frames','quiet'])
    def test_stem_explicit_contract(self):
        r=self.run_tool('stemcontract',rate=2000,channels=1,frames=100)
        self.assertEqual(r['files'][0]['mismatches'],['rate','channels','frames'])
    def test_cue_independent_rounding(self):
        r=self.run_tool('cueclock',np.zeros((10000,1)),bpm=123)
        self.assertEqual(r['cues'][1]['frame'],1951)
        self.assertTrue(all(abs(c['rounding_error_ms'])<=.5+1e-10 for c in r['cues']))
    def test_cue_offset_and_skip(self):
        r=self.run_tool('cueclock',np.zeros((10000,1)),offset_seconds=1,every_bars=2)
        self.assertEqual([c['frame'] for c in r['cues']],[1000,5000,9000])
        self.assertEqual([c['bar'] for c in r['cues']],[1,3,5])
    def test_cue_count_limit(self):
        with self.assertRaises(ValueError):self.run_tool('cueclock',np.zeros((1000,1)),bpm=1e9)
    def test_render_identical(self):
        r,_=analyze('renderdelta',[self.a,self.a],DEFAULTS)
        self.assertTrue(r['identical']);self.assertEqual(r['changed_windows'],[])
    def test_render_changed_window(self):
        b={**self.a,'samples':self.a['samples'].copy()};b['samples'][500:510]+=.01
        r,_=analyze('renderdelta',[self.a,b],DEFAULTS)
        self.assertEqual(len(r['changed_windows']),1);self.assertEqual(r['changed_windows'][0]['start_seconds'],.5)
    def test_render_positive_and_negative_offsets(self):
        y=np.r_[np.zeros((5,2)),self.a['samples']]
        r,_=analyze('renderdelta',[self.a,{'samples':y,'rate':1000}],{**DEFAULTS,'offset_frames':5})
        self.assertEqual(r['residual_peak_dbfs'],-240);self.assertEqual(r['unmatched_b_frames'],5)
        r,_=analyze('renderdelta',[{'samples':y,'rate':1000},self.a],{**DEFAULTS,'offset_frames':-5})
        self.assertEqual(r['residual_peak_dbfs'],-240)
    def test_render_format_and_no_overlap(self):
        with self.assertRaises(ValueError):analyze('renderdelta',[self.a,{**self.a,'rate':2000}],DEFAULTS)
        with self.assertRaises(ValueError):analyze('renderdelta',[self.a,self.a],{**DEFAULTS,'offset_frames':3000})
    def assert_nested_close(self,a,b):
        if isinstance(a,dict):
            self.assertEqual(set(a),set(b))
            for k in a:self.assert_nested_close(a[k],b[k])
        elif isinstance(a,list):
            self.assertEqual(len(a),len(b))
            for x,y in zip(a,b):self.assert_nested_close(x,y)
        elif isinstance(a,(float,int)) and not isinstance(a,bool):self.assertAlmostEqual(a,b,places=8)
        else:self.assertEqual(a,b)
    def test_all_ten_cli_python_js_parity(self):
        # An adversarial fixture exercises polarity, gap, rail runs, DC and quiet tail.
        y=self.x.copy();y[:,1]=-y[:,0];y[300:310]=0;y[500:506,0]=1;y[1200:1300]+=.02;y[-200:]=0
        write_wav(self.p/'fault.wav',y,1000)
        for tool in TOOLS:
            with self.subTest(tool=tool):
                args=[self.p/'fault.wav']
                if tool in ('renderdelta','stemcontract'):args.append(self.p/'a.wav')
                py=self.cli(tool,*args);js=self.cli(tool,*args,js=True)
                self.assertEqual(py.returncode,js.returncode,js.stderr)
                self.assert_nested_close(json.loads(py.stdout),json.loads(js.stdout))
    def test_custom_flags_parity(self):
        cases={'loopbudget':['--bpm','127','--beats','3','--bars','2'], 'tailbudget':['--threshold-db','-50','--pad-ms','5'], 'monoledger':['--window-ms','37','--loss-db','2'], 'gapcontext':['--min-ms','1','--flank-ms','5','--active-db','-60'], 'railruns':['--threshold-db','-30','--min-run','2'], 'dcjourney':['--window-ms','37','--threshold-db','-50'], 'gainbudget':['--gain-db','2','--ceiling-db','-3'], 'stemcontract':['--expect','a.wav','--expect','missing.wav','--require-active','--channels','1'], 'cueclock':['--bpm','137','--every-bars','2','--offset-seconds','.1'], 'renderdelta':['--offset-frames','5','--threshold-db','-50','--window-ms','37']}
        for tool,flags in cases.items():
            with self.subTest(tool=tool):
                args=[self.p/'a.wav']+([self.p/'a.wav'] if tool=='renderdelta' else [])+flags
                py=self.cli(tool,*args);js=self.cli(tool,*args,js=True)
                self.assertEqual(py.returncode,js.returncode,js.stderr)
                self.assert_nested_close(json.loads(py.stdout),json.loads(js.stdout))
    def test_all_audio_exports_match(self):
        for tool in ('tailbudget','monoledger','dcjourney','gainbudget','renderdelta'):
            with self.subTest(tool=tool):
                args=[self.p/'a.wav']+([self.p/'a.wav'] if tool=='renderdelta' else [])
                p=self.p/f'{tool}-py.wav';j=self.p/f'{tool}-js.wav'
                py=self.cli(tool,*args,'--audio-out',p);js=self.cli(tool,*args,'--audio-out',j,js=True)
                self.assertEqual(py.returncode,0,py.stderr);self.assertEqual(js.returncode,0,js.stderr)
                self.assertEqual(p.read_bytes(),j.read_bytes());read_wav(p)
    def test_output_and_overwrite_guards_both(self):
        for js in (False,True):
            report=self.p/f'report-{js}.json'
            self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--output',report,js=js).returncode,0)
            self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--output',report,js=js).returncode,2)
            self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--output',report,'--overwrite',js=js).returncode,0)
            self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--output',self.p/'a.wav','--overwrite',js=js).returncode,2)
            self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--audio-out',report,'--output',report,js=js).returncode,2)
    def test_cli_invalid_options_both(self):
        for js in (False,True):
            for tool,flag,value in [('loopbudget','--bpm','0'),('cueclock','--beats','2.5'),('tailbudget','--pad-ms','-1'),('dcjourney','--window-ms','0'),('gainbudget','--gain-db','nan'),('railruns','--threshold-db','5')]:
                self.assertEqual(self.cli(tool,self.p/'a.wav',flag,value,js=js).returncode,2)
            self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--nonsense','1',js=js).returncode,2)
            self.assertEqual(self.cli('renderdelta',self.p/'a.wav',js=js).returncode,2)
            self.assertEqual(self.cli('loopbudget',self.p/'a.wav',self.p/'a.wav',js=js).returncode,2)
            self.assertEqual(self.cli('stemcontract',self.p/'a.wav',self.p/'a.wav',js=js).returncode,2)
    def test_gain_export_ceiling(self):
        for js in (False,True):self.assertEqual(self.cli('gainbudget',self.p/'a.wav','--gain-db','20','--audio-out',self.p/'unsafe.wav',js=js).returncode,2)
    def test_help_and_missing_file(self):
        for js in (False,True):
            for tool in TOOLS:
                self.assertEqual(self.cli(tool,'--help',js=js).returncode,0)
                self.assertEqual(self.cli(tool,self.p/'missing.wav',js=js).returncode,2)
    def test_truncated_and_invalid_wav_both(self):
        b=(self.p/'a.wav').read_bytes()
        cases=[b'',b'not audio',b[:-1],b[:12],b[:22]+b'\x00\x00'+b[24:]]
        for i,bad in enumerate(cases):
            f=self.p/f'bad{i}.wav';f.write_bytes(bad)
            for js in (False,True):self.assertEqual(self.cli('gainbudget',f,js=js).returncode,2)
    def test_formats_and_float_nonfinite(self):
        for code,bits,payload in [(1,8,bytes([0,128,255,128])),(1,16,struct.pack('<hhhh',-32768,0,32767,0)),(1,24,b'\x00\x00\x80\x00\x00\x00\xff\xff\x7f\x00\x00\x00'),(1,32,struct.pack('<iiii',-2147483648,0,2147483647,0)),(3,32,struct.pack('<ffff',-.5,0,.5,0)),(3,64,struct.pack('<dddd',-.5,0,.5,0))]:
            align=bits//8
            body=b'WAVEfmt '+struct.pack('<IHHIIHH',16,code,1,1000,1000*align,align,bits)+b'data'+struct.pack('<I',len(payload))+payload
            f=self.p/f'f{code}-{bits}.wav';f.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
            py=self.cli('gainbudget',f);js=self.cli('gainbudget',f,js=True)
            self.assertEqual(py.returncode,0,py.stderr);self.assert_nested_close(json.loads(py.stdout),json.loads(js.stdout))
        raw=bytearray(f.read_bytes());struct.pack_into('<d',raw,44,float('nan'));f.write_bytes(raw)
        for js in (False,True):self.assertEqual(self.cli('gainbudget',f,js=js).returncode,2)
    def test_extensible_pcm_and_float(self):
        for code,bits,payload in [(1,24,b'\x00\x00\x80\x00\x00\x00\xff\xff\x7f\x00\x00\x00'),(3,32,struct.pack('<ffff',-.5,0,.5,0))]:
            align=bits//8;guid=struct.pack('<I',code)+bytes.fromhex('00001000800000aa00389b71')
            fmt=struct.pack('<HHIIHHHHI',65534,1,1000,1000*align,align,bits,22,bits,1)+guid
            body=b'WAVEfmt '+struct.pack('<I',40)+fmt+b'data'+struct.pack('<I',len(payload))+payload
            f=self.p/'ext.wav';f.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
            py=self.cli('gainbudget',f);js=self.cli('gainbudget',f,js=True)
            self.assertEqual(py.returncode,0,py.stderr);self.assertEqual(js.returncode,0,js.stderr)
            self.assert_nested_close(json.loads(py.stdout),json.loads(js.stdout))
            bad=bytearray(f.read_bytes());struct.pack_into('<H',bad,38,bits-1);f.write_bytes(bad)
            for use_js in (False,True):self.assertEqual(self.cli('gainbudget',f,js=use_js).returncode,2)
    def test_equals_flag_forms(self):
        for tool in ('railruns','dcjourney'):
            py=self.cli(tool,self.p/'a.wav','--threshold-db=-20');js=self.cli(tool,self.p/'a.wav','--threshold-db=-20',js=True)
            self.assertEqual(py.returncode,0,py.stderr);self.assertEqual(js.returncode,0,js.stderr)
            self.assert_nested_close(json.loads(py.stdout),json.loads(js.stdout))
    def test_unified_entry_points(self):
        for language,entry in [('python','python/drift_audio.py'),('node','site/js/cli.mjs')]:
            executable=sys.executable if language=='python' else 'node'
            r=subprocess.run([executable,str(ROOT/entry),'loopbudget',str(self.p/'a.wav'),'--bpm','120'],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(r.stdout)['frame_error'],0)
    def test_shell_launchers(self):
        import os, shutil
        spaced=self.p/'a file.wav';spaced.write_bytes((self.p/'a.wav').read_bytes())
        if os.name=='nt':
            commands=[['cmd','/c',str(ROOT/'python/drift-audio.cmd'), 'loopbudget',str(spaced),'--bpm','120'], ['powershell','-NoProfile','-File',str(ROOT/'python/drift-audio.ps1'),'loopbudget',str(spaced),'--bpm','120']]
        elif shutil.which('bash'):commands=[['bash',str(ROOT/'python/drift-audio.sh'),'loopbudget',str(spaced),'--bpm','120']]
        else:self.skipTest('No compatible shell')
        for command in commands:
            r=subprocess.run(command,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(r.stdout)['frame_error'],0)
    def test_pathological_numeric_values(self):
        for js in (False,True):
            for args in [('--bpm','1e-300'),('--bars','100000000000'),('--bpm','.001','--bars','1000000000','--beats','1000000000')]:
                r=self.cli('loopbudget',self.p/'a.wav',*args,js=js);self.assertEqual(r.returncode,2,r.stdout)
        payload=struct.pack('<dd',1e300,0);body=b'WAVEfmt '+struct.pack('<IHHIIHH',16,3,1,1000,8000,8,64)+b'data'+struct.pack('<I',len(payload))+payload
        f=self.p/'extreme.wav';f.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
        for js in (False,True):self.assertEqual(self.cli('gainbudget',f,js=js).returncode,2)
    def test_above_fullscale_export_rejected(self):
        with self.assertRaises(ValueError):write_wav(self.p/'bad.wav',np.ones((2,1))*1.1,1000)
    def test_ancillary_odd_chunk(self):
        b=(self.p/'a.wav').read_bytes();body=b[8:12]+b'JUNK'+struct.pack('<I',3)+b'abc\0'+b[12:]
        f=self.p/'chunk.wav';f.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
        np.testing.assert_array_equal(read_wav(f)['samples'],self.a['samples'])
        py=self.cli('gainbudget',f);js=self.cli('gainbudget',f,js=True)
        self.assert_nested_close(json.loads(py.stdout),json.loads(js.stdout))

if __name__=='__main__':unittest.main(verbosity=2)
