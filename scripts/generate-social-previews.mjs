// Run with the local site at localhost:4173. Captures the real demo and extension UI.
import {chromium} from '../browser-extension/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
const browser=await chromium.launch({headless:true});
try {
 const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
 await page.goto('http://localhost:4173/');await page.evaluate(()=>document.fonts.ready);
 const mac=await page.locator('.macbook').screenshot();
 const popup=await fs.readFile(new URL('../frontend/assets/extension-popup.png',import.meta.url));
 for(const [name,title,subtitle,visual] of [
  ['glance','Your notch.\nA little more useful.','Music, Pomodoro and context for your Mac.',`<img class="mac" src="data:image/png;base64,${mac.toString('base64')}" alt="">`],
  ['extension','Keep your focus.\nPause the distractions.','Glance Focus for Chrome · Local-first · No account',`<img class="popup" src="data:image/png;base64,${popup.toString('base64')}" alt="">`]
 ]) {
  await page.setViewportSize({width:1200,height:630});
  await page.setContent(`<style>*{box-sizing:border-box}body{margin:0;background:#223d2b;color:#f0f3e9;font-family:Arial,sans-serif;overflow:hidden}main{height:630px;display:flex;align-items:center;padding:70px;gap:32px}section{width:610px;flex-shrink:0}small{font-size:28px;font-weight:bold}h1{font:64px/1.06 Georgia,serif;white-space:pre-line;letter-spacing:-2px;margin:58px 0 25px}p{font-size:20px;line-height:1.5;color:#d6dfd0}.mac{width:510px;transform:translateX(-70px)}.popup{height:520px;border-radius:24px;transform:rotate(5deg);box-shadow:0 20px 60px #081c22aa}</style><main><section><small>glance.</small><h1>${title}</h1><p>${subtitle}</p></section>${visual}</main>`);
  await page.locator('img').evaluate(img=>img.decode());
  await page.screenshot({path:new URL(`../frontend/assets/social-${name}.png`,import.meta.url).pathname});
 }
 console.log('Generated two 1200×630 social previews from actual local UI.');
} finally {await browser.close();}
