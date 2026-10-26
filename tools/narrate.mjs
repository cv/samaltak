#!/usr/bin/env node
// Generates one ElevenLabs narration clip per step of a narration file (default: tools/narration.json).
// Usage: node narrate.mjs <out-dir> [steps.json]   →  <out-dir>/narration/<id>.mp3, durations.json
// Needs ELEVENLABS_API_KEY (environment or the repo's .env). ELEVENLABS_VOICE picks the voice; ELEVENLABS_REQUEST (JSON)
// adds to each request, e.g. {"voice_settings": {"stability": 0.5, "style": 0}}, and with "continuity": true each line
// gets its neighbours as previous_text and next_text, so the lines flow like one conversation. Clips are cached by
// what is sent.
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
const steps = JSON.parse(readFileSync(resolve(process.argv[3] || join(here, 'narration.json')), 'utf8'));
const durations = {};

for (const [i, step] of steps.entries()) {
  const file = join(out, `${step.id}.mp3`), stamp = join(out, `${step.id}.sha`);
  const body = { text: step.spoken, model_id: MODEL, ...extra };
  if (continuity && i > 0) body.previous_text = steps[i - 1].spoken;
  if (continuity && i < steps.length - 1) body.next_text = steps[i + 1].spoken;
  const sent = Object.keys(body).length > 2 ? JSON.stringify(body) : step.spoken;   // plain requests keep their old hash
  const hash = createHash('sha256').update(`${VOICE}\n${MODEL}\n${sent}`).digest('hex');
  if (!existsSync(file) || !existsSync(stamp) || readFileSync(stamp, 'utf8') !== hash) {
    const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE}?output_format=mp3_44100_128`, {
      method: 'POST',
      headers: { 'xi-api-key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) { console.error(`narrate: ${step.id}: HTTP ${res.status} ${await res.text()}`); process.exit(1); }
    writeFileSync(file, Buffer.from(await res.arrayBuffer()));
    writeFileSync(stamp, hash);
  }
  durations[step.id] = +execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim();
  console.log(`${step.id.padEnd(10)} ${durations[step.id].toFixed(1)}s`);
}
writeFileSync(join(out, 'durations.json'), JSON.stringify(durations, null, 2));
