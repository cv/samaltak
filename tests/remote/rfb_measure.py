#!/usr/bin/env python3
"""Measures a VNC server as a viewer sees it (docs/remote.md, Measurements): the image's RFB server or QEMU's, on a
samaltak-ctl session's World, with tests/remote/rfb_client.py as the viewer (RFB 3.8, VNC authentication, ZRLE,
CopyRect, Cursor, DesktopSize, LastRect, the server's pixel format; the next incremental request as soon as an update
has come, as Screen Sharing and TigerVNC do).

  rfb_measure.py --session S --port N --password-file F [--qemu-pid P] [--seconds 10] [--phases ...] [--silent]
                 [--json out.json]

Per scripted interaction, for its seconds: bytes a second on the wire (the server's RFB bytes), updates a second,
bytes an update (mean and median), frames the World presented a second, the image's server's own time making and
sending updates (RfbConnection statistics' totalMs: ms an update, % of a core), and with --qemu-pid QEMU's CPU (user +
system, % of one core; it includes the guest's vCPUs, so the image's own server, and QEMU's VNC server). --silent asks
for no updates after the first: the same input and drawing with nothing encoded. The interactions: idle (the World as it opens), idle with the windows
that change by themselves closed (Mandelbrot, Process Browser; they stay closed), typing 16 keys a second into the
Workspace (RFB key events), scrolling the System Browser's class list (RFB wheel, 10 notches a second), dragging the
Inspector by its title bar (RFB pointer, 60 moves a second), the Agent window streaming text (a provider that sends
40 text deltas a second). Then latency: a key every 300 ms, from sending its KeyEvent to the end of the first update
that changes the Workspace's pixels (decoded); and full-screen updates (a non-incremental request of the whole screen:
its time to the last byte and its size). Keys and pointer go through RFB, so the same path as a viewer's.
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rfb_client import RfbClient  # noqa: E402

CTL = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'samaltak-ctl')
TICK = os.sysconf('SC_CLK_TCK')

# A provider whose turn streams deltas, pace ms apart (Tests-Agent's ScriptedProvider, made at run time), in an Agent
# window signed in to an account double (no key of anyone's).
PACED = ("(Smalltalk includesKey: #RfbPacedProvider) ifFalse: [ScriptedProvider subclass: #RfbPacedProvider "
         "instanceVariableNames: 'deltas pace' classVariableNames: '' package: 'Tests-Agent'. "
         "(Smalltalk at: #RfbPacedProvider) compile: 'deltas: d pace: ms deltas := d. pace := ms'. "
         "(Smalltalk at: #RfbPacedProvider) compile: 'send: i tools: t onText: tb onItem: ib deltas do: [:d | "
         "(Delay forMilliseconds: pace) wait. tb value: d]. ^Dictionary new at: ''input_tokens'' put: 1; at: "
         "''output_tokens'' put: 1; at: ''total_tokens'' put: 2; yourself']. "
         "AgentWindow account: (ApiKeyAccount new configure: (Dictionary new at: 'provider' put: 'host'; at: 'baseUrl' "
         "put: 'https://models.example'; at: 'model' put: 'scripted'; at: 'apiKey' put: 'kkk-measure-0000'; yourself); "
         "yourself). Smalltalk at: #RfbAgent put: (AgentWindow openOn: (AgentConversation new provider: ((Smalltalk at: "
         "#RfbPacedProvider) new deltas: ((1 to: 2000) collect: [:i | #('the ' 'quick ' 'brown ' 'fox ' 'jumps ' "
         "'over ' 'a ' 'lazy ' 'dog, ' 'and ' 'then ' 'it ' 'streams ' 'on. ') at: i - 1 \\\\ 14 + 1]) pace: 25; yourself); "
         "yourself) origin: nil in: (980 @ 60 extent: 720 @ 700)). AgentWindow account: nil. 1")
ASK = "(Smalltalk at: #RfbAgent) content conversation ask: 'Stream something.'. 1"
CLOSE_AGENT = "(Smalltalk at: #RfbAgent) content conversation stop. (Smalltalk at: #RfbAgent) close. 1"
CLOSE_MOVING = "(World current windows select: [:w | #('Mandelbrot' 'Process Browser') includes: w title]) do: [:w | w close]. 1"


def ctl(session, *args):
    r = subprocess.run([CTL, '--session', session] + list(args), capture_output=True, text=True, timeout=120)
    return r.stdout.strip()


def rect_of(text):
    """x, y, w, h of samaltak-ctl bounds' answer (JSON, in points: one a pixel on UEFI)."""
    b = json.loads(text)
    return [int(b[k]) for k in ('x', 'y', 'w', 'h')]


def cpu_ticks(pid):
    if not pid:
        return None
    with open('/proc/%d/stat' % pid) as f:
        fields = f.read().rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])


# frames presented, and the image's RFB server's time making and sending updates (all its connections; QEMU's: 0)
COUNTS = ("World current compositor presentedCount printString, ' ', (RfbServer current ifNil: [0] ifNotNil: [:s | "
          "s connections inject: 0 into: [:a :c | a + (c statistics at: 'totalMs')]]) printString")


def counts(session):
    out = ctl(session, 'eval', COUNTS).strip("'").split()
    return int(out[0]), int(out[1])


class Meter:
    def __init__(self, client, qemu_pid, session, silent=False):
        self.c, self.pid, self.session, self.silent = client, qemu_pid, session, silent
        self.updates = []          # (time the update ended, bytes since the previous one, rectangles)
        self.on_update = None

    def pump(self, until, actions=()):
        """Read updates (asking for the next one at once) and run actions [(time, fn)] when due, until the time."""
        actions = sorted(actions, key=lambda a: a[0])
        i = 0
        while True:
            now = time.time()
            while i < len(actions) and actions[i][0] <= now:
                actions[i][1]()
                i += 1
            if now >= until:
                return
            nxt = min(until, actions[i][0]) if i < len(actions) else until
            if self.c.wait_readable(max(0.0005, nxt - now)):
                before = self.c.bytes_read - len(self.c.buf)
                t = self.c.read_message()
                if t == 0:
                    if not self.silent:
                        self.c.request(True)
                    end = time.time()
                    nbytes = self.c.bytes_read - len(self.c.buf) - before
                    self.updates.append((end, nbytes, len(self.c.last_rects)))
                    if self.on_update:
                        self.on_update(end)

    def phase(self, seconds, actions_at):
        """actions_at: [(offset s, fn)]; the counts of the phase."""
        frames0, cost0 = counts(self.session)
        self.pump(time.time() + 0.3)   # the REMOTE tag's flash for that command starts here
        start, ticks0 = time.time(), cpu_ticks(self.pid)
        first = len(self.updates)
        self.pump(start + seconds, [(start + o, fn) for o, fn in actions_at])
        ticks1 = cpu_ticks(self.pid)
        frames1, cost1 = counts(self.session)
        frames, cost = frames1 - frames0, cost1 - cost0
        ups = self.updates[first:]
        total = sum(u[1] for u in ups)
        out = {'seconds': seconds, 'bytesPerSecond': round(total / seconds), 'updatesPerSecond': round(len(ups) / seconds, 1),
               'bytesPerUpdate': round(total / len(ups)) if ups else 0,
               'medianBytesPerUpdate': round(statistics.median(u[1] for u in ups)) if ups else 0,
               'framesPerSecond': round(frames / (seconds + 0.3), 1)}
        if cost and ups:
            out['serverMsPerUpdate'] = round(cost / len(ups), 1)
            out['serverCpuPercent'] = round(100.0 * cost / 1000 / seconds)
        if ticks0 is not None:
            out['qemuCpuPercent'] = round(100.0 * (ticks1 - ticks0) / TICK / seconds)
        return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--session', required=True)
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--password-file', required=True)
    ap.add_argument('--qemu-pid', type=int)
    ap.add_argument('--seconds', type=float, default=10)
    ap.add_argument('--json')
    ap.add_argument('--silent', action='store_true',
                    help='ask for no updates after the first (the server encodes nothing): the cost of input and drawing alone')
    ap.add_argument('--phases', default='idle,typing,scrolling,dragging,agent,latency,full',
                    help='which, comma-separated')
    a = ap.parse_args()
    s, secs = a.session, a.seconds
    want = set(a.phases.split(','))
    password = open(a.password_file).readline().strip()
    results = {}

    ctl(s, 'eval', 'SourceFiler default enabled: false. 1')
    c = RfbClient('127.0.0.1', a.port)
    t0 = time.time()
    c.handshake('3.8', 'vnc', password)
    c.set_encodings(['zrle', 'copyrect', 'cursor', 'desktopsize', 'lastrect'])
    c.update(incremental=False, timeout=30)
    results['firstConnect'] = {'ms': round((time.time() - t0) * 1000), 'bytes': c.bytes_read}
    m = Meter(c, a.qemu_pid, s, a.silent)
    if a.silent:
        want -= {'latency', 'full'}
    c.decode = False
    if not a.silent:
        c.request(True)
    m.pump(time.time() + 2)

    if 'idle' in want:
        results['idle'] = m.phase(secs, [])
        ctl(s, 'eval', CLOSE_MOVING)
        m.pump(time.time() + 2)
        results['idleQuiet'] = m.phase(secs, [])

    if 'typing' in want:
        # typing 16 keys a second into the Workspace
        ctl(s, 'click', '@w1.text')
        ctl(s, 'select', '@w1.text', 'end')
        m.pump(time.time() + 1)
        text = 'the quick brown fox jumps over the lazy dog '
        keys = []
        for i in range(int(secs * 16)):
            ch = 0xff0d if i % 48 == 47 else ord(text[i % len(text)])
            keys.append((i / 16.0, lambda ch=ch: c.tap(ch)))
        results['typing'] = m.phase(secs, keys)
        m.pump(time.time() + 1)

    if 'scrolling' in want:
        # scrolling the System Browser's class list: 10 wheel notches a second, down then up
        x, y, w, h = rect_of(ctl(s, 'bounds', '@w6.classes'))
        px, py = x + w // 2, y + h // 2
        c.pointer(0, px, py)
        m.pump(time.time() + 0.5)
        wheel = []
        for i in range(int(secs * 10)):
            b = 16 if (i // 10) % 2 == 0 else 8
            wheel.append((i / 10.0, lambda b=b: (c.pointer(b, px, py), c.pointer(0, px, py))))
        results['scrolling'] = m.phase(secs, wheel)
        m.pump(time.time() + 1)

    if 'dragging' in want:
        # dragging the Inspector by its title bar, 60 moves a second, 240 px left and right
        x, y, w, h = rect_of(ctl(s, 'bounds', '@w5'))
        gx, gy = x + w // 2, y + 8
        c.pointer(0, gx, gy)
        m.pump(time.time() + 0.2)
        c.pointer(1, gx, gy)
        moves = []
        n = int(secs * 60)
        for i in range(n):
            phase = (i % 120) / 120.0
            dx = int(240 * (phase * 2 if phase < 0.5 else 2 - phase * 2))
            moves.append((i / 60.0, lambda dx=dx: c.pointer(1, gx - dx, gy)))
        results['dragging'] = m.phase(secs, moves)
        c.pointer(0, gx, gy)
        m.pump(time.time() + 1)

    if 'agent' in want:
        # the Agent window streaming text
        ctl(s, 'eval', PACED)
        m.pump(time.time() + 2)
        ctl(s, 'eval', ASK)
        m.pump(time.time() + 1)
        results['agentStreaming'] = m.phase(secs, [])
        ctl(s, 'eval', CLOSE_AGENT)
        m.pump(time.time() + 2)

    if 'latency' in want:
        # latency: a key every 300 ms, to the end of the first update that changes the Workspace's pixels
        ctl(s, 'click', '@w1.text')
        ctl(s, 'select', '@w1.text', 'end')
        ex, ey, ew, eh = rect_of(ctl(s, 'bounds', '@w1.text'))
        c.decode = True
        c.update(incremental=False, timeout=30)
        c.request(True)
        m.pump(time.time() + 1)

        def region():
            W = c.width * 4
            return b''.join(bytes(c.fb[(ey + r) * W + ex * 4:(ey + r) * W + (ex + ew) * 4]) for r in range(eh))

        pending = []
        latencies = []

        def on_update(end):
            if pending and region() != pending[0][1]:
                latencies.append((end - pending[0][0]) * 1000)
                pending.clear()

        m.on_update = on_update

        def key(ch):
            pending.clear()
            pending.append((time.time(), region()))
            c.tap(ch)

        lat_keys = [(i * 0.3, lambda ch=ord('lmnopqrstu'[i % 10]): key(ch)) for i in range(30)]
        m.phase(9.3, lat_keys)
        m.on_update = None
        if latencies:
            latencies.sort()
            results['keyLatencyMs'] = {'keys': 30, 'seen': len(latencies), 'median': round(statistics.median(latencies), 1),
                                       'p90': round(latencies[int(len(latencies) * 0.9) - 1], 1),
                                       'min': round(latencies[0], 1), 'max': round(latencies[-1], 1)}

    if 'full' in want:
        # full-screen updates
        c.decode = False
        m.pump(time.time() + 1)
        fulls = []
        for _ in range(5):
            m.pump(time.time() + 0.5)
            while c.wait_readable(0.2):
                if c.read_message() == 0:
                    c.request(True)
            before = c.bytes_read - len(c.buf)
            t = time.time()
            c.request(False)
            # an incremental request may be answered first: until an update that covers the screen
            while True:
                if c.read_message(10) == 0:
                    if sum(r[2] * r[3] for e, r in c.last_rects if e >= 0) >= c.width * c.height * 0.9:
                        break
                    c.request(True)
            fulls.append(((time.time() - t) * 1000, c.bytes_read - len(c.buf) - before))
            c.request(True)
        results['fullScreen'] = {'medianMs': round(statistics.median(f[0] for f in fulls)),
                                 'medianBytes': round(statistics.median(f[1] for f in fulls)),
                                 'all': [[round(ms), b] for ms, b in fulls]}

    c.close()
    print(json.dumps(results, indent=1))
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(results, f, indent=1)


if __name__ == '__main__':
    main()
