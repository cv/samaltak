#!/usr/bin/env node
// Records the "mind blown" video (.context/mindblown.md) on the real system, driven only through samaltak-ctl and
// recorded from the compositor. The snapshot beat (save, quit, relaunch) and the reboot beat (the rebuilt VM is exec'd)
// end the recording: each starts a new segment; VideoSession.finish concatenates them (captions are timed on the result).
// Usage: node walkthrough-mindblown.mjs <out-dir> [--only id,id,...]   →  <out-dir>/raw.mp4, captions.json
// The browser writes accepted methods into a scratch copy of the sources (--source-dir), not the repo; Rebuild & reboot
// builds the VM beside it. It lives in /tmp: the VM Rebuild window prints that directory.
import { execFileSync } from 'node:child_process';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
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
const scratch = '/tmp/samaltak-mindblown';
const srcDir = join(scratch, 'src');
rmSync(scratch, { recursive: true, force: true });
execFileSync('mkdir', ['-p', scratch]);
execFileSync('cp', ['-R', join(root, 'src'), srcDir]);
const openArgs = ['--source-dir', srcDir];
// The Terminal runs the user's login shell: give it a plain environment (a scratch HOME with a short prompt), so the
// video shows no personal shell configuration.
const home = join(out, 'home');
execFileSync('mkdir', ['-p', home]);
writeFileSync(join(home, '.zshrc'), "PS1='%F{blue}nuuk%f %# '\n");
Object.assign(S.env, { HOME: home, SHELL: '/bin/zsh' });
const ctl = (...a) => S.ctl(...a), act = (...a) => S.act(...a);
const DESK = '1431,250';   // the desk at the right edge, never covered
const GAP = '891,300';     // the desk between the System Browser and the Process Browser
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
// Select a do-it in the Workspace (typed there before the recording) and evaluate it (Meta+d or Meta+p).
async function evaluate(text, key = 'Meta+d') {
  act('select', `${W.workspace}.text`, text); await sleep(700);
  act('key', key, `${W.workspace}.text`);
}

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
// The debugger: wait for it, give it the left half of the screen, next to the robot.
async function debuggerOn(re) {
  const dbg = await S.win(re);
  await sleep(600);
  place(dbg, 18, 41, 866, 843);
  return dbg;
}
// Select old in an editor and type new over it. A click first gives the editor focus (a later type or key into an
// unfocused editor would click into it, moving the caret off the selection).
async function replaceIn(ref, old, text, ms = 110) {
  act('click', ref); await sleep(200);
  act('select', ref, old); await sleep(500);
  if (text === '') { act('key', 'Backspace', ref); await sleep(300); return; }
  act('type', ref, text, '--delay', String(ms)); await sleep(text.length * ms + 400);
}
const text = ref => ctl('snapshot', ref).split('\n').filter(l => l.startsWith('  | ')).map(l => l.slice(4)).join('\n');
function expect(ref, part) {
  const t = text(ref);
  if (!t.includes(part)) throw new Error(`${ref} does not contain ${JSON.stringify(part)}:\n${t}`);
}
let J = null;                     // the robot's window (Claude's Robot, a ShannonJuggler)
// The GC beat's do-it: allocates about 100000 arrays a second for a minute or two, keeping the last 3000 (2 MB, less
// than a survivor space): each dies before its second scavenge.
const GLYPH = '(Font code glyphFor: $g) inspect';
const CHURN = "[| keep | keep := Array new: 3000. 1 to: 12000000 do: [:i | keep at: i \\\\ 3000 + 1 put: (Array new: 80). i \\\\ 1200 = 0 ifTrue: [(Delay forMilliseconds: 10) wait]]] forkNamed: 'churn'";

// ---------------------------------------------------------------- beats
const beats = [
  // Claude's Robot juggles at the bottom right, animated every frame in its window's Process.
  ['intro', async () => {
    await sleep(2500);
  }],

  // 1. Restyle from inside: the Theme's accent (UI-Widgets › Theme › initializeBlueBook) becomes red, every window
  // follows at once while the robot juggles; then back.
  ['restyle', async () => {
    await browse('UI-Widgets', 'Theme', 'initializeBlueBook');
    await edit('16r1B3A8C', '16rC8102E', 140);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3000);
    await edit('16rC8102E', '16r1B3A8C', 50);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 2. Live shader edit: Graphics-Canvas › Renderer class › shaderSource, the MSL uber-shader as a String. Layer images
  // (every window) get scan lines; accepting compiles it into a new GPU pipeline before the next frame. Then put it back.
  ['shader', async () => {
    await browse('Graphics-Canvas', 'Renderer', 'shaderSource', 'class');
    await edit('return tex.sample(s, in.uv / size) * in.color.a;',
      'return tex.sample(s, in.uv / size) * in.color.a * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88);', 35);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(2600);
    await edit(' * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88)', '', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 3. The compositor (UI-Windows › Compositor › drawWindow:on:time:, run in its own Process every frame) draws the
  // window shadows: make them 24 times deeper and ultramarine; every window changes at once. Then put it back.
  ['compositor', async () => {
    await browse('UI-Windows', 'Compositor', 'drawWindow:on:time:', 'instance');
    await edit('* s.', '* s * 24.', 80);
    await edit('Color black.', 'Color ultramarine.', 70);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(2800);
    await edit('* s * 24.', '* s.', 0);
    await edit('Color ultramarine.', 'Color black.', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 4. Live glyph rasterizer: Graphics-Canvas › GlyphRasterizer › coverage answers 255 minus the coverage: every glyph
  // re-rasterizes as a block with the letter cut out. The coverage pixels of 'g' in an Inspector; then put it back.
  ['glyphs', async () => {
    await browse('Graphics-Canvas', 'GlyphRasterizer', 'coverage', 'instance');
    await edit('put: (v', 'put: 255 - (v', 80);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1600);
    await evaluate(GLYPH);
    const insp = await S.win(/Inspector: a GlyphForm|Inspector.*Glyph/);
    await sleep(600);
    try { act('hover', `${insp}.pixels`, '--at', '8,14'); } catch {}
    await sleep(1300);
    act('click', `${insp}.close`); await sleep(600);
    await edit('255 - (v', '(v', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 5. Slow motion: World menu › Slow motion (the animation clock 10× slower): the menu, a window opening.
  ['slowmo', async () => {
    act('click', DESK); await sleep(600);
    act('click', '@menu.slow-motion'); await sleep(1000);
    act('click', GAP); await sleep(1100);              // the new Workspace opens here, below DESK
    act('click', '@menu.workspace');
    await S.win(/Workspace/, 15000).catch(() => null);
    await sleep(1500);
    act('click', DESK); await sleep(800);
  }],
  // Normal speed again; the new Workspace closes.
  ['slowmo-off', async () => {
    act('click', '@menu.slow-motion'); await sleep(900);
    const fresh = ctl('snapshot', '--depth', '1').split('\n').filter(l => l.startsWith('window ') && /"Workspace"/.test(l)).map(l => l.match(/@w\d+/)[0]).find(r => r !== W.workspace);
    if (fresh) { act('click', `${fresh}.close`); await sleep(700); }
  }],

  // 6. Edit and continue, no debugger: Tools › ShannonJuggler › move: (run for every ball in every frame) gets gravity
  // pointing up while the robot juggles: the balls fall up and settle at the ceiling.
  ['gravity', async () => {
    await browse('Tools', 'ShannonJuggler', 'move:');
    await edit('0 @ 0.4', '0 @ -0.4', 140);
    expect(`${W.browser}.code`, '(0 @ -0.4)');
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(4000);
  }],
  // Gravity back; a click on the robot restarts the act (the balls into its hands).
  ['restore', async () => {
    await edit('0 @ -0.4', '0 @ 0.4', 60);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
    act('click', `${J}.stage`); await sleep(2500);
  }],

  // 7. The one debugger stop: Tools › ShannonJuggler › ballColor (read every frame) › break in window ▸ Claude's Robot:
  // the robot's Process stops in its next frame, the robot freezes mid-throw; the rest of the system is live.
  ['freeze', async () => {
    act('select', `${W.browser}.methods`, 'ballColor'); await sleep(700);
    act('rightclick', `${W.browser}.methods.ballcolor`); await sleep(800);
    act('click', '@menu.break-in-window'); await sleep(800);
    act('click', '@menu~2.claude-s-robot');
    await debuggerOn(/Breakpoint: ShannonJuggler>>ballColor/);
    await sleep(1000);
    act('drag', W.procs, '-60', '30'); await sleep(900);          // the window manager stays live
    act('drag', W.procs, '60', '-30'); await sleep(900);
  }],
  // The colour changed in the debugger's source pane, ⌘S: recompiled (without the breakpoint), the frame restarts;
  // the Process stays stopped.
  ['recolour', async () => {
    const dbg = await S.win(/Debugger/);
    const old = text(`${dbg}.source`).match(/Color r: [\d.]+ g: [\d.]+ b: [\d.]+|Color \w+/)[0];
    await replaceIn(`${dbg}.source`, old, 'Color r: 0.1 g: 0.8 b: 0.75', 70);
    expect(`${dbg}.source`, 'Color r: 0.1 g: 0.8 b: 0.75');
    await sleep(300);
    act('key', 'Meta+s', `${dbg}.source`); await sleep(1500);
  }],
  // World menu › Save image, › Quit while it is stopped: the screen fades to black, the image quits. It starts again
  // from the saved image: the recording's next segment begins with the restart splash.
  ['snapshot', async () => {
    act('click', DESK); await sleep(700);
    act('click', '@menu.save-image'); await sleep(2500);
    act('click', DESK); await sleep(700);
    try { act('click', '@menu.quit'); } catch {}          // the image quits while the command waits for it to settle
    await S.recordingEnded();                          // its recording ended with it
    S.stopSegment();
    await S.open({ fresh: false, args: openArgs, wait: null });
    S.startSegment();
  }],
  // Everything is back, the robot frozen mid-throw, the debugger open; Proceed: it juggles on, in the new colour.
  ['relaunch', async () => {
    const dbg = await S.win(/Debugger/, 30000);
    await sleep(2500);
    act('click', `${dbg}.proceed`); await sleep(3000);
  }],

  // 8. The JIT (VM-Jit, Smalltalk too) has compiled move: (every ball, every frame): System Browser › move: › machine
  // code: its arm64 under each bytecode, commented; scrolled to the first statement, where sends are inlined.
  ['jit', async () => {
    act('select', `${W.browser}.methods`, 'move:'); await sleep(700);
    act('rightclick', `${W.browser}.methods.move`); await sleep(800);
    act('click', '@menu.machine-code');
    const mc = await S.win(/Machine code: ShannonJuggler>>move:/);
    await sleep(400);
    place(mc, 18, 41, 866, 843);
    await sleep(1800);
    act('scroll', `${mc}.text`, '1240'); await sleep(3000);
    act('scroll', `${mc}.text`, '480'); await sleep(3000);
    act('click', `${mc}.close`); await sleep(600);
  }],

  // 10. Smalltalk in Smalltalk: World menu › VM Simulator runs a guest image on the VM's own Smalltalk classes (the
  // Lowtalk sources, simulated); System Browser › VM-Core › VMMain › banner gets a new text, ⌘S: the guest's next line
  // shows it.
  ['guest', async () => {
    act('click', DESK); await sleep(700);
    act('click', '@menu.vm-simulator');
    const sim = await S.win(/VM Simulator/);
    await sleep(400);
    place(sim, 18, 525, 866, 359);
    await sleep(300);
    act('click', `${sim}.run`); await sleep(3000);
    await browse('VM-Core', 'VMMain', 'banner');
    await edit('Samaltak VM', 'Samaltak VM, edited live', 70);
    expect(`${W.browser}.code`, "^'Samaltak VM, edited live'");
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3500);
  }],
  // 11. The GC is Smalltalk too (VM-Core › GarbageCollector): TENURE_AGE := 0 promotes every survivor of a scavenge
  // (2: those that survive two). World menu › Rebuild VM & reboot: the VM is translated to C (the translation runs
  // the class-side initialize methods again: TENURE_AGE 0), compiled, the image saved, the screen faded, the new VM
  // exec'd (same process, same control port).
  ['gc', async () => {
    const sim = await S.win(/VM Simulator/, 1000).catch(() => null);
    if (sim) { act('click', `${sim}.close`); await sleep(600); }
    await browse('VM-Core', 'GarbageCollector', 'initialize', 'class');
    await edit('TENURE_AGE := 2', 'TENURE_AGE := 0', 110);
    expect(`${W.browser}.code`, 'TENURE_AGE := 0');
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1000);
    act('click', DESK); await sleep(700);
    act('click', '@menu.rebuild-vm-reboot');
    try { const rb = await S.win(/VM Rebuild/); await sleep(300); place(rb, 18, 41, 866, 470); } catch {}
  }],
  // While it compiles, on the old VM: World menu › System Monitor (right column) and a do-it that allocates, keeping
  // its last 3000 arrays: they die young, survivors are promoted after two scavenges, old space barely grows. The
  // recording ends with the old VM; the next segment starts with the new VM's restart splash.
  ['gc-churn', async () => {
    act('click', DESK); await sleep(700);
    act('click', '@menu.system-monitor');
    const mon = await S.win(/System Monitor/);
    await sleep(400);
    place(mon, 898, 41, 524, 843);
    await sleep(500);
    await evaluate(CHURN);
    S.busy = true;                                     // the churn keeps the image busy: commands do not wait to settle
    await S.recordingEnded(240000);                    // the screen fades, the VM execs the new one: the recording ends
    S.stopSegment();
    S.startSegment();                                  // the new VM's World, from the restart splash on
    for (let t = Date.now(); ; await sleep(200)) {
      try { S.run(['wait', 'rebooted in', '15000']); break; } catch (e) { if (Date.now() - t > 120000) throw e; }
    }
    await sleep(800);
  }],
  // The System Monitor, restored with the image, samples on; widened over the screen (its charts keep their last
  // minute): old space climbs, a full GC every few seconds, the count of full GCs in its readout.
  ['gc-after', async () => {
    const mon = await S.win(/System Monitor/);
    place(mon, 18, 41, 1404, 843);
    await sleep(9000);
  }],

  // 12. No hand-written C: World menu › File Browser (Smalltalk too) on the left: vm › gen lists the generated C with
  // line counts; interpreter.c begins "Generated by VMTranslator … Do not edit.", its interpret function a table of
  // bytecode handlers; src › VM-Core › Interpreter.st is the Lowtalk it comes from (interpret, <c: 'void
  // interpret(void)'>).
  ['core', async () => {
    for (const re of [/VM Rebuild/, /System Monitor/]) {
      const w = await S.win(re, 1000).catch(() => null);
      if (w) { act('click', `${w}.close`); await sleep(500); }
    }
    act('click', DESK); await sleep(700);
    act('click', '@menu.file-browser');
    const fb = await S.win(/File Browser/);
    await sleep(400);
    place(fb, 18, 41, 1404, 843);
    await sleep(600);
    const pick = async (column, name, ms = 500) => { act('select', `${fb}.column-${column}`, name); await sleep(ms); };
    // a line of a file, centred in the viewer: select one further down (the viewer scrolls it to its bottom), then it
    const show = async (file, text) => {
      const line = readFileSync(join(root, file), 'utf8').split('\n').findIndex(l => l.includes(text)) + 1;
      act('select', `${fb}.viewer`, `line:${line + 17}`); await sleep(300);
      act('select', `${fb}.viewer`, text); await sleep(1800);
    };
    await pick(1, 'vm');
    await pick(2, 'gen', 1100);
    await pick(3, 'interpreter.c', 1900);
    await show('vm/gen/interpreter.c', 'void interpret(void)');
    await pick(1, 'src');
    await pick(2, 'VM-Core');
    await pick(3, 'Interpreter.st', 700);
    await show('src/VM-Core/Interpreter.st', "<c: 'void interpret(void)'>");
    act('click', `${fb}.close`); await sleep(800);
  }],

  ['outro', async () => {
    await sleep(3000);
  }],
];

// Before recording: Claude's Robot (World menu) takes the Mandelbrot's place at the bottom right, over the Transcript.
await S.open({ args: openArgs });
await sleep(1500);
act('click', `${W.mandel}.close`); await sleep(800);
act('click', DESK); await sleep(900);
act('click', '@menu.claude-s-robot');
J = await S.win(/Claude's Robot/);
await sleep(800);
place(J, 898, 422, 524, 462);
// The Workspace gets the video's two do-its now (a long text types slowly there), its caret back at the top.
act('type', `${W.workspace}.text`, `\n${GLYPH}\n${CHURN}`, '--end', '--delay', '0');
for (const t = Date.now(); !text(`${W.workspace}.text`).includes(CHURN); await sleep(500))
  if (Date.now() - t > 60000) throw new Error('the do-its did not arrive in the Workspace');
act('select', `${W.workspace}.text`, 'start');
await sleep(1500);
S.startSegment();
await sleep(300);
for (const [id, beat] of beats) {
  if (only && !only.has(id) && id !== 'intro' && id !== 'outro') continue;
  await S.say(id);
  await beat();
}
await S.finish();
