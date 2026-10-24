#!/usr/bin/env node
// Records the narrated Debugger and Profiler walkthrough on the real system: a visible Samaltak window (1440x900 points),
// driven only through samaltak-ctl, recorded from the compositor (samaltak-ctl record).
// Usage: node walkthrough.mjs <out-dir>   →  <out-dir>/raw.mp4, <out-dir>/captions.json
// Run narrate.mjs first: each step then lasts at least as long as its narration clip (<out-dir>/narration/durations.json).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] || join(here, '../.context/video-real'));
mkdirSync(out, { recursive: true });
const SESSION = process.env.WALKTHROUGH_SESSION || 'walkthrough';
const env = { ...process.env, SAMALTAK_SESSION: SESSION };
const image = process.env.WALKTHROUGH_IMAGE || join(here, '../build/samaltak.image');

// Input commands wait at most 400 ms for the image to settle: with the Mandelbrot and crunch busy it never does, and
// the script paces itself anyway.
const run = args => execFileSync(join(here, 'samaltak-ctl'), args, { env, encoding: 'utf8' }).trim();
const ctl = (...args) => run(['--settle', '400', ...args]);
// Once 'crunch' runs nothing settles: from there on input commands return at once, and the pauses pace the steps.
let busy = false;
const act = (...args) => busy ? run(['--settle', '0', ...args]) : ctl(...args);
const sleep = ms => new Promise(r => setTimeout(r, ms));

// Window ref by title, from a shallow snapshot; waits until the window exists.
async function win(re, timeout = 15000) {
  const t = Date.now();
  for (;;) {
    let snap = '';
    try { snap = ctl('snapshot', '--depth', '1'); } catch {} // the UI registers a moment after the image listens
    const line = snap.split('\n').find(l => l.startsWith('window ') && re.test(l));
    if (line) return line.match(/@w\d+/)[0];
    if (Date.now() - t > timeout) throw new Error(`no window matching ${re}`);
    await sleep(100);
  }
}
// The ref of the first widget of a role whose label begins with label (samaltak-ctl find).
function find(role, label) {
  const line = ctl('find', label).split('\n').find(l => l.startsWith(role + ' ') && l.includes(`"${label}`));
  if (!line) throw new Error(`no ${role} ${label}`);
  return line.split(' ')[1];
}
// Type like a person: one command, the image types one character every (ms + 95) ms — the pace of the prototype's
// video (measured there: 140 ms a character for ms = 45; its script slept ms after each samaltak-ctl call).
async function typeSlowly(ref, text, ms = 45) {
  act('type', ref, text, '--delay', String(ms + 95));
}

// Each step lasts at least as long as its narration clip.
const steps = JSON.parse(readFileSync(join(here, 'narration.json'), 'utf8'));
const durationsFile = join(out, 'narration', 'durations.json');
const durations = existsSync(durationsFile) ? JSON.parse(readFileSync(durationsFile, 'utf8')) : {};
const captions = [];
let t0 = 0;
async function say(id) {
  const step = steps.find(s => s.id === id);
  if (!step) throw new Error(`no narration step ${id}`);
  const prev = captions[captions.length - 1];
  if (prev && durations[prev.id]) {
    const wait = t0 + (prev.start + durations[prev.id] + 0.4) * 1000 - Date.now();
    if (wait > 0) await sleep(wait);
  }
  const t = (Date.now() - t0) / 1000;
  if (prev) prev.end = t;
  captions.push({ id, start: t, end: null, text: step.caption });
  console.log(`${t.toFixed(1).padStart(6)}s  ${step.caption}`);
}

try { ctl('close'); } catch {}
ctl('open', '--image', image, '--window-size', '1440x900');
await win(/System Browser/);
ctl('wait', 'idle', '15000');
await sleep(1500);
ctl('record', 'start', join(out, 'raw.mp4'), '--size', '1440x900', '--fps', '30');
t0 = Date.now();
let recording = true;
process.on('exit', () => { if (recording) try { ctl('record', 'stop'); } catch {} });
await sleep(300);

// The same actions and pauses as the prototype's walkthrough (prototypes/tools/walkthrough.mjs), with real refs.
// ---------------------------------------------------------------- debugger
await say('intro');
await sleep(4000);

await say('breakpoint');
ctl('select', '@w6.packages', 'Kernel-Numbers'); await sleep(700);
ctl('select', '@w6.classes', 'Integer'); await sleep(700);
ctl('select', '@w6.protocols', 'all'); await sleep(700);
ctl('select', '@w6.methods', 'gcd:'); await sleep(1200);
ctl('click', '@w6.methods.gcd.breakpoint-toggle'); await sleep(1800);

await say('run');
// The click starts a render: the image will not settle until it is done, so the commands of this step do not wait for
// that (the pauses pace them, as in the prototype's script).
busy = true;
act('click', '@w4.view'); await sleep(800);
act('type', '@w1.text', '\n', '--end');
await typeSlowly('@w1.text', '48 gcd: 18');
act('select', '@w1.text', '48 gcd: 18'); await sleep(600);
act('key', 'Meta+p', '@w1.text'); await sleep(2500);
busy = false;

const dbg = await win(/Breakpoint: Integer>>gcd:/);
await say('hit');
await sleep(4500);

await say('step');
for (let i = 0; i < 5; i++) { ctl('click', `${dbg}.over`); await sleep(1300); }

await say('eval');
ctl('select', `${dbg}.context.fields`, 'a'); await sleep(900);
await typeSlowly(`${dbg}.context.evaluator`, 'a + b');
ctl('select', `${dbg}.context.evaluator`, 'all'); await sleep(400);
ctl('key', 'Meta+p', `${dbg}.context.evaluator`); await sleep(2500);

await say('proceed');
ctl('click', `${dbg}.proceed`); await sleep(3000);

await say('dnu');
ctl('type', '@w1.text', '\n', '--end');
await typeSlowly('@w1.text', '3 zork');
ctl('select', '@w1.text', '3 zork'); await sleep(500);
ctl('key', 'Meta+p', '@w1.text'); await sleep(2200);
const note = await win(/MessageNotUnderstood: SmallInteger>>#zork/);
ctl('click', `${note}.create`); await sleep(1200);
ctl('click', '@menu.integer'); await sleep(1800);

await say('create');
const dnu = await win(/Debugger — MessageNotUnderstood/);
await typeSlowly(`${dnu}.source`, 'self * 100', 70);
await sleep(600);
ctl('key', 'Meta+s', `${dnu}.source`); await sleep(1500);
ctl('click', `${dnu}.proceed`); await sleep(2800);

await say('watch');
ctl('select', '@w1.text', 'p := 3 @ 4'); await sleep(500);
ctl('key', 'Meta+i', '@w1.text'); await sleep(1500);
const insp = await win(/Inspector: a Point/);
ctl('rightclick', `${insp}.fields.x`); await sleep(1300);
ctl('click', '@menu.halt-on-write'); await sleep(1500);
ctl('drag', insp, '700', '-330'); await sleep(1200);

await say('watch-hit');
ctl('select', '@w1.text', "[5 timesRepeat: [p x: p x + 1. Transcript show: p printString; cr]] forkNamed: 'mover'"); await sleep(800);
ctl('key', 'Meta+d', '@w1.text'); await sleep(4500);

await say('unwatch');
const watch = await win(/watchpoint on #x/);
ctl('click', `${watch}.unwatch`); await sleep(1000);
ctl('click', `${watch}.proceed`); await sleep(3000);
ctl('click', `${insp}.close`); await sleep(800);

// ---------------------------------------------------------------- profiler
const DESK = '723,555'; // where the prototype's @desktop click landed (desk between the Workspace and the Inspector)
await say('profiler');
// (each input command here costs ~0.3 s more than the prototype's, mostly the pointer's glide: the pauses are shorter by that)
act('click', DESK); await sleep(600);
ctl('click', '@menu.run-long-computation'); busy = true; await sleep(700);
for (let i = 0; i < 3; i++) { act('click', '@w4.view'); await sleep(100); }
await sleep(800);
act('click', DESK); await sleep(600);
act('click', '@menu.profiler'); await sleep(2700);
const prof = await win(/"Profiler"/);
act('drag', prof, '-514', '-40'); await sleep(800);

await say('flame');
await sleep(2500);
act('click', find('flame-frame', 'MandelbrotView>>render ')); await sleep(3000);

await say('filter');
act('click', `${prof}.processes.mandelbrot`); await sleep(3000);

await say('tally');
act('click', `${prof}.tabs.tally`); await sleep(4000);

await say('alloc');
act('click', `${prof}.tabs.allocations`); await sleep(4000);

await say('frames');
act('click', `${prof}.processes.all-but-idle`); await sleep(800);
act('click', `${prof}.tabs.frames`);
const busyFrom = JSON.parse(run(['state'])).micros;
for (let i = 0; i < 3; i++) { act('click', '@w4.view'); await sleep(500); }
await sleep(2000);
// Wait until the three renders' 6.7 s have passed (the prototype's renders were done by now; real ones take longer).
{ const left = busyFrom / 1000 + 6900 - JSON.parse(run(['state'])).micros / 1000; if (left > 0) await sleep(left); }
// The prototype dragged 330 points across its overview, which then held ~12 s: a 6.7 s range over the busy Mandelbrot.
// The real ring holds longer, so drag over the same 6.7 s: from the first of these clicks on. The overview tells where
// time is on the screen (its plot= and time= state).
const ov = run(['snapshot', `${prof}.frame-overview`, '--bounds']).split('\n')[0];
const [px0, px1] = ov.match(/plot=(\d+)-(\d+)/).slice(1).map(Number);
const [tt0, tt1] = ov.match(/time=(\d+)-(\d+)/).slice(1).map(Number);
const xOf = t => Math.round(px0 + (t - tt0) * (px1 - px0) / (tt1 - tt0));
const r1 = Math.min(busyFrom + 6700000, tt1 - 100000), r0 = r1 - 6700000;
const [x0, x1] = [xOf(r0), xOf(r1)];
const bm = ov.match(/\[(\d+),(\d+) (\d+)x(\d+)\]/);
const y = +bm[2] + Math.round(+bm[4] / 2);
act('drag', `${x0},${y}`, `${x1},${y}`); await sleep(3500);

await say('range');
act('click', `${prof}.tabs.flame-graph`); await sleep(3500);

await say('outro');
await sleep(3500);

const last = captions[captions.length - 1];
const rest = t0 + (last.start + (durations[last.id] || 0) + 1.2) * 1000 - Date.now();
if (rest > 0) await sleep(rest);
last.end = (Date.now() - t0) / 1000;
const stopped = (Date.now() - t0) / 1000;
console.log(ctl('record', 'stop'));
recording = false;
ctl('close');
writeFileSync(join(out, 'captions.json'), JSON.stringify(captions, null, 2));
const video = +execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', join(out, 'raw.mp4')], { encoding: 'utf8' }).trim();
console.log(`wrote ${join(out, 'raw.mp4')} (${video.toFixed(2)} s of video for ${stopped.toFixed(2)} s of wall time) and captions.json`);
