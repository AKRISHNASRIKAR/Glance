import {nativeConnectionError, hostname, matches, permissionsFor, remaining, blocks, idleSession, startSession, transition, makeRules, validUsageHost, usageSpan, usageEvents, trimEvents, summarize} from './core.js';
const HOST = 'app.glance.browser';
let state, queue = Promise.resolve(), port, pending = new Map(), poll, retry, lastSnapshotAt = 0;
let polling=false, connectionGeneration=0;
let connection = 'standalone', connectionError = '', usageCurrent = null, nativeSnapshot = null;
let appliedRulesKey=null;
const ready = (async () => {
  const stored = (await chrome.storage.local.get('glance')).glance;
  state = {clientID: crypto.randomUUID(), nextRule: 1, nextSequence: 1, entries: [], session: idleSession(), events: [], tracking: false, exclusions: [], wantsMac: false, suppressedSession: null, nativeEpoch: null, pendingPurge: false, ...stored};
  // Session storage survives worker suspension, but is cleared on browser restart.
  const span=(await chrome.storage.session.get('glanceUsage')).glanceUsage;
  if(span && Date.now()-span.since>=0 && Date.now()-span.since<=90000)usageCurrent=span;
})();
function enqueue(fn) { const task = queue.then(() => ready).then(fn); queue = task.catch(e => { console.warn('Glance:', e.message); }); return task; }
async function save() { state.events = trimEvents(state.events); await chrome.storage.local.set({glance: state}); }
function event(data) { state.events.push({...data, id: `${state.clientID}:${state.nextSequence}`, sequence: state.nextSequence++, clientID: state.clientID}); }
function localFocusRecord(outcome) {
  const s = state.session;
  if (s.owner !== 'extension' || !s.id) return;
  const current = s.state === 'running' ? Math.max(0, Math.min(Date.now() - (s.runSince ?? s.startedAt), s.remaining)) : 0;
  event({type: 'focus', at: Date.now(), seconds: Math.max(0, ((s.accumulated ?? 0) + current) / 1000), sessionID: s.id, outcome});
}
async function expire() {
  if (state.session.state === 'running' && remaining(state.session) <= 0) {
    // Only the Mac may advance/reset a Mac-owned phase. Keep zero until its next snapshot.
    if(state.session.owner==='mac')return;
    localFocusRecord('completed'); state.session = idleSession(); await save();
  }
}
async function rules() {
  await expire();
  for (const e of state.entries) e.granted = await chrome.permissions.contains({origins: permissionsFor(e.domain, e.subdomains)});
  const desired = makeRules(state.entries, state.session, chrome.runtime.getURL(''));
  const key=JSON.stringify(desired);
  if(key!==appliedRulesKey){const prior=await chrome.declarativeNetRequest.getSessionRules();await chrome.declarativeNetRequest.updateSessionRules({removeRuleIds:prior.map(r=>r.id),addRules:desired});appliedRulesKey=key;}
  await chrome.action.setBadgeText({text: blocks(state.session) ? 'ON' : ''});
  await chrome.action.setBadgeBackgroundColor({color:'#284b43'});
  await chrome.alarms.clear('deadline');
  if (state.session.state === 'running' && remaining(state.session)>0) await chrome.alarms.create('deadline', {when: state.session.endAt});
}
function blockedURL(entry) { return `${chrome.runtime.getURL('blocked.html')}?rule=${entry.ruleID}`; }
async function protectTab(tab) {
  if (!blocks(state.session) || tab.incognito) return;
  const host = validUsageHost(tab.pendingUrl ?? tab.url);
  const e = host && state.entries.find(e => e.enabled && e.granted && matches(host,e));
  if (e) await chrome.tabs.update(tab.id, {url: blockedURL(e)}).catch(()=>{});
}
async function protectOpenTabs() { for (const tab of await chrome.tabs.query({})) await protectTab(tab); }
async function flushUsage() {
  if (usageCurrent) { for(const e of usageEvents(usageCurrent))event(e); usageCurrent = null; }
  await chrome.storage.session.remove('glanceUsage');
}
async function observeUsage() {
  await flushUsage();
  if (!state.tracking || !await chrome.permissions.contains({permissions:['tabs','idle']})) return;
  if (await chrome.idle.queryState(60) !== 'active') return;
  const windows = await chrome.windows.getAll();
  const focused = windows.find(w=>w.focused && w.type === 'normal' && !w.incognito && w.state !== 'minimized');
  if (!focused) return;
  const [tab] = await chrome.tabs.query({windowId:focused.id,active:true});
  const domain = tab && !tab.incognito && validUsageHost(tab.url);
  if (domain && !state.exclusions.some(e=>domain===e || domain.endsWith(`.${e}`))) usageCurrent = {domain, since:Date.now()};
  if(usageCurrent)await chrome.storage.session.set({glanceUsage:usageCurrent});
}
function rpc(type, payload = {}) {
  if (!port) return Promise.reject(new Error('The Mac connection is unavailable.'));
  const id = crypto.randomUUID();
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{pending.delete(id);reject(new Error(type==='pair'?'Approval is still pending in Glance. Click Connect again after approving.':'Glance did not respond. Check that the app is running.'));},type==='pair'?120000:6000);
    pending.set(id,{resolve,reject,timer}); port.postMessage({protocolVersion:1,id,type,clientID:state.clientID,payload});
  });
}
async function adopt(snapshot) {
  if (!snapshot || snapshot.protocolVersion !== 1 || !snapshot.session || !Number.isFinite(snapshot.session.revision)) throw new Error('Incompatible Mac bridge. Update the app and extension.');
  if(!snapshot.pomodoro || !snapshot.preferences)throw new Error('Update and reopen the rebuilt Glance app to enable authoritative timer/settings sync.');
  if(state.session.owner==='extension' && state.session.id)localFocusRecord('interrupted');
  const old=new Map(state.entries.map(e=>[e.domain,e]));
  state.entries=snapshot.preferences.value.entries.map(e=>({...e,ruleID:old.get(e.domain)?.ruleID??state.nextRule++}));
  state.trackingDesired=snapshot.preferences.value.tracking;
  state.tracking=snapshot.preferences.value.tracking && await chrome.permissions.contains({permissions:['tabs','idle']});
  state.exclusions=[...snapshot.preferences.value.exclusions];
  nativeSnapshot=snapshot; lastSnapshotAt=Date.now(); connection='connected'; connectionError='';
  if (snapshot.session.id !== state.suppressedSession) state.suppressedSession=null;
  state.nativeEpoch=snapshot.epoch;
  state.session={...snapshot.session,owner:'mac',suppressed:!!snapshot.session.id && snapshot.session.id===state.suppressedSession};
}
function sharedPreferences(){return {entries:state.entries.map(({domain,subdomains,enabled})=>({domain,subdomains,enabled})),tracking:state.trackingDesired??state.tracking,exclusions:state.exclusions};}
async function syncStats() {
  if (state.pendingPurge) { await rpc('purgeStats',{throughSequence:state.pendingPurge.throughSequence ?? state.ack ?? 0}); state.pendingPurge=false; }
  const batch=state.events.filter(e=>e.sequence>(state.ack ?? 0)).slice(0,100);
  if (batch.length) { const result=await rpc('stats',{events:batch}); if (Number.isSafeInteger(result.ack)) state.ack=Math.max(state.ack ?? 0,result.ack); }
}
async function refreshMac() {
  if(!state.wantsMac)return;
  const generation=connectionGeneration;
  let s=await rpc('snapshot');
  if(!state.wantsMac || generation!==connectionGeneration)return;
  if(!s.preferences || !s.pomodoro)throw new Error('Update and reopen the rebuilt Glance app before connecting.');
  if(!s.preferences.initialized)s=await rpc('preferences',{expectedRevision:s.preferences.revision,value:sharedPreferences()});
  await adopt(s); await syncStats(); await save(); await rules(); await protectOpenTabs();
}
function scheduleReconnect() {
  clearTimeout(retry); if (state.wantsMac) retry=setTimeout(()=>{if(state.wantsMac)enqueue(()=>connect(false)).catch(()=>{});},5000);
}
async function connect(pair) {
  if(!state.wantsMac)return;
  if (!await chrome.permissions.contains({permissions:['nativeMessaging']})) throw new Error('Allow the Mac connection permission first.');
  if (typeof chrome.runtime.connectNative !== 'function') {
    connection='needs-setup';
    connectionError='Mac connection API is unavailable. Reload Glance Focus at chrome://extensions, then reopen it and connect again. Use Google Chrome for this developer preview.';
    throw new Error(connectionError);
  }
  if (!port) {
    connection='connecting';
    port=chrome.runtime.connectNative(HOST);
    const thisPort=port;
    port.onMessage.addListener(m=>{
      const item=pending.get(m.id);if (!item) return;
      pending.delete(m.id);clearTimeout(item.timer);
      m.ok?item.resolve(m.payload):item.reject(new Error(m.error ?? 'The Mac rejected this request.'));
    });
    port.onDisconnect.addListener(()=>{
      const rawError=chrome.runtime.lastError?.message;
      if(port!==thisPort)return;
      const message=nativeConnectionError(rawError ?? 'Mac disconnected.'); port=null; clearInterval(poll);
      for (const p of pending.values()) {clearTimeout(p.timer);p.reject(new Error(message));} pending.clear();
      connection=state.wantsMac?'reconnecting':'standalone';connectionError=message;scheduleReconnect();
    });
  }
  try {
    if (pair) await rpc('pair');
    await refreshMac(); clearInterval(poll);poll=setInterval(()=>{if(polling||!state.wantsMac)return;polling=true;enqueue(refreshMac).catch(e=>{if(state.wantsMac){connectionError=e.message;connection='reconnecting';}}).finally(()=>{polling=false;});},500);
  } catch(e) { connectionError=e.message;if (port) connection='reconnecting';scheduleReconnect();throw e; }
}
async function snapshot() {
  await expire();
  if (connection==='connected' && Date.now()-lastSnapshotAt>8000) connection='reconnecting';
  return {...state, events:undefined, stats:summarize(state.events), connection, connectionError, native: nativeSnapshot?.stats ?? null, nativeSession: nativeSnapshot?.session ?? null, pomodoro:state.wantsMac?nativeSnapshot?.pomodoro:null, preferences:state.wantsMac?nativeSnapshot?.preferences:null, remaining: remaining(state.session), blocking: blocks(state.session)};
}
async function handle(m) {
  if (!m || typeof m.type!=='string') throw new Error('Invalid request.');
  const sharedMutation=['add','remove','toggle','tracking','exclude','unexclude'].includes(m.type);
  if(sharedMutation && state.wantsMac){if(connection!=='connected')throw new Error('Reconnect to the Mac before editing shared settings, or choose Use standalone.');await refreshMac();}
  switch(m.type) {
    case 'state': await rules();return snapshot();
    case 'revokeDashboard':state.dashboardAccess=false;await save();return snapshot();
    case 'openDashboard':state.dashboardAccess=true;await save();await chrome.tabs.create({url:'https://glance-notch.vercel.app/extension/dashboard/'});return snapshot();
    case 'pomodoroSettings':
      if(!state.wantsMac || connection!=='connected')throw new Error('Connect to the Mac app to change its Pomodoro settings.');
      await adopt(await rpc('pomodoroSettings',{expected:m.expected,value:m.value}));break;
    case 'add': {
      const domain=hostname(m.domain);if (state.entries.some(e=>e.domain===domain)) throw new Error('That website is already on your list.');
      if (state.entries.length>=100) throw new Error('The local preview supports up to 100 blocked domains.');
      const subdomains=m.subdomains!==false;
      if (!await chrome.permissions.contains({origins:permissionsFor(domain,subdomains)})) throw new Error('Website permission was not granted.');
      state.entries.push({domain,subdomains,ruleID:state.nextRule++,enabled:true});break;
    }
    case 'remove':{const e=state.entries.find(e=>e.ruleID===m.ruleID);state.entries=state.entries.filter(e=>e.ruleID!==m.ruleID);if(e)await chrome.permissions.remove({origins:permissionsFor(e.domain,e.subdomains)});break;}
    case 'toggle': { const e=state.entries.find(e=>e.ruleID===m.ruleID);if(e)e.enabled=!e.enabled;break; }
    case 'timer': {
      if(state.wantsMac && connection!=='connected')throw new Error('Reconnecting to Glance. Your Mac owns the timer; wait for sync or choose Use standalone.');
      if (!['start','pause','resume','stop'].includes(m.action)) throw new Error('Unknown timer command.');
      if (state.wantsMac) {
        if (connection!=='connected') throw new Error('Mac is disconnected. Use Emergency stop or switch to standalone.');
        await refreshMac();
        await adopt(await rpc('timer',{action:m.action,expectedRevision:state.session.revision}));
      } else if (m.action==='start') {
        if(state.session.id) throw new Error('End the current session before starting another.');
        state.session={...startSession(Number(m.minutes)),accumulated:0,runSince:Date.now()};
      } else {
        const s=state.session;
        if(m.action==='stop') localFocusRecord('interrupted');
        const elapsed=s.state==='running'?Math.max(0,Math.min(Date.now()-(s.runSince??s.startedAt),s.remaining)):0;
        state.session=transition(s,m.action);
        if(m.action==='pause')state.session.accumulated=(s.accumulated??0)+elapsed;
        if(m.action==='resume')state.session.runSince=Date.now();
      }
      break;
    }
    case 'connect':state.wantsMac=true;await save();await connect(true);break;
    case 'useMac':
      if(state.session.owner==='extension' && state.session.id) localFocusRecord('interrupted');
      state.session=idleSession();state.suppressedSession=null;await refreshMac();break;
    case 'standalone':
      if(state.session.owner==='mac' && blocks(state.session))state.suppressedSession=state.session.id;
      if(state.session.owner==='extension' && state.session.id)localFocusRecord('interrupted');
      state.wantsMac=false;connectionGeneration++;clearInterval(poll);clearTimeout(retry);state.session=idleSession();connection='standalone';port?.disconnect();port=null;break;
    case 'emergency':
      state.suppressedSession=state.session.id;localFocusRecord('interrupted');state.session=state.wantsMac?{...state.session,suppressed:true}:{...idleSession(),suppressed:true};break;
    case 'tracking':
      if(m.enabled && !await chrome.permissions.contains({permissions:['tabs','idle']}))throw new Error('Usage tracking permission was not granted.');
      await flushUsage();state.tracking=!!m.enabled;state.trackingDesired=state.tracking;await observeUsage();break;
    case 'exclude': {const d=hostname(m.domain);if(!state.exclusions.includes(d))state.exclusions.push(d);await observeUsage();break;}
    case 'unexclude':state.exclusions=state.exclusions.filter(d=>d!==m.domain);await observeUsage();break;
    case 'clear':await flushUsage();state.events=[];state.pendingPurge={throughSequence:state.nextSequence-1};state.ack=state.nextSequence-1;if(connection==='connected')await syncStats();break;
    case 'export':await observeUsage();await save();return {schemaVersion:1,exportedAt:new Date().toISOString(),events:state.events};
    case 'blocked': {
      const e=state.entries.find(e=>e.ruleID===m.ruleID);
      if(!e)return {entry:null,...await snapshot()};
      if(blocks(state.session)) {
        const key=`${state.session.id}:${m.tabID}:${e.ruleID}`;
        if(state.lastBlocked?.key!==key || Date.now()-state.lastBlocked.at>10000) {event({type:'blocked',domain:e.domain,seconds:0,at:Date.now(),sessionID:state.session.id});state.lastBlocked={key,at:Date.now()};}
      }
      await save();return {entry:e,...await snapshot()};
    }
    default:throw new Error('Unsupported request.');
  }
  if(sharedMutation && state.wantsMac){
    try{await adopt(await rpc('preferences',{expectedRevision:nativeSnapshot.preferences.revision,value:sharedPreferences()}));}
    catch(error){await refreshMac().catch(()=>{});throw error;}
  }
  await save();await rules();await protectOpenTabs();return snapshot();
}
chrome.runtime.onMessage.addListener((m,sender,reply)=>{
  if(sender.id!==chrome.runtime.id) return false;
  // Only our packaged pages can mutate preferences or control timers.
  if(!sender.url?.startsWith(chrome.runtime.getURL('')))return false;
  if(m.type==='blocked')m.tabID=sender.tab?.id??0;
  if(m.type==='emergency') {
    ready.then(async()=>{
      state.suppressedSession=state.session.id;localFocusRecord('interrupted');state.session=state.wantsMac?{...state.session,suppressed:true}:{...idleSession(),suppressed:true};
      await chrome.declarativeNetRequest.updateSessionRules({removeRuleIds:state.entries.map(e=>e.ruleID)});appliedRulesKey=null;
      await chrome.action.setBadgeText({text:''});await save();return snapshot();
    }).then(data=>reply({ok:true,data})).catch(e=>reply({ok:false,error:e.message}));return true;
  }
  enqueue(()=>handle(m)).then(data=>reply({ok:true,data})).catch(e=>reply({ok:false,error:e.message}));return true;
});
chrome.alarms.onAlarm.addListener(()=>enqueue(async()=>{await observeUsage();await save();await rules();if(state.wantsMac&&!port)await connect(false).catch(()=>{});}).catch(()=>{}));
chrome.tabs.onActivated.addListener(()=>enqueue(async()=>{await observeUsage();await save();}).catch(()=>{}));
chrome.tabs.onUpdated.addListener((id,change,tab)=>{if(change.url||change.status==='complete')enqueue(async()=>{await expire();await protectTab(tab);if(tab.active){await observeUsage();await save();}}).catch(()=>{});});
chrome.tabs.onRemoved.addListener(()=>enqueue(async()=>{await observeUsage();await save();}).catch(()=>{}));
chrome.windows.onFocusChanged.addListener(()=>enqueue(async()=>{await observeUsage();await save();}).catch(()=>{}));
chrome.permissions.onRemoved.addListener(()=>enqueue(async()=>{if(!await chrome.permissions.contains({permissions:['tabs','idle']})){state.tracking=false;usageCurrent=null;}await rules();await save();}).catch(()=>{}));
chrome.idle?.onStateChanged.addListener(()=>enqueue(async()=>{await observeUsage();await save();}).catch(()=>{}));
chrome.runtime.onStartup.addListener(()=>enqueue(async()=>{await rules();await protectOpenTabs();}).catch(()=>{}));
chrome.runtime.onInstalled.addListener(()=>enqueue(async()=>{await rules();}).catch(()=>{}));
enqueue(async()=>{
 await chrome.alarms.create('checkpoint',{periodInMinutes:1});
 // Recover the authoritative Mac snapshot before exposing a stale/reset display.
 if(state.wantsMac){connection='reconnecting';await connect(false).catch(()=>{});}
 await rules();await observeUsage();
}).catch(()=>{});

// Hosted dashboard is a view/controller of this profile, never a separate database.
chrome.runtime.onMessageExternal.addListener((message,sender,reply)=>{
  let url;try{url=new URL(sender.url);}catch{return false;}
  if(url.origin!=='https://glance-notch.vercel.app' || !url.pathname.startsWith('/extension/dashboard/') || (sender.frameId!==undefined && sender.frameId!==0))return false;
  const allowed=new Set(['state','timer','toggle','remove','exclude','unexclude','tracking','clear','export','pomodoroSettings']);
  enqueue(async()=>{
    if(!state.dashboardAccess)throw new Error('Open Glance Focus and choose Open web dashboard to allow this page to access your local data.');
    if(message?.type==='permissionSetup'){
      const query=new URLSearchParams();
      if(message.domain)query.set('domain',hostname(message.domain));
      else if(message.tracking)query.set('permission','tracking');
      else throw new Error('Choose a domain or usage permission.');
      await chrome.tabs.create({url:chrome.runtime.getURL('options.html')+'?'+query});return {opened:true};
    }
    if(!allowed.has(message?.type))throw new Error('This command is not available to the web dashboard.');
    return handle(message);
  }).then(data=>reply({ok:true,data})).catch(error=>reply({ok:false,error:error.message}));return true;
});
