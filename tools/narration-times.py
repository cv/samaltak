#!/usr/bin/env python3
"""When the cue words of each narration clip are spoken (narrate.mjs runs it).
Usage: narration-times.py <narration-dir> <steps.json>   →  <narration-dir>/times.json: per step, each cue (a phrase of
its spoken text, steps.json "cues") with "at", where its first word starts in the clip, and "cut", a quiet point just
before it.

Each clip has a reference with the start time of every character of its text (<id>.ref.json, from ElevenLabs
/with-timestamps): the clip itself, or a take of the same request (<id>.ref.mp3). A reference take is mapped onto the clip
by dynamic time warping of log-mel spectra; a cue start is then snapped to the nearest speech onset within 80 ms. Checks,
printed per clip: the mapping keeps the order of the characters, mapped word durations are plausible (0.5 to 2 times the
reference's), every cue starts on voiced audio, every cue snapped."""
import json, os, subprocess, sys
import numpy as np

SR, HOP, WIN, NFFT, BANDS = 16000, 160, 400, 512, 40   # 10 ms hop, 25 ms window


def load(path):
    pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 's16le', '-ac', '1', '-ar', str(SR), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(pcm, dtype=np.int16).astype(np.float64) / 32768.0


def mel_filters():
    mel = lambda f: 2595 * np.log10(1 + f / 700)
    hz = lambda m: 700 * (10 ** (m / 2595) - 1)
    edges = hz(np.linspace(mel(60), mel(7600), BANDS + 2))
    bins = np.floor((NFFT + 1) * edges / SR).astype(int)
    fb = np.zeros((BANDS, NFFT // 2 + 1))
    for b in range(BANDS):
        lo, mid, hi = bins[b], bins[b + 1], bins[b + 2]
        fb[b, lo:mid] = (np.arange(lo, mid) - lo) / max(mid - lo, 1)
        fb[b, mid:hi] = (hi - np.arange(mid, hi)) / max(hi - mid, 1)
    return fb


FB = mel_filters()


def features(x):
    """log-mel spectra (frames × bands) and frame energy in dB, one frame per 10 ms."""
    n = 1 + max(0, len(x) - WIN) // HOP
    idx = np.arange(WIN)[None, :] + HOP * np.arange(n)[:, None]
    frames = x[idx] * np.hanning(WIN)
    power = np.abs(np.fft.rfft(frames, NFFT)) ** 2
    logmel = np.log(power @ FB.T + 1e-10)
    energy = 10 * np.log10(np.mean(frames ** 2, axis=1) + 1e-12)
    return logmel, energy


def dtw(a, b):
    """Path of a's frames onto b's (monotonic), banded around the diagonal: for each frame of a, the first frame of b."""
    a = (a - a.mean(0)) / (a.std(0) + 1e-6)
    b = (b - b.mean(0)) / (b.std(0) + 1e-6)
    n, m = len(a), len(b)
    band = max(60, abs(n - m) + 40)
    INF = np.inf
    D = np.full((n, m), INF)
    lo = np.zeros(n, dtype=int)
    hi = np.zeros(n, dtype=int)
    for i in range(n):
        c = int(round(i * (m - 1) / max(n - 1, 1)))
        lo[i], hi[i] = max(0, c - band), min(m, c + band + 1)
        cost = np.sqrt(((b[lo[i]:hi[i]] - a[i]) ** 2).sum(1))
        if i == 0:
            row = np.cumsum(cost) if lo[i] == 0 else np.full(hi[i] - lo[i], INF)
        else:
            up = D[i - 1, lo[i]:hi[i]]
            diag = np.concatenate(([D[i - 1, lo[i] - 1] if lo[i] > 0 else INF], D[i - 1, lo[i]:hi[i] - 1]))
            row = cost + np.minimum(up, diag)
            for k in range(1, len(row)):          # horizontal steps: along b
                row[k] = min(row[k], cost[k] + row[k - 1])
        D[i, lo[i]:hi[i]] = row
    i, j = n - 1, m - 1
    first = np.zeros(n, dtype=int)
    first[i] = j
    while i > 0 or j > 0:
        steps = []
        if i > 0 and j > 0: steps.append((D[i - 1, j - 1], i - 1, j - 1))
        if i > 0: steps.append((D[i - 1, j], i - 1, j))
        if j > 0: steps.append((D[i, j - 1], i, j - 1))
        _, i, j = min(steps)
        first[i] = j
    cost = D[n - 1, m - 1] / (n + m)
    return first, cost


def onsets(logmel):
    """Frames where a syllable sets in: peaks of spectral flux."""
    flux = np.maximum(np.diff(logmel, axis=0), 0).sum(1)
    flux = np.concatenate(([0.0], flux))
    level = flux.mean() + 0.5 * flux.std()
    return [t for t in range(1, len(flux) - 1)
            if flux[t] >= level and flux[t] == flux[max(0, t - 3):t + 4].max()]


def voiced_level(energy):
    return np.percentile(energy, 90) - 25


def align(text, ws, prior, logmel, energy):
    """Each word's start frame in the clip, all words at once (Viterbi): a start of speech after a pause (within 1 s of
    its prior, the mapped reference time, which can be a pause off around ellipses), a syllable onset (within 0.6 s) or
    the prior itself. Costs: distance from the prior, up to 0.15 s; no speech within 120 ms; after punctuation, not
    starting after a pause; between words in one stretch of speech, a step unlike the priors' (where they are in one
    stretch of speech too), else unlike 70 ms a letter. Answer the frames and the kind of each (start, onset, prior)."""
    voiced = voiced_level(energy)
    v = energy >= voiced
    speech = lambda f: v[f:f + 12].any()
    after_pause = [s for s in range(10, len(v) - 6) if v[s] and not v[s - 10:s].any() and v[s:s + 6].mean() >= 0.6]
    peaks = onsets(logmel)
    punct = [i > 0 and text[ws[i - 1][1] - 1] in ',.;:!?' for i in range(len(ws))]
    letters = [max(8.0, 7.0 * sum(ch.isalnum() for ch in text[a:b])) for a, b in ws]   # frames
    for i in range(len(ws) - 1):
        if 0 < prior[i + 1] - prior[i] and v[prior[i]:prior[i + 1]].all():
            letters[i] = prior[i + 1] - prior[i]
    cands = []
    for i, (a, b) in enumerate(ws):
        p = min(prior[i], len(energy) - 1)
        c = {(s, 'start') for s in after_pause if abs(s - p) <= 100}
        c |= {(s, 'onset') for s in peaks if abs(s - p) <= 60}
        c.add((p, 'prior'))
        cands.append(sorted(c))
    def cost(i, f, kind):
        x = min(abs(f - prior[i]) / 100.0, 0.15) + (0.1 if kind == "prior" else 0.0)
        if not speech(f):
            x += 2.0
        if punct[i]:
            x += -0.1 if kind == 'start' else 0.3
        return x
    def step(i, g, f):
        """From word i at g to the next at f: speech that starts after a pause between them starts with no word."""
        gap, want = f - g, letters[i]
        if gap < min(0.5 * want, 3.5 * sum(ch.isalnum() for ch in text[ws[i][0]:ws[i][1]])):
            return None
        if not v[g:f].all():   # a pause between them: any length
            return 0.5 * sum(1 for s in after_pause if g < s < f)
        return max(0.0, abs(gap - want) - 0.3 * want - 3) / 100.0
    best = [[(cost(0, f, k), None) for f, k in cands[0]]]
    for i in range(1, len(ws)):
        row = []
        for f, k in cands[i]:
            prev = [(best[i - 1][j][0] + s, j) for j, (g, _) in enumerate(cands[i - 1]) if (s := step(i - 1, g, f)) is not None]
            if not prev:   # nothing far enough back: the nearest earlier one
                prev = [(best[i - 1][j][0] + 1.0, j) for j, (g, _) in enumerate(cands[i - 1]) if f > g] or \
                       [(best[i - 1][j][0] + 5.0, j) for j in range(len(cands[i - 1]))]
            c, j = min(prev)
            row.append((c + cost(i, f, k), j))
        best.append(row)
    j = int(np.argmin([c for c, _ in best[-1]]))
    path = []
    for i in range(len(ws) - 1, -1, -1):
        path.append(cands[i][j])
        j = best[i][j][1]
    return path[::-1]


def words(text):
    """(start, end) character index of each word."""
    out, i = [], 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        j = i
        while j < len(text) and not text[j].isspace():
            j += 1
        out.append((i, j))
        i = j
    return out


def main():
    d, steps_file = sys.argv[1], sys.argv[2]
    steps = json.load(open(steps_file))
    times, problems = {}, []
    for step in steps:
        sid, text = step['id'], step['spoken']
        ref = json.load(open(os.path.join(d, f'{sid}.ref.json')))
        al = ref['alignment']
        if ''.join(al['characters']) != text:
            sys.exit(f'narration-times: {sid}: the reference timings are not of its text')
        starts, ends = np.array(al['character_start_times_seconds']), np.array(al['character_end_times_seconds'])
        take_mel, energy = features(load(os.path.join(d, f'{sid}.mp3')))
        if ref['audio']:
            ref_mel, _ = features(load(os.path.join(d, ref["audio"])))
            first, cost = dtw(ref_mel, take_mel)
            to_take = lambda t: first[min(int(round(t * 100)), len(first) - 1)] / 100.0
        else:
            cost, to_take = 0.0, (lambda t: float(t))
        mapped = np.array([to_take(t) for t in starts])
        notes = []
        if np.any(np.diff(mapped) < 0):
            notes.append('mapping out of order')
        for a, b in words(text):
            rd = ends[b - 1] - starts[a]
            td = to_take(ends[b - 1]) - mapped[a]
            if rd >= 0.1 and not (0.5 <= td / rd <= 2.0) or rd >= 0.06 and td < 0.02:
                notes.append(f'word {text[a:b]!r} {td:.2f} s (reference {rd:.2f} s)')
        voiced = voiced_level(energy)
        ws = words(text)
        word_at = align(text, ws, [int(round(mapped[a] * 100)) for a, b in ws], take_mel, energy)
        cues, k = [], 0
        for cue in step.get('cues', []):
            k = text.find(cue, k)
            if k < 0:
                sys.exit(f'narration-times: {sid}: cue {cue!r} is not in its text (in order)')
            f, kind = word_at[[a for a, b in ws].index(k)]
            t = f / 100.0
            if kind == 'prior':
                notes.append(f'cue {cue!r} not snapped')
            if abs(t - mapped[k]) > 0.08:
                notes.append(f'cue {cue!r} moved {1000 * (t - mapped[k]):+.0f} ms onto the {kind} of speech')
            if not (energy[f:f + 12] >= voiced).any():
                notes.append(f'cue {cue!r} at {t:.2f} s not on voiced audio')
            quiet = f - 6 + int(np.argmin(energy[max(0, f - 6):f + 1])) if f >= 6 else f
            cues.append({'text': cue, 'at': round(t, 3), 'cut': round(max(0, min(quiet / 100.0, t - 0.01)), 3)})
            k += len(cue)
        # where its speech ends (its trailing silence after)
        times[sid] = {'cues': cues, 'end': round((np.nonzero(energy >= voiced)[0][-1] + 1) / 100 + 0.05, 3)}
        line = f'{sid:14s} {"self" if not ref["audio"] else f"dtw {cost:.2f}"}  ' + \
               '  '.join(f'{c["text"]!r}@{c["at"]:.2f}' for c in cues)
        print(line + ('' if not notes else '\n    ' + '\n    '.join(notes)))
        if notes:
            problems.append(sid)
    json.dump(times, open(os.path.join(d, 'times.json'), 'w'), indent=1)
    if problems:
        print('narration-times: check', ', '.join(problems))


if __name__ == '__main__':
    main()
