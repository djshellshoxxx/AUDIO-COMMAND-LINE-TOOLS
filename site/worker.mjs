import {decodeWav,encodeWav,analyze,renderTools} from './js/engine.mjs';
self.onmessage=({data})=>{
  try {
    const audio=data.buffers.map(decodeWav),{report,rendered}=analyze(data.tool,audio,data.options,data.names);report.inputs=data.names;
    let wav=null,exportError=null;
    if(renderTools.includes(data.tool)) {
      try {if(data.tool==='gainbudget' && !report.fits_ceiling)throw Error('Requested gain exceeds ceiling; reduce gain before exporting.');wav=encodeWav(rendered,audio[0].rate,data.tool==='gainbudget'?data.options.ceiling_db:null);}
      catch(e){exportError=e.message;}
    }
    self.postMessage({report,wav,exportError},wav?[wav]:[]);
  }catch(e){self.postMessage({error:e.message});}
};
