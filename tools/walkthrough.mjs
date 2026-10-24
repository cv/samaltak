#!/usr/bin/env node
// Records the narrated Debugger and Profiler walkthrough on the real system: a visible Samaltak window (1440x900 points),
// driven only through samaltak-ctl, recorded from the compositor (samaltak-ctl record).
// Usage: node walkthrough.mjs <out-dir>   →  <out-dir>/raw.mp4, <out-dir>/captions.json
// Run narrate.mjs first: each step then lasts at least as long as its narration clip (<out-dir>/narration/durations.json).
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { VideoSession, sleep } from './video-lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const S = new VideoSession({
  out: resolve(process.argv[2] || join(here, '../.context/video-real')),
  stepsFile: join(here, 'narration.json'),
  session: process.env.WALKTHROUGH_SESSION || 'walkthrough',
  image: process.env.WALKTHROUGH_IMAGE || join(here, '../build/samaltak.image'),
});
const run = args => S.run(args);
const ctl = (...args) => S.ctl(...args);
const act = (...args) => S.act(...args);
const win = (re, t) => S.win(re, t);
const find = (role, label) => S.find(role, label);
const say = id => S.say(id);
// Type like a person (the prototype's video: 140 ms a character).
const typeSlowly = async (ref, text, ms = 45) => S.type(ref, text, ms);

await S.open();
await sleep(1500);
S.startSegment();
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
S.busy = true;
act('click', '@w4.view'); await sleep(800);
act('type', '@w1.text', '\n', '--end');
await typeSlowly('@w1.text', '48 gcd: 18');
act('select', '@w1.text', '48 gcd: 18'); await sleep(600);
act('key', 'Meta+p', '@w1.text'); await sleep(2500);
S.busy = false;

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
ctl('click', '@menu.run-long-computation'); S.busy = true; await sleep(700);
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

await S.finish();
