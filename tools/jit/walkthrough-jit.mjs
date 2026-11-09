#!/usr/bin/env node
// Records the JIT video on the real system, driven only through samaltak-ctl and recorded from the compositor: the race
// against Pharo 12 in two Terminals, the JIT's sources, its tiers, baseline and optimized machine code, deoptimization
// while the Mandelbrot renders, the running system switched between the tiers, Pharo's Cogit, the measured comparisons.
// Usage: node walkthrough-jit.mjs <out-dir>   →  <out-dir>/raw.mp4, captions.json
// Needs Pharo 12 for the race (~/.cache/pharo12; the Terminals show it as /tmp/pharo12).
// The browser writes accepted methods into a scratch copy of the sources (--source-dir), not the repo. Every cue of
// the narration (narration.json "cues") is spoken when its effect shows (S.cue).
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
// The Terminals run zsh with a scratch configuration (ZDOTDIR): a short prompt, none of the user's. HOME stays (with
// another one Pharo 12 fails to file in the benchmark).
const zdot = join(out, 'home');
execFileSync('mkdir', ['-p', zdot]);
writeFileSync(join(zdot, '.zshrc'), "PS1='%F{blue}nuuk%f %# '\n");
Object.assign(S.env, { ZDOTDIR: zdot, SHELL: '/bin/zsh' });
const ctl = (...a) => S.ctl(...a), act = (...a) => S.act(...a);
const DESK = '1431,250';   // the desk at the right edge, never covered
const W = { workspace: '@w1', transcript: '@w2', procs: '@w3', mandel: '@w4', inspector: '@w5', browser: '@w6' };
const LAPS = 160;
const GO = { pharo: '/tmp/go-pharo', samaltak: '/tmp/go-samaltak' };   // the race's start gun (awfy.sh --go)
const PHARO = '/tmp/pharo12';
execFileSync('ln', ['-sfn', join(process.env.HOME, '.cache/pharo12'), PHARO]);
Object.assign(S.env, { PHARO_VM: join(PHARO, 'vm/Pharo.app/Contents/MacOS/Pharo'), PHARO_IMAGE: join(PHARO, 'bench.image') });
const PHARO_CORE = join(PHARO, 'vm/Pharo.app/Contents/MacOS/Plugins/libPharoVMCore.dylib');

// The Workspace's do-its, typed there before the recording.
const DO = {
  fresh: '(Complex >> #-) jitSendSites',
  calls: "| z | z := Complex real: 0.5 imaginary: 0.25. 1 to: 10 do: [:i | z - z]. ((Complex >> #-) jitSendSites reject: [:site | (site at: 3) isEmpty]) collect: [:site | (site at: 5), ' saw ', (site at: 3) first name]",
  baseline: "TextView openOn: ((Complex >> #+) machineCodeFor: #baseline) title: 'Machine code: Complex>>+ (baseline)' near: nil",
  opt: "TextView openOn: ((Complex >> #+) machineCodeFor: #opt) title: 'Machine code: Complex>>+ (opt)' near: nil",
  before: "\"before\" | s | s := Smalltalk vm statistics. 'invalidations ', s optInvalidations printString, ', deoptimizations ', s optDeoptimizations printString",
  after: "\"after\" | s | s := Smalltalk vm statistics. 'invalidations ', s optInvalidations printString, ', deoptimizations ', s optDeoptimizations printString",
  baselineOnly: "| ms | Smalltalk vm jitParameters: {'baseline'. nil. nil. nil}. ms := ((1 to: 7) collect: [:i | [Mandelbrot new innerBenchmarkLoop: 500] timeToRun]) asSortedCollection asArray. 'baseline: ', (ms at: 4) printString, ' ms per Mandelbrot run (median of 7)'",
  optAgain: "| ms | Smalltalk vm jitParameters: {'opt'. nil. nil. nil}. ms := ((1 to: 7) collect: [:i | [Mandelbrot new innerBenchmarkLoop: 500] timeToRun]) asSortedCollection asArray. 'opt: ', (ms at: 4) printString, ' ms per Mandelbrot run (median of 7)'",
};
// AWFY's Mandelbrot, from the sources the race runs (500: its size there), for the Workspace to time.
const FILE_IN = "#('Samaltak' 'Harness' 'Core' 'Mandelbrot') do: [:n | Compiler fileIn: 'vm/tests/bench/awfy/', n, '.st']. Smalltalk at: #Mandelbrot";

// A window's bounds; as a region [x, y, w, h] for a cue; place a window (drag by the title bar, resize from the corner).
const bounds = ref => JSON.parse(ctl('bounds', ref));
const box = ref => { const b = bounds(ref); return [b.x, b.y, b.w, b.h]; };
const VIEWER = [810, 100, 600, 760];     // the File Browser's file viewer, right of three columns
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
  for (let t = 0; !test(); t += 150) {
    if (t > timeout) throw new Error(`timed out waiting for ${what}`);
    await sleep(150);
  }
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
// Select a do-it in the Workspace now; answer its evaluation (Meta+p or Meta+d), for a cue (its effect: the result, a
// window).
async function selected(source, key = 'Meta+p') {
  act('select', `${W.workspace}.text`, source); await sleep(400);
  return () => act('key', key, `${W.workspace}.text`);
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
// Highlight the first what after the first after in the front listing (a TextView); the editor scrolls it into view
// in the same frame (to the bottom when it was below). The snapshot holds only the first lines of a long text: the
// image finds what.
const quote = s => `'${s.replace(/'/g, "''")}'`;
function mark(win, what, after = '') {
  const [from, to] = S.eval(`| t i | t := (Tools windowsOf: TextView) first content text. i := t indexOfSubCollection: ${quote(what)} startingAt: ((t indexOfSubCollection: ${quote(after || what)} startingAt: 1) max: 1). {i - 1. i - 1 + ${what.length}}`)
    .match(/-?\d+/g).map(Number);
  if (from < 0) throw new Error(`no ${what} in the listing`);
  act('select', `${win}.text`, `${from}-${to}`);
}
// Browse a method in the System Browser.
async function browse(pkg, cls, selector) {
  act('select', `${W.browser}.packages`, pkg); await sleep(450);
  act('select', `${W.browser}.classes`, cls); await sleep(450);
  act('select', `${W.browser}.protocols`, 'all'); await sleep(450);
  act('select', `${W.browser}.methods`, selector); await sleep(700);
}
let T1 = null, T2 = null, T3 = null, FB = null, MC = null, MO = null, raceStart = null;
const pick = async (column, name, ms = 500) => { act('select', `${FB}.column-${column}`, name); await sleep(ms); };
// A Terminal's race is over once awfy.sh printed its summary (--ms); a failed run stops the recording. The image sees
// it in the right (Samaltak) or the left (Pharo) Terminal when SUMMARY is true.
const lapsDone = ref => {
  const t = text(ref);
  if (/FAILED|ERROR/.test(t)) throw new Error(`the race failed:\n${t}`);
  return /^Mandelbrot: first lap/m.test(t);
};
const SHOWS = (right, text) => `((Tools windowsOf: Terminal) detect: [:w | w bounds left ${right ? '>' : '<'} 700]) content view shownLines anySatisfy: [:l | l includesSubstring: ${quote(text)}]`;
const SUMMARY = right => SHOWS(right, 'Mandelbrot: first lap');
// The Workspace shows the result of a print-it of source (after it, on its line), as a condition for a cue.
const PRINTED = source => `[:t | | i | i := t indexOfSubCollection: ${quote(source)} startingAt: 1. i > 0 and: [((t copyFrom: i + ${source.length} to: t size) copyUpTo: Character lf) anySatisfy: [:c | c isSeparator not]]] value: (Tools windowsOf: Workspace) first content text`;

// ---------------------------------------------------------------- beats
const beats = [
  // Two Terminals: Pharo 12 (left), Samaltak (right), the same AWFY sources, each lap's CPU time in ms as it ends (--ms
  // --cpu). Both started before the recording and wait, loaded, for the start gun (--go): the first laps show about 2 s
  // in, the words "each line" a while later (the take says who is racing first).
  ['race', async () => {
    await sleep(1400);
    raceStart = { real: Date.now(), video: S.now() };
    for (const f of Object.values(GO)) writeFileSync(f, '');
    await S.spoken();
  }],
  // Samaltak's summary, as its Terminal shows it: it is done; Pharo runs on.
  ['race-done', async () => {
    await S.cue("Samaltak's done", null, null, { when: SUMMARY(true), max: 30 });
    const speed = (Date.now() - raceStart.real) / 1000 / (S.now() - raceStart.video);    // recorder waits: load dependent
    console.log(`the race on screen: ${speed.toFixed(2)} x real speed`);
    const caption = S.captions.find(c => c.id === 'race');
    caption.text = caption.text.replace('{speed}', speed.toFixed(1));
    if (!lapsDone(`${T2}.terminal`)) throw new Error('Samaltak\'s laps are not done');
    lapsDone(`${T1}.terminal`);                       // Pharo's laps go on, not failed
    await S.spoken();
  }],

  // The Terminals close over the File Browser (opened before the recording; Pharo's run with its Terminal): src ›
  // VM-Jit with each file's lines, the baseline compiler, the optimizer's first pass; vm › gen: the C translated from them.
  ['source', async () => {
    await S.cue("The jit's written in Smalltalk", [730, 60, 680, 800], () => act('click', `${T2}.close`));
    act('click', `${T1}.close`); await sleep(300);
    await S.cue('a baseline compiler', VIEWER, () => pick(3, 'JitBaselineCompiler.st', 0));
    await S.cue('an optimizing one', VIEWER, () => pick(3, 'OptBuilder.st', 0));
    await sleep(600);
    await pick(1, 'vm');
    await pick(2, 'gen', 600);
    await S.cue('translated to C', VIEWER, () => pick(3, 'opt_codegen.c', 0));
    await S.spoken();
  }],

  // JitRuntime>>defaults says when the tiers come in (its comment, highlighted); the File Browser closes.
  ['tiers', async () => {
    await pick(1, 'src', 300);
    await pick(2, 'VM-Jit', 300);
    await pick(3, 'JitRuntime.st', 400);
    // the line selected: the viewer scrolls it into view as it highlights it
    const show = 'threshold 2, OSR after 50 backward jumps, optimization after 1000 entries and backward jumps';
    await S.cue('Its third call', VIEWER, () => act('select', `${FB}.viewer`, show));
    await S.spoken();
  }],
  // The File Browser closes. Complex>>- (nothing in the image sends it): no baseline code yet; ten calls, and the
  // inline caches its baseline code used saw Complex (it is compiled at the third; its caches link in the calls after).
  ['tiers-demo', async () => {
    act('click', `${FB}.close`); await sleep(500);
    await S.cue('no machine code yet', null, await selected(DO.fresh), { when: PRINTED(DO.fresh) });
    await S.cue('Ten calls later', null, await selected(DO.calls), { when: PRINTED(DO.calls) });
    await S.spoken();
  }],

  // Complex>>+ (the Mandelbrot's escapeTimeAt: adds Complex numbers): its baseline code, as installed, commented: the
  // inline cache's class check at the checked entry, a call through each send's cache, inline SmallInteger arithmetic.
  // The listings take the top of the screen, over the System Browser; the Workspace and the Mandelbrot stay in view.
  ['baseline', async () => {
    const open = await selected(DO.baseline, 'Meta+d');
    let opened = null;
    await S.cue("Here's baseline code", () => opened, async () => {
      open();
      MC = await S.win(/Machine code: Complex>>\+ \(baseline\)/);
      opened = box(MC);
    });
    place(MC, 18, 41, 1404, 470);
    const LISTING = box(`${MC}.text`);
    await S.cue('An inline cache check', LISTING, () => mark(MC, 'not the cached class: the miss handler relinks'));
    await S.cue('a call through its own cache', LISTING, () => mark(MC, "call the inline cache's target", 'send: #real'));
    await S.cue('tag checks', LISTING, () => mark(MC, 'SmallInteger tag checks', 'send: #real'));
    await S.cue('an overflow branch', LISTING, () => mark(MC, '+ (overflow: the slow path)', 'send: #real'));
    await S.spoken();
  }],
  // The same method from opt, compiled from the feedback the image has: guards, inlined activations, Floats on d
  // registers, the deoptimization stubs. Over the baseline listing.
  ['opt', async () => {
    const open = await selected(DO.opt, 'Meta+d');
    let opened = null;
    await S.cue('Opt compiles it again', () => opened, async () => {
      open();
      MO = await S.win(/Machine code: Complex>>\+ \(opt\)/);
      opened = box(MO);
    });
    place(MO, 18, 41, 1404, 470);
    const LISTING = box(`${MO}.text`);
    await S.cue('the accessors', LISTING, () => mark(MO, 'inlined activation 1', 'send: #real'));
    await S.cue('a class guard', LISTING, () => mark(MO, 'guard: its class', 'send: #real'));
    await S.cue('the floats added in FP registers', LISTING, () => mark(MO, 'fadd', 'send: #real'));
    await S.cue('a failed guard', LISTING, () => mark(MO, 'guard failed: deoptimize'));
    await S.spoken();
  }],

  // MandelbrotView>>pixelFor: (escape time → colour, inlined into the render loop; in the System Browser since before
  // the recording). The Mandelbrot, made taller, renders again (zoomed in: a few seconds); meanwhile the inside of the
  // set becomes red, the counters, ⌘S.
  ['deopt', async () => {
    act('click', `${MO}.close`); await sleep(400);
    act('click', `${MC}.close`); await sleep(400);
    S.busy = true;                                     // the Mandelbrot's Process renders: commands do not wait to settle
    place(W.mandel, 898, 41, 524, 843);                // taller: it renders again (⌘S lands about a third in)
    await until(() => /rendering/.test(ctl('snapshot', `${W.mandel}.status`)), 10000, 'the render to start');
    await evaluate(DO.before);
    await printed(DO.before);
    // the new method is in: the next rows the render publishes (every 50 ms) are red
    await S.cue('save', null, () => act('key', 'Meta+s', `${W.browser}.code`),
      { when: '(MandelbrotView >> #pixelFor:) literals includes: 16rFF0000FF', max: 5, prepare: async () => {
        act('select', `${W.browser}.code`, '16rFF000000'); await sleep(200);
        act('type', `${W.browser}.code`, '16rFF0000FF', '--delay', '45'); await sleep(200);
      } });
  }],
  // The counters again; the render goes on, red from the row where the method changed.
  ['deopt-after', async () => {
    await sleep(300);
    await evaluate(DO.after);
    await printed(DO.after);
    await until(() => !/rendering/.test(ctl('snapshot', `${W.mandel}.status`)), 30000, 'the render');
    S.busy = false;
    // while this is said: the Terminal for the why beat (World menu, top left, over the System Browser), its command typed
    T3 = await openTool('terminal', /^window @w\d+ "Terminal"/);
    place(T3, 18, 41, 866, 470);
    await sleep(300);
    act('type', `${T3}.terminal`, `strings ${PHARO_CORE} | grep VMMaker`, '--delay', '12');
  }],

  // The running system on baseline only, then on opt again (all machine code dropped each time): AWFY Mandelbrot runs,
  // in the Workspace (bottom left).
  ['why-switch', async () => {
    const baseline = await selected(DO.baselineOnly);
    S.busy = true;
    await S.cue('switched to baseline only', null, baseline, { lead: 1.15, max: 15, when: PRINTED(DO.baselineOnly) });
    S.busy = false;
    const opt = await selected(DO.optAgain);
    S.busy = true;
    await S.cue('back to opt', null, opt, { lead: 0.4, max: 15, when: PRINTED(DO.optAgain) });
    S.busy = false;
  }],
  // Which Cogit Pharo 12's VM was generated with (strings answers at once once the file is cached). Once that has been
  // seen a while: the next beat's File Browser (World menu) on docs › jit.md, while this is said.
  ['why', async () => {
    await S.cue("Cog's StackToRegisterMappingCogit", null, () => act('key', 'Enter', `${T3}.terminal`),
      { lead: 0.2, when: SHOWS(false, 'StackToRegisterMappingCogit') });
    await sleep(3500);
    FB = await openTool('file-browser', /File Browser/);
    place(FB, 18, 41, 1404, 843);
    await pick(1, 'docs', 300);
    await pick(2, 'jit.md', 400);
  }],
  // The measured table: the File Browser on docs › jit.md, the Comparison's baseline and opt rows selected.
  ['why-table', async () => {
    const doc = readFileSync(join(root, 'docs/jit.md'), 'utf8');
    const from = doc.indexOf('| `baseline` | Cog-style: inline caches');
    const to = doc.indexOf('\n', doc.indexOf('| `opt` | baseline code plus the optimizing tier'));
    if (from < 0 || to < 0) throw new Error('no Comparison rows in docs/jit.md');
    await S.cue('Are We Fast Yet', VIEWER, () => act('select', `${FB}.viewer`, `${from}-${to}`));
    await S.spoken();
  }],
  // The real-world table: docs › benchmarks.md, its geometric mean row and the summary after it selected.
  ['realworld', async () => {
    await pick(2, 'benchmarks.md', 300);
    const doc = readFileSync(join(root, 'docs/benchmarks.md'), 'utf8');
    const from = doc.indexOf('| geometric mean |', doc.indexOf('## Real-world workloads'));
    const to = doc.indexOf('PrintParse (0.85).', from) + 'PrintParse (0.85).'.length;
    if (from < 0 || to < from) throw new Error('no real-world result in docs/benchmarks.md');
    await S.cue('On sixteen real-world programs', VIEWER, () => act('select', `${FB}.viewer`, `${from}-${to}`));
    await S.spoken();
  }],

  // The File Browser closes: the system as the video leaves it.
  ['outro', async () => {
    act('click', `${FB}.close`); await sleep(2500);
  }],
];

// Before recording: the Process Browser, the Inspector and the Transcript closed; the Mandelbrot, bottom right, renders
// again, zoomed in twice (for the deoptimization beat: a render of a few seconds). The Workspace widened, its text the
// video's do-its; AWFY's Mandelbrot filed in; the File Browser on src › VM-Jit; two Terminals over it all, the race's
// commands typed.
await S.open({ args: openArgs });
await sleep(1500);
for (const w of [W.procs, W.inspector, W.transcript]) { act('click', `${w}.close`); await sleep(400); }
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
for (const f of Object.values(GO)) for (const g of [f, `${f}.ready`]) rmSync(g, { force: true });
act('type', `${T1}.terminal`, `vm/tests/bench/awfy.sh --ms --cpu --go ${GO.pharo} --pharo -n ${LAPS} Mandelbrot`, '--delay', '0');
act('type', `${T2}.terminal`, `vm/tests/bench/awfy.sh --ms --cpu --go ${GO.samaltak} -n ${LAPS} Mandelbrot`, '--delay', '0');
await sleep(1500);
act('key', 'Enter', `${T1}.terminal`);
act('key', 'Enter', `${T2}.terminal`);
await until(() => Object.values(GO).every(f => existsSync(`${f}.ready`)), 120000, 'both racers at the start');
await sleep(1500);                                 // the top bar's frame times settle
S.startSegment();
S.preroll(1.4);
await sleep(1500);
for (const [id, beat] of beats) {
  await S.say(id);
  await beat();
}
await S.finish();
