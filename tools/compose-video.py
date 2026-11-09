#!/usr/bin/env python3
"""Adds a caption band and the narration (if <dir>/narration exists) to the walkthrough recording.
Usage: compose-video.py <dir> [out-name]   (expects <dir>/raw.mp4 and <dir>/captions.json; writes <dir>/<out-name>,
default walkthrough.mp4, and <dir>/cues.json)

A step's clip plays from its caption's start, unless the step has cues (video-lib.mjs cue): for each, the time its
effect showed is known (the image's) or found, the first frame after its action where its region of the screen changed;
the clip is cut before each cue's words (narration/times.json) so that they are spoken SPOKEN_AFTER s after it; what
comes before the first cue runs straight into it. Clips never overlap: a piece that would run into the next loses its
trailing silence (a pause shortened), else the next comes later (its words at most LATE s late)."""
import html, json, os, subprocess, sys
import numpy as np

SPOKEN_AFTER = 0.06   # a cue's words start this long after its effect shows (word times are good to about 50 ms)
LATE = 0.15
CAPTION_ONLY = 3.5    # how long a caption without narration stays up, over the next step's narration
MIN_PAUSE = 0.15      # a shortened pause, from the end of the speech (+50 ms) to the next piece
FPS = 30

d = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../.context/video-real'))
fonts = os.path.abspath(os.path.join(os.path.dirname(__file__), '../prototypes/shared/pi-orb-fonts.css'))
caps = json.load(open(os.path.join(d, 'captions.json')))
name = sys.argv[2] if len(sys.argv) > 2 else 'walkthrough.mp4'
raw = os.path.join(d, 'raw.mp4')
narration = os.path.join(d, 'narration')
times = json.load(open(os.path.join(narration, 'times.json'))) if os.path.exists(os.path.join(narration, 'times.json')) else {}
durations = json.load(open(os.path.join(narration, 'durations.json'))) if os.path.exists(os.path.join(narration, 'durations.json')) else {}


def region_frames(t0, seconds, region):
    """The frames of region [x, y, w, h] from the frame at video time t0 on, and the time of the first."""
    x, y, w, h = [int(round(v)) // 2 * 2 for v in region]   # even: the video is yuv420p
    k = max(0, int(np.floor(t0 * FPS)))
    t0 = k / FPS
    out = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{max(0.0, (k - 0.5) / FPS):.4f}', '-i', raw, '-t', f'{seconds:.3f}',
                          '-vf', f'crop={w}:{h}:{x}:{y}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                         check=True, capture_output=True).stdout
    frames = np.frombuffer(out, dtype=np.uint8).reshape(-1, h, w, 3).astype(np.int16)
    return frames, t0


def shown(cue, until):
    """Video time of the first frame after cue's action whose region changed by frac of its largest change (before
    until, the next action)."""
    frames, t0 = region_frames(cue['t'] - 0.1, min(cue['max'], until - cue['t'] - 1 / FPS) + 0.1, cue['region'])
    change = np.array([(np.abs(f - frames[0]).max(axis=2) > 16).mean() for f in frames])
    if change.max() < 0.002:
        return None, change.max()
    first = int(np.argmax(change >= cue['frac'] * change.max()))
    return t0 + first / FPS, change.max()


energy = {}


def speech_end(sid, a, b):
    """Where the speech of clip sid between a and b s ends: 50 ms after its last voiced 10 ms (25 dB under its loud ones)."""
    if sid not in energy:
        pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', os.path.join(narration, f'{sid}.mp3'), '-ac', '1', '-ar', '16000',
                              '-f', 's16le', '-'], check=True, capture_output=True).stdout
        x = np.frombuffer(pcm, dtype=np.int16).astype(float)
        e = 10 * np.log10((x[:len(x) // 160 * 160].reshape(-1, 160) ** 2).mean(axis=1) + 1)
        energy[sid] = (e, np.percentile(e, 90) - 25)
    e, voiced = energy[sid]
    fa, fb = int(round(a * 100)), int(round(b * 100))
    v = np.nonzero(e[fa:fb] >= voiced)[0]
    return b if len(v) == 0 else min(b, (fa + v[-1] + 1) / 100 + 0.05)


# Where each clip's pieces play (step, start: in the video, a-b: of the clip; cue: its report) — a cue step is cut
# before each cue.
pieces, report, problems = [], [], []
for c in caps:
    sid, dur = c['id'], durations.get(c['id'])
    if dur is None or not os.path.exists(os.path.join(narration, f'{sid}.mp3')):
        continue
    cues = c.get('cues') or []
    if not cues:
        pieces.append({'sid': sid, 'start': c['start'], 'a': 0.0, 'b': dur, 'cue': None})
        continue
    spec = {x['text']: x for x in times[sid]['cues']}
    places = []
    for k, cue in enumerate(cues):
        at, cut = spec[cue['text']]['at'], spec[cue['text']]['cut']
        if cue.get('shown') is not None:
            e, amount = cue['shown'], None
        else:
            e, amount = shown(cue, cues[k + 1]['t'] if k + 1 < len(cues) else c['end'])
            if e is None:
                problems.append(f'{sid}: {cue["text"]!r}: no change in its region within {cue["max"]} s')
                e = cue['est']
        report.append({'step': sid, 'cue': cue['text'], 'action': round(cue['t'], 3), 'shown': round(e, 3),
                       'spoken': None, 'change': None if amount is None else round(float(amount), 4), 'at': at - cut})
        places.append((cut, e + SPOKEN_AFTER - (at - cut), report[-1]))
    cut0, start0, _ = places[0]
    pieces.append({'sid': sid, 'start': start0 - cut0, 'a': 0.0, 'b': cut0, 'cue': None})
    for k, (cut, start, r) in enumerate(places):
        pieces.append({'sid': sid, 'start': start, 'a': cut, 'b': places[k + 1][0] if k + 1 < len(places) else dur, 'cue': r})
    c['start'] = start0 if cut0 < 0.1 else min(c['start'], start0 - cut0)   # a narration that begins with its effect brings its caption

for prev, cur in zip(pieces, pieces[1:]):
    if prev['start'] + prev['b'] - prev['a'] > cur['start'] + 0.005:
        prev['b'] = speech_end(prev['sid'], prev['a'], prev['b'])
        cur['start'] = max(cur['start'], prev['start'] + prev['b'] - prev['a'] + MIN_PAUSE)
for p in pieces:
    if p['cue']:
        r = p['cue']
        r['spoken'] = round(p['start'] + r.pop('at'), 3)
        if r['spoken'] - r['shown'] > SPOKEN_AFTER + LATE:
            problems.append(f"{r['step']}: {r['cue']!r} spoken {r['spoken'] - r['shown']:.2f} s after it showed")

# Captions change when their step's narration (or its screen) begins.
for i in range(1, len(caps)):
    caps[i]['start'] = max(caps[i]['start'], caps[i - 1]['start'] + (0 if caps[i - 1]['id'] in durations else CAPTION_ONLY))
    caps[i - 1]['end'] = caps[i]['start']
problems += [f"{p['sid']}: starts before the video, at {p['start']:.2f} s" for p in pieces if p['start'] < 0]
json.dump(report, open(os.path.join(d, 'cues.json'), 'w'), indent=1)
for r in report:
    print(f"{r['spoken']:7.2f}s  {r['step']:12s} {r['cue']!r}  (action {r['action']:.2f}, shown {r['shown']:.2f})")
if problems:
    sys.exit('compose-video: ' + '\n  '.join(problems))

page = f'''<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="file://{fonts}">
<style>body{{margin:0;background:#fff}}
.cap{{box-sizing:border-box;width:1440px;height:80px;display:flex;align-items:center;gap:22px;padding:0 28px;
background:#fff;border-top:2px solid #000;font:19px/1.35 "Iosevka Etoile",serif;color:#000;font-feature-settings:"calt" 1}}
.n{{flex:none;font:700 13px "JetBrains Mono",monospace;color:#fff;background:#1b3a8c;padding:4px 8px;letter-spacing:.04em}}</style>
''' + ''.join(f'<div class="cap" id="c{i}"><span class="n">{i + 1:02d}/{len(caps):02d}</span><span>{html.escape(c["text"])}</span></div>\n'
              for i, c in enumerate(caps))
open(os.path.join(d, 'captions.html'), 'w').write(page)

ab = lambda *a: subprocess.run(['agent-browser', '--session', 'captions', *a], check=True, capture_output=True)
ab('open', 'file://' + os.path.join(d, 'captions.html'))
ab('set', 'viewport', '1440', str(80 * len(caps) + 20))
for i in range(len(caps)):
    ab('screenshot', f'#c{i}', os.path.join(d, f'cap{i}.png'))
ab('close')

args = ['ffmpeg', '-v', 'error', '-y', '-i', raw]
for i in range(len(caps)):
    args += ['-i', os.path.join(d, f'cap{i}.png')]
graph = [f'[0:v]fps={FPS},pad=1440:980:0:0:white[v0]']
graph += [f"[v{i}][{i + 1}:v]overlay=0:900:enable='between(t,{c['start']:.2f},{c['end']:.2f})'[v{i + 1}]" for i, c in enumerate(caps)]
maps = ['-map', f'[v{len(caps)}]']
if pieces:
    base = 1 + len(caps)
    for k, p in enumerate(pieces):
        args += ['-i', os.path.join(narration, f"{p['sid']}.mp3")]
        ms = int(round(p['start'] * 1000))
        graph.append(f"[{base + k}:a]atrim=start={p['a']:.3f}:end={p['b']:.3f},asetpts=PTS-STARTPTS,adelay={ms}|{ms}[a{k}]")
    graph.append(''.join(f'[a{k}]' for k in range(len(pieces))) + f'amix=inputs={len(pieces)}:normalize=0[aout]')
    maps += ['-map', '[aout]', '-c:a', 'aac', '-b:a', '160k']
args += ['-filter_complex', ';'.join(graph), *maps, '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
         '-crf', '20', '-preset', 'slow', '-movflags', '+faststart', os.path.join(d, name)]
subprocess.run(args, check=True)
print(os.path.join(d, name))
