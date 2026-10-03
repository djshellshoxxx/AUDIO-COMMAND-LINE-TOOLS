#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {tools,flags,renderTools,decodeWav,encodeWav,analyze} from './engine.mjs';
export function main(argv=process.argv.slice(2),fixedTool=null) {
  argv=[...argv];
  const tool=fixedTool||argv.shift();
  argv=argv.flatMap(arg=>arg.startsWith('--') && arg.includes('=')?[arg.slice(0,arg.indexOf('=')),arg.slice(arg.indexOf('=')+1)]:[arg]);
  if(!tools.includes(tool) || argv.includes('--help') || argv.includes('-h')) {
    console.log(`Usage: node cli.mjs TOOL input.wav [second.wav] [--output report.json] [--overwrite]\nTools: ${tools.join(', ')}\n${flags[tool]?.map(k=>'--'+k.replaceAll('_','-')).join(' ')||''}${renderTools.includes(tool)?' --audio-out result.wav':''}`);
    return !tools.includes(tool)?2:0;
  }
  const o={},inputs=[];let output=null,audioOut=null,overwrite=false;
  try {
    for(let i=0;i<argv.length;i++) {
      const arg=argv[i];if(arg==='--'){inputs.push(...argv.slice(i+1));break;}if(!arg.startsWith('-')) {inputs.push(arg);continue;}
      if(arg==='--overwrite'){overwrite=true;continue;}
      const key=arg.replace(/^--/,'').replaceAll('-','_');
      if(key==='require_active' && flags[tool].includes(key)){o[key]=true;continue;}
      if(!(arg==='-o' || key==='output' || (key==='audio_out' && renderTools.includes(tool)) || flags[tool].includes(key)))throw Error('Unknown flag '+arg);
      if(i+1>=argv.length)throw Error('Missing value for '+arg); const value=argv[++i];
      if(arg==='-o' || key==='output')output=value;
      else if(key==='audio_out')audioOut=value;
      else if(key==='expect')o.expect=[...(o.expect||[]),value];
      else {if(!value.trim())throw Error('Empty flag value');o[key]=Number(value);}
    }
    const paths=[output,audioOut].filter(Boolean).map(p=>path.resolve(p)),sources=inputs.map(p=>path.resolve(p));
    if(new Set(paths).size!==paths.length || paths.some(p=>sources.includes(p)))throw Error('Output paths must be distinct and cannot replace inputs');
    if(!overwrite && paths.some(p=>fs.existsSync(p)))throw Error('Output exists; choose a new path or --overwrite');
    const audio=inputs.map(p=>{if(fs.statSync(p).size>64*1024*1024)throw Error('WAV exceeds 64 MiB limit');const b=fs.readFileSync(p);return decodeWav(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));});
    const names=inputs.map(p=>path.basename(p));const {report,rendered}=analyze(tool,audio,o,names);report.inputs=names;
    if(audioOut && tool==='gainbudget' && !report.fits_ceiling)throw Error('Requested gain exceeds ceiling; reduce --gain-db');
    if(audioOut)fs.writeFileSync(audioOut,Buffer.from(encodeWav(rendered,audio[0].rate)),{flag:overwrite?'w':'wx'});
    const data=JSON.stringify(report,null,2)+'\n';if(output)fs.writeFileSync(output,data,{flag:overwrite?'w':'wx'});else process.stdout.write(data);
    return tool==='stemcontract' && !report.passed?1:0;
  }catch(e){console.error('error: '+e.message);return 2;}
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)process.exitCode=main();
