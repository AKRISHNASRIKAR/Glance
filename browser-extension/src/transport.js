export async function send(type,data={}) {
  const result=await chrome.runtime.sendMessage({type,...data});
  if(!result?.ok)throw new Error(result?.error??'The extension is reloading. Please reopen it.');
  return result.data;
}
export const requestPermissions=permissions=>chrome.permissions.request(permissions);
export async function currentTab(){const [tab]=await chrome.tabs.query({active:true,currentWindow:true});return tab;}
