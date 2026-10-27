const extensionID='cdhoadjbhjmgclemjdjdbcfknognhjdm';
export async function send(type,data={}) {
  if(!globalThis.chrome?.runtime?.sendMessage)throw new Error('Load Glance Focus in Chrome, then choose Open web dashboard in its popup.');
  const result=await chrome.runtime.sendMessage(extensionID,{type,...data});
  if(!result?.ok)throw new Error(result?.error??'Open Glance Focus and choose Open web dashboard to connect this page.');
  return result.data;
}
export async function requestPermissions(request){
  // Browser permission prompts must run in a packaged extension page.
  if(request.origins){const domain=new URL(request.origins[0]).hostname.replace(/^\*\./,'');await send('permissionSetup',{domain});}
  else if(request.permissions?.includes('tabs'))await send('permissionSetup',{tracking:true});
  else throw new Error('Pair with your Mac from the extension popup.');
  throw new Error('An extension settings tab has opened. Approve the change there, then return here.');
}
export async function currentTab(){return null;}
