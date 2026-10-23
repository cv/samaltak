#!/usr/bin/env node
// Generates one ElevenLabs narration clip per step in narration.json.
// Usage: node narrate.mjs <out-dir>   →  <out-dir>/narration/<id>.mp3, durations.json
// Needs ELEVENLABS_API_KEY (environment or the repo's .env). Clips are cached by text and voice.
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
const steps = JSON.parse(readFileSync(join(here, 'narration.json'), 'utf8'));
const durations = {};

for (const step of steps) {
  const file = join(out, `${step.id}.mp3`), stamp = join(out, `${step.id}.sha`);
  const hash = createHash('sha256').update(`${VOICE}\n${MODEL}\n${step.spoken}`).digest('hex');
  if (!existsSync(file) || !existsSync(stamp) || readFileSync(stamp, 'utf8') !== hash) {
    const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE}?output_format=mp3_44100_128`, {
      method: 'POST',
      headers: { 'xi-api-key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: step.spoken, model_id: MODEL }),
    });
    if (!res.ok) { console.error(`narrate: ${step.id}: HTTP ${res.status} ${await res.text()}`); process.exit(1); }
    writeFileSync(file, Buffer.from(await res.arrayBuffer()));
    writeFileSync(stamp, hash);
  }
  durations[step.id] = +execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file], { encoding: 'utf8' }).trim();
  console.log(`${step.id.padEnd(10)} ${durations[step.id].toFixed(1)}s`);
}
writeFileSync(join(out, 'durations.json'), JSON.stringify(durations, null, 2));
