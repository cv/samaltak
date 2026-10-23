#!/usr/bin/env python3
"""Adds a caption band and the narration (if <dir>/narration exists) to the walkthrough recording.
Usage: compose-video.py <dir>   (expects <dir>/raw.webm and <dir>/captions.json from walkthrough.mjs)"""
import html, json, os, subprocess, sys

d = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../../.context/video'))
fonts = os.path.abspath(os.path.join(os.path.dirname(__file__), '../shared/pi-orb-fonts.css'))
caps = json.load(open(os.path.join(d, 'captions.json')))

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

args = ['ffmpeg', '-v', 'error', '-y', '-i', os.path.join(d, 'raw.webm')]
for i in range(len(caps)):
    args += ['-i', os.path.join(d, f'cap{i}.png')]
graph = ['[0:v]fps=30,pad=1440:980:0:0:white[v0]']
graph += [f"[v{i}][{i + 1}:v]overlay=0:900:enable='between(t,{c['start']:.2f},{c['end']:.2f})'[v{i + 1}]" for i, c in enumerate(caps)]
maps = ['-map', f'[v{len(caps)}]']
clips = [(c, os.path.join(d, 'narration', f"{c.get('id')}.mp3")) for c in caps]
clips = [(c, f) for c, f in clips if os.path.exists(f)]
if clips:
    base = 1 + len(caps)
    for _, f in clips:
        args += ['-i', f]
    for k, (c, _) in enumerate(clips):
        ms = int(c['start'] * 1000)
        graph.append(f'[{base + k}:a]adelay={ms}|{ms}[a{k}]')
    graph.append(''.join(f'[a{k}]' for k in range(len(clips))) + f'amix=inputs={len(clips)}:normalize=0[aout]')
    maps += ['-map', '[aout]', '-c:a', 'aac', '-b:a', '160k']
args += ['-filter_complex', ';'.join(graph), *maps, '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
         '-crf', '20', '-preset', 'slow', '-movflags', '+faststart', os.path.join(d, 'walkthrough.mp4')]
subprocess.run(args, check=True)
print(os.path.join(d, 'walkthrough.mp4'))
