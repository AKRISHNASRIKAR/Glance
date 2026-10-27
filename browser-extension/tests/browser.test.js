import {chromium} from 'playwright';
import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import http from 'node:http';import {spawn} from 'node:child_process';import {randomBytes,randomUUID} from 'node:crypto';import assert from 'node:assert/strict';import {fileURLToPath} from 'node:url';
const source=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');const repo=path.dirname(source);
const temp=await fs.mkdtemp('/tmp/glance-extension-test-');const extension=path.join(temp,'extension'),profile=path.join(temp,'profile'),native=path.join(temp,'native');
await fs.cp(source,extension,{recursive:true,filter:p=>!p.includes('node_modules')&&!p.includes('.test-results')});await fs.mkdir(native,{mode:0o700});await fs.mkdir(path.join(profile,'NativeMessagingHosts'),{recursive:true});
const manifest=JSON.parse(await fs.readFile(path.join(extension,'manifest.json'),'utf8'));const dev=JSON.parse(await fs.readFile(path.join(repo,'protocol/development.json'),'utf8'));
// TEST FIXTURE ONLY: pregrant the exact test host and optional metadata/native APIs.
// The actual unpacked release still requests optional permissions through user gestures.
manifest.permissions.push(...manifest.optional_permissions);manifest.optional_permissions=[];manifest.host_permissions=['http://*.distraction.test/*','https://*.distraction.test/*'];await fs.writeFile(path.join(extension,'manifest.json'),JSON.stringify(manifest));
const env={...process.env,GLANCE_BROWSER_DIR:native};const config={enabled:true,token:randomBytes(32).toString('base64'),allowedOrigins:[`chrome-extension://${dev.extensionID}/`],approvedClients:[]};await fs.writeFile(path.join(native,'connection.json'),JSON.stringify(config),{mode:0o600});
const helper=path.join(repo,'.build/debug/GlanceBrowserBridge'),harnessBin=path.join(repo,'.build/debug/GlanceBrowserHarness');
await fs.writeFile(path.join(profile,'NativeMessagingHosts/app.glance.browser.json'),JSON.stringify({name:'app.glance.browser',description:'Isolated Glance integration test',path:helper,type:'stdio',allowed_origins:config.allowedOrigins}));
const log=[];const check=(name)=>{log.push(name);console.log('PASS',name);};let harness,context;
function startHarness(){harness=spawn(harnessBin,[],{env,stdio:['ignore','pipe','pipe']});harness.stderr.on('data',b=>console.error('Harness:',b.toString().trim()));return harness;}
async function until(fn,ms=15000){const start=Date.now();while(Date.now()-start<ms){try{const value=await fn();if(value)return value;}catch{}await new Promise(r=>setTimeout(r,100));}throw new Error('Condition timed out');}
const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end('<!doctype html><title>Focus test site</title><h1>Distraction test page</h1>');});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const port=server.address().port;
try{
 startHarness();await until(async()=>{await fs.access(path.join(native,'bridge.sock'));return true;});
 context=await chromium.launchPersistentContext(profile,{channel:'chromium',headless:true,env,viewport:{width:1100,height:900},args:[`--disable-extensions-except=${extension}`,`--load-extension=${extension}`,'--no-proxy-server','--host-resolver-rules=MAP distraction.test 127.0.0.1,MAP m.distraction.test 127.0.0.1']});
 let worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker');assert.ok(worker.url().includes(dev.extensionID));check('stable development extension ID and worker loaded');
 let ui=await context.newPage();await ui.goto(`chrome-extension://${dev.extensionID}/options.html`);
 await ui.getByRole('button',{name:'Start focus',exact:true}).waitFor();
 const send=(type,payload={})=>ui.evaluate(async({type,payload})=>{const r=await chrome.runtime.sendMessage({type,...payload});if(!r.ok)throw new Error(r.error);return r.data;},{type,payload});
 await ui.getByRole('textbox',{name:'Website domain',exact:true}).fill('distraction.test');await ui.getByRole('button',{name:'Add',exact:true}).click();await until(async()=> (await send('state')).entries.length===1);check('domain add and persisted block list');
 const site=await context.newPage();await site.goto(`http://distraction.test:${port}/before`);assert.equal(await site.locator('h1').textContent(),'Distraction test page');
 await ui.getByRole('button',{name:'Start focus',exact:true}).click();await site.waitForURL(`chrome-extension://${dev.extensionID}/blocked.html?rule=1`);check('starting focus replaces an already-open distracting tab');
 await site.getByText('distraction.test',{exact:true}).waitFor();assert.ok((await send('state')).blocking);
 let nav=await context.newPage();await nav.goto(`http://m.distraction.test:${port}/next`).catch(()=>{});await nav.waitForURL(`chrome-extension://${dev.extensionID}/blocked.html?rule=1`);check('Chrome DNR blocks new subdomain navigation');
 await until(async()=> (await ui.getByRole('button',{name:'Pause',exact:true}).count())>0);await ui.getByRole('button',{name:'Pause',exact:true}).click();await until(async()=>!(await send('state')).blocking);await site.goto(`http://distraction.test:${port}/paused`);assert.equal(await site.locator('h1').textContent(),'Distraction test page');check('pause clears blocking');
 await send('timer',{action:'resume'});await site.waitForURL(`chrome-extension://${dev.extensionID}/blocked.html?rule=1`);await send('timer',{action:'stop'});await site.goto(`http://distraction.test:${port}/stopped`);check('resume blocks and stop restores access');
 await ui.getByRole('button',{name:'Enable usage stats',exact:true}).click();await until(async()=> (await send('state')).tracking);check('usage tracking can be explicitly enabled');
 await send('timer',{action:'start',minutes:1});
 const cdp=await context.newCDPSession(ui);await cdp.send('ServiceWorker.enable');await cdp.send('ServiceWorker.stopAllWorkers');await ui.reload();await until(async()=> (await send('state')).blocking);check('worker restart restores a valid persisted session');await send('timer',{action:'stop'});
 worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker');
 // Chrome resolves manifests relative to platform paths. If the isolated profile
 // lookup differs, test the actual framing/helper/socket through stdin as well.
 let nativeThroughChrome=true;
 try{await send('connect');}catch(e){nativeThroughChrome=false;console.log('INFO Chrome-native lookup:',e.message);}
 if(nativeThroughChrome){
  await until(async()=> (await send('state')).connection==='connected');check('Chrome Native Messaging handshake and approved Mac pairing');await until(async()=>await ui.locator('#mac-connection').getAttribute('data-state')==='connected');
  await send('timer',{action:'start',minutes:1});assert.equal((await send('state')).session.owner,'mac');await nav.goto(`http://distraction.test:${port}/mac`).catch(()=>{});await nav.waitForURL(`chrome-extension://${dev.extensionID}/blocked.html?rule=1`);check('real Mac engine start enforces browser blocking');
  const beforeReload=(await send('state')).session;
  // Match an unpacked install: Developer mode must stay enabled after reload.
  const manager=await context.newPage();await manager.goto('chrome://extensions');
  await manager.evaluate(()=>new Promise(resolve=>chrome.developerPrivate.updateProfileConfiguration({inDeveloperMode:true},resolve)));
  await manager.close();
  await ui.evaluate(()=>{setTimeout(()=>chrome.runtime.reload(),25);return true;});
  await new Promise(r=>setTimeout(r,750));
  ui=await context.newPage();
  await ui.goto(`chrome-extension://${dev.extensionID}/options.html`);
  await until(async()=> (await send('state')).connection==='connected');
  const recovered=await send('state');assert.equal(recovered.session.owner,'mac');assert.equal(recovered.session.id,beforeReload.id);assert.equal(recovered.session.endAt,beforeReload.endAt);assert.ok(recovered.blocking);check('full extension reload reconnects automatically and preserves the active Mac session deadline');
  if(nav.isClosed())nav=await context.newPage();

  await send('timer',{action:'pause'});assert.equal((await send('state')).blocking,false);await send('timer',{action:'resume'});assert.equal((await send('state')).blocking,true);
  await send('emergency');assert.equal((await send('state')).blocking,false);await new Promise(r=>setTimeout(r,2500));assert.equal((await send('state')).blocking,false);check('emergency suppression survives Mac snapshot polling');
  await send('useMac');assert.equal((await send('state')).blocking,true);
  harness.kill('SIGTERM');await new Promise(r=>harness.once('exit',r));await until(async()=> (await send('state')).connection!=='connected',12000);assert.ok((await send('state')).blocking);check('disconnect retains the last known active deadline');
  const offlineDeadline=(await send('state')).session.endAt;
  await ui.evaluate(()=>{setTimeout(()=>chrome.runtime.reload(),25);return true;});
  await new Promise(r=>setTimeout(r,750));ui=await context.newPage();await ui.goto(`chrome-extension://${dev.extensionID}/options.html`);
  const offline=await send('state');assert.equal(offline.session.endAt,offlineDeadline);assert.equal(offline.wantsMac,true);check('reload while Mac is unavailable preserves ownership and last deadline');
  if(nav.isClosed())nav=await context.newPage();

  startHarness();await until(async()=> (await send('state')).connection==='connected',20000);assert.equal((await send('state')).blocking,false);check('Mac restart reconciles its authoritative idle state');check('startup connection failure retries automatically when the Mac returns');
  await send('standalone');
 }
 // Independently verify native framing, authentication, revisions, idempotency,
 // statistics replay/purge and disconnect diagnostics with no browser mocks.
 const clientID=randomUUID();let sequence=0;
 function nativeCall(type,payload={},id=randomUUID()){
  return new Promise((resolve,reject)=>{
   const child=spawn(helper,[config.allowedOrigins[0]],{env,stdio:['pipe','pipe','pipe']});let buf=Buffer.alloc(0),err='';
   const request=Buffer.from(JSON.stringify({protocolVersion:1,id,type,clientID,payload}));const header=Buffer.alloc(4);header.writeUInt32LE(request.length);child.stdin.end(Buffer.concat([header,request]));child.stdout.on('data',b=>buf=Buffer.concat([buf,b]));child.stderr.on('data',b=>err+=b);
   child.on('error',reject);child.on('exit',code=>{try{if(code!==0)throw new Error(err);assert.ok(buf.length>=4);const len=buf.readUInt32LE();assert.equal(buf.length,len+4);resolve(JSON.parse(buf.subarray(4).toString()));}catch(e){reject(e)}});
  });
 }
 assert.equal((await nativeCall('snapshot')).ok,false);const paired=await nativeCall('pair');assert.ok(paired.ok,paired.error);let snap=(await nativeCall('snapshot')).payload;
 const commandID=randomUUID();const command={action:'start',minutes:1,expectedRevision:snap.session.revision};const started=await nativeCall('timer',command,commandID);assert.ok(started.ok,started.error);const replay=await nativeCall('timer',command,commandID);assert.deepEqual(replay.payload,started.payload);assert.equal((await nativeCall('timer',{action:'pause',expectedRevision:-1})).ok,false);check('native framed protocol, pairing, idempotency and stale revisions');
 snap=(await nativeCall('snapshot')).payload;assert.ok((await nativeCall('timer',{action:'stop',expectedRevision:snap.session.revision})).ok);
 const event={id:`${clientID}:1`,sequence:1,clientID,type:'usage',domain:'distraction.test',seconds:30,at:Date.now()};assert.equal((await nativeCall('stats',{events:[event]})).payload.ack,1);const before=(await nativeCall('snapshot')).payload.stats.sites.find(s=>s.domain==='distraction.test')?.seconds??0;await nativeCall('stats',{events:[event]});const after=(await nativeCall('snapshot')).payload.stats.sites.find(s=>s.domain==='distraction.test')?.seconds??0;assert.equal(before,after);await nativeCall('purgeStats',{throughSequence:1});await nativeCall('stats',{events:[event]});check('native stats batches are acknowledged and replay/purge safe');

 // Reproduce stale browser duration vs the Mac's authoritative configuration.
 snap=(await nativeCall('snapshot')).payload;
 const twoMinutes={...snap.pomodoro,focusDuration:120};
 assert.ok((await nativeCall('pomodoroSettings',{expected:snap.pomodoro,value:twoMinutes})).ok);
 await send('standalone');await send('timer',{action:'start',minutes:9});
 await send('connect');let authoritative=await send('state');
 assert.equal(authoritative.connection,'connected');assert.equal(authoritative.session.owner,'mac');assert.equal(authoritative.session.state,'idle');assert.equal(authoritative.pomodoro.focusDuration,120);assert.equal(authoritative.remaining,120000);check('connecting discards a competing nine-minute browser timer and adopts the two-minute Mac configuration');
 snap=(await nativeCall('snapshot')).payload;
 const nativeStarted=await nativeCall('timer',{action:'start',minutes:9,expectedRevision:snap.session.revision});assert.ok(nativeStarted.ok,nativeStarted.error);
 assert.ok(nativeStarted.payload.session.remaining<=120000 && nativeStarted.payload.session.remaining>118000);
 await until(async()=> (await send('state')).session.id===nativeStarted.payload.session.id);
 authoritative=await send('state');assert.equal(authoritative.session.endAt,nativeStarted.payload.session.endAt);assert.equal(authoritative.pomodoro.focusDuration,120);check('Mac start ignores stale browser duration and both clients share the exact two-minute deadline');
 snap=(await nativeCall('snapshot')).payload;await nativeCall('timer',{action:'stop',expectedRevision:snap.session.revision});await until(async()=> (await send('state')).session.state==='idle');
 await send('timer',{action:'start',minutes:9});authoritative=await send('state');assert.ok(authoritative.remaining<=120000 && authoritative.remaining>118000);assert.equal(authoritative.pomodoro.focusDuration,120);check('Chrome start uses the Mac duration instead of its stale nine-minute selection');
 await send('timer',{action:'stop'});
 const pref=(await nativeCall('snapshot')).payload.preferences;
 const edited={...pref.value,exclusions:['example.com']};assert.ok((await nativeCall('preferences',{expectedRevision:pref.revision,value:edited})).ok);
 await until(async()=> (await send('state')).exclusions.includes('example.com'));check('app-owned browser settings propagate to Chrome');
 assert.equal((await nativeCall('preferences',{expectedRevision:pref.revision,value:pref.value})).ok,false);check('stale preference writes cannot overwrite newer Mac settings');
 const websiteRoot=path.join(repo,'frontend');
 await context.route('https://glance-notch.vercel.app/**',async route=>{
  const url=new URL(route.request().url());let file=path.resolve(websiteRoot,'.'+decodeURIComponent(url.pathname));
  if(!file.startsWith(websiteRoot+path.sep)&&file!==websiteRoot){await route.abort();return;}
  if((await fs.stat(file)).isDirectory())file=path.join(file,'index.html');
  const body=await fs.readFile(file);const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.webp':'image/webp','.png':'image/png'};
  await route.fulfill({body,contentType:mime[path.extname(file)]??'application/octet-stream'});
 });
 const web=await context.newPage();await web.goto('https://glance-notch.vercel.app/extension/dashboard/');
 const webSend=(type,data={})=>web.evaluate(async({type,data,id})=>chrome.runtime.sendMessage(id,{type,...data}),{type,data,id:dev.extensionID});
 assert.equal((await webSend('state')).ok,false);check('hosted dashboard cannot read local data before explicit extension authorization');
 await send('openDashboard');await web.reload();await web.locator('.stack').waitFor({state:'visible'});
 assert.equal(await web.locator('#pomodoro-settings').count(),0);assert.equal(await web.locator('#pomodoro-form').count(),0);
 await until(async()=>await web.locator('#mac-connection').getAttribute('data-state')==='connected');
 assert.equal(await web.locator('#bridge-title').textContent(),'Your Mac is connected');assert.equal(await web.locator('.connection-diagram').count(),1);
 check('hosted dashboard omits Pomodoro settings and shows its confirmed visual Mac connection');
 await web.getByRole('button',{name:'Start focus',exact:true}).click();await until(async()=> (await nativeCall('snapshot')).payload.session.state==='running');
 const webTimer=(await nativeCall('snapshot')).payload.session;assert.ok(webTimer.remaining<=120000 && webTimer.remaining>118000);
 await web.getByRole('button',{name:'End',exact:true}).click();await until(async()=> (await nativeCall('snapshot')).payload.session.state==='idle');
 check('visual dashboard retains working controls for the authoritative Mac timer');
 const webPrefs=(await nativeCall('snapshot')).payload.preferences;await webSend('exclude',{domain:'second.example.com'});await until(async()=> (await nativeCall('snapshot')).payload.preferences.value.exclusions.includes('second.example.com'));check('hosted and packaged settings use the same app-owned preferences');await web.screenshot({path:path.join(source,'.test-results/hosted-dashboard.png'),fullPage:true});await web.setViewportSize({width:375,height:812});assert.ok(await web.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));check('hosted dashboard stays within a narrow mobile viewport');
 for(const surface of [ui,web])for(const width of [320,375,768,1440])for(const textSize of ['100%','200%']){
  await surface.setViewportSize({width,height:900});await surface.evaluate(size=>document.documentElement.style.fontSize=size,textSize);
  const box=await surface.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,items:[...document.querySelectorAll('body *')].filter(el=>{const r=el.getBoundingClientRect();return r.width&&r.right>innerWidth+1&&getComputedStyle(el).position!=='absolute';}).slice(0,8).map(el=>({tag:el.tagName,cls:el.className,text:el.textContent.slice(0,35),right:el.getBoundingClientRect().right}))}));assert.ok(box.scroll<=width+1,`Connected ${surface===ui?'packaged':'hosted'} settings overflow at ${width}px / ${textSize}: ${JSON.stringify(box)}`);
 }
 check('connected packaged and hosted settings fit four viewports at normal and enlarged text');
 await ui.evaluate(()=>document.documentElement.style.fontSize='100%');await ui.setViewportSize({width:1100,height:900});

 await send('revokeDashboard');assert.equal((await webSend('state')).ok,false);assert.equal((await webSend('timer',{action:'start'})).ok,false);await web.close();check('revoking web dashboard access blocks further reads and writes');

 await send('standalone');await send('timer',{action:'start',minutes:1});await until(async()=> (await ui.locator('#connection').textContent())==='Standalone');await ui.screenshot({path:path.join(source,'.test-results/dashboard.png'),fullPage:true});await ui.close();await nav.goto(`http://distraction.test:${port}/popup-closed`).catch(()=>{});await nav.waitForURL(`chrome-extension://${dev.extensionID}/blocked.html?rule=1`);check('blocking does not depend on an open popup or dashboard');
 await new Promise(r=>setTimeout(r,62000));await nav.goto(`http://distraction.test:${port}/expired`).catch(()=>{});await until(async()=>!nav.url().startsWith('chrome-extension://'));assert.equal(await nav.locator('h1').textContent(),'Distraction test page');check('real deadline expiry restores navigation after popup closure');
 await fs.writeFile(path.join(source,'.test-results/report.json'),JSON.stringify({checks:log,nativeThroughChrome,isolatedProfile:true,permissionPrompts:'Not automated; exact-host fixture permissions are pregranted. Production manifest uses optional permissions.'},null,2));console.log('TEST PROFILE:',temp);
 if(!nativeThroughChrome)throw new Error('Native framing passed, but Chrome host lookup needs fixing before calling end-to-end pairing verified.');
}finally{await context?.close();harness?.kill('SIGTERM');server.close();}
