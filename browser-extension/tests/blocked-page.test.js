import {chromium} from 'playwright';

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const tmp=await fs.mkdtemp(path.join(os.tmpdir(),'glance-blocked-ui-'));
const ext=path.join(tmp,'extension');
await fs.cp(root,ext,{recursive:true,filter:p=>!p.includes('node_modules')&&!p.includes('.test-results')});
const manifest=JSON.parse(await fs.readFile(path.join(ext,'manifest.json'),'utf8'));
manifest.host_permissions=['https://*.example.com/*','http://*.example.com/*'];
await fs.writeFile(path.join(ext,'manifest.json'),JSON.stringify(manifest));

const context=await chromium.launchPersistentContext(path.join(tmp,'profile'),{channel:'chromium',headless:true,args:[`--disable-extensions-except=${ext}`,`--load-extension=${ext}`],viewport:{width:1440,height:1000},deviceScaleFactor:2});

try{const worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker');
const id=new URL(worker.url()).host;
const page=await context.newPage();
await page.goto(`chrome-extension://${id}/options.html`);
const send=(type,data={})=>page.evaluate(async({type,data})=>{const r=await chrome.runtime.sendMessage({type,...data});
if(!r.ok)throw Error(r.error);
return r.data;
},{type,data});
await send('add',{domain:'example.com',subdomains:true});
await send('timer',{action:'start',minutes:25});
await page.goto(`chrome-extension://${id}/blocked.html?rule=1`);
await page.waitForFunction(()=>/\d+:\d+/.test(document.querySelector('#time').textContent));
await page.screenshot({path:path.join(root,'.test-results','after-blocked.png'),fullPage:true});
console.log(JSON.stringify(await page.locator('#time').boundingBox()));
{const assert=(v,m)=>{if(!v)throw Error(m)};
assert(await page.locator('button').count()===0,'No bypass buttons');
assert(await page.locator('a').count()===1,'Only Manage list');
await page.keyboard.press('Tab');
assert(await page.locator('#manage').evaluate(el=>el===document.activeElement),'Manage list keyboard focus');
await page.locator('#manage').click();
await page.waitForURL('**/options.html');
await page.goBack();
await page.setViewportSize({width:375,height:812});
await page.screenshot({path:path.join(root,'.test-results/after-blocked-mobile.png'),fullPage:true});
assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No mobile overflow');
await page.evaluate(()=>document.documentElement.style.fontSize='200%');
assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No overflow at enlarged text');
await page.setViewportSize({width:320,height:640});
assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No narrow overflow with enlarged text');
await send('timer',{action:'pause'});
await page.waitForFunction(()=>document.querySelector('#message').textContent==='Session paused');
await send('timer',{action:'stop'});
await page.waitForFunction(()=>document.querySelector('#message').textContent==='Session complete');
await page.evaluate(()=>{chrome.runtime.sendMessage=async()=>{throw Error('Connection lost');
};
});
await page.waitForFunction(()=>!document.querySelector('#feedback').hidden);
assert(await page.locator('a').count()===1,'Errors add no bypass action');
console.log('PASS desktop, mobile, enlarged text, single action, keyboard navigation, paused, finished and error states');
for(const surface of ['popup.html','options.html']){
 await page.goto(`chrome-extension://${id}/${surface}`);
 for(const width of [320,375,768,1440])for(const textSize of ['100%','200%']){
  await page.setViewportSize({width,height:900});await page.evaluate(size=>document.documentElement.style.fontSize=size,textSize);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${surface} overflow at ${width}px / ${textSize}`);
 }
 console.log('PASS',surface,'responsive and enlarged text');
}

} }
finally{await context.close();
await fs.rm(tmp,{recursive:true,force:true});
}
