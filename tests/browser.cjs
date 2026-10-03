/* Run after serving site/ at localhost:8000. Requires Playwright + Chromium. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');const os=require('node:os');const path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({acceptDownloads:true});const page=await context.newPage();const errors=[];
 page.on('pageerror',e=>errors.push(e.message));await page.goto(process.env.CDL_TEST_URL||'http://127.0.0.1:8000');
 await page.waitForSelector('#tool-list button');const names=await page.locator('#tool-list button').evaluateAll(buttons=>buttons.map(b=>b.dataset.tool));assert.equal(names.length,10);
 for(const name of names){
  await page.locator(`#tool-list button[data-tool="${name}"]`).click();await page.locator('#demo').click();if(name==='gainbudget')await page.locator('#opt-gain_db').fill('-3');await page.locator('#run').click();
  await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));
  const report=JSON.parse(await page.locator('#report').textContent());assert.equal(report.tool,name);assert.equal(report.sample_rate,48000);assert.equal(report.frames,96000);
  assert.equal(await page.locator('#results').isVisible(),true);
  const downloadPromise=page.waitForEvent('download');await page.locator('#save-report').click();const download=await downloadPromise;assert.equal(download.suggestedFilename(),name+'-report.json');
  const tmp=path.join(os.tmpdir(),`cdl-${name}-${Date.now()}.json`);await download.saveAs(tmp);assert.equal(JSON.parse(fs.readFileSync(tmp)).tool,name);fs.unlinkSync(tmp);
  if(['tailbudget','monoledger','dcjourney','gainbudget','renderdelta'].includes(name)){
   assert.equal(await page.locator('#save-audio').isVisible(),true,name);
   const wavPromise=page.waitForEvent('download');await page.locator('#save-audio').click();const wav=await wavPromise;const wp=path.join(os.tmpdir(),`cdl-${name}-${Date.now()}.wav`);await wav.saveAs(wp);const data=fs.readFileSync(wp);assert.equal(data.subarray(0,4).toString(),'RIFF');fs.unlinkSync(wp);
  }
  const firstInput=page.locator('#options input[type=number]').first();if(await firstInput.count()){await firstInput.fill('1');assert.equal(await page.locator('#results').isVisible(),false);}
 }
 await page.locator('[data-tool="renderdelta"]').click();
 await page.locator('#files').setInputFiles({name:'bad.wav',mimeType:'audio/wav',buffer:Buffer.from('bad')});await page.locator('#run').click();
 await page.waitForFunction(()=>document.querySelector('#status').classList.contains('error'));assert.equal(await page.locator('#results').isVisible(),false);
 await page.locator('[data-tool="loopbudget"]').click();await page.locator('#run').click();assert.match(await page.locator('#status').textContent(),/Choose a WAV/);
 await page.locator('[data-tool="gainbudget"]').click();await page.locator('#demo').click();await page.locator('#opt-gain_db').fill('30');await page.locator('#run').click();
 await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));assert.equal(await page.locator('#save-audio').isVisible(),false);assert.match(await page.locator('#status').textContent(),/exceeds ceiling/);
 const quiet=Buffer.alloc(44+100*8);quiet.write('RIFF',0);quiet.writeUInt32LE(quiet.length-8,4);quiet.write('WAVEfmt ',8);quiet.writeUInt32LE(16,16);quiet.writeUInt16LE(3,20);quiet.writeUInt16LE(1,22);quiet.writeUInt32LE(1000,24);quiet.writeUInt32LE(8000,28);quiet.writeUInt16LE(8,32);quiet.writeUInt16LE(64,34);quiet.write('data',36);quiet.writeUInt32LE(800,40);for(let i=0;i<100;i++)quiet.writeDoubleLE(.001,44+i*8);
 await page.locator('#files').setInputFiles({name:'quiet.wav',mimeType:'audio/wav',buffer:quiet});await page.locator('#opt-gain_db').fill('0');await page.locator('#opt-ceiling_db').fill('-60');await page.locator('#run').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));
 const quietDownload=page.waitForEvent('download');await page.locator('#save-audio').click();const quietWav=await quietDownload;const quietPath=path.join(os.tmpdir(),'cdl-ceiling-'+Date.now()+'.wav');await quietWav.saveAs(quietPath);const quietBytes=fs.readFileSync(quietPath);for(let i=44;i<quietBytes.length;i+=2)assert.ok(Math.abs(quietBytes.readInt16LE(i)/32768)<=.001);fs.unlinkSync(quietPath);
 const failed=await context.newPage();const failedErrors=[];failed.on('pageerror',e=>failedErrors.push(e.message));await failed.route('**/catalog.json',route=>route.abort());await failed.goto(process.env.CDL_TEST_URL||'http://127.0.0.1:8000');await failed.waitForFunction(()=>document.querySelector('#status').classList.contains('error'));for(const id of ['files','demo','run'])assert.equal(await failed.locator('#'+id).isDisabled(),true);assert.deepEqual(failedErrors,[]);await failed.close();
 const fixture=Buffer.alloc(44+4000*2);fixture.write('RIFF',0);fixture.writeUInt32LE(fixture.length-8,4);fixture.write('WAVEfmt ',8);fixture.writeUInt32LE(16,16);fixture.writeUInt16LE(1,20);fixture.writeUInt16LE(2,22);fixture.writeUInt32LE(1000,24);fixture.writeUInt32LE(4000,28);fixture.writeUInt16LE(4,32);fixture.writeUInt16LE(16,34);fixture.write('data',36);fixture.writeUInt32LE(8000,40);
 await page.locator('[data-tool="loopbudget"]').click();await page.locator('#files').setInputFiles({name:'uploaded.wav',mimeType:'audio/wav',buffer:fixture});await page.locator('#run').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));assert.equal(JSON.parse(await page.locator('#report').textContent()).frame_error,0);
 for(const file of ['cdl-audio-python.zip','cdl-audio-javascript.zip','cdl-winaudioforensics-powershell.zip']){const event=page.waitForEvent('download');await page.locator(`a[href="downloads/${file}"]`).click();const dl=await event;const tmp=path.join(os.tmpdir(),file);await dl.saveAs(tmp);const bytes=fs.readFileSync(tmp);assert.equal(bytes.subarray(0,2).toString(),'PK');assert.ok(bytes.length>20000);fs.unlinkSync(tmp);}
 for(const name of names){const response=await page.request.get(new URL('spec/'+name+'.md',page.url()).href);assert.equal(response.status(),200);assert.match(await response.text(),/Pseudocode/);}
 for(const name of ['onsetpack','phasebatch','packdelta','edgeguard']){const response=await page.request.get(new URL('spec/'+name+'.md',page.url()).href);assert.equal(response.status(),200);}
 const wafSpec=await page.request.get(new URL('spec/winaudioforensics.md',page.url()).href);assert.equal(wafSpec.status(),200);assert.match(await wafSpec.text(),/Pseudocode/);
 const wafGuide=await page.request.get(new URL('docs/WINAUDIOFORENSICS.md',page.url()).href);assert.equal(wafGuide.status(),200);assert.match(await wafGuide.text(),/WinAudioForensics/);
 await page.reload();await page.waitForSelector('#tool-list button');await page.locator('body').evaluate(el=>{el.tabIndex=-1;el.focus();});await page.keyboard.press('Tab');assert.equal(await page.evaluate(()=>document.activeElement.className),'skip');await page.keyboard.press('Enter');assert.match(page.url(),/#workbench$/);
 for(const width of [320,768,1024,1440]){await page.setViewportSize({width,height:1000});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`Overflow at ${width}`);}
 await page.setViewportSize({width:1440,height:1100});await page.locator('[data-tool="loopbudget"]').click();await page.locator('#demo').click();await page.locator('#run').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));
 await page.locator('#tool-title').evaluate(el=>{el.tabIndex=-1;el.focus();});
 if(process.env.CDL_SCREENSHOT)await page.screenshot({path:process.env.CDL_SCREENSHOT,fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: 10 browser tools, 4 batch specs, three bundles, PowerShell docs, downloads, errors, and 4 viewport widths.');await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});