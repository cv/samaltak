#!/usr/bin/env node
// Records a narrated walkthrough of the Debugger and Profiler, driven entirely through samaltak-ctl.
// Usage: node walkthrough.mjs <out-dir>   →  <out-dir>/raw.webm, <out-dir>/captions.json
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] || join(here, '../../.context/video'));
mkdirSync(out, { recursive: true });
const SESSION = 'walkthrough';
const env = { ...process.env, SAMALTAK_SESSION: SESSION };

const ctl = (...args) => execFileSync(join(here, 'samaltak-ctl'), args, { env, encoding: 'utf8' });
const ab = (...args) => execFileSync('agent-browser', ['--session', SESSION, ...args], { encoding: 'utf8' });
const sleep = ms => new Promise(r => setTimeout(r, ms));

// Window ref by title regex, from a shallow snapshot.
function win(re) {
  const line = ctl('snapshot', '--depth', '1').split('\n').find(l => l.startsWith('window ') && re.test(l));
  if (!line) throw new Error(`no window matching ${re}`);
  return line.match(/@w\d+/)[0];
}
// First ref in a window whose line matches re.
function refIn(w, re) {
  const line = ctl('snapshot', w).split('\n').find(l => re.test(l));
  if (!line) throw new Error(`no widget matching ${re} in ${w}`);
  return line.match(/@[\w.~-]+/)[0];
}
// Type like a person, one character at a time at the caret (the first replaces any selection).
async function typeSlowly(ref, text, ms = 45) {
  for (const ch of text) { ctl('type', ref, ch); await sleep(ms); }
}

// Each step lasts at least as long as its narration clip (durations from narrate.mjs, if present).
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

try { ab('record', 'stop'); } catch {}
ctl('open');
await sleep(1500);
ab('record', 'start', join(out, 'raw.webm'));
process.on('exit', () => { try { ab('record', 'stop'); } catch {} });
t0 = Date.now();
await sleep(300);

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
ctl('click', '@w4.view'); await sleep(800);
ctl('type', '@w1.text', '\n', '--end');
await typeSlowly('@w1.text', '48 gcd: 18');
ctl('select', '@w1.text', '48 gcd: 18'); await sleep(600);
ctl('key', 'Meta+p', '@w1.text'); await sleep(2500);

const dbg = win(/Breakpoint: Integer>>gcd:/);
await say('hit');
await sleep(4500);

await say('step');
for (let i = 0; i < 5; i++) { ctl('click', `${dbg}.over`); await sleep(1300); }

await say('eval');
const ctxFields = refIn(dbg, /fields @w\d+\.context/);
ctl('select', ctxFields, 'a'); await sleep(900);
await typeSlowly(`${dbg}.context-evaluator`, 'a + b');
ctl('select', `${dbg}.context-evaluator`, 'all'); await sleep(400);
ctl('key', 'Meta+p', `${dbg}.context-evaluator`); await sleep(2500);

await say('proceed');
ctl('click', `${dbg}.proceed`); await sleep(3000);

await say('dnu');
ctl('type', '@w1.text', '\n', '--end');
await typeSlowly('@w1.text', '3 zork');
ctl('select', '@w1.text', '3 zork'); await sleep(500);
ctl('key', 'Meta+p', '@w1.text'); await sleep(2200);
const note = win(/MessageNotUnderstood: SmallInteger>>#zork/);
ctl('click', `${note}.create`); await sleep(1200);
ctl('click', '@menu.integer'); await sleep(1800);

await say('create');
const dnu = win(/Debugger — MessageNotUnderstood/);
await typeSlowly(`${dnu}.source`, 'self * 100', 70);
await sleep(600);
ctl('key', 'Meta+s', `${dnu}.source`); await sleep(1500);
ctl('click', `${dnu}.proceed`); await sleep(2800);

await say('watch');
ctl('select', '@w1.text', 'p := 3 @ 4'); await sleep(500);
ctl('key', 'Meta+i', '@w1.text'); await sleep(1500);
const insp = win(/Inspector: a Point/);
ctl('rightclick', `${insp}.fields.x`); await sleep(1300);
ctl('click', '@menu.halt-on-write'); await sleep(1500);
ctl('drag', `${insp}.title`, '700', '-330'); await sleep(1200);

await say('watch-hit');
ctl('select', '@w1.text', "[5 timesRepeat: [p x: p x + 1. Transcript show: p printString; cr]] forkNamed: 'mover'"); await sleep(800);
ctl('key', 'Meta+d', '@w1.text'); await sleep(4500);

await say('unwatch');
const watch = win(/watchpoint on #x/);
ctl('click', `${watch}.unwatch`); await sleep(1000);
ctl('click', `${watch}.proceed`); await sleep(3000);
ctl('click', `${insp}.close`); await sleep(800);

// ---------------------------------------------------------------- profiler
await say('profiler');
ctl('click', '@desktop'); await sleep(900);
ctl('click', '@menu.run-long-computation'); await sleep(1000);
for (let i = 0; i < 3; i++) { ctl('click', '@w4.view'); await sleep(400); }
await sleep(800);
ctl('click', '@desktop'); await sleep(900);
ctl('click', '@menu.profiler'); await sleep(3000);
const prof = win(/"Profiler"/);
ctl('drag', `${prof}.title`, '-514', '-40'); await sleep(800);

await say('flame');
await sleep(2500);
ctl('click', refIn(prof, /flame-frame .*"MandelbrotView>>render /)); await sleep(3000);

await say('filter');
ctl('click', `${prof}.processes.mandelbrot`); await sleep(3000);

await say('tally');
ctl('click', `${prof}.tally`); await sleep(4000);

await say('alloc');
ctl('click', `${prof}.allocations`); await sleep(4000);

await say('frames');
ctl('click', `${prof}.processes.all-but-idle`); await sleep(800);
ctl('click', `${prof}.frames`);
for (let i = 0; i < 3; i++) { ctl('click', '@w4.view'); await sleep(500); }
await sleep(2000);
ctl('drag', `${prof}.frame-overview`, '330', '0'); await sleep(3500);

await say('range');
ctl('click', `${prof}.flame-graph`); await sleep(3500);

await say('outro');
await sleep(3500);

const last = captions[captions.length - 1];
const rest = t0 + (last.start + (durations[last.id] || 0) + 1.2) * 1000 - Date.now();
if (rest > 0) await sleep(rest);
last.end = (Date.now() - t0) / 1000;
ab('record', 'stop');
ctl('close');
writeFileSync(join(out, 'captions.json'), JSON.stringify(captions, null, 2));
console.log(`wrote ${join(out, 'raw.webm')} and captions.json`);
