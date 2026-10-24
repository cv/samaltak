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
const W = { workspace: '@w1', transcript: '@w2', procs: '@w3', mandel: '@w4', inspector: '@w5', browser: '@w6' };

// Browse a method in the default System Browser (@w6).
async function browse(pkg, cls, selector) {
  act('select', `${W.browser}.packages`, pkg); await sleep(500);
  act('select', `${W.browser}.classes`, cls); await sleep(500);
  act('select', `${W.browser}.protocols`, 'all'); await sleep(500);
  act('select', `${W.browser}.methods`, selector); await sleep(800);
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

  // 1. Restyle from inside. TODO (feature): the Theme accent as an editable method; revert at the end of the act.
  ['restyle', async () => {
    await sleep(4000);
  }],

  // 2. Live shader edit. TODO (feature): Renderer's MSL source method; edit, accept, revert.
  ['shader', async () => {
    await sleep(4000);
  }],

  // 3. Live glyph rasterizer. TODO (feature): coverage tweak + glyph pixel inspector.
  ['glyphs', async () => {
    await sleep(4000);
  }],

  // 4. Slow motion. TODO (feature): the animation clock rate.
  ['slowmo', async () => {
    await sleep(4000);
  }],

  // 5. Edit and continue mid-computation: the Mandelbrot's colour function is edited while a render runs; the rows it
  // has not drawn yet use the new method (its Process sends pixelFor: for every pixel).
  ['palette', async () => {
    await browse('Tools', 'MandelbrotView', 'pixelFor:');
    // invert the colours: white becomes black, ultramarine becomes amber
    act('select', `${W.browser}.code`, '^palette at: index + 1'); await sleep(500);
    S.type(`${W.browser}.code`, '^(palette at: index + 1) bitXor: 16rFFFFFF'); await sleep(6000);
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

  // 7. Halt the window system itself. TODO (feature): conditional breakpoint for the Transcript's redraw.
  ['halt-ui', async () => {
    await sleep(4000);
  }],

  // 8. Debug the debugger. TODO (feature): breakpoint in the Debugger's own Over.
  ['debug-debugger', async () => {
    await sleep(4000);
  }],

  // 9. Watch the window manager. TODO (feature): halt on write on a window's bounds, then drag it.
  ['watch-wm', async () => {
    await sleep(4000);
  }],

  // 10. Infinite recursion. TODO (feature): a debugger instead of the VM's out-of-memory exit.
  ['recursion', async () => {
    await sleep(3000);
  }],

  // 13. Snapshot mid-debugging: a debugger stopped mid-step, Save image, Quit; relaunch; step on.
  ['snapshot', async () => {
    // TODO (feature): set up the debugger mid-step, World menu › Save image, World menu › Quit.
    await sleep(3000);
    S.stopSegment();
    // TODO (feature): quit the image here (World menu › Quit) instead of closing it.
    ctl('close');
    await S.open({ fresh: false, args: openArgs });
    S.startSegment();
    await sleep(3000);
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
