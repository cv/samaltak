// Samaltak classic prototype — desktop, World menu, help, startup arrangement.
'use strict';

const WORKSPACE_TEXT = `"Put the cursor on a line or select an expression, then
 ${MOD}D do it · ${MOD}P print it · ${MOD}I inspect it · right-click for the menu."

"Green thread: fork a busy Process. Drag windows and type while it runs. ${MOD}. interrupts."
[1 to: 300 do: [:i | 999 factorial. Transcript show: '.']] forkNamed: 'crunch'

100 factorial
(1 to: 20) select: [:i | i isPrime]
3/4 + (1/4)
(3/4) + (1/3)
3 @ 4 + 1
Transcript show: 'hello, Samaltak'; cr
#(3 1 4 1 5 9 2 6) asSortedCollection
'hello world' asUppercase reversed
{3/4. 3@4. 'text'. #sym. $c. 2 raisedTo: 100}

"Errors open a notifier; syntax errors are marked inline."
1/0
3 zork  "${MOD}P, Debug, then Create defines #zork"
(3 + 4

"Debugger. Breakpoint: Browser, Integer, gcd:, click the gutter dot. Then ${MOD}P:"
48 gcd: 18
| sum | sum := 0. 1 to: 5 do: [:i | i = 3 ifTrue: [self halt]. sum := sum + (i * i)]. sum
#(3 1 4) inject: 0 into: [:acc :each | each = 1 ifTrue: [self halt]. acc + each]
"Watchpoint: ${MOD}I on p, right-click x, Halt on write; then fork the mover."
p := 3 @ 4
[5 timesRepeat: [p x: p x + 1. Transcript show: p printString; cr]] forkNamed: 'mover'
`;

const INSPECT_DEMO = `{3/4. 3@4. 'text'. #sym. $c. 2 raisedTo: 100}`;

// ---------------------------------------------------------------- top bar
function buildTopbar() {
  const spark = h('canvas', { id: 'spark', width: 128, height: 32 });
  const ms = h('b'), fps = h('span'), procs = h('span');
  const themeB = h('button', { class: 'tbtn', title: 'Theme', onclick: e => { const r = e.currentTarget.getBoundingClientRect(); themeMenu(r.right - 220, r.bottom + 4); }, html: '<svg viewBox="0 0 16 16"><path d="M8 1.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zm0 1.6v9.8a4.9 4.9 0 0 1 0-9.8z" fill="currentColor"/></svg>' });
  const typeB = h('button', { class: 'tbtn', title: 'Typography', onclick: e => { const r = e.currentTarget.getBoundingClientRect(); typeMenu(r.right - 260, r.bottom + 4); } }, 'Aa');
  const helpB = h('button', { class: 'tbtn', title: 'Help (?)', onclick: () => toggleHelp(true) }, '?');
  const bar = h('div', { id: 'topbar' },
    h('div', { class: 'brand', html: '<svg viewBox="0 0 16 16"><ellipse cx="8" cy="6.4" rx="4.6" ry="5.2" fill="var(--accent)"/><path d="M8 11.6c-.6 1.1-.2 2 .6 2.9" stroke="var(--ink-3)" fill="none" stroke-width="1"/><path d="M5.6 3.6c.7-.9 1.6-1.3 2.4-1.3" stroke="#fff" stroke-opacity=".6" fill="none" stroke-width="1.1" stroke-linecap="round"/></svg>Samaltak' }),
    h('span', { class: 'sep' }), h('span', null, 'nuuk.image'),
    h('span', { class: 'hint' }, 'Click the desktop for the World menu'),
    h('span', { class: 'stat', title: 'Compositor frame time (vsync-driven, independent of window Processes)' }, h('span', { class: 'lbl' }, 'compositor'), spark, ms, fps, h('span', { class: 'sep' }), procs),
    typeB, themeB, helpB);
  document.body.append(bar);
  const g = spark.getContext('2d');
  let acc = 0;
  Sched.listeners.add(() => {
    const ft = Sched.frameTimes;
    g.clearRect(0, 0, 128, 32);
    const cs = getComputedStyle(document.documentElement);
    const yOf = v => 30 - Math.min(50, v) / 50 * 28;
    g.fillStyle = cs.getPropertyValue('--line-2'); g.fillRect(0, Math.round(yOf(16.7)), 128, 1);
    g.beginPath();
    ft.forEach((v, i) => { const x = i * 2, y = yOf(v); i ? g.lineTo(x, y) : g.moveTo(x, y); });
    g.lineWidth = 2; g.lineJoin = 'round'; g.strokeStyle = cs.getPropertyValue('--accent'); g.stroke();
    ft.forEach((v, i) => { if (v > 22) { g.fillStyle = cs.getPropertyValue('--busy'); g.fillRect(i * 2 - 1, yOf(v) - 1, 3, 3); } });
    if (++acc % 15 === 0) {
      const avg = ft.reduce((a, b) => a + b, 0) / ft.length;
      ms.textContent = avg.toFixed(1) + ' ms';
      fps.textContent = Math.round(1000 / avg) + ' fps';
      procs.textContent = `${Sched.procs.length} processes`;
    }
  });
}

// Each theme is a palette + typography; its CSS lives in themes/<id>.css, scoped to html[data-theme="<id>"].
const THEMES = [
  { id: 'light', name: 'Classic', desc: 'system sans · blue' },
  { id: 'dark', name: 'Classic Dark', desc: 'system sans · blue' },
  { id: 'reading-room', name: 'Reading Room', desc: 'Charter small caps · terracotta' },
  { id: 'lamplight', name: 'Lamplight', desc: 'Charter small caps · amber, dark' },
  { id: 'blue-book', name: 'Blue Book', desc: 'Smalltalk-80, 1983' },
  { id: 'swiss', name: 'Swiss', desc: 'Helvetica · signal red' },
  { id: 'sage', name: 'Sage', desc: 'Avenir · forest green' },
  { id: 'phosphor', name: 'Phosphor', desc: 'all mono · amber, dark' },
];

// Typography overrides the theme's fonts; types/<id>.css is scoped to html[data-type="<id>"].
const TYPES = [
  { id: 'theme', name: 'Theme default', desc: 'fonts chosen by the theme' },
  { id: 'pi-orb', name: 'pi-orb', desc: 'Iosevka Etoile + JetBrains Mono' },
];

function setType(id) {
  if (!TYPES.some(t => t.id === id)) id = 'pi-orb';
  document.documentElement.dataset.type = id;
  localStorage.setItem('samaltak-type', id);
  const u = new URL(location.href); u.searchParams.set('type', id); history.replaceState(null, '', u);
}

function typeMenu(x, y) {
  const cur = document.documentElement.dataset.type;
  Menu.show(x, y, TYPES.map(t => ({ label: (t.id === cur ? '✓ ' : '\u2003') + t.name, desc: t.desc, fn: () => setType(t.id) })), 'Typography');
}

function setTheme(id) {
  if (!THEMES.some(t => t.id === id)) id = 'blue-book';
  document.documentElement.dataset.theme = id;
  localStorage.setItem('samaltak-theme', id);
  const u = new URL(location.href); u.searchParams.set('theme', id); history.replaceState(null, '', u);
  for (const w of WM.wins.values()) if (w.kind === 'mandel' && w.proc.state !== 'suspended') w.render();
}

function toggleTheme() {
  const i = THEMES.findIndex(t => t.id === document.documentElement.dataset.theme);
  setTheme(THEMES[(i + 1) % THEMES.length].id);
}

function themeMenu(x, y) {
  const cur = document.documentElement.dataset.theme;
  Menu.show(x, y, THEMES.map(t => ({ label: (t.id === cur ? '✓ ' : '\u2003') + t.name, desc: t.desc, fn: () => setTheme(t.id) })), 'Theme');
}

// ---------------------------------------------------------------- help
function buildHelp() {
  const row = (keys, text) => h('div', { class: 'row' }, h('span', { class: 'keys' }, ...keys.map(k => h('kbd', null, k))), h('span', null, text));
  const help = h('div', { id: 'help', hidden: true, onpointerdown: e => { if (e.target.id === 'help') toggleHelp(false); } },
    h('div', { class: 'card' },
      h('div', { class: 'titlebar' }, h('button', { class: 'tb-box tb-close', html: ICON.close, onclick: () => toggleHelp(false) }), h('div', { class: 'stripes' }), h('div', { class: 'title' }, 'Samaltak — how to drive it'), h('div', { class: 'stripes' })),
      h('div', { class: 'content' },
        h('p', { class: 'lede' }, 'Every window runs in its own green thread (Process). A busy window never freezes the others; the compositor keeps dragging smooth. The title-bar dot is the window\'s Process.'),
        h('h3', null, 'Evaluate (any text pane)'),
        row([MOD + 'D'], 'do it — selection, or the current line'),
        row([MOD + 'P'], 'print it — result inserted, selected'),
        row([MOD + 'I'], 'inspect it — opens an Inspector'),
        row([MOD + 'B'], 'browse it — class or implementor'),
        row([MOD + 'S'], 'accept — compile method in a Browser'),
        row(['right-click'], 'the same, as a menu'),
        h('h3', null, 'Processes'),
        row([MOD + '.'], 'user interrupt — suspends the busy Process'),
        row(['…forkNamed:'], "evaluate the 'crunch' line in the Workspace"),
        row(['click'], 'Mandelbrot: zoom (renders in its Process)'),
        row(['dbl-click'], 'Process Browser row: debug it'),
        h('h3', null, 'Windows & desktop'),
        row(['drag'], 'title bar moves; edges and corner resize'),
        row(['dbl-click'], 'title bar collapses / expands'),
        row(['click'], 'empty desktop: World menu'),
        row(['?'], 'this help · Esc closes'),
      )));
  document.body.append(help);
}
function toggleHelp(on) { const el = document.getElementById('help'); el.hidden = on === undefined ? !el.hidden : !on; }

// ---------------------------------------------------------------- World menu
function worldMenu(x, y) {
  const at = (w, hh) => ({ x: clamp(x - 30, 8, innerWidth - w - 8), y: clamp(y - 10, TOPBAR + 8, innerHeight - hh - 8) });
  Menu.show(x, y, [
    { head: 'open…' },
    { label: 'System Browser', fn: () => Tools.openBrowser(at(860, 500)) },
    { label: 'Workspace', fn: () => Tools.openWorkspace({ ...at(560, 300), w: 560, h: 300, value: '"A fresh workspace. Variables persist between evaluations."\n\nx := 6 * 7.\nx factorial printString size\n' }) },
    { label: 'Transcript', fn: () => Tools.openTranscript(at(520, 210)) },
    { label: 'Process Browser', fn: () => Tools.openProcessBrowser(at(530, 340)) },
    { label: 'Mandelbrot', desc: 'busy window demo', fn: () => Tools.openMandelbrot(at(330, 300)) },
    { label: 'Profiler', desc: 'samples · frames', fn: () => Tools.openProfiler && Tools.openProfiler(at(820, 520)) },
    { label: 'Breakpoints', desc: 'break · log · watch', fn: () => Tools.openBreakpoints && Tools.openBreakpoints(at(440, 236)) },
    '-',
    { label: 'Run long computation', desc: "fork 'crunch'", fn: () => runCrunch() },
    { label: 'User interrupt', key: MOD + '.', fn: () => userInterrupt() },
    '-',
    { label: 'Arrange windows', fn: () => arrange() },
    { label: 'Theme…', key: MOD + '⇧T', fn: () => themeMenu(x, y) },
    { label: 'Typography…', fn: () => typeMenu(x, y) },
    { label: 'Save image', fn: () => Toast.show('nuuk.image saved — 14.2 MB, 0.31 s (pretend)') },
    { label: 'Help…', key: '?', fn: () => toggleHelp(true) },
  ], 'World');
}

let crunchN = 0;
function runCrunch() {
  const name = crunchN++ ? `crunch ${crunchN}` : 'crunch';
  const src = `[1 to: 400 do: [:i | 1000 factorial. i \\\\ 40 = 0 ifTrue: [Transcript show: i printString; show: ' ']]] forkNamed: '${name}'`;
  const fk = detectFork(src);
  const ws = [...WM.wins.values()].find(w => w.kind === 'workspace');
  const p = spawnForked(fk, ws ? ws.editor : null, { source: src });
  Toast.show(`Forked ${procPrint(p)} — drag windows, type, it keeps going`);
  if (![...WM.wins.values()].some(w => w.kind === 'procs')) Tools.openProcessBrowser();
}

function userInterrupt() {
  const act = WM.active;
  const run = Sched.runnable().filter(p => p.kind !== 'system');
  let p = null;
  if (act) p = run.find(q => q === act.proc) || run.find(q => q.origin === act.id);
  if (!p) p = run.sort((a, b) => b.started - a.started)[0];
  if (!p) { Toast.show('User interrupt: no busy Process to interrupt'); return; }
  p.state = 'suspended';
  const near = WM.wins.get(p.win || p.origin) || act;
  Tools.openNotifier({ title: 'User Interrupt', message: `Process '${p.name}' (priority ${p.priority}) suspended at a safepoint.`, frames: framesOf(p), proc: p, near, interrupt: true, doit: p.source });
  WM.syncBusy();
}

// ---------------------------------------------------------------- arrangement
function layoutFor(vw, vh) {
  const sx = vw / 1440, sy = (vh - TOPBAR) / (900 - TOPBAR);
  const r = (x, y, w, hh) => ({ x: Math.round(x * sx), y: Math.round(TOPBAR + (y - TOPBAR) * sy), w: Math.round(w * sx), h: Math.round(hh * sy) });
  return {
    browser: r(18, 44, 866, 468),
    procs: r(898, 44, 524, 366),
    transcript: r(898, 424, 524, 140),
    workspace: r(18, 526, 690, 358),
    inspector: r(684, 572, 404, 312),
    mandel: r(1098, 578, 324, 306),
  };
}
function arrange() {
  const L = layoutFor(innerWidth, innerHeight);
  const kinds = { browser: 'browser', procs: 'procs', transcript: 'transcript', workspace: 'workspace', inspector: 'inspector', mandel: 'mandel' };
  for (const [k, kind] of Object.entries(kinds)) {
    const w = [...WM.wins.values()].find(x => x.kind === kind);
    if (w) { Object.assign(w, L[k]); w.root.classList.remove('collapsed'); w.apply(); w.onResize && w.onResize(); }
  }
}

function boot() {
  WM.desktop = h('div', { id: 'desktop' });
  document.body.append(WM.desktop);
  buildTopbar(); buildHelp();

  for (const p of FakeImage.processes) if (!p.window) Sched.add({ ...p, kind: 'system' });

  const nCls = FakeImage.allClasses().length;
  TranscriptBuf.append(`Samaltak 0.1 (prototype) · Smalltalk-80\nnuuk.image · ${FakeImage.packages.length} packages · ${nCls} classes · 6 layers\ngreen threads, preempted at safepoints\n`);

  const small = innerWidth < 1100 || innerHeight < 700;
  const L = small ? null : layoutFor(innerWidth, innerHeight);
  const ws = Tools.openWorkspace({ ...(L ? L.workspace : { x: 16, y: TOPBAR + 260, w: Math.min(600, innerWidth - 32), h: 300 }), value: WORKSPACE_TEXT, noFocus: true });
  Tools.openTranscript(L ? L.transcript : { x: Math.max(16, innerWidth - 540), y: TOPBAR + 60, w: Math.min(520, innerWidth - 32), h: 190 });
  Tools.openProcessBrowser(L ? L.procs : { x: Math.max(16, innerWidth - 560), y: TOPBAR + 20, w: Math.min(530, innerWidth - 32), h: 320 });
  Tools.openMandelbrot(L ? { ...L.mandel, delay: 400 } : { x: Math.max(16, innerWidth - 350), y: innerHeight - 310, w: 330, h: 300, delay: 400 });
  // the inspector on a sample collection, as if "inspect it" had been used
  const v = '__insp' + (++inspN);
  const r = MiniST.evaluate(`${v} := [${INSPECT_DEMO}] value`, { workspace: ws.id });
  Tools.openInspector({ ...(L ? L.inspector : WM.nextPos(450, 290)), result: r, varName: v, workspace: ws.id, near: ws });
  const br = Tools.openBrowser(L ? L.browser : { x: 12, y: TOPBAR + 12, w: Math.min(860, innerWidth - 24), h: Math.min(500, innerHeight - TOPBAR - 24) });
  br.focus();

  WM.desktop.addEventListener('pointerdown', e => {
    if (e.target !== WM.desktop || e.button > 2) return;
    e.stopPropagation();
    WM.focus(null);
    worldMenu(e.clientX, e.clientY);
  });
  WM.desktop.addEventListener('contextmenu', e => { if (e.target === WM.desktop) e.preventDefault(); });

  addEventListener('keydown', e => {
    const mod = IS_MAC ? e.metaKey : e.ctrlKey;
    if (mod && e.key === '.') { e.preventDefault(); e.stopPropagation(); userInterrupt(); return; }
    if (e.key === 'Escape') { Menu.hide(); toggleHelp(false); return; }
    if (mod && e.shiftKey && e.key.toLowerCase() === 't') { e.preventDefault(); toggleTheme(); return; }
    const inText = /^(TEXTAREA|INPUT)$/.test(document.activeElement && document.activeElement.tagName);
    if (e.key === '?' && !inText) { e.preventDefault(); toggleHelp(); }
    if (mod && ['d', 'p', 'i', 's', 'b'].includes(e.key.toLowerCase()) && !inText) e.preventDefault();
  }, true);

  Sched.start();
}
boot();
