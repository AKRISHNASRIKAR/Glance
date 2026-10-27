const tabs = [...document.querySelectorAll('[role="tab"]')];
function selectTab(tab) {
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
    document.getElementById(`screen-${item.dataset.screen}`).hidden = !selected;
  }
  document.getElementById('activity-panel').setAttribute('aria-labelledby', tab.id);
  const screen = document.getElementById(`screen-${tab.dataset.screen}`);
  document.querySelectorAll('[data-demo-controls]').forEach(group => { group.hidden = group.dataset.demoControls !== tab.dataset.screen; });
  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) screen.animate([{opacity:0, transform:'translateY(4px)'},{opacity:1, transform:'translateY(0)'}], {duration:280, easing:'cubic-bezier(.2,.7,.2,1)'});
  document.getElementById('activity-panel').classList.toggle('artwork-preview', tab.dataset.screen === 'music');
  document.getElementById('activity-panel').dataset.screen = tab.dataset.screen;
  const index = tabs.indexOf(tab);
  document.querySelectorAll('.native-dots i').forEach((dot, i) => dot.classList.toggle('selected', i === index));
  document.getElementById('previous-screen').disabled = index === 0;
  document.getElementById('next-screen').disabled = index === tabs.length - 1;
  document.getElementById('demo-note').textContent = {
    music: 'Now Playing · Artwork appearance. Sample playback; no connection to your Mac.',
    focus: 'Pomodoro · Classic appearance. Try a focus session in this browser demo.',
    claude: 'Claude Code · Needs your input. Sample status; no live Claude session.'
  }[tab.dataset.screen];
}
for (const tab of tabs) {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', (event) => {
    let next;
    const index = tabs.indexOf(tab);
    if (event.key === 'ArrowRight') next = tabs[(index + 1) % tabs.length];
    if (event.key === 'ArrowLeft') next = tabs[(index - 1 + tabs.length) % tabs.length];
    if (event.key === 'Home') next = tabs[0];
    if (event.key === 'End') next = tabs[tabs.length - 1];
    if (next) { event.preventDefault(); selectTab(next); next.focus(); }
  });
}
const playback = document.getElementById('play-toggle');
playback.addEventListener('click', () => {
  const paused = playback.getAttribute('aria-label') === 'Pause demo playback';
  playback.setAttribute('aria-label', paused ? 'Resume demo playback' : 'Pause demo playback');
  playback.textContent = paused ? '▶' : 'Ⅱ';
});

for (const [id, delta] of [['previous-screen', -1], ['next-screen', 1]]) {
  document.getElementById(id).addEventListener('click', () => {
    const index = tabs.findIndex(tab => tab.getAttribute('aria-selected') === 'true');
    if (tabs[index + delta]) selectTab(tabs[index + delta]);
  });
}
// A browser-local demo of the native Classic Pomodoro controls.
const presets = [5, 15, 25, 50];
let phase = 'focus';
let minutes = 25;
let remaining = minutes * 60;
let timerState = 'idle';
let deadline = 0;
let interval;
const timerButton = document.getElementById('timer-toggle');
function renderTimer() {
  document.getElementById('timer-value').textContent = `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, '0')}`;
  document.getElementById('duration-label').textContent = `${minutes}m`;
  document.querySelector('.native-stepper').hidden = timerState !== 'idle';
  document.querySelector('.native-phases').hidden = timerState !== 'idle';
  document.querySelector('.native-running').hidden = timerState === 'idle';
  document.querySelector('.native-running > span').textContent = phase === 'focus' ? 'WORK MODE' : 'REST';
  document.getElementById('timer-reset').hidden = timerState === 'idle';
  document.getElementById('timer-skip').hidden = timerState !== 'idle' || phase === 'focus';
  timerButton.textContent = timerState === 'running' ? 'Ⅱ' : '▶';
  timerButton.setAttribute('aria-label', `${timerState === 'idle' ? 'Start' : timerState === 'running' ? 'Pause' : 'Resume'} demo timer`);
  document.querySelectorAll('[data-phase]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.phase === phase)));
  document.querySelector('.native-pomodoro').dataset.phase = phase;
  document.getElementById('activity-panel').dataset.phase = phase;
  document.querySelector('.native-pomodoro').dataset.state = timerState;
  document.getElementById('timer-phase-label').textContent = timerState === 'paused' ? 'PAUSED' : phase === 'focus' ? 'WORK MODE' : 'REST';
  document.querySelector('.orbit-progress').style.strokeDashoffset = 1 - Math.max(0.004, Math.min(1, 1 - remaining / (minutes * 60)));
}
function resetTimer() {
  clearInterval(interval);
  timerState = 'idle';
  remaining = minutes * 60;
  renderTimer();
}
for (const [id, delta] of [['duration-up', 1], ['duration-down', -1]]) {
  document.getElementById(id).addEventListener('click', () => {
    const index = presets.indexOf(minutes);
    minutes = presets[Math.max(0, Math.min(presets.length - 1, index + delta))];
    resetTimer();
  });
}
for (const button of document.querySelectorAll('[data-phase]')) {
  button.addEventListener('click', () => { phase = button.dataset.phase; minutes = phase === 'focus' ? 25 : 5; resetTimer(); });
}
timerButton.addEventListener('click', () => {
  if (timerState === 'running') {
    remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
    clearInterval(interval);
    timerState = 'paused';
  } else {
    timerState = 'running';
    deadline = Date.now() + remaining * 1000;
    interval = setInterval(() => {
      remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      if (remaining === 0) { clearInterval(interval); timerState = 'paused'; }
      renderTimer();
    }, 1000);
  }
  renderTimer();
});
document.getElementById('timer-reset').addEventListener('click', resetTimer);
document.getElementById('timer-skip').addEventListener('click', () => { phase = 'focus'; minutes = 25; resetTimer(); });
document.getElementById('claude-open').addEventListener('click', () => {
  document.getElementById('demo-note').textContent = 'In the Mac app, Open Claude activates your terminal. This website shows a sample session.';
});
for (const button of document.querySelectorAll('[data-transport]')) {
  button.addEventListener('click', () => {
    document.getElementById('demo-note').textContent = 'In the Mac app, these controls change tracks in Apple Music or Spotify. This is sample playback.';
  });
}
renderTimer();

// Reveal once, with readable fallbacks when motion is disabled or unavailable.
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
if (!motionPreference.matches && 'IntersectionObserver' in window) {
  const revealTargets = document.querySelectorAll('.section-intro, .feature-grid article, .principles > div, .get-started');
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) { entry.target.classList.add('revealed'); observer.unobserve(entry.target); }
    }
  }, {threshold:0.12});
  revealTargets.forEach((element, index) => {
    element.classList.add('motion-reveal');
    element.style.setProperty('--reveal-delay', `${index % 3 * 70}ms`);
    observer.observe(element);
  });
  motionPreference.addEventListener('change', event => {
    if (event.matches) { revealTargets.forEach(element => element.classList.add('revealed')); observer.disconnect(); }
  });
}

// Mobile navigation disclosure and full-size demo controls.
const mobileControls = document.createElement('div');
mobileControls.className = 'demo-mobile-controls';
mobileControls.dataset.demoControls = 'music';
mobileControls.setAttribute('aria-label', 'Music demo controls');
for (const [label, target] of [['Previous track', '[data-transport="previous"]'], ['Play / pause', '#play-toggle'], ['Next track', '[data-transport="next"]']]) {
  const button = document.createElement('button');
  button.textContent = label;
  button.addEventListener('click', () => document.querySelector(target).click());
  mobileControls.append(button);
}
document.querySelector('.preview-controls').after(mobileControls);
for (const tab of tabs) tab.addEventListener('click', () => { mobileControls.hidden = tab.dataset.screen !== 'music'; });
const artworkCheck = new Image();
artworkCheck.onload = () => document.getElementById('activity-panel').removeAttribute('aria-busy');
artworkCheck.onerror = () => {
  document.getElementById('activity-panel').removeAttribute('aria-busy');
  document.getElementById('demo-note').textContent = 'Artwork could not load. Playback and timer demos are still available.';
};
document.getElementById('activity-panel').setAttribute('aria-busy', 'true');
artworkCheck.src = 'assets/now-playing-reference.webp';

const focusControls = document.createElement('div');
focusControls.className = 'demo-mobile-controls';
focusControls.dataset.demoControls = 'focus';
focusControls.hidden = true;
focusControls.setAttribute('aria-label', 'Timer demo controls');
for (const [label, target] of [['Shorter', '#duration-down'], ['Start / pause', '#timer-toggle'], ['Longer', '#duration-up'], ['Reset', '#timer-reset']]) {
  const button = document.createElement('button'); button.textContent = label;
  button.addEventListener('click', () => document.querySelector(target).click());
  focusControls.append(button);
}
mobileControls.after(focusControls);
