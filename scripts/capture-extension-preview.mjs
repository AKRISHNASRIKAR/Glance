// Capture actual extension UI in an isolated developer profile, never user data.
import {chromium} from '../browser-extension/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import {spawn} from 'node:child_process';import {randomBytes} from 'node:crypto';import {fileURLToPath} from 'node:url';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url))),source=path.join(root,'browser-extension');
const temp=await fs.mkdtemp('/tmp/glance-public-preview-'),extension=path.join(temp,'extension'),profile=path.join(temp,'profile'),native=path.join(temp,'native');
await fs.cp(source,extension,{recursive:true,filter:p=>!p.includes('node_modules')&&!p.includes('.test-results')});await fs.mkdir(native,{mode:0o700});await fs.mkdir(path.join(profile,'NativeMessagingHosts'),{recursive:true});
const manifest=JSON.parse(await fs.readFile(path.join(extension,'manifest.json'),'utf8'));const id=JSON.parse(await fs.readFile(path.join(root,'protocol/development.json'),'utf8')).extensionID;
manifest.permissions.push(...manifest.optional_permissions);manifest.optional_permissions=[];manifest.host_permissions=['youtube.com','reddit.com','news.ycombinator.com'].flatMap(d=>[`http://*.${d}/*`,`https://*.${d}/*`]);await fs.writeFile(path.join(extension,'manifest.json'),JSON.stringify(manifest));
const config={enabled:true,token:randomBytes(32).toString('base64'),allowedOrigins:[`chrome-extension://${id}/`],approvedClients:[]};await fs.writeFile(path.join(native,'connection.json'),JSON.stringify(config),{mode:0o600});
await fs.writeFile(path.join(profile,'NativeMessagingHosts/app.glance.browser.json'),JSON.stringify({name:'app.glance.browser',description:'Isolated preview capture',path:path.join(root,'.build/debug/GlanceBrowserBridge'),type:'stdio',allowed_origins:config.allowedOrigins}));
const env={...process.env,GLANCE_BROWSER_DIR:native};const harness=spawn(path.join(root,'.build/debug/GlanceBrowserHarness'),[],{env,stdio:['ignore','ignore','pipe']});let context;
try{
 for(let i=0;i<100;i++){try{await fs.access(path.join(native,'bridge.sock'));break;}catch{await new Promise(r=>setTimeout(r,50));}}
 await fs.access(path.join(native,'bridge.sock'));
 context=await chromium.launchPersistentContext(profile,{channel:'chromium',headless:true,env,viewport:{width:1100,height:900},deviceScaleFactor:2,args:[`--disable-extensions-except=${extension}`,`--load-extension=${extension}`]});
 const page=await context.newPage();await page.goto(`chrome-extension://${id}/options.html`);
 const send=(type,data={})=>page.evaluate(async({type,data})=>{const r=await chrome.runtime.sendMessage({type,...data});if(!r.ok)throw Error(r.error);return r.data;},{type,data});
 for(const domain of ['youtube.com','reddit.com','news.ycombinator.com'])await send('add',{domain,subdomains:true});
 await send('connect');await page.waitForFunction(()=>document.querySelector('#mac-connection').dataset.state==='connected');
 await page.locator('#mac-connection').screenshot({path:path.join(root,'frontend/assets/extension-connection.png')});
 await send('timer',{action:'start'});const state=await send('state');
 const popup=await context.newPage();await popup.setViewportSize({width:380,height:640});await popup.goto(`chrome-extension://${id}/popup.html`);await popup.waitForFunction(()=>document.querySelector('#primary').textContent==='Pause');
 await popup.evaluate(end=>{Date.now=()=>end-1500000;},state.session.endAt);await popup.screenshot({path:path.join(root,'frontend/assets/extension-popup.png')});
 await page.setViewportSize({width:1000,height:660});await page.goto(`chrome-extension://${id}/blocked.html?rule=1`);await page.waitForFunction(()=>/\d+:\d+/.test(document.querySelector('#time').textContent));await page.evaluate(end=>{Date.now=()=>end-1500000;},state.session.endAt);
 await page.screenshot({path:path.join(root,'frontend/assets/extension-blocked.png')});console.log('Captured real popup, blocked page and native connection from an isolated demo profile.');
}finally{await context?.close();harness.kill('SIGTERM');await fs.rm(temp,{recursive:true,force:true});}
