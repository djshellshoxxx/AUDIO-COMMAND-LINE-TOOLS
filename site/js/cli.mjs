#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {tools,flags,integerFlags,renderTools,options,checkInputCount,decodeWav,encodeWav,analyze} from './engine.mjs';

const flagHelp={
  threshold_db:'Sample amplitude threshold in dBFS',window_ms:'Nonoverlapping window in milliseconds',
  bpm:'Quarter-note tempo in beats per minute',beats:'Quarter-note beats per bar',bars:'Expected loop length in bars',
  pad_ms:'Keep existing quiet tail after activity, in milliseconds',loss_db:'Report mono energy loss greater than this many dB',
  min_ms:'Minimum interior gap in milliseconds',flank_ms:'RMS context length before and after gaps',active_db:'Required RMS of both flanks in dBFS',
  min_run:'Minimum consecutive threshold hits per channel',gain_db:'Requested gain in dB',ceiling_db:'Maximum decoded export sample peak in dBFS',
  rate:'Required sample rate; 0 inherits first file',channels:'Required channel count; 0 inherits first file',frames:'Required frames; 0 inherits first file',
  require_active:'Reject stems entirely below threshold',expect:'Expected basename; repeat for a set',every_bars:'Cue spacing in bars',
  offset_seconds:'Bar 1 origin in seconds',offset_frames:'Positive skips samples in B; negative skips samples in A',
};
function help(tool,fixed){
  if(!tools.includes(tool)){console.log('Usage: node cli.mjs TOOL input.wav [flags]\nTools: '+tools.join(', '));return;}
  console.log(`Usage: node ${fixed?tool+'.mjs':'cli.mjs '+tool} input.wav [second.wav] [flags]\nReports are JSON; exit codes 0=complete, 1=failed stem contract, 2=error.\n  -h, --help                 Show this help\n  -o, --output PATH          JSON report path; omitted prints to stdout\n  --overwrite                Replace output files, never inputs`);
  if(renderTools.includes(tool))console.log('  --audio-out PATH           Optional 16-bit WAV export');
  const d=options(tool);
  for(const key of flags[tool])console.log(`  --${key.replaceAll('_','-')}${key==='require_active'?'':' VALUE'}\n      ${flagHelp[key]} (default: ${JSON.stringify(d[key])})`);
}
function canonicalPath(file){
  let current=path.resolve(file);const suffix=[];
  while(!fs.existsSync(current)){
    let entry;try{entry=fs.lstatSync(current);}catch(e){if(e.code!=='ENOENT'&&e.code!=='ENOTDIR')throw e;}
    if(entry?.isSymbolicLink())throw Error('Output contains a dangling symlink: '+current);
    const parent=path.dirname(current);if(parent===current)break;
    suffix.unshift(path.basename(current));current=parent;
  }
  return path.join(fs.realpathSync(current),...suffix);
}
function sameFile(a,b){
  if(!fs.existsSync(a)||!fs.existsSync(b))return false;
  const x=fs.statSync(a,{bigint:true}),y=fs.statSync(b,{bigint:true});return x.dev===y.dev && x.ino===y.ino;
}
function numberValue(key,value){
  const pattern=integerFlags.includes(key)?/^[+-]?[0-9]+$/:/^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/;
  if(!pattern.test(value.trim()))throw Error(`Expected a decimal ${integerFlags.includes(key)?'integer':'number'} for --${key.replaceAll('_','-')}`);
  return Number(value);
}
export function main(argv=process.argv.slice(2),fixedTool=null){
  argv=[...argv];const tool=fixedTool||argv.shift();
  if(!tools.includes(tool)){help(tool,fixedTool);return tool==='--help'||tool==='-h'?0:2;}
  const supplied={},inputs=[];let output=null,audioOut=null,overwrite=false;
  try{
    for(let i=0;i<argv.length;i++){
      const token=argv[i];
      if(token==='--'){inputs.push(...argv.slice(i+1));break;}
      if(token==='--help'||token==='-h'){help(tool,fixedTool);return 0;}
      if(!token.startsWith('-')){inputs.push(token);continue;}
      const equal=token.indexOf('='),flag=equal<0?token:token.slice(0,equal),key=flag.replace(/^--/,'').replaceAll('-','_');
      if(flag==='--overwrite'||(flag==='--require-active'&&flags[tool].includes('require_active'))){
        if(equal>=0)throw Error('Boolean flags do not take a value: '+flag);
        if(flag==='--overwrite')overwrite=true;else supplied.require_active=true;continue;
      }
      if(!(flag==='-o'||flag==='--output'||(flag==='--audio-out'&&renderTools.includes(tool))||(flags[tool].includes(key)&&flag==='--'+key.replaceAll('_','-'))))throw Error('Unknown flag '+flag);
      let value;
      if(equal>=0)value=token.slice(equal+1);
      else{
        if(i+1>=argv.length)throw Error('Missing value for '+flag);
        value=argv[++i];
        const numeric=flags[tool].includes(key)&&key!=='expect';
        if(value.startsWith('-')&&(!numeric||!/^-[0-9.]/.test(value)))throw Error('Missing value for '+flag);
      }
      if(value==='')throw Error('Empty value for '+flag);
      if(flag==='-o'||flag==='--output')output=value;
      else if(flag==='--audio-out')audioOut=value;
      else if(key==='expect')supplied.expect=[...(supplied.expect||[]),value];
      else supplied[key]=numberValue(key,value);
    }
    const o=options(tool,supplied);checkInputCount(tool,inputs.length);
    const names=inputs.map(p=>path.basename(p));
    if(tool==='stemcontract'&&new Set(names).size!==names.length)throw Error('Stem basenames must be unique');
    const paths=[output,audioOut].filter(p=>p!==null).map(canonicalPath),sources=inputs.map(p=>path.resolve(p));
    if(new Set(paths).size!==paths.length||paths.some(p=>sources.includes(p)||sources.some(s=>sameFile(p,s)))||paths.some((p,i)=>paths.slice(i+1).some(q=>sameFile(p,q))))throw Error('Output paths must be distinct and cannot replace inputs');
    for(const p of paths){
      if(!fs.existsSync(path.dirname(p))||!fs.statSync(path.dirname(p)).isDirectory())throw Error('Output parent directory does not exist: '+path.dirname(p));
      if(fs.existsSync(p)&&!fs.statSync(p).isFile())throw Error('Output must be a regular file: '+p);
    }
    if(!overwrite&&paths.some(p=>fs.existsSync(p)))throw Error('Output exists; choose a new path or --overwrite');
    const sizes=inputs.map(p=>fs.statSync(p).size);
    if(sizes.some(n=>n>64*1024*1024))throw Error('WAV exceeds 64 MiB limit');
    if(sizes.reduce((s,n)=>s+n,0)>128*1024*1024)throw Error('Selected files exceed the 128 MiB CLI total; split the batch');
    const audio=inputs.map(p=>{const b=fs.readFileSync(p);return decodeWav(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));});
    const {report,rendered}=analyze(tool,audio,o,names);report.inputs=names;
    if(audioOut&&tool==='gainbudget'&&!report.fits_ceiling)throw Error('Requested gain exceeds ceiling; reduce --gain-db');
    if(audioOut)fs.writeFileSync(audioOut,Buffer.from(encodeWav(rendered,audio[0].rate,tool==='gainbudget'?o.ceiling_db:null)),{flag:overwrite?'w':'wx'});
    const data=JSON.stringify(report,null,2)+'\n';
    if(output)fs.writeFileSync(output,data,{flag:overwrite?'w':'wx'});else process.stdout.write(data);
    return tool==='stemcontract'&&!report.passed?1:0;
  }catch(e){console.error('error: '+e.message);return 2;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)process.exitCode=main();
