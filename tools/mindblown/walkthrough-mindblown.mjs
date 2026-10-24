#!/usr/bin/env node
// Records the "mind blown" video (.context/mindblown.md) on the real system, driven only through samaltak-ctl and
// recorded from the compositor. Beat 13 saves the image, quits and relaunches it: the recording has a segment before
// and one after, concatenated by VideoSession.finish (captions are timed on the concatenated video).
// Usage: node walkthrough-mindblown.mjs <out-dir> [--only id,id,...]   →  <out-dir>/raw.mp4, captions.json
// The browser writes accepted methods into a scratch copy of the sources (<out-dir>/src, --source-dir), not the repo.
import { execFileSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { VideoSession, sleep } from '../video-lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');
const argv = process.argv.slice(2);
const out = resolve(argv.find(a => !a.startsWith('--')) || join(root, '.context/video-mindblown'));
const onlyArg = argv.indexOf('--only');
const only = onlyArg >= 0 ? new Set(argv[onlyArg + 1].split(',')) : null;

const S = new VideoSession({
  out,
  stepsFile: join(here, 'narration.json'),
  session: process.env.WALKTHROUGH_SESSION || 'mindblown',
  image: process.env.WALKTHROUGH_IMAGE || join(root, 'build/samaltak.image'),
});
const srcDir = join(out, 'src');
rmSync(srcDir, { recursive: true, force: true });
execFileSync('cp', ['-R', join(root, 'src'), srcDir]);
const openArgs = ['--source-dir', srcDir];
const ctl = (...a) => S.ctl(...a), act = (...a) => S.act(...a);
const DESK = '1431,250';   // the desk at the right edge, never covered
const W = { workspace: '@w1', transcript: '@w2', procs: '@w3', mandel: '@w4', inspector: '@w5', browser: '@w6' };

// Browse a method in the default System Browser (@w6), on the instance or class side.
async function browse(pkg, cls, selector, side) {
  act('select', `${W.browser}.packages`, pkg); await sleep(500);
  act('select', `${W.browser}.classes`, cls); await sleep(500);
  if (side) { act('click', `${W.browser}.side.${side}`); await sleep(400); }
  act('select', `${W.browser}.protocols`, 'all'); await sleep(500);
  act('select', `${W.browser}.methods`, selector); await sleep(800);
}
// Select old in the browser's code pane and type new over it, ms per character ('' deletes the selection).
async function edit(old, text, ms = 110) {
  act('select', `${W.browser}.code`, old); await sleep(500);
  if (text === '') { act('key', 'Backspace', `${W.browser}.code`); await sleep(300); return; }
  act('type', `${W.browser}.code`, text, '--delay', String(ms)); await sleep(text.length * ms + 400);
}
// Append an expression to the Workspace on its own line and evaluate it (Meta+d or Meta+p).
async function evaluate(text, key = 'Meta+d') {
  act('type', `${W.workspace}.text`, '\n', '--end', '--delay', '0');
  S.type(`${W.workspace}.text`, text);
  await sleep(text.length * 140 + 300);
  act('select', `${W.workspace}.text`, text); await sleep(300);
  act('key', key, `${W.workspace}.text`);
}

// ---------------------------------------------------------------- beats
const beats = [
  ['intro', async () => {
    await sleep(3500);
  }],

  // 1. Restyle from inside: the Theme's accent (UI-Widgets › Theme › initializeBlueBook) becomes red, every window
  // follows at once; then the desk's halftone (UI-Windows › World › drawDeskOn:) is drawn in the accent.
  ['restyle', async () => {
    await browse('UI-Widgets', 'Theme', 'initializeBlueBook');
    await edit('16r1B3A8C', '16rC8102E', 140);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(2200);
    await browse('UI-Windows', 'World', 'drawDeskOn:');
    await edit('Color black', 'Color ultramarine', 110);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3000);
    // and back, for the rest of the video
    await edit('Color ultramarine', 'Color black', 50);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(500);
    await browse('UI-Widgets', 'Theme', 'initializeBlueBook');
    await edit('16rC8102E', '16r1B3A8C', 50);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 2. Live shader edit: Graphics-Canvas › Renderer class › shaderSource, the MSL uber-shader. Layer images (every
  // window) get scan lines; accepting rebuilds the GPU pipeline before the next frame. Then put it back.
  ['shader', async () => {
    await browse('Graphics-Canvas', 'Renderer', 'shaderSource', 'class');
    await edit('return tex.sample(s, in.uv / size) * in.color.a;',
      'return tex.sample(s, in.uv / size) * in.color.a * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88);', 35);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3500);
    await edit(' * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88)', '', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1500);
  }],

  // 3. Live glyph rasterizer: Graphics-Canvas › GlyphRasterizer › coverage gets a gamma (square root): every glyph
  // re-rasterizes bolder. Then the coverage pixels of 'g' in an Inspector; then put the rasterizer back.
  ['glyphs', async () => {
    await browse('Graphics-Canvas', 'GlyphRasterizer', 'coverage', 'instance');
    await edit('v := sum < 0.0', 'v := (sum < 0.0', 70);
    await edit('ifFalse: [sum].', 'ifFalse: [sum]) sqrt.', 70);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(2500);
    await evaluate('(Font code glyphFor: $g) inspect');
    const insp = await S.win(/Inspector: a GlyphForm|Inspector.*Glyph/);
    await sleep(800);
    for (const at of ['3,8', '6,12', '9,15']) { try { act('hover', `${insp}.pixels`, '--at', at); } catch {} await sleep(700); }
    await sleep(800);
    act('click', `${insp}.close`); await sleep(600);
    await edit('v := (sum < 0.0', 'v := sum < 0.0', 0);
    await edit('ifFalse: [sum]) sqrt.', 'ifFalse: [sum].', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 4. Slow motion: World menu › Slow motion (the animation clock 10× slower): the menu, a window opening, the
  // selection glide, closing; then back to 1×.
  ['slowmo', async () => {
    act('click', DESK); await sleep(600);
    act('click', '@menu.slow-motion'); await sleep(2500);
    act('click', DESK); await sleep(2500);
    act('click', '@menu.workspace');
    const ws = await S.win(/Workspace/ , 15000).catch(() => null);
    await sleep(3000);
    act('select', `${W.browser}.packages`, 'Graphics-GPU'); await sleep(2500);   // the selection glides
    act('select', `${W.browser}.packages`, 'Graphics-Canvas'); await sleep(2500);
    const fresh = ctl('snapshot', '--depth', '1').split('\n').filter(l => l.startsWith('window ') && /"Workspace"/.test(l)).map(l => l.match(/@w\d+/)[0]).find(r => r !== W.workspace);
    if (fresh) { act('click', `${fresh}.close`); await sleep(2500); }
    act('click', DESK); await sleep(1500);
    act('click', '@menu.slow-motion'); await sleep(1200);
  }],

  // 5. Edit and continue mid-computation: the Mandelbrot's colour function is edited while a render runs; the rows it
  // has not drawn yet use the new method (its Process sends pixelFor: for every pixel).
  ['palette', async () => {
    await browse('Tools', 'MandelbrotView', 'pixelFor:');
    // invert the colours: white becomes black, ultramarine becomes amber
    await edit('^palette at: index + 1', '^(palette at: index + 1) bitXor: 16rFFFFFF', 70);
    S.busy = true;
    act('click', `${W.mandel}.view`); await sleep(1100);   // a render starts
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3500);
    S.busy = false;
  }],

  // 6. An infinite loop in a do-it: that Process is busy, the rest stays live; ⌘. interrupts it; closing the debugger
  // terminates it.
  ['loop', async () => {
    S.busy = true;
    await evaluate('[true] whileTrue');
    await sleep(1800);
    act('drag', W.transcript, '-40', '30'); await sleep(900);   // the window manager stays live
    act('key', 'Meta+.');
    const note = await S.win(/User [Ii]nterrupt/);
    await sleep(1200);
    act('click', `${note}.debug`);
    const dbg = await S.win(/Debugger/);
    await sleep(2500);
    act('click', `${dbg}.close`); await sleep(800);
    S.busy = false;
  }],

  // 7. Halt the window system itself: System Browser › UI-Windows › Window › redraw › break in window ▸ Transcript.
  // The Transcript's Process stops in a debugger at its next redraw; the other windows keep working. From the
  // debugger: write to the Transcript (it shows after Proceed), remove the breakpoint, proceed.
  ['halt-ui', async () => {
    await browse('UI-Windows', 'Window', 'redraw');
    act('rightclick', `${W.browser}.methods.redraw`); await sleep(900);
    act('click', '@menu.break-in-window'); await sleep(900);
    act('click', '@menu~2.transcript');
    const dbg = await S.win(/Breakpoint: Window>>redraw/);
    await sleep(1500);
    act('click', `${W.mandel}.view`); await sleep(1200);        // the rest of the system is live
    act('type', `${dbg}.receiver.evaluator`, "Transcript show: 'hello from the debugger'; cr", '--delay', '60');
    await sleep(3800);
    act('key', 'Meta+d', `${dbg}.receiver.evaluator`); await sleep(1000);
    act('click', `${dbg}.remove-breakpoint`); await sleep(800);
    act('click', `${dbg}.proceed`); await sleep(2200);
  }],

  // 8. Debug the debugger: a debugger A on 48 gcd: 18; Tools › Debugger › stepOver › break in window ▸ A; Over in A
  // opens debugger B on A's Process; step in B; remove the breakpoint; proceed: A's Over completes.
  ['debug-debugger', async () => {
    await browse('Kernel-Numbers', 'Integer', 'gcd:');
    act('click', `${W.browser}.methods.gcd.breakpoint-toggle`); await sleep(700);
    act('select', `${W.workspace}.text`, '48 gcd: 18'); await sleep(400);
    act('key', 'Meta+p', `${W.workspace}.text`);
    const a = await S.win(/Breakpoint: Integer>>gcd:/);
    const aTitle = ctl('snapshot', '--depth', '1').split('\n').find(l => l.startsWith(`window ${a} `)).match(/"([^"]+)"/)[1];
    await sleep(800);
    await browse('Tools', 'Debugger', 'stepOver');
    act('rightclick', `${W.browser}.methods.stepover`); await sleep(800);
    act('click', '@menu.break-in-window'); await sleep(800);
    act('click', S.find('item', aTitle)); await sleep(800);
    act('click', `${a}.over`);
    const b = await S.win(/Breakpoint: Debugger>>stepOver/);
    await sleep(1600);
    act('click', `${b}.over`); await sleep(1100);
    act('click', `${b}.over`); await sleep(1100);
    act('click', `${b}.remove-breakpoint`); await sleep(700);
    act('click', `${b}.proceed`); await sleep(1500);
    act('click', `${a}.over`); await sleep(1100);
    act('click', `${a}.proceed`); await sleep(1000);
    await browse('Kernel-Numbers', 'Integer', 'gcd:');
    act('click', `${W.browser}.methods.gcd.breakpoint-toggle`); await sleep(500);
  }],

  // 9. Watch the window manager: an Inspector on the Transcript's Window, halt on write (all processes) on bounds;
  // drag the window: the input dispatcher stops in Window>>bounds: under the drag gesture; a stand-in dispatcher keeps
  // input live. Unwatch, proceed.
  ['watch-wm', async () => {
    await evaluate("(World current windowNamed: 'Transcript') inspect");
    const insp = await S.win(/Inspector: a Window/);
    await sleep(900);
    act('rightclick', `${insp}.fields.bounds`); await sleep(800);
    act('click', '@menu.halt-on-write-everywhere'); await sleep(900);
    act('drag', W.transcript, '-120', '60');
    const dbg = await S.win(/watchpoint on #bounds/);
    await sleep(2200);
    act('click', `${dbg}.unwatch`); await sleep(700);
    act('click', `${dbg}.proceed`); await sleep(1200);
    act('click', `${insp}.close`); await sleep(500);
  }],

  // 10. Infinite recursion. TODO (feature): a debugger instead of the VM's out-of-memory exit.
  ['recursion', async () => {
    await sleep(3000);
  }],

  // 13. Snapshot mid-debugging: a do-it halted in a loop, stepped in its debugger; World menu › Save image, › Quit;
  // the image is started again and the debugger steps on and proceeds: the do-it prints its result.
  ['snapshot', async () => {
    const line = '| sum | sum := 0. 1 to: 5 do: [:i | i = 3 ifTrue: [self halt]. sum := sum + (i * i)]. sum';
    act('select', `${W.workspace}.text`, line); await sleep(600);
    act('key', 'Meta+p', `${W.workspace}.text`);
    const note = await S.win(/Halt/);
    await sleep(900);
    act('click', `${note}.debug`);
    let dbg = await S.win(/Debugger/);
    await sleep(900);
    for (let k = 0; k < 2; k++) { act('click', `${dbg}.over`); await sleep(900); }
    act('click', DESK); await sleep(700);
    act('click', '@menu.save-image'); await sleep(2500);
    act('click', DESK); await sleep(700);
    try { act('click', '@menu.quit'); } catch {}          // the image quits while the command waits for it to settle
    await sleep(1500);
    S.stopSegment();                                   // the image quit: its recording ended with it
    await S.open({ fresh: false, args: openArgs, wait: /Debugger/ });
    S.startSegment();
    await sleep(1500);
    dbg = await S.win(/Debugger/);
    act('click', `${dbg}.over`); await sleep(1200);
    act('click', `${dbg}.proceed`); await sleep(2500);
  }],

  // 14. The tiny core. TODO (feature): the Terminal tool: wc -l, Smalltalk line count, gst vs the Workspace's suite.
  ['core', async () => {
    await sleep(5000);
  }],

  ['outro', async () => {
    await sleep(3000);
  }],
];

await S.open({ args: openArgs });
await sleep(1500);
S.startSegment();
await sleep(300);
for (const [id, beat] of beats) {
  if (only && !only.has(id) && id !== 'intro' && id !== 'outro') continue;
  await S.say(id);
  await beat();
}
await S.finish();
