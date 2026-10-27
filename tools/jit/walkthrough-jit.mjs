#!/usr/bin/env node
// Records the JIT video on the real system, driven only through samaltak-ctl and recorded from the compositor: the race
// against Pharo 12 in two Terminals, the JIT's sources, its tiers, baseline and optimized machine code, deoptimization
// while the Mandelbrot renders, Pharo's Cogit and the running system switched between the tiers.
// Usage: node walkthrough-jit.mjs <out-dir>   →  <out-dir>/raw.mp4, captions.json
// Needs Pharo 12 for the race (vm/tests/bench/awfy.sh --pharo: $PHARO_VM, $PHARO_IMAGE, default /tmp/pharo-dl).
// The browser writes accepted methods into a scratch copy of the sources (--source-dir), not the repo.
import { execFileSync } from 'node:child_process';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { VideoSession, sleep } from '../video-lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');
const out = resolve(process.argv[2] || join(root, '.context/video-jit'));

const S = new VideoSession({
  out,
  stepsFile: join(here, 'narration.json'),
  session: process.env.WALKTHROUGH_SESSION || 'jit',
  image: process.env.WALKTHROUGH_IMAGE || join(root, 'build/samaltak.image'),
});
const scratch = '/tmp/samaltak-jit';
const srcDir = join(scratch, 'src');
rmSync(scratch, { recursive: true, force: true });
execFileSync('mkdir', ['-p', scratch]);
execFileSync('cp', ['-R', join(root, 'src'), srcDir]);
const openArgs = ['--source-dir', srcDir];
// The Terminals run the user's login shell: a scratch HOME with a short prompt, no personal shell configuration.
const home = join(out, 'home');
execFileSync('mkdir', ['-p', home]);
writeFileSync(join(home, '.zshrc'), "PS1='%F{blue}nuuk%f %# '\n");
Object.assign(S.env, { HOME: home, SHELL: '/bin/zsh' });
const ctl = (...a) => S.ctl(...a), act = (...a) => S.act(...a);
const DESK = '1431,250';   // the desk at the right edge, never covered
const W = { workspace: '@w1', transcript: '@w2', procs: '@w3', mandel: '@w4', inspector: '@w5', browser: '@w6' };
const LAPS = 25;
const PHARO_CORE = '/tmp/pharo-dl/vm/Pharo.app/Contents/MacOS/Plugins/libPharoVMCore.dylib';

// The Workspace's do-its, typed there before the recording.
const DO = {
  fresh: '(Complex >> #-) jitSendSites',
  calls: '| z | z := Complex real: 0.5 imaginary: 0.25. z - z. z - z. z - z. (Complex >> #-) jitSendSites',
  baseline: "TextView openOn: ((Complex >> #+) machineCodeFor: #baseline) title: 'Machine code: Complex>>+ (baseline)' near: nil",
  opt: "TextView openOn: ((Complex >> #+) machineCodeFor: #opt) title: 'Machine code: Complex>>+ (opt)' near: nil",
  before: "\"before\" | s | s := Smalltalk vm statistics. 'invalidations ', s optInvalidations printString, ', deoptimizations ', s optDeoptimizations printString",
  after: "\"after\" | s | s := Smalltalk vm statistics. 'invalidations ', s optInvalidations printString, ', deoptimizations ', s optDeoptimizations printString",
  baselineOnly: "Smalltalk vm jitParameters: {'baseline'. nil. nil. nil}. (1 to: 6) collect: [:i | [Mandelbrot new innerBenchmarkLoop: 500] timeToRun]",
  optAgain: "Smalltalk vm jitParameters: {'opt'. nil. nil. nil}. (1 to: 6) collect: [:i | [Mandelbrot new innerBenchmarkLoop: 500] timeToRun]",
};
// AWFY's Mandelbrot, from the sources the race runs (500: its size there), for the Workspace to time.
const FILE_IN = "#('Samaltak' 'Harness' 'Core' 'Mandelbrot') do: [:n | Compiler fileIn: 'vm/tests/bench/awfy/', n, '.st']. Smalltalk at: #Mandelbrot";

// A window's bounds; place a window (drag by the title bar, resize from the corner).
const bounds = ref => JSON.parse(ctl('bounds', ref));
function place(ref, x, y, w, h) {
  const moveTo = (tx, ty) => { const b = bounds(ref); if (b.x !== tx || b.y !== ty) act('drag', ref, String(tx - b.x), String(ty - b.y)); };
  const b = bounds(ref);
  if (w && (b.w !== w || b.h !== h)) {
    // the resize handle stays on the screen: first where both sizes fit, then resize
    moveTo(Math.min(x, 1440 - Math.max(w, b.w)), Math.min(y, 900 - Math.max(h, b.h)));
    act('resize', ref, String(w), String(h));
  }
  moveTo(x, y);
}
const text = ref => ctl('snapshot', ref).split('\n').filter(l => l.startsWith('  | ')).map(l => l.slice(4)).join('\n');
async function until(test, timeout, what) {
  for (const t = Date.now(); !test(); await sleep(150))
    if (Date.now() - t > timeout) throw new Error(`timed out waiting for ${what}`);
}
// Open a tool from the World menu; answer its window.
async function openTool(item, re) {
  act('click', DESK); await sleep(600);
  act('click', `@menu.${item}`);
  const w = await S.win(re);
  await sleep(300);
  return w;
}
// Select a do-it in the Workspace and evaluate it (Meta+d or Meta+p).
async function evaluate(source, key = 'Meta+p') {
  act('select', `${W.workspace}.text`, source); await sleep(600);
  act('key', key, `${W.workspace}.text`);
}
// The Workspace's text once a print-it of source has answered (its result follows the do-it).
async function printed(source, timeout = 20000) {
  let after = '';
  await until(() => {
    const t = text(`${W.workspace}.text`) || '';
    const i = t.indexOf(source);
    after = i < 0 ? '' : t.slice(i + source.length);
    return /\S/.test(after.split('\n')[0]);
  }, timeout, `the result of ${source}`);
  return after;
}
// Highlight the first what after the first after in the front listing (a TextView), about in the middle of its window
// (select a line further down: the editor scrolls it to the bottom; then what), for ms. The snapshot holds only the
// first lines of a long text: the image finds what.
const quote = s => `'${s.replace(/'/g, "''")}'`;
async function mark(win, what, ms, after = '') {
  const [line, from, to] = S.eval(`| t i | t := (Tools windowsOf: TextView) first content text. i := t indexOfSubCollection: ${quote(what)} startingAt: ((t indexOfSubCollection: ${quote(after || what)} startingAt: 1) max: 1). {((t first: i) occurrencesOf: Character lf) + 1. i - 1. i - 1 + ${what.length}}`)
    .match(/-?\d+/g).map(Number);
  if (from < 0) throw new Error(`no ${what} in the listing`);
  if (line > 10) { act('select', `${win}.text`, `line:${line + 10}`); await sleep(150); }
  act('select', `${win}.text`, `${from}-${to}`); await sleep(ms);
}
// Browse a method in the System Browser.
async function browse(pkg, cls, selector) {
  act('select', `${W.browser}.packages`, pkg); await sleep(450);
  act('select', `${W.browser}.classes`, cls); await sleep(450);
  act('select', `${W.browser}.protocols`, 'all'); await sleep(450);
  act('select', `${W.browser}.methods`, selector); await sleep(700);
}
let T1 = null, T2 = null, FB = null, MC = null, MO = null;
const pick = async (column, name, ms = 500) => { act('select', `${FB}.column-${column}`, name); await sleep(ms); };
const lapsDone = ref => text(ref).includes('steady_ms');

// ---------------------------------------------------------------- beats
const beats = [
  // Two Terminals, the commands typed before the recording: Pharo 12 (left), Samaltak (right), the same AWFY sources
  // (vm/tests/bench/awfy.sh files them in), each lap's microseconds as it ends. Pharo first, Samaltak right after.
  ['race', async () => {
    act('key', 'Enter', `${T1}.terminal`);
    act('key', 'Enter', `${T2}.terminal`);
    await until(() => lapsDone(`${T2}.terminal`), 30000, 'Samaltak\'s laps');
  }],
  ['race-done', async () => {
    await until(() => lapsDone(`${T1}.terminal`), 60000, 'Pharo\'s laps');
    await sleep(1200);
  }],

  // The Terminals close over the File Browser (opened before the recording): src › VM-Jit with each file's lines, the
  // baseline compiler, the optimizer's first pass; vm › gen: the C translated from them.
  ['source', async () => {
    act('click', `${T2}.close`); await sleep(300);
    act('click', `${T1}.close`); await sleep(1500);
    await pick(3, 'JitBaselineCompiler.st', 1300);
    await pick(3, 'OptBuilder.st', 1300);
    await pick(1, 'vm');
    await pick(2, 'gen', 900);
    await pick(3, 'opt_codegen.c', 1500);
  }],

  // JitRuntime>>defaults says when the tiers come in (its comment, highlighted); the File Browser closes.
  ['tiers', async () => {
    await pick(1, 'src');
    await pick(2, 'VM-Jit', 400);
    await pick(3, 'JitRuntime.st', 700);
    // the line centred in the viewer: select one further down (the viewer scrolls it to its bottom), then it
    const show = 'threshold 2, OSR after 50 backward jumps, optimization after 1000 entries and backward jumps';
    const line = readFileSync(join(root, 'src/VM-Jit/JitRuntime.st'), 'utf8').split('\n').findIndex(l => l.includes(show)) + 1;
    act('select', `${FB}.viewer`, `line:${line + 17}`); await sleep(250);
    act('select', `${FB}.viewer`, show);
  }],
  // The File Browser closes. Complex>>- (nothing in the image sends it): no baseline code yet; three calls, and its
  // inline caches saw Complex.
  ['tiers-demo', async () => {
    act('click', `${FB}.close`); await sleep(500);
    await evaluate(DO.fresh);
    await printed(DO.fresh); await sleep(1800);
    await evaluate(DO.calls);
    await printed(DO.calls); await sleep(2500);
  }],

  // Complex>>+ (the Mandelbrot's escapeTimeAt: adds Complex numbers): its baseline code, as installed, commented: the
  // inline cache's class check at the checked entry, a call through each send's cache, inline SmallInteger arithmetic.
  // The listings take the top of the screen, over the System Browser; the Workspace and the Mandelbrot stay in view.
  ['baseline', async () => {
    await evaluate(DO.baseline, 'Meta+d');
    MC = await S.win(/Machine code: Complex>>\+ \(baseline\)/);
    place(MC, 18, 41, 1404, 470);
    await sleep(700);
    await mark(MC, 'not the cached class: the miss handler relinks', 2400);
    await mark(MC, "call the inline cache's target", 2400, 'send: #real');
    await mark(MC, 'SmallInteger tag checks', 2200, 'send: #real');
    await mark(MC, '+ (overflow: the slow path)', 2200, 'send: #real');
  }],
  // The same method from opt, compiled from the feedback the image has: guards, inlined activations, Floats on d
  // registers, the deoptimization stubs. Over the baseline listing.
  ['opt', async () => {
    await evaluate(DO.opt, 'Meta+d');
    MO = await S.win(/Machine code: Complex>>\+ \(opt\)/);
    place(MO, 18, 41, 1404, 470);
    await sleep(700);
    await mark(MO, 'guard: its class', 2400, 'send: #real');
    await mark(MO, 'inlined activation 1', 2400, 'send: #real');
    await mark(MO, 'fadd', 2400, 'send: #real');
    await mark(MO, 'guard failed: deoptimize', 2400);
  }],

  // MandelbrotView>>pixelFor: (escape time → colour, inlined into the render loop; in the System Browser since before
  // the recording). The counters; the Mandelbrot, made taller, renders again (zoomed in: a few seconds); meanwhile the
  // inside of the set becomes red, ⌘S.
  ['deopt', async () => {
    act('click', `${MO}.close`); await sleep(400);
    act('click', `${MC}.close`); await sleep(400);
    await evaluate(DO.before);
    await printed(DO.before); await sleep(300);
    S.busy = true;                                     // the Mandelbrot's Process renders: commands do not wait to settle
    place(W.mandel, 898, 41, 524, 843);
    await until(() => /rendering/.test(ctl('snapshot', `${W.mandel}.status`)), 10000, 'the render to start');
    act('select', `${W.browser}.code`, '16rFF000000'); await sleep(400);
    act('type', `${W.browser}.code`, '16rFF0000FF', '--delay', '45'); await sleep(11 * 45 + 300);
    act('key', 'Meta+s', `${W.browser}.code`);
  }],
  // The render goes on, red from the row where the method changed; the counters again.
  ['deopt-after', async () => {
    await until(() => !/rendering/.test(ctl('snapshot', `${W.mandel}.status`)), 30000, 'the render');
    S.busy = false;
    await sleep(600);
    await evaluate(DO.after);
    await printed(DO.after); await sleep(2500);
  }],

  // A Terminal (World menu): which Cogit Pharo 12's VM was generated with.
  ['why', async () => {
    const t = await openTool('terminal', /^window @w\d+ "Terminal"/);
    place(t, 18, 41, 866, 470);
    await sleep(500);
    act('type', `${t}.terminal`, `strings ${PHARO_CORE} | grep VMMaker\n`, '--delay', '12');
    await until(() => text(`${t}.terminal`).includes('StackToRegisterMappingCogit'), 15000, 'the strings');
    await sleep(2500);
  }],
  // The running system on baseline only, then on opt again (all machine code dropped each time): AWFY Mandelbrot laps.
  ['why-switch', async () => {
    S.busy = true;
    await evaluate(DO.baselineOnly);
    await printed(DO.baselineOnly, 60000); await sleep(1500);
    await evaluate(DO.optAgain);
    await printed(DO.optAgain, 60000); await sleep(2500);
    S.busy = false;
  }],

  ['outro', async () => {
    await sleep(2500);
  }],
];

// Before recording: the Process Browser, the Inspector and the Transcript closed. The JIT keeps the notes of the code
// it installs (jitParameters: notes), so the listings show the installed baseline code: listing baseline code by
// compiling it again would clear the Float feedback bytes of its sites, which opt reads. That drops all machine code;
// the Mandelbrot, bottom right, renders again, zoomed in twice (Complex>>+ runs hot again, with Floats). The Workspace
// widened, its text the video's do-its; AWFY's Mandelbrot filed in; the File Browser on src › VM-Jit; two Terminals
// over it all, the race's commands typed.
await S.open({ args: openArgs });
await sleep(1500);
for (const w of [W.procs, W.inspector, W.transcript]) { act('click', `${w}.close`); await sleep(400); }
S.eval("Smalltalk vm jitParameters: {nil. 'notes'. nil. nil}");
const rendered = () => !/rendering/.test(ctl('snapshot', `${W.mandel}.status`));
place(W.mandel, 898, 525, 524, 359);
for (let i = 0; i < 2; i++) {
  await sleep(500); await until(rendered, 30000, 'the Mandelbrot');
  act('click', `${W.mandel}.view`); await sleep(800);
}
await until(rendered, 60000, 'the Mandelbrot');
await browse('Tools', 'MandelbrotView', 'pixelFor:');
place(W.workspace, 18, 525, 866, 359);
const doits = Object.values(DO).join('\n');
act('type', `${W.workspace}.text`, doits, '--replace', '--delay', '0');
await until(() => (text(`${W.workspace}.text`) || '').includes(DO.optAgain), 60000, 'the do-its in the Workspace');
act('select', `${W.workspace}.text`, 'start');
S.run(['eval', FILE_IN, '--timeout', '60000']);
FB = await openTool('file-browser', /File Browser/);
place(FB, 18, 41, 1404, 843);
await pick(1, 'src');
await pick(2, 'VM-Jit');
T1 = await openTool('terminal', /^window @w\d+ "Terminal"/);
place(T1, 18, 41, 702, 843);
T2 = await openTool('terminal', new RegExp(`^window @w(?!${T1.slice(2)} )\\d+ "Terminal"`));
place(T2, 720, 41, 702, 843);
act('type', `${T1}.terminal`, `vm/tests/bench/awfy.sh --pharo -n ${LAPS} Mandelbrot`, '--delay', '0');
act('type', `${T2}.terminal`, `vm/tests/bench/awfy.sh -n ${LAPS} Mandelbrot`, '--delay', '0');
await sleep(2500);
S.startSegment();
await sleep(300);
for (const [id, beat] of beats) {
  await S.say(id);
  await beat();
}
await S.finish();
