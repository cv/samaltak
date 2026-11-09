#!/usr/bin/env node
// Records the "mind blown" video (.context/mindblown.md) on the real system, driven only through samaltak-ctl and
// recorded from the compositor. The quit (snapshot beat) and the exec of the rebuilt VM (reboot beat) end the recording:
// a new segment begins with the restart; VideoSession.finish joins them in real time (black in between).
// Every cue of the narration (narration.json "cues") is spoken when its effect shows (S.cue: the region of the screen
// where it shows, or a condition in the image).
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

// A window's or widget's bounds; as a region [x, y, w, h] for a cue.
const bounds = ref => JSON.parse(ctl('bounds', ref));
const box = ref => { const b = bounds(ref); return [b.x, b.y, b.w, b.h]; };
// The effects that show in the Workspace's text (static: nothing else moves there) and in the browser's status bar.
const WORKSPACE = () => box(`${W.workspace}.text`);
const CODE = () => box(`${W.browser}.code`);
const STATUS = () => box(`${W.browser}.status`);
// Typing shows at its first change (the selection); everything else at about a third of its change.
const TYPING = { frac: 0.05, max: 6 };

// Browse to a method in the default System Browser (@w6), on the instance or class side; the method's own selection is
// a function, for a cue (its source shows in the code pane).
async function browseTo(pkg, cls, side) {
  act('select', `${W.browser}.packages`, pkg); await sleep(150);
  act('select', `${W.browser}.classes`, cls); await sleep(150);
  if (side) { act('click', `${W.browser}.side.${side}`); await sleep(150); }
  act('select', `${W.browser}.protocols`, 'all'); await sleep(150);
}
const pickMethod = selector => async () => { act('select', `${W.browser}.methods`, selector); await sleep(300); };
async function browse(pkg, cls, selector, side) {
  await browseTo(pkg, cls, side);
  await pickMethod(selector)(); await sleep(400);
}
// Select old in the browser's code pane and type new over it, ms per character ('' deletes the selection).
async function edit(old, text, ms = 110) {
  act('select', `${W.browser}.code`, old); await sleep(500);
  if (text === '') { act('key', 'Backspace', `${W.browser}.code`); await sleep(300); return; }
  act('type', `${W.browser}.code`, text, '--delay', String(ms)); await sleep(300);   // it answers once typed
}
const save = () => act('key', 'Meta+s', `${W.browser}.code`);
// Select a do-it in the Workspace (typed there before the recording) and evaluate it (Meta+d or Meta+p).
async function evaluate(text, key = 'Meta+d') {
  act('select', `${W.workspace}.text`, text); await sleep(700);
  act('key', key, `${W.workspace}.text`);
}

// A window's bounds; place a window (drag by the title bar, resize from the corner).
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
// Select old in an editor and type new over it. A click first gives the editor focus (a later type or key into an
// unfocused editor would click into it, moving the caret off the selection).
async function replaceIn(ref, old, text, ms = 110) {
  act('click', ref); await sleep(200);
  act('select', ref, old); await sleep(500);
  if (text === '') { act('key', 'Backspace', ref); await sleep(300); return; }
  act('type', ref, text, '--delay', String(ms)); await sleep(300);
}
const text = ref => ctl('snapshot', ref).split('\n').filter(l => l.startsWith('  | ')).map(l => l.slice(4)).join('\n');
function expect(ref, part) {
  const t = text(ref);
  if (!t.includes(part)) throw new Error(`${ref} does not contain ${JSON.stringify(part)}:\n${t}`);
}
let J = null;                     // the robot's window (Claude's Robot, a ShannonJuggler)
const ROBOT = '(Tools windowsOf: ShannonJuggler) first content';
const REBUILD = "(Process allInstances select: [:p | p name = 'VM rebuild'])";   // Rebuild VM & reboot, in its Process
// The GC beat's do-it: allocates about 100000 arrays a second for a minute or two, keeping the last 3000 (2 MB, less
// than a survivor space): each dies before its second scavenge.
const GLYPH = '(Font code glyphFor: $g) inspect';
const CHURN = "[| keep | keep := Array new: 3000. 1 to: 12000000 do: [:i | keep at: i \\\\ 3000 + 1 put: (Array new: 80). i \\\\ 1200 = 0 ifTrue: [(Delay forMilliseconds: 10) wait]]] forkNamed: 'churn'";
// The World menu's region, once it is open.
const MENU = () => box('@menu');

// ---------------------------------------------------------------- beats
const beats = [
  // The caption saying how the video was recorded.
  ['clock', async () => { await sleep(3500); }],
  // Claude's Robot juggles at the bottom right, animated every frame in its window's Process.
  ['intro', async () => {
    await sleep(2500);
  }],

  // 1. Restyle from inside: the Theme's accent (UI-Widgets › Theme › initializeBlueBook) becomes red, every window
  // follows at once while the robot juggles (in the Workspace: the class names); back once that has been said.
  ['restyle', async () => {
    await browse('UI-Widgets', 'Theme', 'initializeBlueBook');
    await edit('16r1B3A8C', '16rC8102E', 140);
    await S.cue('save', WORKSPACE(), save);
    await S.spoken();
    await edit('16rC8102E', '16r1B3A8C', 50);
    save(); await sleep(1200);
  }],

  // 2. Live shader edit: Graphics-Canvas › Renderer class › shaderSource, the MSL uber-shader as a String. Layer images
  // (every window) get scan lines; accepting compiles it into a new GPU pipeline before the next frame. Then put it back.
  ['shader', async () => {
    await browse('Graphics-Canvas', 'Renderer', 'shaderSource', 'class');
    await S.cue('edit it here', CODE(), () => edit('return tex.sample(s, in.uv / size) * in.color.a;',
      'return tex.sample(s, in.uv / size) * in.color.a * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88);', 35), TYPING);
    await S.cue('Save', WORKSPACE(), save);
    await S.cue('undo', WORKSPACE(), async () => {
      await edit(' * (((uint(in.pos.y) / 4u) & 1u) == 0u ? 1.0 : 0.88)', '', 0);
      save();
    }, { lead: 0.9 });
    await sleep(1200);
  }],

  // 3. The compositor (UI-Windows › Compositor › drawWindow:on:time:, run in its own Process every frame) draws the
  // window shadows: make them 24 times deeper and ultramarine; every window changes at once (between the System Browser
  // and the Process Browser: the desk shows the browser's shadow). Then put it back.
  ['compositor', async () => {
    await browseTo('UI-Windows', 'Compositor', 'instance');
    await S.cue('This is the compositor', CODE(), pickMethod('drawWindow:on:time:'));
    await sleep(600);
    await edit('* s.', '* s * 24.', 80);
    await edit('Color black.', 'Color ultramarine.', 70);
    await S.cue('and there', [886, 60, 11, 400], save);
    await S.spoken();
    await edit('* s * 24.', '* s.', 0);
    await edit('Color ultramarine.', 'Color black.', 0);
    save(); await sleep(1200);
  }],

  // 4. Live glyph rasterizer: Graphics-Canvas › GlyphRasterizer › coverage answers 255 minus the coverage: every glyph
  // re-rasterizes as a block with the letter cut out. The coverage pixels of 'g' in an Inspector; then put it back.
  ['glyphs', async () => {
    await browse('Graphics-Canvas', 'GlyphRasterizer', 'coverage', 'instance');
    await S.cue('flip the coverage', CODE(), () => edit('put: (v', 'put: 255 - (v', 80), TYPING);
    await S.cue('yeah', WORKSPACE(), save);
    act('select', `${W.workspace}.text`, GLYPH); await sleep(400);
    let insp = null;
    await S.cue('Those are the real pixels', () => box(insp), async () => {
      act('key', 'Meta+d', `${W.workspace}.text`);
      insp = await S.win(/Inspector: a GlyphForm|Inspector.*Glyph/);
    });
    try { act('hover', `${insp}.pixels`, '--at', '8,14'); } catch {}
    await sleep(1000);
    act('click', `${insp}.close`); await sleep(600);
    await S.cue('back', WORKSPACE(), async () => { await edit('255 - (v', '(v', 0); save(); }, { lead: 1.0 });
    await sleep(1200);
  }],

  // 5. Slow motion: World menu › Slow motion (the animation clock 10× slower): the menu, a window opening.
  ['slowmo', async () => {
    await S.cue('a setting', MENU, async () => { act('click', DESK); await sleep(300); });
    await sleep(500);
    act('click', '@menu.slow-motion'); await sleep(1000);
    await S.cue('The menu', MENU, async () => { act('click', GAP); await sleep(300); }, { frac: 0.1, max: 3 });
    await sleep(800);
    let fresh = null;
    await S.cue('a window opening', () => box(fresh), async () => {
      act('click', '@menu.workspace');
      fresh = await S.win(/^window @w(?!1 )\d+ "Workspace"/, 15000);
    }, { frac: 0.1, max: 3 });
    await sleep(1500);
    act('click', DESK); await sleep(800);
  }],
  // Normal speed again (the menu, opened slowly, closes); the new Workspace closes.
  ['slowmo-off', async () => {
    await S.cue('back to normal speed', MENU(), () => act('click', '@menu.slow-motion'), { frac: 0.5 });
    await sleep(500);
    const fresh = ctl('snapshot', '--depth', '1').split('\n').filter(l => l.startsWith('window ') && /"Workspace"/.test(l)).map(l => l.match(/@w\d+/)[0]).find(r => r !== W.workspace);
    if (fresh) { act('click', `${fresh}.close`); await sleep(700); }
  }],

  // 6. Edit and continue, no debugger: Tools › ShannonJuggler › move: (run for every ball in every frame) gets gravity
  // pointing up while the robot juggles: the balls fall up and settle at the ceiling (they rise within a split second
  // of the save; "fall up" comes as long after "save" as the take has it).
  ['gravity', async () => {
    await browseTo('Tools', 'ShannonJuggler');
    await S.cue('This is move', CODE(), pickMethod('move:'));
    await S.cue('flip gravity', CODE(), () => edit('0 @ 0.4', '0 @ -0.4', 140), TYPING);
    expect(`${W.browser}.code`, '(0 @ -0.4)');
    await S.cue('save', STATUS(), save);
    await S.spoken();
  }],
  // Gravity back; a click on the robot restarts the act (the balls into its hands: its frame count starts over).
  ['restore', async () => {
    await S.cue('put gravity back', STATUS(), async () => { await edit('0 @ -0.4', '0 @ 0.4', 60); save(); }, { ...TYPING, lead: 0.5 });
    act('hover', `${J}.stage`); await sleep(300);
    await S.cue('click', null, () => act('click', `${J}.stage`), { when: `${ROBOT} frame < 100` });
    await sleep(1500);
  }],

  // 7. The one debugger stop: Tools › ShannonJuggler › ballColor (read every frame) › break in window ▸ Claude's Robot:
  // the robot's Process stops in its next frame, the robot freezes mid-throw (the debugger opens); the rest of the
  // system is live (the Process Browser is dragged).
  ['freeze', async () => {
    act('select', `${W.browser}.methods`, 'ballColor'); await sleep(700);
    await S.cue('a breakpoint in ball colour', MENU, async () => { act('rightclick', `${W.browser}.methods.ballcolor`); await sleep(300); });
    await sleep(500);
    act('click', '@menu.break-in-window'); await sleep(800);
    let dbg = null;
    await S.cue('It stops mid-throw', () => dbg, async () => {
      act('click', '@menu~2.claude-s-robot');
      const ref = await S.win(/Breakpoint: ShannonJuggler>>ballColor/);
      dbg = box(ref);
      await sleep(600);
      place(ref, 18, 41, 866, 843);
    });
    await sleep(600);
    await S.cue('keeps going', box(W.procs), async () => { act('drag', W.procs, '-60', '30'); await sleep(900); });
    act('drag', W.procs, '60', '-30'); await sleep(900);
  }],
  // The colour changed in the debugger's source pane, ⌘S: recompiled (without the breakpoint), the frame restarts;
  // the Process stays stopped.
  ['recolour', async () => {
    const dbg = await S.win(/Debugger/);
    const old = text(`${dbg}.source`).match(/Color r: [\d.]+ g: [\d.]+ b: [\d.]+|Color \w+/)[0];
    await S.cue('change the colour', box(`${dbg}.source`), () => replaceIn(`${dbg}.source`, old, 'Color r: 0.1 g: 0.8 b: 0.75', 70), TYPING);
    expect(`${dbg}.source`, 'Color r: 0.1 g: 0.8 b: 0.75');
    await sleep(300);
    await S.cue('save', box(dbg), () => act('key', 'Meta+s', `${dbg}.source`));
    await sleep(1500);
  }],
  // World menu › Save image, › Quit while it is stopped: the screen fades to black, the image quits.
  ['snapshot', async () => {
    act('click', DESK); await sleep(700);
    const menu = MENU();
    await S.cue('save the image', menu, async () => { act('click', '@menu.save-image'); await sleep(300); }, { frac: 0.5 });
    await sleep(1500);
    act('click', DESK); await sleep(700);
    await S.cue('quit', [300, 150, 840, 600], async () => {
      try { act('click', '@menu.quit'); } catch {}          // the image quits while the command waits for it to settle
    }, { max: 1 });
    await S.recordingEnded();                          // its recording ended with it
    S.stopSegment();
  }],
  // It starts again from the saved image (the screen black between the segments); the next segment begins with
  // everything back, the robot frozen mid-throw, the debugger open. Proceed: it juggles on, in the new colour (the
  // debugger closes).
  ['relaunch', async () => {
    await S.cue('start it again', null, async () => {
      await S.open({ fresh: false, args: openArgs, wait: null });
      S.startSegment();
    });
    S.mark("Everything's back", S.videoBefore);
    const dbg = await S.win(/Debugger/, 30000);
    await S.cue('Proceed', box(dbg), () => act('click', `${dbg}.proceed`), { frac: 0.5 });
    await sleep(1500);
    // the System Browser behind still shows ballColor as it was when it was selected: show it again
    act('select', `${W.browser}.methods`, 'move:'); await sleep(400);
    act('select', `${W.browser}.methods`, 'ballColor'); await sleep(1500);
  }],

  // 8. The JIT (VM-Jit, Smalltalk too) has compiled move: (every ball, every frame): System Browser › move: › machine
  // code: its arm64 under each bytecode, commented; scrolled to the first statement, where sends are inlined.
  ['jit', async () => {
    act('select', `${W.browser}.methods`, 'move:'); await sleep(700);
    act('rightclick', `${W.browser}.methods.move`); await sleep(800);
    let mc = null, opened = null;
    await S.cue("here's what it made for move", () => opened, async () => {
      act('click', '@menu.machine-code');
      mc = await S.win(/Machine code: ShannonJuggler>>move:/);
      opened = box(mc);
      await sleep(400);
      place(mc, 18, 41, 866, 843);
    });
    await sleep(1800);
    act('scroll', `${mc}.text`, '1240'); await sleep(1500);
    await S.cue('the sends got inlined', box(`${mc}.text`), () => act('scroll', `${mc}.text`, '480'));
    await sleep(2000);
    act('click', `${mc}.close`); await sleep(600);
  }],

  // 10. Smalltalk in Smalltalk: World menu › VM Simulator › Smalltalk-80 boots a small Smalltalk-80 image on the
  // simulated VM (the VM's own Smalltalk classes, run as Smalltalk); its 640×400 1-bit screen is the tool's guest
  // display. In its Workspace: 3 + 4 typed and printed, 100 factorial printString size printed; its ball window
  // dragged. Guest pixels are addressed through the display (hover --at x,y answers the screen point).
  ['guest', async () => {
    act('click', DESK); await sleep(700);
    act('click', '@menu.vm-simulator');
    const sim = await S.win(/VM Simulator/);
    await sleep(400);
    place(sim, 18, 41, 1404, 843);
    await sleep(400);
    const screen = `${sim}.screen`;
    // the guest display appears with the guest, its first frame a moment later
    const shown = () => ctl('snapshot', sim, '--depth', '1').split('\n').some(l => l.includes('.screen ') && / frames=[1-9]/.test(l));
    await S.cue("here's Smalltalk running inside Smalltalk", () => box(screen), async () => {
      act('click', `${sim}.st80`);
      for (let t = 0; !shown(); t += 100) {
        if (t > 15000) throw new Error('the Smalltalk-80 guest shows no frames');
        await sleep(100);
      }
    }, { lead: 2, max: 15 });
    await sleep(1500);
    const pixel = (x, y) => JSON.parse(ctl('hover', screen, '--at', `${x},${y}`)).at.join(',');
    const at = pixel(220, 195);                        // the Workspace's empty last line, right of where 3 + 4 goes
    // A line of the guest's Workspace from guest x 0 (guest pixels are 1.5 points here), where what is typed and printed
    // shows, as a region: without the pointer (on the last line it clicks right of it) or the guest's ball window
    // (animated).
    const [ax, ay] = at.split(',').map(Number);
    const lineAt = (y, w) => [Math.round(ax - 220.5 * 1.5), y - 14, w, 28];
    const LINE = lineAt(ay, 240);
    await S.cue('Three plus four', LINE, async () => {
      act('click', at); await sleep(300);
      act('type', screen, '3 + 4', '--delay', '130'); await sleep(300);
    }, { frac: 0.15, max: 6 });                        // the first character, not the caret
    await S.cue('seven', LINE, () => act('key', 'Meta+p', screen));
    await sleep(800);
    const line = pixel(200, 115);
    await S.cue('Something bigger', lineAt(Number(line.split(',')[1]), 440), async () => {
      act('click', line); await sleep(300);            // the line 100 factorial printString size
      act('key', 'Meta+p', screen);
    }, { lead: 0.3 });
    await sleep(1000);
    const tab = pixel(390, 199);
    await S.cue('drag around', box(screen), () => act('drag', tab, '-230', '25'), { frac: 0.1 });   // the ball window, by its title tab
    await sleep(2200);
  }],
  // 11. The GC is Smalltalk too (VM-Core › GarbageCollector): TENURE_AGE := 0 promotes every survivor of a scavenge
  // (2: those that survive two). World menu › Rebuild VM & reboot: the VM is translated to C (the translation runs
  // the class-side initialize methods again: TENURE_AGE 0), compiled, the image saved, the screen faded, the new VM
  // exec'd (same process, same control port).
  ['gc', async () => {
    const sim = await S.win(/VM Simulator/, 1000).catch(() => null);
    if (sim) { act('click', `${sim}.close`); await sleep(600); }
    await browseTo('VM-Core', 'GarbageCollector', 'class');
    await S.cue("The garbage collector's Smalltalk too", CODE(), pickMethod('initialize'));
    await sleep(600);
    await S.cue('make that zero', CODE(), () => edit('TENURE_AGE := 2', 'TENURE_AGE := 0', 110), TYPING);
    expect(`${W.browser}.code`, 'TENURE_AGE := 0');
    await S.cue('save', STATUS(), save);
    await sleep(500);
    act('click', DESK); await sleep(700);
    let rb = null, ref = null;
    await S.cue('rebuild the VM', () => rb, async () => {
      act('click', '@menu.rebuild-vm-reboot');
      try { ref = await S.win(/VM Rebuild/); rb = box(ref); } catch {}
    });
    await sleep(300);
    if (ref) place(ref, 18, 41, 866, 470);
    // On the recording clock a rebuild takes less video than the next beat's narration: it waits for it.
    S.eval(`${REBUILD} do: [:p | p suspend]. 1`);
  }],
  // While it compiles, on the old VM: a do-it that allocates, keeping its last 3000 arrays, then World menu › System
  // Monitor (right column): they die young, survivors are promoted after two scavenges, old space barely grows. The
  // recording ends with the old VM; the next segment starts with the new VM's restart splash.
  ['gc-churn', async () => {
    await S.cue("here's a little loop", WORKSPACE(), () => evaluate(CHURN));
    S.busy = true;                                     // the churn keeps the image busy: commands do not wait to settle
    act('click', DESK); await sleep(500);
    act('click', '@menu.system-monitor');
    const mon = await S.win(/System Monitor/);
    await sleep(300);
    place(mon, 898, 41, 524, 843);
    await S.spoken(1.5);                               // the rebuild goes on, to fade once this has been said
    S.eval(`${REBUILD} do: [:p | p resume]. 1`);
    await S.recordingEnded(240000);                    // the screen fades, the VM execs the new one: the recording ends
    S.stopSegment();
    await S.spoken(-0.35);                             // black until this narration and the next one's first word are over
    for (let t = 0; ; t += 15000) {                    // the new VM has resumed, its World composited
      try { S.run(['wait', 'rebooted in', '15000']); break; } catch (e) { if (t > 120000) throw e; }
    }
    S.startSegment();
    await sleep(800);
  }],
  // The System Monitor, restored with the image, samples on; widened over the screen (its charts keep their last
  // minute): old space climbs, a full GC every few seconds, the count of full GCs in its readout.
  ['gc-after', async () => {
    S.mark("there's the new VM", S.videoBefore);
    const mon = await S.win(/System Monitor/);
    await S.cue('old space fills right up', [40, 80, 820, 760], () => place(mon, 18, 41, 1404, 843));
    await sleep(6000);
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
      act('select', `${fb}.viewer`, text);
    };
    const VIEWER = [810, 100, 600, 760];   // the file viewer, right of three columns
    await pick(1, 'vm');
    await pick(2, 'gen', 1100);
    await S.cue("Here's the C", VIEWER, () => pick(3, 'interpreter.c', 300));
    await sleep(1200);
    await S.cue('the whole interpreter', VIEWER, () => show('vm/gen/interpreter.c', 'void interpret(void)'));
    await sleep(1500);
    await pick(1, 'src');
    await pick(2, 'VM-Core');
    await S.cue("here's the Smalltalk it came from", VIEWER, async () => {
      await pick(3, 'Interpreter.st', 700);
      await show('src/VM-Core/Interpreter.st', "<c: 'void interpret(void)'>");
    }, { frac: 0.1 });
    await S.spoken();
    await sleep(800);
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
for (let t = 0; !text(`${W.workspace}.text`).includes(CHURN); t += 500) {
  if (t > 60000) throw new Error('the do-its did not arrive in the Workspace');
  await sleep(500);
}
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
