import {options as resolveOptions,flags,encodeWav} from './js/engine.mjs';
const $=id=>document.getElementById(id);
const hints={threshold_db:['Threshold (dBFS)','Sample amplitude; zero is full scale.'],window_ms:['Window (ms)','Nonoverlapping analysis windows.'],bpm:['Tempo (BPM)','Quarter-note tempo supplied by you.'],beats:['Beats per bar','Quarter-note beats in each bar.'],bars:['Loop length (bars)','Expected number of complete bars.'],pad_ms:['Keep after activity (ms)','Keep this much existing quiet audio.'],loss_db:['Mono loss limit (dB)','Report loss greater than this amount.'],min_ms:['Minimum gap (ms)','Ignore shorter quiet runs.'],flank_ms:['Context length (ms)','RMS before and after each gap.'],active_db:['Active flank (dBFS)','Both neighboring regions must reach this RMS.'],min_run:['Minimum run (samples)','Consecutive threshold hits per channel.'],gain_db:['Requested gain (dB)','Gain to predict or apply.'],ceiling_db:['Sample peak ceiling (dBFS)','Maximum permitted peak for gain exports.'],rate:['Required rate (Hz)','0 uses the first file’s sample rate.'],channels:['Required channels','0 uses the first file’s channel count.'],frames:['Required frames','0 uses the first file’s frame count.'],require_active:['Require active audio','Reject stems entirely below threshold.'],expect:['Expected filenames','One exact basename per line; extras allowed.'],every_bars:['Cue spacing (bars)','Place a cue every N bars.'],offset_seconds:['Grid origin (seconds)','Bar 1 starts here.'],offset_frames:['B offset (samples)','Positive skips B; negative skips A.']};
let catalog=[],selected=null,demoFiles=[],worker=null,urls=[],revision=0;
function status(message,error=false){$('status').textContent=message;$('status').classList.toggle('error',error);}
function invalidate(){revision++;if(worker){worker.terminate();worker=null;}$('run').disabled=false;$('results').hidden=true;$('preview').pause();$('preview').removeAttribute('src');urls.forEach(URL.revokeObjectURL);urls=[];}
function outputURL(blob){const url=URL.createObjectURL(blob);urls.push(url);return url;}
function select(name,updateHash=true){
  const item=catalog.find(t=>t.name===name)||catalog[0];selected=item;invalidate();
  for(const button of $('tool-list').querySelectorAll('button'))button.setAttribute('aria-current',String(button.dataset.tool===item.name));
  $('tool-index').textContent=`${String(catalog.indexOf(item)+1).padStart(2,'0')} / ${item.title.toUpperCase()}`;
  $('tool-title').textContent=item.name;$('description').textContent=item.description;$('limitations').textContent=item.limit;
  $('command').textContent=`python ${item.name}.py ${item.name==='renderdelta'?'A.wav B.wav':item.name==='stemcontract'?'drums.wav bass.wav':'input.wav'} ${item.example}\nnode ${item.name}.mjs ${item.name==='renderdelta'?'A.wav B.wav':item.name==='stemcontract'?'drums.wav bass.wav':'input.wav'} ${item.example}`;
  $('spec-link').href=`spec/${item.name}.md`;
  $('files').multiple=['stemcontract','renderdelta'].includes(item.name);$('files').value='';demoFiles=[];
  $('file-label').textContent=item.name==='renderdelta'?'Choose two WAV files (A, then B)':item.name==='stemcontract'?'Choose the stem WAV files':'Choose a WAV file';
  $('file-help').textContent=item.name==='renderdelta'?'File order is shown below. Offset is applied to file B.':'Source audio stays on your device.';
  $('filenames').textContent='No files selected.';$('options').replaceChildren();
  const defaults=resolveOptions(item.name);
  for(const key of flags[item.name]) {
    const wrap=document.createElement('div');wrap.className='option';const label=document.createElement('label');label.htmlFor='opt-'+key;label.textContent=hints[key][0];let input;
    if(key==='expect'){input=document.createElement('textarea');input.rows=3;input.placeholder='drums.wav\nbass.wav';input.style.width='100%';}
    else {input=document.createElement('input');input.type=key==='require_active'?'checkbox':'number';if(input.type==='number'){input.value=defaults[key];input.required=true;input.step=['beats','bars','min_run','rate','channels','frames','every_bars','offset_frames'].includes(key)?'1':'any';}}
    input.id='opt-'+key;input.name=key;const help=document.createElement('small');help.id='help-'+key;help.textContent=hints[key][1];input.setAttribute('aria-describedby',help.id);wrap.append(label,input,help);$('options').append(wrap);
  }
  status('Select a file or load a test recording.');if(updateHash)history.replaceState(null,'','#'+item.name);
}
function userOptions(){const o={};for(const key of flags[selected.name]){const el=$('opt-'+key);o[key]=key==='require_active'?el.checked:key==='expect'?el.value.split(/\r?\n/).map(v=>v.trim()).filter(Boolean):Number(el.value);}return o;}
function present(data){
  if(data.error){status(data.error,true);return;}
  const r=data.report;$('results').hidden=false;$('report').textContent=JSON.stringify(r,null,2);$('result-format').textContent=`${r.sample_rate} Hz / ${r.channels} CH`;
  const metricSets={loopbudget:[['Frame error',r.frame_error],['Implied BPM',r.implied_bpm?.toFixed(3)],['Seam jump dBFS',r.seam_jump_dbfs?.map(v=>v.toFixed(2)).join(' / ')]],tailbudget:[['Removed frames',r.removable_frames],['Kept frames',r.kept_frames],['All quiet',r.all_quiet?'Yes':'No']],monoledger:[['Risky windows',r.risky_windows?.length],['Mono peak dBFS',r.fold_peak_dbfs?.toFixed(2)]],gapcontext:[['Gap candidates',r.candidates?.length]],railruns:[['Threshold runs',r.events?.length],['Peak dBFS',r.peak_dbfs?.toFixed(2)]],dcjourney:[['Max local DC',r.max_window_offset?.toFixed(6)],['Flagged windows',r.windows?.filter(w=>w.flagged).length]],gainbudget:[['Fits ceiling',r.fits_ceiling?'Yes':'No'],['Safe gain dB',r.safe_gain_db===null?'Silence':r.safe_gain_db?.toFixed(2)],['Predicted peak dBFS',r.predicted_peak_dbfs?.toFixed(2)]],stemcontract:[['Contract',r.passed?'Passed':'Failed'],['Files',r.files?.length],['Missing names',r.missing?.length]],cueclock:[['Cue points',r.cues?.length],['Tempo BPM',r.bpm]],renderdelta:[['Identical',r.identical?'Yes':'No'],['Changed windows',r.changed_windows?.length],['Residual dBFS',r.residual_peak_dbfs?.toFixed(2)]]};
  $('summary').replaceChildren();for(const [label,value] of [['Duration (seconds)',r.duration_seconds.toFixed(3)],...(metricSets[r.tool]||[])]){const box=document.createElement('div');box.className='metric';const title=document.createElement('span');title.textContent=label;const number=document.createElement('strong');number.textContent=String(value);box.append(title,number);$('summary').append(box);}
  $('save-report').href=outputURL(new Blob([JSON.stringify(r,null,2)+'\n'],{type:'application/json'}));$('save-report').download=r.tool+'-report.json';$('save-audio').hidden=!data.wav;$('preview').hidden=!data.wav;
  if(data.wav){const url=outputURL(new Blob([data.wav],{type:'audio/wav'}));$('save-audio').href=url;$('save-audio').download=r.tool+'-result.wav';$('preview').src=url;}
  status(`Analysis complete.${r.tool==='stemcontract'&&!r.passed?' Stem contract failed; inspect the report.':''}${data.exportError?' WAV export unavailable: '+data.exportError:''}`,!!data.exportError || (r.tool==='stemcontract'&&!r.passed));
}
$('files').addEventListener('change',()=>{demoFiles=[];invalidate();$('filenames').textContent=Array.from($('files').files,(f,i)=>`${i+1}. ${f.name}`).join(' · ')||'No files selected.';status('Ready to analyze.');});
$('options').addEventListener('input',()=>{invalidate();status('Options changed. Run analysis to update the report.');});
$('demo').addEventListener('click',()=>{
  invalidate();const rate=48000,n=rate*2,left=new Float64Array(n),right=new Float64Array(n);
  for(let i=0;i<n;i++){const v=i>n-rate/5?0:.25*Math.sin(i*2*Math.PI*220/rate);left[i]=v;right[i]=i<rate?v:-v;if(i>=rate/2&&i<rate/2+480)left[i]=right[i]=0;if(i>=rate+100&&i<rate+108)left[i]=.999;}
  const wav=encodeWav([left,right],rate);demoFiles=[new File([wav],'demo-A.wav',{type:'audio/wav'})];
  if(['stemcontract','renderdelta'].includes(selected.name)){const b=left.slice();b[500]+=.05;demoFiles.push(new File([encodeWav([b,right],rate)],'demo-B.wav',{type:'audio/wav'}));}
  $('files').value='';$('filenames').textContent=demoFiles.map((f,i)=>`${i+1}. ${f.name}`).join(' · ');status('Test recording loaded: tone, gap, polarity flip, threshold run, and quiet tail. Click Analyze WAV.');
});
$('analyze-form').addEventListener('submit',async e=>{
  e.preventDefault();invalidate();const current=revision,files=demoFiles.length?demoFiles:Array.from($('files').files);
  try{
    if(!files.length)throw Error('Choose a WAV file or load the test recording.');
    if(files.reduce((n,f)=>n+f.size,0)>64*1024*1024)throw Error('Selected files exceed the 64 MiB browser total.');
    const o=resolveOptions(selected.name,userOptions());$('run').disabled=true;status('Reading WAV files…');
    const buffers=await Promise.all(files.map(f=>f.arrayBuffer()));if(current!==revision)return;
    worker=new Worker('worker.mjs',{type:'module'});worker.onmessage=({data})=>{if(current!==revision)return;worker.terminate();worker=null;$('run').disabled=false;present(data);};
    worker.onerror=()=>{if(current!==revision)return;worker.terminate();worker=null;$('run').disabled=false;status('Audio worker failed. Refresh and try a smaller WAV.',true);};
    status('Analyzing audio…');worker.postMessage({tool:selected.name,buffers,options:o,names:files.map(f=>f.name)},buffers);
  }catch(error){if(current===revision){$('run').disabled=false;status(error.message,true);}}
});
window.addEventListener('hashchange',()=>{const name=location.hash.slice(1);if(catalog.some(t=>t.name===name))select(name,false);});
try{const response=await fetch('catalog.json');if(!response.ok)throw Error('Tool catalog unavailable.');catalog=await response.json();for(const [i,item] of catalog.entries()){const button=document.createElement('button');button.type='button';button.dataset.tool=item.name;const number=document.createElement('span');number.textContent=String(i+1).padStart(2,'0');button.append(number,document.createTextNode(item.name));button.addEventListener('click',()=>select(item.name));$('tool-list').append(button);}select(location.hash.slice(1),false);}catch(e){status(e.message,true);$('run').disabled=true;}
