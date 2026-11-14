'use strict';
const themeButtons = [...document.querySelectorAll('[data-theme-choice]')];
function setTheme(theme) {
  const choice = ['light', 'dark', 'system'].includes(theme) ? theme : 'system';
  if (choice === 'system') delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = choice;
  themeButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.themeChoice === choice)));
  try { localStorage.setItem('garhub.theme', choice); } catch { /* Preference storage is optional. */ }
}
let savedTheme = 'system';
try { savedTheme = localStorage.getItem('garhub.theme') || 'system'; } catch { /* System appearance remains usable. */ }
setTheme(savedTheme);
themeButtons.forEach(button => button.addEventListener('click', () => setTheme(button.dataset.themeChoice)));
const examples = {
  run: {sport:'RUNNING · OUTDOOR',title:'The morning loop',oneLabel:'Distance',one:'8.24 km',two:'42:18',threeLabel:'Avg. pace',three:'5:08 /km',metric:'Heart rate · bpm',trace:'M0 124L15 118 30 100 45 104 60 86 75 83 90 64 105 69 120 60 135 72 150 48 165 53 180 39 195 57 210 49 225 71 240 58 255 64 270 42 285 48 300 32 315 43 330 39 345 58 360 50 375 57 390 38 405 44 420 62 435 46 450 53 465 36 480 49 495 64 510 77 525 89 540 100'},
  ride: {sport:'CYCLING · OUTDOOR',title:'The long way home',oneLabel:'Distance',one:'64.8 km',two:'2:21:40',threeLabel:'Avg. power',three:'184 W',metric:'Power · watts',trace:'M0 115L20 85 40 110 60 45 80 62 100 27 120 49 140 115 160 125 180 76 200 49 220 73 240 30 260 45 280 71 300 99 320 115 340 67 360 41 380 67 400 25 420 47 440 99 460 69 480 40 500 83 520 65 540 110'},
  swim: {sport:'SWIMMING · POOL',title:'One length at a time',oneLabel:'Distance',one:'2,000 m',two:'42:00',threeLabel:'Avg. pace',three:'2:06 /100m',metric:'Pace · min/100m',trace:'M0 45L20 49 40 43 60 96 80 46 100 49 120 45 140 103 160 43 180 49 200 47 220 110 240 41 260 44 280 47 300 103 320 45 340 49 360 43 380 108 400 48 420 45 440 50 460 107 480 46 500 49 520 48 540 111'},
  hike: {sport:'HIKING · OUTDOOR',title:'A little higher',oneLabel:'Distance',one:'12.6 km',two:'3:42:10',threeLabel:'Total ascent',three:'640 m',metric:'Elevation · metres',trace:'M0 124L20 115 40 102 60 111 80 95 100 85 120 69 140 76 160 52 180 64 200 42 220 47 240 31 260 38 280 20 300 37 320 44 340 59 360 51 380 76 400 70 420 89 440 86 460 104 480 99 500 113 520 119 540 126'},
  gym: {sport:'STRENGTH · INDOOR',title:'Time under tension',oneLabel:'Recorded sets',one:'18 sets',two:'48:30',threeLabel:'Avg. heart rate',three:'118 bpm',metric:'Heart rate · bpm',trace:'M0 120L20 94 40 63 60 112 80 96 100 54 120 117 140 95 160 49 180 110 200 90 220 46 240 108 260 91 280 39 300 107 320 93 340 42 360 109 380 95 400 46 420 107 440 91 460 37 480 106 500 94 520 63 540 118'}
};
const sportTabs = [...document.querySelectorAll('[data-sport]')];
function selectSport(tab) {
  const data = examples[tab.dataset.sport];
  const fields = {'preview-sport':'sport','preview-title':'title','stat-one-label':'oneLabel','stat-one':'one','stat-two':'two','stat-three-label':'threeLabel','stat-three':'three','chart-label':'metric'};
  Object.entries(fields).forEach(([id, key]) => { document.getElementById(id).textContent = data[key]; });
  document.getElementById('preview-trace').setAttribute('d', data.trace);
  document.getElementById('chart-title').textContent = `Fictional ${data.metric.toLowerCase()} recording`;
  document.getElementById('preview-panel').setAttribute('aria-labelledby', tab.id);
  sportTabs.forEach(button => { const active = button === tab; button.setAttribute('aria-selected', String(active)); button.tabIndex = active ? 0 : -1; });
}
sportTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectSport(tab));
  tab.addEventListener('keydown', event => {
    let target;
    if(event.key === 'ArrowRight') target = (index + 1) % sportTabs.length;
    if(event.key === 'ArrowLeft') target = (index + sportTabs.length - 1) % sportTabs.length;
    if(event.key === 'Home') target = 0;
    if(event.key === 'End') target = sportTabs.length - 1;
    if(target !== undefined) { event.preventDefault(); sportTabs[target].focus(); selectSport(sportTabs[target]); }
  });
});
