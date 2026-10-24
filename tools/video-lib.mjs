// Shared driver for the narrated videos (walkthrough.mjs, mindblown/walkthrough-mindblown.mjs): a visible Samaltak
// window driven only through samaltak-ctl, recorded from the compositor (samaltak-ctl record), with a caption per step.
// Each step lasts at least as long as its narration clip (<out>/narration/durations.json from narrate.mjs).
// A recording may have several segments (e.g. across a quit and relaunch of the image): the segments are concatenated
// into <out>/raw.mp4 and the captions are timed on the concatenated video.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const sleep = ms => new Promise(r => setTimeout(r, ms));
const probe = file => +execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim();

export class VideoSession {
  // out: output directory; stepsFile: narration.json (id, caption, spoken per step).
  constructor({ out, stepsFile, session = 'walkthrough', image }) {
    this.out = out;
    mkdirSync(out, { recursive: true });
    this.env = { ...process.env, SAMALTAK_SESSION: session };
    this.image = image;
    this.steps = JSON.parse(readFileSync(stepsFile, 'utf8'));
    const durationsFile = join(out, 'narration', 'durations.json');
    this.durations = existsSync(durationsFile) ? JSON.parse(readFileSync(durationsFile, 'utf8')) : {};
    this.captions = [];
    this.segments = [];
    this.videoBefore = 0;   // seconds of video in finished segments
    this.t0 = 0;            // wall clock (ms) at which the current segment's video time is videoBefore
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

  // Start the image (fresh: close any old session first) and wait for its desktop.
  async open({ fresh = true, image = this.image, args = [] } = {}) {
    if (fresh) { try { this.ctl('close'); } catch {} }
    this.ctl('open', '--image', image, '--window-size', '1440x900', ...args);
    await this.win(/System Browser|Workspace/);
    try { this.ctl('wait', 'idle', '15000'); } catch {}
  }
  startSegment() {
    const file = join(this.out, `raw-${this.segments.length + 1}.mp4`);
    this.ctl('record', 'start', file, '--size', '1440x900', '--fps', '30');
    this.segments.push(file);
    this.t0 = Date.now();
    this.recording = true;
  }
  stopSegment() {
    console.log(this.ctl('record', 'stop'));
    this.recording = false;
    this.videoBefore += probe(this.segments[this.segments.length - 1]);
  }

  // Begin step id: wait until the previous step's narration is over, then show id's caption.
  async say(id) {
    const step = this.steps.find(s => s.id === id);
    if (!step) throw new Error(`no narration step ${id}`);
    const prev = this.captions[this.captions.length - 1];
    if (prev && this.durations[prev.id]) {
      const wait = (prev.start + this.durations[prev.id] + 0.4 - this.now()) * 1000;
      if (wait > 0) await sleep(wait);
    }
    const t = this.now();
    if (prev) prev.end = t;
    this.captions.push({ id, start: t, end: null, text: step.caption });
    console.log(`${t.toFixed(1).padStart(6)}s  ${step.caption}`);
  }
  // Seconds left of the current step's narration (0 when over).
  remaining() {
    const cur = this.captions[this.captions.length - 1];
    return cur && this.durations[cur.id] ? Math.max(0, cur.start + this.durations[cur.id] - this.now()) : 0;
  }

  // End: let the last narration finish, stop recording, close the image, concatenate the segments into raw.mp4.
  async finish() {
    const last = this.captions[this.captions.length - 1];
    const rest = (last.start + (this.durations[last.id] || 0) + 1.2 - this.now()) * 1000;
    if (rest > 0) await sleep(rest);
    last.end = this.now();
    this.stopSegment();
    this.ctl('close');
    const raw = join(this.out, 'raw.mp4');
    if (this.segments.length === 1) {
      execFileSync('mv', [this.segments[0], raw]);
    } else {
      const list = join(this.out, 'segments.txt');
      writeFileSync(list, this.segments.map(f => `file '${f}'`).join('\n') + '\n');
      execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', raw]);
      rmSync(list);
    }
    writeFileSync(join(this.out, 'captions.json'), JSON.stringify(this.captions, null, 2));
    console.log(`wrote ${raw} (${probe(raw).toFixed(2)} s, ${this.segments.length} segment(s)) and captions.json`);
  }
}
