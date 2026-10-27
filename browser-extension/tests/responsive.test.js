import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const extension=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.resolve(extension,'../frontend');
const artifacts=path.join(extension,'.test-results');await fs.mkdir(artifacts,{recursive:true});
const mime={'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'};
const server=http.createServer(async(req,res)=>{
 try{const url=new URL(req.url,'http://localhost');let file=path.resolve(root,'.'+decodeURIComponent(url.pathname));if(!file.startsWith(root+path.sep)&&file!==root)throw Error('Forbidden');if((await fs.stat(file)).isDirectory())file=path.join(file,'index.html');res.setHeader('Content-Type',mime[path.extname(file)]??'application/octet-stream');res.end(await fs.readFile(file));}catch{res.statusCode=404;res.end('Not found');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true});let checks=0;
try{
 const context=await browser.newContext({reducedMotion:'reduce'});
 for(const route of ['/','/extension/','/extension/connect/','/icon-lab.html','/extension/dashboard/']){
  const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base+route);await page.evaluate(()=>document.fonts.ready);assert.ok(await page.title());assert.ok(await page.locator('meta[name=description]').getAttribute('content'));assert.ok(await page.locator('link[rel=icon]').getAttribute('href'));
  for(const width of [320,375,768,1024,1440])for(const size of ['100%','200%']){
   await page.setViewportSize({width,height:900});await page.evaluate(size=>document.documentElement.style.fontSize=size,size);
   const overflow=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,items:[...document.querySelectorAll('body *')].filter(el=>{const r=el.getBoundingClientRect();return r.width&&r.right>innerWidth+1&&getComputedStyle(el).position!=='absolute';}).slice(0,6).map(el=>({tag:el.tagName,cls:el.className,parent:el.parentElement?.className,text:el.textContent.slice(0,45),right:el.getBoundingClientRect().right}))}));
   assert.ok(overflow.scroll<=width+1,`${route} ${width}px ${size}: ${JSON.stringify(overflow)}`);checks++;
   if(size==='100%')await page.screenshot({path:path.join(artifacts,`responsive-${route.replace(/\W+/g,'-')||'home'}-${width}.png`),fullPage:true});
  }
  await page.setViewportSize({width:375,height:900});await page.evaluate(()=>document.documentElement.style.fontSize='100%');
  const menu=page.getByRole('button',{name:'Menu',exact:true});await menu.click();assert.equal(await menu.getAttribute('aria-expanded'),'true');await page.keyboard.press('Escape');assert.equal(await menu.getAttribute('aria-expanded'),'false');assert.ok(await menu.evaluate(el=>el===document.activeElement));checks++;
  for(const href of await page.locator('a[href]').evaluateAll(links=>links.map(a=>a.href))){const url=new URL(href);if(url.origin!==base)continue;const response=await context.request.get(url.origin+url.pathname);assert.ok(response.ok(),`Broken link ${href}`);if(url.hash){const html=await response.text();assert.ok(html.includes(`id="${url.hash.slice(1)}"`),`Missing anchor ${href}`);}}
  if(route==='/icon-lab.html'){await page.getByRole('button',{name:'Play motion',exact:true}).click();assert.ok(await page.locator('body').evaluate(el=>el.classList.contains('motion-playing')));assert.notEqual(await page.locator('.glitch .base').evaluate(el=>getComputedStyle(el).animationName),'none');await page.getByRole('button',{name:'Pause motion',exact:true}).click();assert.ok(await page.locator('body').evaluate(el=>el.classList.contains('motion-paused')));assert.equal(await page.locator('.glitch .base').evaluate(el=>getComputedStyle(el).animationName),'none');}
  assert.deepEqual(errors,[],`JavaScript errors on ${route}`);await page.close();console.log('PASS',route,'responsive, enlarged text, keyboard menu, metadata and links');
 }

 const interaction=await context.newPage();await interaction.goto(base+'/');
 if(await interaction.locator('#activity-panel').count()){
  await interaction.locator('#tab-music').focus();await interaction.keyboard.press('ArrowRight');assert.equal(await interaction.locator('#tab-focus').getAttribute('aria-selected'),'true');assert.ok(await interaction.locator('#screen-focus').isVisible());await interaction.keyboard.press('Home');assert.equal(await interaction.locator('#tab-music').getAttribute('aria-selected'),'true');checks++;console.log('PASS restored landing preview tabs and keyboard navigation');await interaction.close();
  const failed=await context.newPage();await failed.route('**/assets/now-playing-reference.webp',route=>route.abort());await failed.goto(base+'/');await failed.getByText('Artwork could not load. Playback and timer demos are still available.',{exact:true}).waitFor();assert.equal(await failed.locator('#activity-panel').getAttribute('aria-busy'),null);checks++;console.log('PASS restored landing artwork failure has a readable fallback');await failed.close();
 }else{
  await interaction.close();
 const interaction=await context.newPage();await interaction.goto(base+'/');
 await interaction.locator('#tab-music').focus();await interaction.keyboard.press('ArrowRight');assert.equal(await interaction.locator('#tab-focus').getAttribute('aria-selected'),'true');assert.ok(await interaction.locator('#capture-music').isHidden());
 await interaction.keyboard.press('Tab');assert.ok(await interaction.locator('#capture-focus').evaluate(el=>el===document.activeElement));
 await interaction.locator('#tab-focus').focus();await interaction.keyboard.press('Home');assert.equal(await interaction.locator('#tab-music').getAttribute('aria-selected'),'true');
 checks++;console.log('PASS capture tabs, keyboard activation and tabpanel focus');await interaction.close();
 const failed=await context.newPage();let unavailable=true;
 await failed.route('**/assets/now-playing-artwork.png*',route=>unavailable?route.abort():route.continue());
 await failed.goto(base+'/');await failed.locator('#preview-status').getByRole('button',{name:'Try again',exact:true}).waitFor();
 assert.equal(await failed.locator('#capture-music').getAttribute('aria-busy'),'false');unavailable=false;await failed.locator('#preview-status').getByRole('button',{name:'Try again',exact:true}).click();
 await failed.waitForFunction(()=>document.querySelector('#capture-music img').naturalWidth>0);assert.ok(await failed.locator('#preview-status').isHidden());checks++;console.log('PASS failed media has an actionable retry and recovers');await failed.close();
 const slow=await context.newPage();let release;
 const pending=new Promise(resolve=>release=resolve);
 await slow.route('**/assets/now-playing-artwork.png',async route=>{await pending;await route.continue();});
 await slow.goto(base+'/',{waitUntil:'domcontentloaded'});await slow.getByText('Loading the app capture…',{exact:true}).waitFor();
 release();await slow.waitForFunction(()=>document.querySelector('#capture-music').getAttribute('aria-busy')==='false');assert.ok(await slow.locator('#preview-status').isHidden());checks++;console.log('PASS loading status resolves without a permanent spinner');await slow.close();
 }
 await fs.writeFile(path.join(artifacts,'responsive-report.json'),JSON.stringify({checks,routes:5,widths:[320,375,768,1024,1440],text:['100%','200%']},null,2));console.log(`PASS ${checks} responsive/menu combinations`);
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
