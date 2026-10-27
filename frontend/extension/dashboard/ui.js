import {send,requestPermissions,currentTab} from './transport.js';
import {hostname,permissionsFor,timerText} from './core.js';
const $=id=>document.getElementById(id);let current,formBaseline,formDirty=false,refreshing=false,busy=false,sitesKey="",exclusionsKey="";
function text(id,value){$(id).textContent=value;}
function feedback(message,error=false){text('feedback',message);$('feedback').classList.toggle('error',error);}
function el(tag,content,cls){const x=document.createElement(tag);x.textContent=content;if(cls)x.className=cls;return x;}
function duration(seconds){return seconds>=3600?`${(seconds/3600).toFixed(1)}h`:`${Math.round(seconds/60)}m`;}
async function action(fn){if(busy)return;busy=true;feedback('Working…');try{await fn();feedback(current?.wantsMac?'Saved on your Mac.':'Saved in this browser.');await refresh();}catch(e){feedback(e.message,true);}finally{busy=false;}}
function waitingForMac(s){return s.wantsMac && s.connection!=='connected';}
function renderCountdown(s){text('time',waitingForMac(s)?'--:--':timerText(s.session));}
function render(s){
 if($('dashboard-gate')){$('dashboard-gate').hidden=true;document.querySelector('.stack').hidden=false;}
 if($('pomodoro-form') && s.pomodoro && !formDirty){formBaseline=structuredClone(s.pomodoro);for(const [key,value] of Object.entries(s.pomodoro)){const input=$('setting-'+key);if(input){if(input.type==='checkbox')input.checked=value;else input.value=Array.isArray(value)?value.join(', '):['focusDuration','shortBreakDuration','longBreakDuration'].includes(key)?value/60:value;}}}
 if($('pomodoro-form'))$('pomodoro-form').hidden=!s.pomodoro;
 current=s;$('connection').dataset.state=s.connection;text('connection',({connected:'Connected to Glance',standalone:'Standalone',connecting:'Connecting…',reconnecting:'Reconnecting…',conflict:'Choose a timer','needs-setup':'Mac setup needed'})[s.connection]??s.connection);
 renderCountdown(s);
 text('phase',s.session.phase==='focus'?'Focus':s.session.phase==='longBreak'?'Long break':'Short break');
 text('primary',s.session.state==='running'?'Pause':s.session.state==='paused'?'Resume':s.session.phase==='focus'?'Start focus':'Start break');if(waitingForMac(s))text('primary','Syncing with Glance…');$('primary').disabled=waitingForMac(s);
 $('minutes').hidden=!!s.session.id||s.session.owner==='mac';$('stop').hidden=!s.session.id;
 text('blocking',s.blocking?'Focus is active. Listed websites are blocked.':s.session.suppressed?'Browser blocking stopped locally. The Mac timer may still be running.':'Blocking is off during breaks and pauses.');
 const nextSitesKey=JSON.stringify(s.entries);if(nextSitesKey!==sitesKey){sitesKey=nextSitesKey;
 $('sites').replaceChildren();$('sites-empty').hidden=s.entries.length>0;
 for(const e of s.entries){const li=el('li','','site row');const info=el('div','');info.append(el('strong',e.domain),el('div',!e.granted?'Permission needed':e.enabled?(e.subdomains?'Domain and subdomains':'Exact domain'):'Disabled','muted'));const controls=el('div','','actions');
  const toggle=el('button',e.granted?(e.enabled?'Disable':'Enable'):'Grant access');toggle.onclick=()=>action(async()=>{if(!e.granted){if(!await requestPermissions({origins:permissionsFor(e.domain,e.subdomains)}))throw new Error('Permission was not granted.');}else await send('toggle',{ruleID:e.ruleID});});
  const remove=el('button','Remove');remove.onclick=()=>action(()=>send('remove',{ruleID:e.ruleID}));controls.append(toggle,remove);li.append(info,controls);$('sites').append(li);}}
 text('tracking',s.tracking?'Pause usage stats':'Enable usage stats');text('tracking-description',s.tracking?'Tracking active website time locally. Retention: 30 days. Idle threshold: 60 seconds.':'Optional: measure active website time while Chrome is focused and you are not idle. Only domains and durations are stored locally.');
 const totals=s.connection==='connected' && s.native ? s.native:s.stats;const siteTotals=totals.sites.map(row=>Array.isArray(row)?row:[row.domain,row.seconds]);
 text('activity-title',s.connection==='connected'&&s.native?'This Mac and paired profiles':'Your browser activity');
 text('focus-total',duration(totals.focusSeconds));text('sessions-total',String(totals.completed));text('blocked-total',String(totals.blocked));$('usage').replaceChildren();$('usage-empty').hidden=siteTotals.length>0;
 for(const [domain,seconds] of siteTotals.slice(0,15)){const row=el('li','','row site');row.append(el('span',domain),el('strong',duration(seconds)));$('usage').append(row);}
 $('daily').replaceChildren();for(const d of s.stats.daily??[]){const row=el('li','','row site');row.append(el('span',d.date),el('span',`${duration(d.usageSeconds)} browsing · ${duration(d.focusSeconds)} focus · ${d.blocked} blocked`));$('daily').append(row);}
 const nextExclusionsKey=JSON.stringify(s.exclusions);if(nextExclusionsKey!==exclusionsKey){exclusionsKey=nextExclusionsKey;
 $('exclusions').replaceChildren();for(const domain of s.exclusions){const row=el('li','','row site');const b=el('button','Remove');b.onclick=()=>action(()=>send('unexclude',{domain}));row.append(el('span',domain),b);$('exclusions').append(row);}}
 $('standalone').hidden=!s.wantsMac;$('use-mac').hidden=s.connection!=='conflict'&&!s.suppressedSession;$('emergency').hidden=!s.blocking||s.session.owner!=='mac';
 const warning=s.connection==='conflict'?'Your browser timer is running independently. Use Mac timer ends it and adopts Glance’s timer.':s.suppressedSession?'A local emergency stop is active for this Mac session.':s.connectionError;
 $('connection-warning').hidden=!warning;text('connection-warning',warning??'');
 if($('mac-connection')){
  const connected=s.connection==='connected';const reconnecting=['reconnecting','connecting'].includes(s.connection);
  $('mac-connection').dataset.state=connected?'connected':reconnecting?'reconnecting':'standalone';
  text('bridge-state',connected?'Connected locally':reconnecting?'Finding your Mac':'Works better together');
  text('bridge-title',connected?'Your Mac is connected':reconnecting?'Reconnecting to Glance':'Connect your Mac');
  $('pairing-help').hidden=connected;
 }
 text('bridge-message',s.connection==='connected'?'Glance keeps your timer and shared settings in sync. Your browser follows your Mac.':s.connection==='reconnecting'?'Your last confirmed timer is preserved while we reconnect to Glance.':'Pair with Glance to follow your Mac’s focus timer and bring browser activity into the app.');
}
async function refresh(){if(refreshing)return;refreshing=true;try{render(await send('state'));}catch(e){feedback(e.message,true);if($('dashboard-gate')){$('dashboard-gate').hidden=false;document.querySelector('.stack').hidden=true;text('connection','Extension not connected');$('connection').dataset.state='disconnected';feedback('');}}finally{refreshing=false;}}
$('add-form').onsubmit=e=>{e.preventDefault();text('domain-error','');action(async()=>{let domain;try{domain=hostname($('domain').value);}catch(e){text('domain-error',e.message);throw e;}const subdomains=$('subdomains').checked;if(!await requestPermissions({origins:permissionsFor(domain,subdomains)}))throw new Error('Website permission was not granted.');await send('add',{domain,subdomains});$('domain').value='';});};
$('add-current').onclick=()=>action(async()=>{const tab=await currentTab();if(!tab?.url)throw new Error('Enter the domain above, or enable usage stats to access current-tab metadata.');$('domain').value=hostname(tab.url);feedback('Domain filled in. Click Add to grant website access.');});
$('primary').onclick=()=>action(()=>send('timer',{action:current.session.state==='running'?'pause':current.session.state==='paused'?'resume':'start',...(current.wantsMac?{}:{minutes:Number($('minutes').value)})}));
$('stop').onclick=()=>action(()=>send('timer',{action:'stop'}));
$('tracking').onclick=()=>action(async()=>{if(!current.tracking&&!await requestPermissions({permissions:['tabs','idle']}))throw new Error('Usage permission was not granted. Blocking still works.');await send('tracking',{enabled:!current.tracking});});
$('connect').onclick=()=>action(async()=>{await send('connect');});
$('standalone').onclick=()=>action(()=>send('standalone'));$('use-mac').onclick=()=>action(()=>send('useMac'));$('emergency').onclick=()=>action(()=>send('emergency'));
$('exclude-form').onsubmit=e=>{e.preventDefault();action(async()=>{await send('exclude',{domain:$('exclude-domain').value});$('exclude-domain').value='';});};
$('clear').onclick=()=>{$('confirm-clear').hidden=false;};$('cancel-delete').onclick=()=>{$('confirm-clear').hidden=true;};$('confirm-delete').onclick=()=>action(async()=>{await send('clear');$('confirm-clear').hidden=true;});
$('export').onclick=()=>action(async()=>{const data=await send('export');const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='glance-focus-data.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);});
await refresh();setInterval(()=>{if(!busy)refresh();},250);
setInterval(()=>{if(current)renderCountdown(current);},100);

if($('open-dashboard'))$('open-dashboard').onclick=()=>action(()=>send('openDashboard'));
if($('pomodoro-form'))$('pomodoro-form').onsubmit=event=>{event.preventDefault();action(async()=>{const value={...formBaseline};for(const key of Object.keys(value)){const input=$('setting-'+key);if(input)value[key]=input.type==='checkbox'?input.checked:key==='durationPresetsMinutes'?input.value.split(',').map(x=>Number(x.trim())):input.type==='number'?Number(input.value)*(['focusDuration','shortBreakDuration','longBreakDuration'].includes(key)?60:1):input.value;}await send('pomodoroSettings',{expected:formBaseline,value});formDirty=false;});};
const pendingDomain=new URLSearchParams(location.search).get('domain');if(pendingDomain)$('domain').value=pendingDomain;

if($('revoke-dashboard'))$('revoke-dashboard').onclick=()=>action(()=>send('revokeDashboard'));

if($('pomodoro-form'))$('pomodoro-form').oninput=()=>{formDirty=true;};
if($('reload-pomodoro'))$('reload-pomodoro').onclick=()=>{formDirty=false;refresh();};
