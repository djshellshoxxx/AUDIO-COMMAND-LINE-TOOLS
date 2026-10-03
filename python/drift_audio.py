#!/usr/bin/env python3
"""Circuit Drift Labs: offline PCM WAV workflow utilities. See spec/ for contracts."""
import argparse
import json
import math
import re
from pathlib import Path
import struct
import sys
import numpy as np

TOOLS = ('loopbudget', 'tailbudget', 'monoledger', 'gapcontext', 'railruns',
         'dcjourney', 'gainbudget', 'stemcontract', 'cueclock', 'renderdelta')
MAX_BYTES = 64 * 1024 * 1024
MAX_TOTAL_BYTES = 128 * 1024 * 1024
MAX_ROWS = 100000

def db(value):
    return max(-240.0, 20 * math.log10(max(float(value), 1e-12)))

def read_wav(path):
    p = Path(path)
    if p.stat().st_size > MAX_BYTES:
        raise ValueError('WAV exceeds 64 MiB limit; split it before analysis')
    return decode_wav(p.read_bytes())

def decode_wav(b):
    if len(b) > MAX_BYTES: raise ValueError('WAV exceeds 64 MiB limit; split it before analysis')
    if len(b) < 12 or b[:4] != b'RIFF' or b[8:12] != b'WAVE':
        raise ValueError('Expected little-endian RIFF WAVE')
    end = struct.unpack_from('<I', b, 4)[0] + 8
    if end != len(b):
        raise ValueError('RIFF size does not match file length')
    fmt = payload = None
    pos = 12
    while pos < end:
        if pos + 8 > end:
            raise ValueError('Truncated WAV chunk header')
        kind, size = b[pos:pos+4], struct.unpack_from('<I', b, pos+4)[0]
        start = pos + 8
        if start + size + (size & 1) > end:
            raise ValueError('Truncated WAV chunk')
        if kind == b'fmt ':
            if fmt is not None or size < 16 or size == 17:
                raise ValueError('Invalid or duplicate format chunk')
            if size >= 18 and 18 + struct.unpack_from('<H', b, start+16)[0] > size:
                raise ValueError('Truncated WAV format extension')
            fmt = struct.unpack_from('<HHIIHH', b, start)
            if fmt[0] == 0xFFFE:
                if size < 40 or struct.unpack_from('<H',b,start+16)[0] < 22 or 18+struct.unpack_from('<H',b,start+16)[0] > size:
                    raise ValueError('Invalid extensible WAV header')
                valid_bits=struct.unpack_from('<H',b,start+18)[0]
                guid=b[start+24:start+40]
                if valid_bits != fmt[-1] or guid[4:] != bytes.fromhex('00001000800000aa00389b71') or guid[:4] not in (b'\x01\x00\x00\x00',b'\x03\x00\x00\x00'):
                    raise ValueError('Unsupported extensible WAV subformat or valid bits')
                fmt=(struct.unpack_from('<I',guid)[0],)+fmt[1:]
        if kind == b'data':
            if payload is not None:
                raise ValueError('Multiple data chunks unsupported')
            payload = b[start:start+size]
        pos = start + size + (size & 1)
    if fmt is None or payload is None:
        raise ValueError('Missing format or data chunk')
    code, channels, rate, byte_rate, align, bits = fmt
    if code not in (1, 3) or channels < 1 or channels > 32 or rate < 1 or rate > 384000:
        raise ValueError('Unsupported WAV encoding, channel count or sample rate')
    if (code == 1 and bits not in (8, 16, 24, 32)) or (code == 3 and bits not in (32, 64)):
        raise ValueError('Unsupported bit depth')
    if align != channels * (bits // 8) or byte_rate != rate * align or len(payload) % align:
        raise ValueError('Invalid frame alignment or byte rate')
    if not payload:
        raise ValueError('Empty audio')
    if code == 3:
        x = np.frombuffer(payload, dtype='<f4' if bits == 32 else '<f8').astype(float)
    elif bits == 8:
        x = (np.frombuffer(payload, dtype=np.uint8).astype(float) - 128) / 128
    elif bits == 24:
        u = np.frombuffer(payload, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = u[:, 0] | (u[:, 1] << 8) | (u[:, 2] << 16)
        x = np.where(v & 0x800000, v - 0x1000000, v) / 8388608
    else:
        x = np.frombuffer(payload, dtype='<i2' if bits == 16 else '<i4').astype(float) / (2 ** (bits-1))
    if not np.isfinite(x).all():
        raise ValueError('Nonfinite samples')
    if np.max(np.abs(x)) > 1e6:
        raise ValueError('Sample amplitude exceeds supported range (1e6)')
    return {'samples': x.reshape(-1, channels), 'rate': rate, 'bits': bits, 'encoding': code}

def write_wav(path, x, rate, overwrite=False, ceiling_db=None):
    if not len(x) or not np.isfinite(x).all() or np.max(np.abs(x)) > 1:
        raise ValueError('Cannot export empty, nonfinite or above-full-scale audio')
    # Symmetric quantization keeps both ports deterministic. Metadata is not copied.
    q = np.sign(x) * np.floor(np.abs(x) * 32767 + .5)
    if ceiling_db is not None:
        # The decoded 16-bit samples use a 32768 denominator. Bound rounding too.
        limit = min(32767, math.floor(10 ** (ceiling_db / 20) * 32768))
        q = np.clip(q, -limit, limit)
    payload = q.astype('<i2').tobytes()
    align = x.shape[1] * 2
    header = b'RIFF' + struct.pack('<I', 36 + len(payload)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, x.shape[1], rate, rate*align, align, 16) + b'data' + struct.pack('<I', len(payload))
    with open(path, 'wb' if overwrite else 'xb') as f:
        f.write(header + payload)

def spans(mask):
    # Yield runs in bounded chunks instead of allocating a list for every transition.
    start = None
    previous = False
    for offset in range(0, len(mask), 65536):
        block = mask[offset:offset+65536]
        edges = np.flatnonzero(np.diff(np.r_[previous, block].astype(np.int8)))
        for edge in edges:
            frame = offset + int(edge)
            if block[edge]: start = frame
            else:
                yield start, frame
                start = None
        previous = bool(block[-1])
    if start is not None: yield start, len(mask)

def check_windows(frames, size):
    if math.ceil(frames / size) > MAX_ROWS:
        raise ValueError('Analysis exceeds 100000 windows; increase --window-ms or split the audio')

def append_row(rows, row):
    if len(rows) >= MAX_ROWS:
        raise ValueError('Report exceeds 100000 entries; increase minimum run/gap duration or split the audio')
    rows.append(row)

def context_rms(x, prefix, start, end):
    energy = float(prefix[end] - prefix[start])
    # Quiet material after a loud section can disappear in prefix subtraction.
    if energy <= 1e-8 * max(float(prefix[start]), float(prefix[end])):
        return float(np.sqrt(np.mean(x[start:end] ** 2)))
    return math.sqrt(max(0., energy) / (end-start))

def windows(x, size):
    for start in range(0, len(x), size):
        yield start, x[start:start+size]

def analyze(tool, audio, o, names=None):
    validate(tool, o)
    if not audio or (tool == 'renderdelta' and len(audio) != 2) or (tool not in ('stemcontract','renderdelta') and len(audio) != 1):
        raise ValueError('Incorrect number of input files')
    a = audio[0]; x = a['samples']; rate = a['rate']; n, channels = x.shape
    threshold = 10 ** (o['threshold_db'] / 20)
    win = max(1, round_half(o['window_ms'] * rate / 1000))
    result = {'tool': tool, 'sample_rate': rate, 'frames': n, 'channels': channels, 'duration_seconds': n/rate}
    rendered = None
    if tool == 'loopbudget':
        expected = round_half(o['bars'] * o['beats'] * 60 / o['bpm'] * rate)
        if expected > 9007199254740991: raise ValueError('Expected loop frame count exceeds safe integer range')
        jump = np.abs(x[0] - x[-1])
        slope = np.abs((x[1]-x[0]) - (x[-1]-x[-2])) if n > 1 else np.zeros(channels)
        result.update(seam_jump_dbfs=[db(v) for v in jump], slope_mismatch_dbfs=[db(v) for v in slope], expected_frames=expected, frame_error=n-expected, implied_bpm=o['bars']*o['beats']*60*rate/n)
    elif tool == 'tailbudget':
        active = np.flatnonzero(np.max(np.abs(x), axis=1) > threshold)
        last = int(active[-1])+1 if len(active) else 0
        keep = min(n, max(1, last + round_half(o['pad_ms']*rate/1000)))
        result.update(last_active_end_seconds=last/rate, removable_frames=n-keep, kept_frames=keep, all_quiet=not len(active), ending_rms_dbfs=db(np.sqrt(np.mean(x[-win:]**2))))
        rendered = x[:keep].copy()
    elif tool == 'monoledger':
        if channels != 2:
            raise ValueError('monoledger requires exactly two channels')
        rows = []
        check_windows(n, win)
        for start, w in windows(x, win):
            energy = float(np.mean(w*w)); mono = float(np.mean(np.mean(w, axis=1)**2))
            loss = db(math.sqrt(mono/energy)) if energy else 0.0
            left, right = w[:,0]-np.mean(w[:,0]), w[:,1]-np.mean(w[:,1])
            denom = math.sqrt(float(np.sum(left*left)*np.sum(right*right)))
            variable = np.ptp(w[:,0]) > 0 and np.ptp(w[:,1]) > 0
            corr = float(np.clip(np.sum(left*right)/denom, -1, 1)) if denom and variable else None
            if db(math.sqrt(energy)) > o['threshold_db'] and loss < -o['loss_db']:
                append_row(rows, {'start_seconds':start/rate,'end_seconds':(start+len(w))/rate,'fold_loss_db':loss,'correlation':corr})
        result.update(risky_windows=rows, fold_peak_dbfs=db(np.max(np.abs(np.mean(x,axis=1)))))
        rendered = np.mean(x,axis=1,keepdims=True)
    elif tool == 'gapcontext':
        quiet = np.max(np.abs(x),axis=1) <= threshold
        flank = max(1, round_half(o['flank_ms']*rate/1000)); rows=[]
        power = np.einsum('ij,ij->i', x, x) / channels
        prefix = np.r_[0., np.cumsum(power)]
        for start,end in spans(quiet):
            if start == 0 or end == n or (end-start)*1000/rate < o['min_ms']:
                continue
            before_start = max(0, start-flank); after_end = min(n, end+flank)
            before = db(context_rms(x, prefix, before_start, start))
            after = db(context_rms(x, prefix, end, after_end))
            if min(before,after) >= o['active_db']:
                append_row(rows, {'start_seconds':int(start)/rate,'end_seconds':int(end)/rate,'frames':int(end-start),'before_rms_dbfs':before,'after_rms_dbfs':after})
        result.update(candidates=rows, interpretation='Candidates can be intentional rests; listen before editing.')
    elif tool == 'railruns':
        rows=[]
        for c in range(channels):
            for start,end in spans(np.abs(x[:,c]) >= threshold):
                if end-start >= o['min_run']:
                    append_row(rows, {'channel':c+1,'start_seconds':int(start)/rate,'end_seconds':int(end)/rate,'frames':int(end-start)})
        result.update(events=rows, peak_dbfs=db(np.max(np.abs(x))), interpretation='Threshold hits are not proof of analog clipping.')
    elif tool == 'dcjourney':
        rows=[]
        check_windows(n, win)
        for start,w in windows(x,win):
            means=np.mean(w,axis=0)
            rows.append({'start_seconds':start/rate,'end_seconds':(start+len(w))/rate,'mean':means.tolist(),'flagged':bool(np.max(np.abs(means)) > threshold)})
        means=np.mean(x,axis=0)
        result.update(channel_mean=means.tolist(), windows=rows, max_window_offset=max(abs(v) for row in rows for v in row['mean']))
        rendered=x-means
    elif tool == 'gainbudget':
        peaks=np.max(np.abs(x),axis=0); rms=np.sqrt(np.mean(x*x,axis=0))
        peak=float(np.max(peaks)); safe=o['ceiling_db']-20*math.log10(peak) if peak else None
        result.update(channel_peak_dbfs=[db(v) for v in peaks], channel_rms_dbfs=[db(v) for v in rms], safe_gain_db=safe, requested_gain_db=o['gain_db'], fits_ceiling=peak*10**(o['gain_db']/20) <= 10**(o['ceiling_db']/20), predicted_peak_dbfs=db(peak*10**(o['gain_db']/20)))
        rendered=x*10**(o['gain_db']/20)
    elif tool == 'stemcontract':
        reference={'rate':o['rate'] or rate,'channels':o['channels'] or channels,'frames':o['frames'] or n}
        files=[]
        for i,item in enumerate(audio):
            y=item['samples']; actual={'rate':item['rate'],'channels':y.shape[1],'frames':len(y)}
            errors=[key for key in reference if reference[key]!=actual[key]]
            if o['require_active'] and np.max(np.abs(y)) <= threshold:
                errors.append('quiet')
            files.append({'file':names[i] if names else str(i),'actual':actual,'mismatches':errors})
        missing=sorted(set(o.get('expect',[]))-set(names or []))
        result.update(contract=reference, files=files, missing=missing, passed=not missing and not any(f['mismatches'] for f in files))
    elif tool == 'cueclock':
        step=60/o['bpm']*o['beats']*o['every_bars']; start=o['offset_seconds']; rows=[]; i=0
        limit_time = start + MAX_ROWS * step
        if limit_time < n/rate and round_half(limit_time*rate) < n:
            raise ValueError('Grid exceeds 100000 cues')
        while start+i*step < n/rate:
            t=start+i*step; frame=round_half(t*rate)
            if frame >= n: break
            rows.append({'bar':1+i*o['every_bars'],'frame':frame,'seconds':frame/rate,'rounding_error_ms':(frame/rate-t)*1000})
            i+=1
        result.update(cues=rows, bpm=o['bpm'], beats_per_bar=o['beats'])
    elif tool == 'renderdelta':
        if len(audio)!=2:
            raise ValueError('renderdelta requires exactly two files')
        b=audio[1]
        if b['rate']!=rate or b['samples'].shape[1]!=channels:
            raise ValueError('Render formats must match; no resampling or channel conversion')
        shift=o['offset_frames']; y=b['samples']; xs=max(0,-shift); ys=max(0,shift)
        count=min(n-xs,len(y)-ys)
        if count<=0:
            raise ValueError('Offset leaves no overlap')
        check_windows(count, win)
        residual=x[xs:xs+count]-y[ys:ys+count]; rows=[]
        for start,w in windows(residual,win):
            peak=db(np.max(np.abs(w))); rms=db(np.sqrt(np.mean(w*w)))
            if peak > o['threshold_db']:
                rows.append({'start_seconds':(xs+start)/rate,'end_seconds':(xs+start+len(w))/rate,'peak_dbfs':peak,'rms_dbfs':rms})
        result.update(offset_frames=shift, compared_frames=count, unmatched_a_frames=n-count, unmatched_b_frames=len(y)-count, residual_peak_dbfs=db(np.max(np.abs(residual))), residual_rms_dbfs=db(np.sqrt(np.mean(residual*residual))), changed_windows=rows, identical=bool(n==len(y) and shift==0 and np.array_equal(x,y)))
        rendered=residual
    return result,rendered

def round_half(v):
    return math.floor(v+.5)

DEFAULTS={'threshold_db':-60.,'window_ms':100.,'bpm':120.,'beats':4,'bars':1,'pad_ms':100.,'loss_db':6.,'min_ms':2.,'flank_ms':20.,'active_db':-35.,'min_run':3,'gain_db':0.,'ceiling_db':-1.,'rate':0,'channels':0,'frames':0,'require_active':False,'expect':[],'every_bars':1,'offset_seconds':0.,'offset_frames':0}
FLAGS={
'loopbudget':['bpm','beats','bars'], 'tailbudget':['threshold_db','pad_ms','window_ms'],
'monoledger':['window_ms','threshold_db','loss_db'], 'gapcontext':['threshold_db','min_ms','flank_ms','active_db'],
'railruns':['threshold_db','min_run'], 'dcjourney':['window_ms','threshold_db'],
'gainbudget':['gain_db','ceiling_db'], 'stemcontract':['rate','channels','frames','threshold_db','require_active','expect'],
'cueclock':['bpm','beats','every_bars','offset_seconds'], 'renderdelta':['window_ms','threshold_db','offset_frames']}
RENDER_TOOLS={'tailbudget','monoledger','dcjourney','gainbudget','renderdelta'}

def validate(tool,o):
    if tool not in FLAGS: raise ValueError('Unknown tool')
    if 'expect' in FLAGS[tool] and any(not isinstance(v,str) or not v for v in o['expect']):
        raise ValueError('Expected names must be nonempty basenames')
    for key in FLAGS[tool]:
        value=o[key]
        if isinstance(value,(float,int)) and not math.isfinite(value):
            raise ValueError(key+' must be finite')
        if isinstance(value,(float,int)) and abs(value)>1e9: raise ValueError(key+' magnitude cannot exceed 1e9')
    for key in ('window_ms','bpm','beats','bars','loss_db','min_ms','flank_ms','min_run','every_bars'):
        if key in FLAGS[tool] and o[key]<=0:
            raise ValueError(key+' must be positive')
    if 'bpm' in FLAGS[tool] and o['bpm'] < .001: raise ValueError('bpm must be at least 0.001')
    for key in ('pad_ms','rate','channels','frames','offset_seconds'):
        if key in FLAGS[tool] and o[key]<0:
            raise ValueError(key+' cannot be negative')
    for key in ('threshold_db','active_db'):
        if key in FLAGS[tool] and not -240 <= o[key] <= 0:
            raise ValueError(key.replace('_','-')+' must be between -240 and 0')
    if tool=='gainbudget' and (not -120<=o['gain_db']<=120 or not -120<=o['ceiling_db']<=0):
        raise ValueError('gain-db range is -120..120; ceiling-db range is -120..0')

FLAG_HELP = {
    'threshold_db':'Sample amplitude threshold in dBFS',
    'window_ms':'Nonoverlapping analysis window in milliseconds',
    'bpm':'Quarter-note tempo in beats per minute',
    'beats':'Quarter-note beats per bar', 'bars':'Expected loop length in bars',
    'pad_ms':'Keep this much existing quiet tail after the last active frame',
    'loss_db':'Report mono energy losses greater than this many dB',
    'min_ms':'Minimum interior quiet gap in milliseconds',
    'flank_ms':'RMS context before and after each gap, in milliseconds',
    'active_db':'Required RMS of both neighboring regions in dBFS',
    'min_run':'Minimum consecutive threshold hits per channel, in samples',
    'gain_db':'Requested gain in dB', 'ceiling_db':'Maximum decoded export sample peak in dBFS',
    'rate':'Required sample rate; 0 inherits the first file',
    'channels':'Required channel count; 0 inherits the first file',
    'frames':'Required frame count; 0 inherits the first file',
    'every_bars':'Cue spacing in bars', 'offset_seconds':'Bar 1 origin in seconds',
    'offset_frames':'Positive skips samples in B; negative skips samples in A',
}

def decimal_integer(value):
    if not re.fullmatch(r'[+-]?[0-9]+',value.strip()): raise ValueError('Expected a decimal integer')
    return int(value)

def decimal_float(value):
    if not re.fullmatch(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?',value.strip()):
        raise ValueError('Expected a decimal number')
    return float(value)

def main(argv=None, fixed_tool=None):
    parser=argparse.ArgumentParser(description=__doc__, allow_abbrev=False, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    if fixed_tool:
        parser.prog=fixed_tool
        tool=fixed_tool
    else:
        if argv is None: argv=sys.argv[1:]
        if not argv or argv[0] not in TOOLS:
            parser.add_argument('tool',choices=TOOLS); parser.parse_args(argv); return 2
        tool=argv[0]; argv=argv[1:]; parser.prog+=' '+tool
    parser.add_argument('input',nargs='+',help='PCM or float RIFF WAV paths')
    parser.add_argument('-o','--output',help='JSON report path (stdout if omitted)')
    parser.add_argument('--overwrite',action='store_true',help='Allow replacing output files, never inputs')
    if tool in RENDER_TOOLS: parser.add_argument('--audio-out',help='Optional 16-bit WAV result, metadata omitted')
    for key in FLAGS[tool]:
        default=DEFAULTS[key]
        if key=='threshold_db' and tool in ('railruns','dcjourney'): default=-.1 if tool=='railruns' else -40.
        opts={'default':default}
        if key=='require_active': opts={'action':'store_true','help':'Reject stems entirely below the activity threshold'}
        elif key=='expect': opts={'action':'append','default':[],'help':'Expected basename; repeat to specify a set'}
        else:
            opts['type']=decimal_integer if isinstance(default,int) else decimal_float
            opts['help']=FLAG_HELP[key]
        parser.add_argument('--'+key.replace('_','-'),**opts)
    args=parser.parse_args(argv); o=dict(DEFAULTS); o.update(vars(args))
    try:
        validate(tool,o)
        for value in (args.output, getattr(args,'audio_out',None)):
            if value is not None and not value: raise ValueError('Output paths cannot be empty')
        if tool not in ('stemcontract','renderdelta') and len(args.input)!=1:
            raise ValueError('This tool takes one input file')
        if tool=='renderdelta' and len(args.input)!=2: raise ValueError('renderdelta takes two input files')
        inputs={Path(p).resolve() for p in args.input}
        outputs=[Path(p).resolve() for p in (args.output,getattr(args,'audio_out',None)) if p]
        same_input=any(p.exists() and source.exists() and p.samefile(source) for p in outputs for source in inputs)
        same_output=any(p.exists() and q.exists() and p.samefile(q) for i,p in enumerate(outputs) for q in outputs[i+1:])
        if len(set(outputs))!=len(outputs) or any(p in inputs for p in outputs) or same_input or same_output:
            raise ValueError('Output paths must be distinct and cannot replace inputs')
        for p in outputs:
            if not p.parent.is_dir(): raise ValueError('Output parent directory does not exist: '+str(p.parent))
            if p.exists() and not p.is_file(): raise ValueError('Output must be a regular file: '+str(p))
        if not args.overwrite and any(p.exists() for p in outputs): raise ValueError('Output exists; choose a new path or --overwrite')
        names=[Path(p).name for p in args.input]
        if tool=='stemcontract' and len(set(names))!=len(names): raise ValueError('Stem basenames must be unique')
        if sum(Path(p).stat().st_size for p in args.input) > MAX_TOTAL_BYTES:
            raise ValueError('Selected files exceed the 128 MiB CLI total; split the batch')
        audio=[read_wav(p) for p in args.input]
        report,rendered=analyze(tool,audio,o,names)
        report['inputs']=names
        data=json.dumps(report,indent=2,allow_nan=False)+'\n'
        if getattr(args,'audio_out',None) and tool=='gainbudget' and not report['fits_ceiling']: raise ValueError('Requested gain exceeds ceiling; reduce --gain-db')
        if getattr(args,'audio_out',None): write_wav(args.audio_out,rendered,audio[0]['rate'],args.overwrite,o['ceiling_db'] if tool=='gainbudget' else None)
        if args.output:
            with open(args.output,'w' if args.overwrite else 'x',encoding='utf-8') as f: f.write(data)
        else: print(data,end='')
        return 1 if tool=='stemcontract' and not report['passed'] else 0
    except MemoryError:
        print('error: Not enough memory; use a smaller file or batch',file=sys.stderr); return 2
    except (OSError,ValueError,OverflowError) as error:
        print('error: '+str(error),file=sys.stderr); return 2

if __name__=='__main__': sys.exit(main())
