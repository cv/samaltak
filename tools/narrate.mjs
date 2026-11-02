#!/usr/bin/env node
// Generates one ElevenLabs narration clip per step of a narration file (default: tools/narration.json), and when its cue
// words are spoken (narration-times.py: <out-dir>/narration/times.json).
// Usage: node narrate.mjs <out-dir> [steps.json]   →  <out-dir>/narration/<id>.mp3, durations.json, times.json
// Needs ELEVENLABS_API_KEY (environment or the repo's .env). ELEVENLABS_VOICE picks the voice; ELEVENLABS_REQUEST (JSON)
// adds to each request, e.g. {"voice_settings": {"stability": 0.5, "style": 0}}, and with "continuity": true each line
// gets its neighbours as previous_text and next_text, so the lines flow like one conversation. Clips are cached by
// what is sent. Each clip has a reference with the timing of every character (<id>.ref.json, /with-timestamps): a new
// clip is its own; a clip made before keeps its audio, and a take of the same request (<id>.ref.mp3) is mapped onto it.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(resolve(process.argv[2] || join(here, '../.context/video-real')), 'narration');
mkdirSync(out, { recursive: true });

const envFile = join(here, '../.env');
if (!process.env.ELEVENLABS_API_KEY && existsSync(envFile))
  for (const line of readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*"?([^"\n]*)"?\s*$/);
    if (m) process.env[m[1]] ??= m[2];
  }
const key = process.env.ELEVENLABS_API_KEY;
if (!key) { console.error('narrate: ELEVENLABS_API_KEY is not set'); process.exit(1); }

const VOICE = process.env.ELEVENLABS_VOICE || 'CwhRBWXzGAHq8TQ4Fs17'; // "Roger": laid-back, casual, conversational
const MODEL = 'eleven_v4'; // delivery via inline audio tags such as [warm], [pause]
const { continuity, ...extra } = JSON.parse(process.env.ELEVENLABS_REQUEST || '{}');
const stepsFile = resolve(process.argv[3] || join(here, 'narration.json'));
const steps = JSON.parse(readFileSync(stepsFile, 'utf8'));
const durations = {};

// A take of body with the start and end time of each character of its text.
async function speak(id, body) {
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE}/with-timestamps?output_format=mp3_44100_128`, {
    method: 'POST',
    headers: { 'xi-api-key': key, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) { console.error(`narrate: ${id}: HTTP ${res.status} ${await res.text()}`); process.exit(1); }
  const j = await res.json();
  return { audio: Buffer.from(j.audio_base64, 'base64'), alignment: j.alignment };
}

for (const [i, step] of steps.entries()) {
  const file = join(out, `${step.id}.mp3`), stamp = join(out, `${step.id}.sha`), ref = join(out, `${step.id}.ref.json`);
  const body = { text: step.spoken, model_id: MODEL, ...extra };
  if (continuity && i > 0) body.previous_text = steps[i - 1].spoken;
  if (continuity && i < steps.length - 1) body.next_text = steps[i + 1].spoken;
  const sent = Object.keys(body).length > 2 ? JSON.stringify(body) : step.spoken;   // plain requests keep their old hash
  const hash = createHash('sha256').update(`${VOICE}\n${MODEL}\n${sent}`).digest('hex');
  if (!existsSync(file) || !existsSync(stamp) || readFileSync(stamp, 'utf8') !== hash) {
    const take = await speak(step.id, body);
    writeFileSync(file, take.audio);
    writeFileSync(stamp, hash);
    writeFileSync(ref, JSON.stringify({ hash, audio: null, alignment: take.alignment }));
  } else if (!existsSync(ref) || JSON.parse(readFileSync(ref, 'utf8')).hash !== hash) {
    const take = await speak(step.id, body);
    writeFileSync(join(out, `${step.id}.ref.mp3`), take.audio);
    writeFileSync(ref, JSON.stringify({ hash, audio: `${step.id}.ref.mp3`, alignment: take.alignment }));
  }
  durations[step.id] = +execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim();
  console.log(`${step.id.padEnd(10)} ${durations[step.id].toFixed(1)}s`);
}
writeFileSync(join(out, 'durations.json'), JSON.stringify(durations, null, 2));
execFileSync('python3', [join(here, 'narration-times.py'), out, stepsFile], { stdio: 'inherit' });
