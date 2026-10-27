// Platform-independent policy shared by the worker and meaningful unit tests.
export const PROTOCOL = 1;
export const RETENTION_MS = 30 * 86400000;
export function hostname(input) {
  const text = String(input ?? '').trim();
  if (!text || /[\s*]/.test(text)) throw new Error('Enter a website domain, such as youtube.com.');
  let url;
  try { url = new URL(text.includes('://') ? text : `https://${text}`); } catch { throw new Error('That website address is invalid.'); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.port) throw new Error('Use an HTTP or HTTPS domain without credentials or a port.');
  const host = url.hostname.toLowerCase().replace(/\.$/, '');
  if (!host || host === 'localhost' || !host.includes('.') || /^[\d.:]+$/.test(host) || host.length > 253 || host.split('.').some(x => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(x))) throw new Error('Use a public website domain. Local addresses are excluded.');
  return host;
}
export function matches(host, entry) { return host === entry.domain || (entry.subdomains && host.endsWith(`.${entry.domain}`)); }
export function permissionsFor(domain, subdomains = true) { return [`http://${subdomains ? '*.' : ''}${domain}/*`, `https://${subdomains ? '*.' : ''}${domain}/*`]; }
export function remaining(session, now = Date.now()) { return session.state === 'running' ? Math.max(0, session.endAt - now) : Math.max(0, session.remaining ?? 0); }
export function blocks(session, now = Date.now()) { return session.phase === 'focus' && session.state === 'running' && remaining(session, now) > 0 && !session.suppressed; }
export function idleSession(minutes = 25) { return {id: null, owner: 'extension', phase: 'focus', state: 'idle', remaining: minutes * 60000, endAt: null, revision: 0}; }
export function startSession(minutes, now = Date.now(), id = crypto.randomUUID()) {
  if (!Number.isFinite(minutes) || minutes < 1 || minutes > 120) throw new Error('Choose a duration between 1 and 120 minutes.');
  return {id, owner: 'extension', phase: 'focus', state: 'running', remaining: minutes * 60000, endAt: now + minutes * 60000, startedAt: now, revision: 1};
}
export function transition(session, action, now = Date.now()) {
  if (action === 'pause' && session.state === 'running') return {...session, state: 'paused', remaining: remaining(session, now), endAt: null, revision: session.revision + 1};
  if (action === 'resume' && session.state === 'paused') return {...session, state: 'running', endAt: now + session.remaining, revision: session.revision + 1};
  if (action === 'stop') return idleSession();
  throw new Error('The session changed. Refresh and try again.');
}
export function makeRules(entries, session, baseURL, now = Date.now()) {
  if (!blocks(session, now)) return [];
  return entries.filter(e => e.enabled && e.granted).map(e => ({id: e.ruleID, priority: 1, action: {type: 'redirect', redirect: {url: `${baseURL}blocked.html?rule=${e.ruleID}`}}, condition: {regexFilter: `^https?://${e.subdomains ? '([a-z0-9-]+\\.)*' : ''}${e.domain.replace(/\./g, '\\.')}(:[0-9]+)?(/|$)`, resourceTypes: ['main_frame'], isUrlFilterCaseSensitive: false}}));
}
export function validUsageHost(url) { try { const u=new URL(url); return ['http:','https:'].includes(u.protocol) ? hostname(u.hostname) : null; } catch { return null; } }
export function usageSpan(prior, now = Date.now()) {
  if (!prior?.domain || !Number.isFinite(prior.since) || now <= prior.since) return null;
  // A restart cannot invent an offline browsing interval. Checkpoint loss is bounded.
  const seconds = Math.min((now - prior.since) / 1000, 60);
  return seconds >= 0.1 ? {type: 'usage', domain: prior.domain, seconds, at: now} : null;
}
export function trimEvents(events, now = Date.now()) { return events.filter(e => e.at >= now - RETENTION_MS && e.at <= now + 300000).slice(-50000); }
export function summarize(events) {
  const sites = new Map(), days = new Map(); let focusSeconds = 0, completed = 0, interrupted = 0, blocked = 0;
  for (const e of events) {
    const date=new Date(e.at);const key=`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
    if(!days.has(key))days.set(key,{date:key,usageSeconds:0,focusSeconds:0,completed:0,blocked:0});
    const day=days.get(key);
    if(e.type==='usage')day.usageSeconds+=e.seconds;
    if(e.type==='focus'){day.focusSeconds+=e.seconds;if(e.outcome==='completed')day.completed++;}
    if(e.type==='blocked')day.blocked++;
    if (e.type === 'usage') sites.set(e.domain, (sites.get(e.domain) ?? 0) + e.seconds);
    if (e.type === 'focus') { focusSeconds += e.seconds; e.outcome === 'completed' ? completed++ : interrupted++; }
    if (e.type === 'blocked') blocked++;
  }
  return {sites: [...sites].sort((a,b) => b[1]-a[1]), daily:[...days.values()].sort((a,b)=>b.date.localeCompare(a.date)), focusSeconds, completed, interrupted, blocked};
}

export function usageEvents(prior,now=Date.now()) {
  const total=usageSpan(prior,now);if(!total)return [];
  let start=now-total.seconds*1000;const result=[];
  while(start<now){const next=new Date(start);next.setHours(24,0,0,0);const end=Math.min(now,next.getTime());result.push({...total,seconds:(end-start)/1000,at:end-1});start=end;}
  return result;
}

export function nativeConnectionError(message = 'Mac disconnected.') {
  if (/native messaging host not found/i.test(message)) return 'Glance’s Mac helper is not registered for this browser. Open the rebuilt Glance app, go to Settings → Browser Focus, and click Enable browser connection or Repair browser connection. Then reconnect here. This preview supports Google Chrome and Chromium.';
  return message;
}

// Matches Swift TimeFormatting.minutesSeconds: nearest whole second, not ceil.
export function timerText(session, now = Date.now()) {
  const seconds = Math.max(0, Math.round(remaining(session, now) / 1000));
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
}
