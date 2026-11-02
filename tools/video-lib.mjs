// Shared driver for the narrated videos (walkthrough.mjs, mindblown/walkthrough-mindblown.mjs): a visible Samaltak
// window driven only through samaltak-ctl, recorded from the compositor (samaltak-ctl record), with a caption per step.
// Each step lasts at least as long as its narration clip (<out>/narration/durations.json from narrate.mjs); its cue
// words are spoken when their effects show (cue, compose-video.py).
// A recording may have several segments (e.g. across a quit and relaunch of the image): the video keeps real time, each
// segment's last frame (black, after a quit's fade) holds until the next begins; <out>/raw.mp4 is the result, the
// captions are timed on it.
import { execFile, execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const sleep = ms => new Promise(r => setTimeout(r, ms));
const sleepSync = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
const probe = file => +execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim();

export class VideoSession {
  // out: output directory; stepsFile: narration.json (id, caption, spoken per step).
  constructor({ out, stepsFile, session = 'walkthrough', image }) {
    this.out = out;
    mkdirSync(out, { recursive: true });
    this.env = { ...process.env, SAMALTAK_SESSION: session };
    this.image = image;
    this.steps = JSON.parse(readFileSync(stepsFile, 'utf8'));
    const durationsFile = join(out, 'narration', 'durations.json'), timesFile = join(out, 'narration', 'times.json');
    this.durations = existsSync(durationsFile) ? JSON.parse(readFileSync(durationsFile, 'utf8')) : {};
    this.times = existsSync(timesFile) ? JSON.parse(readFileSync(timesFile, 'utf8')) : {};
    this.captions = [];
    this.segments = [];     // {file, start: its video time, dur}
    this.videoBefore = 0;   // video time at which the current (or last) segment began
    this.t0 = 0;            // wall clock (ms) at which the video time is videoBefore
    this.recording = false;
    // Input commands wait at most 400 ms for the image to settle; with busy set they return at once (a busy image
    // never settles, and the script paces itself).
    this.busy = false;
    process.on('exit', () => { if (this.recording) try { this.ctl('record', 'stop'); } catch {} });
  }
  run(args) { return execFileSync(join(here, 'samaltak-ctl'), args, { env: this.env, encoding: 'utf8' }).trim(); }
  ctl(...args) { return this.run(['--settle', '400', ...args]); }
  act(...args) { return this.busy ? this.run(['--settle', '0', ...args]) : this.ctl(...args); }
  eval(source) { return this.run(['eval', source]); }
  now() { return this.videoBefore + (Date.now() - this.t0) / 1000; }

  // Window ref by title, from a shallow snapshot; waits until the window exists.
  async win(re, timeout = 15000) {
    const t = Date.now();
    for (;;) {
      let snap = '';
      try { snap = this.ctl('snapshot', '--depth', '1'); } catch {} // the UI registers a moment after the image listens
      const line = snap.split('\n').find(l => l.startsWith('window ') && re.test(l));
      if (line) return line.match(/@w\d+/)[0];
      if (Date.now() - t > timeout) throw new Error(`no window matching ${re}`);
      await sleep(100);
    }
  }
  async gone(re, timeout = 15000) {
    const t = Date.now();
    while (this.ctl('snapshot', '--depth', '1').split('\n').some(l => l.startsWith('window ') && re.test(l))) {
      if (Date.now() - t > timeout) throw new Error(`window ${re} still open`);
      await sleep(100);
    }
  }
  // The ref of the first widget of a role whose label begins with label (samaltak-ctl find).
  find(role, label) {
    const line = this.ctl('find', label).split('\n').find(l => l.startsWith(role + ' ') && l.includes(`"${label}`));
    if (!line) throw new Error(`no ${role} ${label}`);
    return line.split(' ')[1];
  }
  // Type like a person: one command, the image types one character every (ms + 95) ms (the walkthrough's pace).
  type(ref, text, ms = 45, ...flags) { return this.act('type', ref, text, '--delay', String(ms + 95), ...flags); }

  // Start the image (fresh: close any old session first) and wait for its desktop (wait: null, only until it listens).
  async open({ fresh = true, image = this.image, args = [], wait = /System Browser|Workspace/ } = {}) {
    if (fresh) { try { this.ctl('close'); } catch {} }
    this.ctl('open', '--image', image, '--window-size', '1440x900', ...args);
    if (!wait) return;
    await this.win(wait);
    try { this.ctl('wait', 'idle', '15000'); } catch {}
  }
  // Start recording a segment, as soon as the image's UI can (right after a start it registers record a moment later).
  startSegment() {
    const file = join(this.out, `raw-${this.segments.length + 1}.mp4`);
    for (const t = Date.now(); ; sleepSync(30)) {
      try { this.run(['record', 'start', file, '--size', '1440x900', '--fps', '30']); break; }
      catch (e) { if (Date.now() - t > 30000) throw e; }
    }
    // The video's clock is the recorder's (its first frame at its startTime, image ms): now() follows it.
    const [start, at] = this.eval("(World current compositor recorder instVarNamed: 'startTime') printString, ' ', (Time microsecondClockValue / 1000.0) printString")
      .replace(/'/g, '').split(' ').map(Number);
    const first = Date.now() - (at - start);
    if (this.segments.length) this.videoBefore += (first - this.t0) / 1000;
    this.imageStart = start;
    this.t0 = first;
    this.segments.push({ file, start: this.videoBefore });
    this.recording = true;
  }
  // The video time of image time ms (Time microsecondClockValue / 1000) in the current segment.
  imageToVideo(ms) { return this.videoBefore + (ms - this.imageStart) / 1000; }
  // Evaluate source without waiting: a Promise of its printString.
  evalAsync(source, timeout = 30000) {
    return new Promise((resolve, reject) => execFile(join(here, 'samaltak-ctl'), ['eval', source, '--timeout', String(timeout)],
      { env: this.env, encoding: 'utf8' }, (err, out) => err ? reject(err) : resolve(out.trim())));
  }
  // Wait until the recording ended by itself: the image quit, or its VM exec'd another (ffmpeg saw the end of the FIFO).
  async recordingEnded(timeout = 30000) {
    const session = join(process.env.TMPDIR || tmpdir(), 'samaltak-ctl', `${this.env.SAMALTAK_SESSION}.json`);
    const t = Date.now();
    for (;;) {
      let rec = null;
      try { rec = JSON.parse(readFileSync(session, 'utf8')).recording; } catch {}
      if (!rec || !alive(rec.pid)) return;
      if (Date.now() - t > timeout) throw new Error('the recording did not end');
      await sleep(50);
    }
  }
  stopSegment() {
    console.log(this.ctl('record', 'stop'));
    this.recording = false;
    const seg = this.segments[this.segments.length - 1];
    seg.dur = probe(seg.file);
  }

  // Begin step id: wait until the previous step's narration is over, then show id's caption.
  async say(id) {
    const step = this.steps.find(s => s.id === id);
    if (!step) throw new Error(`no narration step ${id}`);
    const prev = this.captions[this.captions.length - 1];
    if (prev) {
      const wait = (this.narrationEnd(prev) + 0.4 - this.now()) * 1000;
      if (wait > 0) await sleep(wait);
    }
    const t = this.now();
    if (prev) prev.end = t;
    this.captions.push({ id, start: t, end: null, text: step.caption, cues: [] });
    console.log(`${t.toFixed(1).padStart(6)}s  ${step.caption}`);
  }
  // Where cue text starts in step id's clip (s; times.json from narrate.mjs).
  cueAt(id, text) {
    const c = (this.times[id]?.cues || []).find(c => c.text === text);
    if (!c) throw new Error(`no cue ${JSON.stringify(text)} in step ${id} (its "cues" in the narration file; narrate.mjs)`);
    return c.at;
  }
  // When a step's narration ends at the latest (its speech: times.json "end", else its clip): from its last cue so far,
  // else from its start.
  narrationEnd(step) {
    const d = this.times[step.id]?.end ?? this.durations[step.id] ?? 0, last = step.cues[step.cues.length - 1];
    return last ? last.est + d - this.cueAt(step.id, last.text) : step.start + d;
  }
  // A cue of the current step: text, a phrase of its narration ("cues"), says that action happens or that its effect
  // shows. Wait until the narration could have got to text (spoken on from the step's start or its previous cue; lead
  // seconds earlier when the effect takes about that long to show), run action, note when. Where the effect shows:
  // region, [x, y, w, h] of the screen (or a function answering it after the action), in which compose-video.py finds
  // the frame where it changed (within max seconds; frac of its largest change counts as shown); or, where the screen
  // moves anyway, when: a Smalltalk condition that turns true with the effect, waited for in the image (false when the
  // cue begins: else the effect came before its words); neither: the action is what shows (e.g. a launch, while the
  // screen is black). Text is spoken there.
  async cue(text, region, action, { lead = 0, max = 2, frac = 0.3, when = null } = {}) {
    const step = this.captions[this.captions.length - 1];
    const at = this.cueAt(step.id, text), prev = step.cues[step.cues.length - 1];
    const waiting = when && this.evalAsync(`[${when}] value ifTrue: [-1] ifFalse: [[${when}] whileFalse: [(Delay forMilliseconds: 10) wait]. Time microsecondClockValue / 1000.0]`, (max + 30) * 1000);
    const earliest = prev ? prev.est + at - this.cueAt(step.id, prev.text) : step.start + at;
    const wait = (earliest - lead - this.now()) * 1000;
    if (wait > 0) await sleep(wait);
    const t = this.now();
    if (action) await action();
    // the image's time: the next frame (60 Hz) shows it
    const ms = waiting ? parseFloat(await waiting) : null;
    if (ms < 0) throw new Error(`cue ${JSON.stringify(text)}: ${when} before it began`);
    const shown = waiting ? this.imageToVideo(ms) + 1 / 60 : region == null ? t : null;
    step.cues.push({ text, t, est: shown ?? Math.max(this.now(), t + lead), shown, max, frac,
      region: shown != null ? null : typeof region === 'function' ? region() : region });
  }
  // A cue whose effect showed at video time t without an action (e.g. the first frame after a restart).
  mark(text, t) {
    const step = this.captions[this.captions.length - 1];
    this.cueAt(step.id, text);
    step.cues.push({ text, t, est: t, shown: t, region: null });
  }
  // Wait until the current step's narration is over.
  async spoken() {
    const wait = (this.narrationEnd(this.captions[this.captions.length - 1]) - this.now()) * 1000;
    if (wait > 0) await sleep(wait);
  }

  // End: let the last narration finish, stop recording, close the image, concatenate the segments into raw.mp4.
  async finish() {
    const last = this.captions[this.captions.length - 1];
    const rest = (this.narrationEnd(last) + 1.2 - this.now()) * 1000;
    if (rest > 0) await sleep(rest);
    last.end = this.now();
    this.stopSegment();
    this.ctl('close');
    const raw = join(this.out, 'raw.mp4');
    if (this.segments.length === 1) {
      execFileSync('mv', [this.segments[0].file, raw]);
    } else {
      const segs = this.segments, holds = segs.map((s, i) => i + 1 < segs.length ? segs[i + 1].start - s.start - s.dur : 0);
      if (holds.some(h => h < -0.05)) throw new Error(`segments overlap: ${JSON.stringify(segs)}`);
      const graph = segs.map((s, i) => `[${i}:v]tpad=stop_mode=clone:stop_duration=${Math.max(0, holds[i]).toFixed(3)}[s${i}]`)
        .concat(segs.map((s, i) => `[s${i}]`).join('') + `concat=n=${segs.length}:v=1:a=0[v]`);
      execFileSync('ffmpeg', ['-v', 'error', '-y', ...segs.flatMap(s => ['-i', s.file]), '-filter_complex', graph.join(';'),
        '-map', '[v]', '-c:v', 'libx264', '-crf', '12', '-preset', 'fast', '-pix_fmt', 'yuv420p', raw]);
    }
    writeFileSync(join(this.out, 'captions.json'), JSON.stringify(this.captions, null, 2));
    console.log(`wrote ${raw} (${probe(raw).toFixed(2)} s, ${this.segments.length} segment(s)) and captions.json`);
  }
}
