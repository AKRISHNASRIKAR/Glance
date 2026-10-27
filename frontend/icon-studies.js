const preference=matchMedia('(prefers-reduced-motion: reduce)');
const button=document.getElementById('toggle');
let playing=!preference.matches;
let chosen=false;
function render(){
 document.body.classList.toggle('motion-playing',playing);
 document.body.classList.toggle('motion-paused',!playing);
 button.textContent=playing?'Pause motion':'Play motion';
 document.getElementById('motion-state').textContent=playing?'Motion is playing.':'Motion is paused.';
}
button.addEventListener('click',()=>{chosen=true;playing=!playing;render();});
preference.addEventListener('change',()=>{if(!chosen){playing=!preference.matches;render();}});
render();
