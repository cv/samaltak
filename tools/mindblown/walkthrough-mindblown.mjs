#!/usr/bin/env node
// Records the "mind blown" video (.context/mindblown.md) on the real system, driven only through samaltak-ctl and
// recorded from the compositor. The snapshot beat (save, quit, relaunch) and the reboot beat (the rebuilt VM is exec'd)
// end the recording: each starts a new segment; VideoSession.finish concatenates them (captions are timed on the result).
// Usage: node walkthrough-mindblown.mjs <out-dir> [--only id,id,...]   →  <out-dir>/raw.mp4, captions.json
// The browser writes accepted methods into a scratch copy of the sources (--source-dir), not the repo; Rebuild & reboot
// builds the VM beside it. It lives in /tmp: the VM Rebuild window prints that directory.
import { execFileSync } from 'node:child_process';
import { rmSync, writeFileSync } from 'node:fs';
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
async function evaluate(text, key = 'Meta+d', ms = 140) {
  act('type', `${W.workspace}.text`, '\n', '--end', '--delay', '0');
  act('type', `${W.workspace}.text`, text, '--delay', String(ms));
  await sleep(text.length * ms + 300);
  act('select', `${W.workspace}.text`, text); await sleep(300);
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
const breakInJuggler = async () => {
  await browse('Tools', 'ShannonJuggler', 'move:');
  act('rightclick', `${W.browser}.methods.move`); await sleep(800);
  act('click', '@menu.break-in-window'); await sleep(800);
  act('click', '@menu~2.claude-s-robot');
};

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
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3500);
    await edit('16rC8102E', '16r1B3A8C', 50);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 2. Live shader edit: Graphics-Canvas › Renderer class › shaderSource, the MSL uber-shader as a String. Layer images
  // (every window) get scan lines; accepting compiles it into a new GPU pipeline before the next frame. Then put it back.
  ['shader', async () => {
    await browse('Graphics-Canvas', 'Renderer', 'shaderSource', 'class');
    await edit('return tex.sample(s, in.uv / size) * in.color.a;',
      'return tex.sample(s, in.uv / size) * in.color.a * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88);', 35);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3000);
    await edit(' * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88)', '', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 3. The compositor (UI-Windows › Compositor › drawWindow:on:time:, run in its own Process every frame) draws the
  // window shadows: make them 24 times deeper and ultramarine; every window changes at once. Then put it back.
  ['compositor', async () => {
    await browse('UI-Windows', 'Compositor', 'drawWindow:on:time:', 'instance');
    await edit('* s.', '* s * 24.', 80);
    await edit('Color black.', 'Color ultramarine.', 70);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(3200);
    await edit('* s * 24.', '* s.', 0);
    await edit('Color ultramarine.', 'Color black.', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 4. Live glyph rasterizer: Graphics-Canvas › GlyphRasterizer › coverage answers 255 minus the coverage: every glyph
  // re-rasterizes as a block with the letter cut out. The coverage pixels of 'g' in an Inspector; then put it back.
  ['glyphs', async () => {
    await browse('Graphics-Canvas', 'GlyphRasterizer', 'coverage', 'instance');
    await edit('put: (v', 'put: 255 - (v', 80);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(2000);
    await evaluate('(Font code glyphFor: $g) inspect', 'Meta+d', 60);
    const insp = await S.win(/Inspector: a GlyphForm|Inspector.*Glyph/);
    await sleep(800);
    try { act('hover', `${insp}.pixels`, '--at', '8,14'); } catch {}
    await sleep(1500);
    act('click', `${insp}.close`); await sleep(600);
    await edit('255 - (v', '(v', 0);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1200);
  }],

  // 5. Slow motion: World menu › Slow motion (the animation clock 10× slower): the menu, a window opening, the
  // selection glide, closing.
  ['slowmo', async () => {
    act('click', DESK); await sleep(600);
    act('click', '@menu.slow-motion'); await sleep(1700);
    act('click', DESK); await sleep(1700);
    act('click', '@menu.workspace');
    await S.win(/Workspace/, 15000).catch(() => null);
    await sleep(2200);
    act('select', `${W.browser}.packages`, 'Graphics-GPU'); await sleep(2000);   // the selection glides
    const fresh = ctl('snapshot', '--depth', '1').split('\n').filter(l => l.startsWith('window ') && /"Workspace"/.test(l)).map(l => l.match(/@w\d+/)[0]).find(r => r !== W.workspace);
    if (fresh) { act('click', `${fresh}.close`); await sleep(2200); }
    act('click', DESK); await sleep(1300);
  }],
  ['slowmo-off', async () => {
    act('click', '@menu.slow-motion'); await sleep(1500);
  }],

  // 6. Edit and continue: the robot's balls turn turquoise from the next frame on (Tools › ShannonJuggler ›
  // ballColor, read by its stage every frame in its window's Process).
  ['juggle-edit', async () => {
    await browse('Tools', 'ShannonJuggler', 'ballColor');
    // to turquoise: it reads on the dark curtain
    const old = text(`${W.browser}.code`).match(/Color r: [\d.]+ g: [\d.]+ b: [\d.]+|Color \w+/)[0];
    await edit(old, 'Color r: 0.1 g: 0.8 b: 0.75', 60);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(2500);
  }],

  // 7. An infinite loop in the robot's step (Tools › ShannonJuggler › step): its window hangs (busy), everything
  // else stays live. ⌘. on the robot: the notifier, Debug: the debugger highlights the loop.
  ['loop', async () => {
    await browse('Tools', 'ShannonJuggler', 'step');
    // the first statement: after the selector line, the comment and the temporaries
    const first = text(`${W.browser}.code`).split('\n').slice(1).map(l => l.trim()).find(l => l && !/^["|]/.test(l));
    act('click', `${W.browser}.code`); await sleep(200);
    act('select', `${W.browser}.code`, first); await sleep(400);
    act('key', 'Left', `${W.browser}.code`); await sleep(300);                // the caret before it
    act('type', `${W.browser}.code`, '[true] whileTrue.\n', '--delay', '110'); await sleep(18 * 110 + 400);
    expect(`${W.browser}.code`, `\t[true] whileTrue.\n\t${first}`);
    act('key', 'Meta+s', `${W.browser}.code`);
    S.busy = true;
    await sleep(2500);
    act('drag', W.procs, '-60', '30'); await sleep(900);          // the window manager stays live
    act('drag', W.procs, '60', '-30'); await sleep(900);
    act('click', J); await sleep(500);
    act('key', 'Meta+.');
    const note = await S.win(/User [Ii]nterrupt/);
    await sleep(1400);
    act('click', `${note}.debug`);
    await debuggerOn(/Debugger/);
    S.busy = false;
    await sleep(1500);
  }],
  // In the debugger: delete the loop, ⌘S (recompiles step, restarts the frame), Proceed: it juggles again.
  ['loop-fix', async () => {
    const dbg = await S.win(/Debugger/);
    await replaceIn(`${dbg}.source`, '[true] whileTrue.\n\t', '');
    if (text(`${dbg}.source`).includes('whileTrue.')) throw new Error('the loop is still there');
    await sleep(500);
    act('key', 'Meta+s', `${dbg}.source`); await sleep(1500);
    act('click', `${dbg}.proceed`); await sleep(2500);
  }],

  // 8. System Browser › move: › break in window ▸ Claude's Robot: the robot's Process stops at its next move:,
  // the balls freeze mid-air; the context inspector shows the ball; the rest of the system is live.
  ['freeze', async () => {
    await breakInJuggler();
    const dbg = await debuggerOn(/Breakpoint: ShannonJuggler>>move:/);
    await sleep(500);
    act('click', `${dbg}.context.fields#1`); await sleep(1500);             // the ball, move:'s argument
    act('drag', W.procs, '-60', '30'); await sleep(900);
    act('drag', W.procs, '60', '-30'); await sleep(900);
  }],
  // Flip gravity in the debugger's source pane, ⌘S (recompiles, also without the breakpoint), Proceed.
  ['gravity', async () => {
    const dbg = await S.win(/Debugger/);
    await replaceIn(`${dbg}.source`, '0 @ 0.4', '0 @ -0.4', 160);
    expect(`${dbg}.source`, '(0 @ -0.4)');
    await sleep(400);
    act('key', 'Meta+s', `${dbg}.source`); await sleep(1200);
    act('click', `${dbg}.proceed`); await sleep(4000);
  }],
  // Gravity back in the System Browser (showing the method again, as the debugger left it); a click restarts the act.
  ['restore', async () => {
    act('select', `${W.browser}.methods`, 'step'); await sleep(500);
    act('select', `${W.browser}.methods`, 'move:'); await sleep(700);
    await edit('0 @ -0.4', '0 @ 0.4', 60);
    act('key', 'Meta+s', `${W.browser}.code`); await sleep(1500);
    act('click', `${J}.stage`); await sleep(2500);
  }],

  // 9. Snapshot mid-debugging: the robot stopped in move:; World menu › Save image, › Quit; the image is started
  // again: the debugger and the frozen robot are back; Remove breakpoint, Proceed: it juggles on.
  ['snapshot', async () => {
    await breakInJuggler();
    await debuggerOn(/Breakpoint: ShannonJuggler>>move:/);
    await sleep(1200);
    act('click', DESK); await sleep(700);
    act('click', '@menu.save-image'); await sleep(2500);
    act('click', DESK); await sleep(700);
    try { act('click', '@menu.quit'); } catch {}          // the image quits while the command waits for it to settle
    await sleep(1500);
    S.stopSegment();                                   // the image quit: its recording ended with it
    await S.open({ fresh: false, args: openArgs, wait: /Debugger/ });
    S.startSegment();
  }],
  ['relaunch', async () => {
    await sleep(2500);
    const dbg = await S.win(/Debugger/);
    act('click', `${dbg}.remove-breakpoint`); await sleep(900);
    act('click', `${dbg}.proceed`); await sleep(2500);
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
  // Rebuild & reboot: translate the VM to C, compile it, save the image, exec the new VM on it (same process, same
  // control port). The recording ends with the old VM; a new segment starts on the new one: the top bar shows its banner.
  ['reboot', async () => {
    const sim = await S.win(/VM Simulator/);
    act('click', `${sim}.rebuild`);
    try { const rb = await S.win(/VM Rebuild/); await sleep(300); place(rb, 18, 41, 866, 470); } catch {}
    for (let t = Date.now(); ; await sleep(200)) {     // the image goes away for a moment while the new VM starts
      try { S.run(['wait', 'rebooted in', '15000']); break; } catch (e) { if (Date.now() - t > 120000) throw e; }
    }
    S.stopSegment();
    S.startSegment();
    await sleep(3500);
  }],

  // 11. No hand-written C: the Terminal tool (Smalltalk: pty primitives, VT100 parser, view) counts the Smalltalk
  // lines of the VM (VM-Core, VM-Platform, VM-Jit) and the C lines generated from them, and shows a generated file's
  // header.
  ['core', async () => {
    for (const re of [/VM Rebuild/, /VM Simulator/]) { act('click', `${await S.win(re)}.close`); await sleep(500); }
    act('click', DESK); await sleep(700);
    act('click', '@menu.terminal');
    const term = await S.win(/Terminal/);
    await sleep(600);
    place(term, 18, 41, 866, 470);                    // over the System Browser, the robot stays in view
    await sleep(900);
    const t = `${term}.terminal`;
    const command = async (text, wait) => {
      act('type', t, text, '--delay', '35'); await sleep(text.length * 35 + 300);
      act('key', 'Return', t); await sleep(wait);
    };
    await command('cat src/VM-{Core,Platform,Jit}/*.st | wc -l', 1200);
    await command('wc -l vm/gen/*.[ch] | tail -1', 1200);
    await command('head -1 vm/gen/interpreter.c', 2500);
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
await sleep(800);
await sleep(1500);
S.startSegment();
await sleep(300);
for (const [id, beat] of beats) {
  if (only && !only.has(id) && id !== 'intro' && id !== 'outro') continue;
  await S.say(id);
  await beat();
}
await S.finish();
