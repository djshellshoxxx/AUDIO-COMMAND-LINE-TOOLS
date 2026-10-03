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
 // Real upload error flows.
 await page.locator('[data-tool="renderdelta"]').click();
 await page.locator('#files').setInputFiles({name:'bad.wav',mimeType:'audio/wav',buffer:Buffer.from('bad')});await page.locator('#run').click();
 await page.waitForFunction(()=>document.querySelector('#status').classList.contains('error'));assert.equal(await page.locator('#results').isVisible(),false);
 await page.locator('[data-tool="loopbudget"]').click();await page.locator('#run').click();assert.match(await page.locator('#status').textContent(),/Choose a WAV/);
 // Explicit over-ceiling export: retain report, suppress WAV.
 await page.locator('[data-tool="gainbudget"]').click();await page.locator('#demo').click();await page.locator('#opt-gain_db').fill('30');await page.locator('#run').click();
 await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));assert.equal(await page.locator('#save-audio').isVisible(),false);assert.match(await page.locator('#status').textContent(),/exceeds ceiling/);
 // Keyboard and viewport geometry.
 for(const width of [320,768,1024,1440]){
  await page.setViewportSize({width,height:1000});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`Overflow at ${width}`);
 }
 await page.setViewportSize({width:1440,height:1100});await page.locator('[data-tool="loopbudget"]').click();await page.locator('#demo').click();await page.locator('#run').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('Analysis complete.'));
 if(process.env.CDL_SCREENSHOT)await page.screenshot({path:process.env.CDL_SCREENSHOT,fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: 10 browser tools, report/WAV downloads, input errors, ceiling protection, stale-result reset, and 4 viewport widths.');await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
