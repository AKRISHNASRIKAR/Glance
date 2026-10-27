import {timerText} from './core.js';
const $=id=>document.getElementById(id);
let current,refreshing=false;
async function request(type,data={}){
  const result=await chrome.runtime.sendMessage({type,...data});
  if(!result?.ok)throw new Error(result?.error??'Reopen Glance Focus to reconnect.');
  return result.data;
}
function renderTime(){
  if(!current)return;
  $('time').textContent=timerText(current.session);
  const active=current.session.state==='running' && current.session.endAt>Date.now();
  $('message').textContent=current.session.state==='paused'?'Session paused':active?(current.session.phase==='focus'?'Time to focus':'Take a breath'):'Session complete';
  document.title=`${timerText(current.session)} · Glance`;
}
function render(state){current=state;renderTime();$('feedback').hidden=true;}
function showError(error){
  $('feedback').textContent=current?'Connection interrupted. Showing the last known timer.':'Open Glance Focus to reconnect to your session.';
  $('feedback').hidden=false;
  if(!current){$('message').textContent='Your focus space';$('time').textContent='--:--';}
}
async function refresh(){if(refreshing)return;refreshing=true;try{render(await request('state'));}catch(error){showError(error);}finally{refreshing=false;}}
try{
  const state=await request('blocked',{ruleID:Number(new URLSearchParams(location.search).get('rule'))});
  $('domain').textContent=state.entry?.domain??'';
  render(state);
}catch(error){showError(error);}
setInterval(refresh,500);
setInterval(renderTime,100);
