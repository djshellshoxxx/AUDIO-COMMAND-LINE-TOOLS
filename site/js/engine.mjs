/* Circuit Drift Labs — explicit WAV parser and independent JavaScript audio port. */
export const tools = ['loopbudget','tailbudget','monoledger','gapcontext','railruns','dcjourney','gainbudget','stemcontract','cueclock','renderdelta'];
export const defaults = {threshold_db:-60,window_ms:100,bpm:120,beats:4,bars:1,pad_ms:100,loss_db:6,min_ms:2,flank_ms:20,active_db:-35,min_run:3,gain_db:0,ceiling_db:-1,rate:0,channels:0,frames:0,require_active:false,expect:[],every_bars:1,offset_seconds:0,offset_frames:0};
export const flags = {
loopbudget:['bpm','beats','bars'],tailbudget:['threshold_db','pad_ms','window_ms'],monoledger:['window_ms','threshold_db','loss_db'],gapcontext:['threshold_db','min_ms','flank_ms','active_db'],railruns:['threshold_db','min_run'],dcjourney:['window_ms','threshold_db'],gainbudget:['gain_db','ceiling_db'],stemcontract:['rate','channels','frames','threshold_db','require_active','expect'],cueclock:['bpm','beats','every_bars','offset_seconds'],renderdelta:['window_ms','threshold_db','offset_frames']};
export const renderTools = ['tailbudget','monoledger','dcjourney','gainbudget','renderdelta'];
export function options(tool, supplied={}) {
  if (!tools.includes(tool)) throw Error('Unknown tool');
  const o={...defaults,...(tool==='railruns'?{threshold_db:-.1}:{}),...(tool==='dcjourney'?{threshold_db:-40}:{}),...supplied};
  for(const key of flags[tool]) {
    if(key==='expect') {if(!Array.isArray(o[key]) || o[key].some(v=>typeof v!=='string')) throw Error('expect must be a list of basenames'); continue;}
    if(key==='require_active') {if(typeof o[key]!=='boolean') throw Error('require-active must be boolean'); continue;}
    if(!Number.isFinite(o[key])) throw Error(key+' must be finite');
    if(Math.abs(o[key])>1e9)throw Error(key+' magnitude cannot exceed 1e9');
    if(['beats','bars','min_run','rate','channels','frames','every_bars','offset_frames'].includes(key) && !Number.isInteger(o[key])) throw Error(key+' must be an integer');
    if(['window_ms','bpm','beats','bars','loss_db','min_ms','flank_ms','min_run','every_bars'].includes(key) && o[key]<=0) throw Error(key+' must be positive');
    if(['pad_ms','rate','channels','frames','offset_seconds'].includes(key) && o[key]<0) throw Error(key+' cannot be negative');
  }
  if(flags[tool].includes('bpm') && o.bpm<.001)throw Error('bpm must be at least 0.001');
  if(flags[tool].includes('threshold_db') && (o.threshold_db < -240 || o.threshold_db>0)) throw Error('threshold-db must be between -240 and 0');
  if(tool==='gainbudget' && (o.gain_db < -120 || o.gain_db>120 || o.ceiling_db < -120 || o.ceiling_db>0)) throw Error('gain-db range is -120..120; ceiling-db range is -120..0');
  return o;
}
const db=v=>Math.max(-240,20*Math.log10(Math.max(v,1e-12)));
const round=v=>Math.floor(v+.5);
const sum=a=>a.reduce((s,v)=>s+v,0);
const mean=a=>sum(a)/a.length;
const rms=a=>Math.sqrt(mean(a.map(v=>v*v)));
const peak=a=>a.reduce((p,v)=>Math.max(p,Math.abs(v)),0);
const means=x=>x.map(mean);
const flatten=x=>x.flatMap(c=>Array.from(c));
function ranges(mask) { const out=[]; let start=-1; for(let i=0;i<=mask.length;i++) {if(mask[i] && start<0) start=i; if(!mask[i] && start>=0) {out.push([start,i]);start=-1;}}return out; }
export function decodeWav(buffer) {
  if(buffer.byteLength>64*1024*1024) throw Error('WAV exceeds 64 MiB limit; split it before analysis');
  const v=new DataView(buffer);const tag=p=>String.fromCharCode(...new Uint8Array(buffer,p,4));
  if(buffer.byteLength<12 || tag(0)!=='RIFF' || tag(8)!=='WAVE') throw Error('Expected little-endian RIFF WAVE');
  const end=v.getUint32(4,true)+8; if(end!==buffer.byteLength) throw Error('RIFF size does not match file length');
  let fmt=null,data=null,pos=12;
  while(pos<end) {
    if(pos+8>end) throw Error('Truncated WAV chunk header');
    const kind=tag(pos),size=v.getUint32(pos+4,true),start=pos+8;
    if(start+size+(size&1)>end) throw Error('Truncated WAV chunk');
    if(kind==='fmt ') {if(fmt || size<16) throw Error('Invalid or duplicate format chunk');fmt={encoding:v.getUint16(start,true),channels:v.getUint16(start+2,true),rate:v.getUint32(start+4,true),byteRate:v.getUint32(start+8,true),align:v.getUint16(start+12,true),bits:v.getUint16(start+14,true)};
      if(fmt.encoding===0xfffe){
        if(size<40 || v.getUint16(start+16,true)<22 || 18+v.getUint16(start+16,true)>size)throw Error('Invalid extensible WAV header');
        const guid=Array.from(new Uint8Array(buffer,start+24,16)),code=v.getUint32(start+24,true);
        if(v.getUint16(start+18,true)!==fmt.bits || ![1,3].includes(code) || guid.slice(4).join(',')!=='0,0,16,0,128,0,0,170,0,56,155,113')throw Error('Unsupported extensible WAV subformat or valid bits');
        fmt.encoding=code;
      }
    }
    if(kind==='data') {if(data) throw Error('Multiple data chunks unsupported');data={start,size};}
    pos=start+size+(size&1);
  }
  if(!fmt || !data) throw Error('Missing format or data chunk');
  const {encoding,channels,rate,byteRate,align,bits}=fmt;
  if(![1,3].includes(encoding) || channels<1 || channels>32 || rate<1 || rate>384000) throw Error('Unsupported WAV encoding, channel count or sample rate');
  if(encoding===1?![8,16,24,32].includes(bits):![32,64].includes(bits)) throw Error('Unsupported bit depth');
  if(align!==channels*(bits/8) || byteRate!==rate*align || data.size%align) throw Error('Invalid frame alignment or byte rate');
  if(!data.size) throw Error('Empty audio');
  const frames=data.size/align,x=Array.from({length:channels},()=>new Float64Array(frames));
  for(let i=0;i<frames;i++) for(let c=0;c<channels;c++) {
    const p=data.start+i*align+c*bits/8;let z;
    if(encoding===3) z=bits===32?v.getFloat32(p,true):v.getFloat64(p,true);
    else if(bits===8) z=(v.getUint8(p)-128)/128;
    else if(bits===16) z=v.getInt16(p,true)/32768;
    else if(bits===32) z=v.getInt32(p,true)/2147483648;
    else {let t=v.getUint8(p)|(v.getUint8(p+1)<<8)|(v.getUint8(p+2)<<16);if(t&0x800000)t-=0x1000000;z=t/8388608;}
    if(!Number.isFinite(z)) throw Error('Nonfinite samples');if(Math.abs(z)>1e6)throw Error('Sample amplitude exceeds supported range (1e6)');x[c][i]=z;
  }
  return {samples:x,rate,bits,encoding};
}
export function encodeWav(x,rate) {
  const channels=x.length,n=x[0].length;
  if(!n || x.some(c=>c.length!==n || c.some(v=>!Number.isFinite(v) || Math.abs(v)>1))) throw Error('Cannot export empty, nonfinite or above-full-scale audio');
  const buffer=new ArrayBuffer(44+n*channels*2),v=new DataView(buffer),tag=(p,t)=>[...t].forEach((c,i)=>v.setUint8(p+i,c.charCodeAt(0)));
  tag(0,'RIFF');v.setUint32(4,buffer.byteLength-8,true);tag(8,'WAVE');tag(12,'fmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,channels,true);v.setUint32(24,rate,true);v.setUint32(28,rate*channels*2,true);v.setUint16(32,channels*2,true);v.setUint16(34,16,true);tag(36,'data');v.setUint32(40,n*channels*2,true);
  for(let i=0;i<n;i++) for(let c=0;c<channels;c++) {const z=x[c][i];v.setInt16(44+(i*channels+c)*2,Math.sign(z)*Math.floor(Math.abs(z)*32767+.5),true);}
  return buffer;
}
export function analyze(tool,audio,supplied={},names=[]) {
  const o=options(tool,supplied);
  if((tool==='renderdelta' && audio.length!==2) || (tool!=='renderdelta' && tool!=='stemcontract' && audio.length!==1) || !audio.length) throw Error('Incorrect number of input files');
  if(tool==='stemcontract' && new Set(names).size!==names.length) throw Error('Stem basenames must be unique');
  const a=audio[0],x=a.samples,rate=a.rate,n=x[0].length,channels=x.length,threshold=10**(o.threshold_db/20),win=Math.max(1,round(o.window_ms*rate/1000));
  const result={tool,sample_rate:rate,frames:n,channels,duration_seconds:n/rate};let rendered=null;
  const blocks=function*(z) {for(let s=0;s<z[0].length;s+=win)yield [s,z.map(c=>Array.from(c.slice(s,s+win)))];};
  if(tool==='loopbudget') {
    const expected=round(o.bars*o.beats*60/o.bpm*rate);if(!Number.isSafeInteger(expected))throw Error('Expected loop frame count exceeds safe integer range');
    Object.assign(result,{seam_jump_dbfs:x.map(c=>db(Math.abs(c[0]-c[n-1]))),slope_mismatch_dbfs:x.map(c=>db(n>1?Math.abs((c[1]-c[0])-(c[n-1]-c[n-2])):0)),expected_frames:expected,frame_error:n-expected,implied_bpm:o.bars*o.beats*60*rate/n});
  } else if(tool==='tailbudget') {
    let last=0;for(let i=0;i<n;i++)if(x.some(c=>Math.abs(c[i])>threshold))last=i+1;
    const keep=Math.min(n,Math.max(1,last+round(o.pad_ms*rate/1000)));
    Object.assign(result,{last_active_end_seconds:last/rate,removable_frames:n-keep,kept_frames:keep,all_quiet:last===0,ending_rms_dbfs:db(rms(flatten(x.map(c=>c.slice(-win)))))});rendered=x.map(c=>c.slice(0,keep));
  } else if(tool==='monoledger') {
    if(channels!==2) throw Error('monoledger requires exactly two channels'); const rows=[];
    for(const [s,w] of blocks(x)) {
      const energy=mean(flatten(w).map(v=>v*v)),mono=w[0].map((v,i)=>(v+w[1][i])/2),loss=energy?db(Math.sqrt(mean(mono.map(v=>v*v))/energy)):0;
      const lm=mean(w[0]),rm=mean(w[1]),l=w[0].map(v=>v-lm),r=w[1].map(v=>v-rm),denom=Math.sqrt(sum(l.map(v=>v*v))*sum(r.map(v=>v*v)));
      if(db(Math.sqrt(energy))>o.threshold_db && loss < -o.loss_db)rows.push({start_seconds:s/rate,end_seconds:(s+w[0].length)/rate,fold_loss_db:loss,correlation:denom?sum(l.map((v,i)=>v*r[i]))/denom:null});
    }
    rendered=[Float64Array.from(x[0],(v,i)=>(v+x[1][i])/2)];Object.assign(result,{risky_windows:rows,fold_peak_dbfs:db(peak(rendered[0]))});
  } else if(tool==='gapcontext') {
    const quiet=Array.from({length:n},(_,i)=>x.every(c=>Math.abs(c[i])<=threshold)),flank=Math.max(1,round(o.flank_ms*rate/1000)),rows=[];
    for(const [s,e] of ranges(quiet)) {if(s===0 || e===n || (e-s)*1000/rate<o.min_ms)continue;
      const before=db(rms(flatten(x.map(c=>c.slice(Math.max(0,s-flank),s))))),after=db(rms(flatten(x.map(c=>c.slice(e,Math.min(n,e+flank))))));
      if(Math.min(before,after)>=o.active_db)rows.push({start_seconds:s/rate,end_seconds:e/rate,frames:e-s,before_rms_dbfs:before,after_rms_dbfs:after});
    }
    Object.assign(result,{candidates:rows,interpretation:'Candidates can be intentional rests; listen before editing.'});
  } else if(tool==='railruns') {
    const rows=[];x.forEach((c,i)=>{for(const [s,e] of ranges(Array.from(c,v=>Math.abs(v)>=threshold)))if(e-s>=o.min_run)rows.push({channel:i+1,start_seconds:s/rate,end_seconds:e/rate,frames:e-s});});
    Object.assign(result,{events:rows,peak_dbfs:db(Math.max(...x.map(peak))),interpretation:'Threshold hits are not proof of analog clipping.'});
  } else if(tool==='dcjourney') {
    const rows=[];for(const [s,w] of blocks(x)) {const m=means(w);rows.push({start_seconds:s/rate,end_seconds:(s+w[0].length)/rate,mean:m,flagged:Math.max(...m.map(Math.abs))>threshold});}
    const m=x.map(c=>mean(Array.from(c)));Object.assign(result,{channel_mean:m,windows:rows,max_window_offset:rows.reduce((p,row)=>Math.max(p,...row.mean.map(Math.abs)),0)});rendered=x.map((c,i)=>Float64Array.from(c,v=>v-m[i]));
  } else if(tool==='gainbudget') {
    const peaks=x.map(peak),r=x.map(c=>rms(Array.from(c))),p=Math.max(...peaks),factor=10**(o.gain_db/20);
    Object.assign(result,{channel_peak_dbfs:peaks.map(db),channel_rms_dbfs:r.map(db),safe_gain_db:p?o.ceiling_db-db(p):null,requested_gain_db:o.gain_db,fits_ceiling:p*factor<=10**(o.ceiling_db/20),predicted_peak_dbfs:db(p*factor)});rendered=x.map(c=>Float64Array.from(c,v=>v*factor));
  } else if(tool==='stemcontract') {
    const reference={rate:o.rate||rate,channels:o.channels||channels,frames:o.frames||n};
    const files=audio.map((item,i)=>{const y=item.samples,actual={rate:item.rate,channels:y.length,frames:y[0].length},errors=Object.keys(reference).filter(k=>reference[k]!==actual[k]);if(o.require_active && Math.max(...y.map(peak))<=threshold)errors.push('quiet');return {file:names[i]??String(i),actual,mismatches:errors};});
    const missing=[...new Set(o.expect)].filter(v=>!names.includes(v)).sort();Object.assign(result,{contract:reference,files,missing,passed:!missing.length && files.every(f=>!f.mismatches.length)});
  } else if(tool==='cueclock') {
    const step=60/o.bpm*o.beats*o.every_bars,rows=[];if(Math.ceil(n/rate/step)>100000)throw Error('Grid exceeds 100000 cues');
    for(let i=0;o.offset_seconds+i*step<n/rate;i++) {const t=o.offset_seconds+i*step,frame=round(t*rate);if(frame<n)rows.push({bar:1+i*o.every_bars,frame,seconds:frame/rate,rounding_error_ms:(frame/rate-t)*1000});}
    Object.assign(result,{cues:rows,bpm:o.bpm,beats_per_bar:o.beats});
  } else if(tool==='renderdelta') {
    const b=audio[1];if(b.rate!==rate || b.samples.length!==channels)throw Error('Render formats must match; no resampling or channel conversion');
    const shift=o.offset_frames,y=b.samples,xs=Math.max(0,-shift),ys=Math.max(0,shift),count=Math.min(n-xs,y[0].length-ys);if(count<=0)throw Error('Offset leaves no overlap');
    rendered=x.map((c,k)=>Float64Array.from(c.slice(xs,xs+count),(v,i)=>v-y[k][ys+i]));const rows=[];
    for(const [s,w] of blocks(rendered)) {const flat=flatten(w),p=db(peak(flat)),r=db(rms(flat));if(p>o.threshold_db)rows.push({start_seconds:(xs+s)/rate,end_seconds:(xs+s+w[0].length)/rate,peak_dbfs:p,rms_dbfs:r});}
    let residualPeak=0,squares=0;for(const c of rendered)for(const v of c){residualPeak=Math.max(residualPeak,Math.abs(v));squares+=v*v;}Object.assign(result,{offset_frames:shift,compared_frames:count,unmatched_a_frames:n-count,unmatched_b_frames:y[0].length-count,residual_peak_dbfs:db(residualPeak),residual_rms_dbfs:db(Math.sqrt(squares/(count*channels))),changed_windows:rows,identical:n===y[0].length && shift===0 && x.every((c,k)=>c.every((v,i)=>v===y[k][i]))});
  }
  return {report:result,rendered};
}
