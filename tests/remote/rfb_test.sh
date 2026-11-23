#!/bin/sh
# The image's remote display (RfbServer, docs/remote.md: the frame tap's screen, hosted and on
# UEFI) seen by RFB clients (tests/remote/rfb_client.py): RFB 3.3 with
# VNC authentication and ZRLE, RFB 3.8 with VeNCrypt-Plain and Raw in another pixel format, ZRLE in two more (CPIXELs
# in the high bytes; 16-bit RGB565 big-endian), and two clients that do what the viewers do (rfb_client.py's
# SCREEN_SHARING_* and TIGERVNC_*: macOS Screen Sharing's RFB 3.3, VNC authentication, shared, depth 32 BGRX and its
# encodings with Apple's unknown ones; TigerVNC's 3.8, VNC authentication, its encodings and pseudo-encodings), each
# sent only rectangles in encodings it offered; None never offered; the decoded framebuffer equals the image's own
# screenshot pixel for pixel at first, after typing, after a window move, after keys sent through RFB, and for a client
# that asked for nothing for a while; a wrong
# password is refused and makes the next attempt wait; a fifth client is refused. Below the top bar: its readout of
# the compositor's frame times is redrawn twice a second whenever frames were presented (so, for ever) and its REMOTE
# tag flashes with each samaltak-ctl command, so no screenshot is of the same instant as a frame sent.
# usage: tests/remote/rfb_test.sh [--uefi] [image]   (hosted: default build/samaltak.image; --uefi: the VM in QEMU,
#        samaltak-ctl open --uefi --vnc n: the image's server forwarded from 127.0.0.1:5900+n)
set -u
cd "$(dirname "$0")/../.."
UEFI=
[ "${1:-}" = --uefi ] && { UEFI=1; shift; }
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=rfb-test-$$
DIR=${TMPDIR:-/tmp}/samaltak-ctl
WORK=$(mktemp -d)
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT

if [ -n "$UEFI" ]; then
  # a free n in 10-89 for 5900+n (not 5900-5909, which people's own sessions use)
  n=$(python3 -c 'import socket,random
for n in random.sample(range(10, 90), 80):
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 5900 + n)); print(n); break
    except OSError:
        pass
    finally:
        s.close()')
  printf 'rfb%04d\n' $(($$ % 10000)) > "$WORK/password"
  $CTL open --uefi --window-size 1024x768 --vnc "$n" --vnc-password-file "$WORK/password" >"$WORK/open.log" 2>&1 || { echo "FAIL open --uefi"; cat "$WORK/open.log"; exit 1; }
  PORT=$((5900 + n))
else
  printf 'rfb%04d\n' $(($$ % 10000)) > "$WORK/password"
  $CTL open --hidden --image "$IMAGE" --window-size 640x400 --display-port 0 --display-password-file "$WORK/password" >"$WORK/open.log" 2>&1 \
    || { echo "FAIL open"; cat "$WORK/open.log"; exit 1; }
  PORT=$(cat "$DIR/$SAMALTAK_SESSION.display-port")
fi
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$DIR/$SAMALTAK_SESSION.json" > "$WORK/token"
$CTL eval 'SourceFiler default enabled: false. 1' >/dev/null
# a caret that blinks (every 530 ms) would be in one state in the screenshot and in the other in a frame a second later
$CTL eval 'Theme current metric: #caretBlinkMs put: 100000000. 1' >/dev/null
i=0; until $CTL wait '@w1' 10000 >/dev/null 2>&1 || [ $i -ge 300 ]; do i=$((i + 1)); sleep 0.2; done
# the Workspace and the System Browser over it: the Process Browser's columns and the Mandelbrot window change by themselves
$CTL eval '(World current windows reject: [:w | w title = '\''Workspace'\'' or: [w title beginsWith: '\''System Browser'\'']]) do: [:w | w close]. 1' >/dev/null
$CTL wait idle 5000 >/dev/null

python3 -u - "$PORT" "$WORK" "$CTL" <<'EOF'
import base64, json, os, subprocess, sys, time
sys.path.insert(0, 'tests/remote')
from rfb_client import (RfbClient, RfbError, PixelFormat, read_png, SCREEN_SHARING_FORMAT, SCREEN_SHARING_ENCODINGS,
                        TIGERVNC_FORMAT, TIGERVNC_ENCODINGS, SCREEN_SHARING_COMMAND, SCREEN_SHARING_OPTION,
                        TIGERVNC_COMMAND, TIGERVNC_OPTION)

port, work, ctl_path = int(sys.argv[1]), sys.argv[2], sys.argv[3]
password = open(os.path.join(work, 'password')).readline().strip()
token = open(os.path.join(work, 'token')).readline().strip()
fails = 0


def ok(name):
    print('ok   ' + name)


def fail(name):
    global fails
    fails += 1
    print('FAIL ' + name)


def ctl(*args):
    r = subprocess.run([ctl_path] + list(args), capture_output=True, text=True, timeout=120)
    return r.stdout.strip()


def connect(label, version, auth, secret, encodings, rgbx=False, pf=None, shared=True):
    c = RfbClient('127.0.0.1', port)
    c.label = label
    c.handshake(version, auth, secret, shared=shared)
    if rgbx:
        c.set_pixel_format_rgbx()
    if pf:
        c.set_pixel_format(pf)
    c.set_encodings(encodings)
    if not c.update(incremental=False):
        raise RfbError('no first update')
    return c


def settle(c, seconds=1.0):
    """The updates of the next seconds (the top bar's readout changes twice a second: never quiet for long)."""
    end = time.time() + seconds
    while time.time() < end:
        c.update(incremental=True, timeout=max(0.01, end - time.time()))


# The image takes its screenshot itself, 400 ms after the command that asks for it: each command flashes the top bar's
# REMOTE tag for 220 ms, which samaltak-ctl screenshot would catch and the screen does not keep.
SHOOT = ("Smalltalk at: #RfbTestShot put: nil. [(Delay forMilliseconds: 400) wait. Smalltalk at: #RfbTestShot put: "
         "(World current compositor sync: [:k | k screenshotScale: World current displayScale])] fork. 1")
TOP = "World current topBar height * World current displayScale"
FETCH = "(Smalltalk at: #RfbTestShot ifAbsent: [nil]) ifNil: ['none'] ifNotNil: [:f | Base64 encode: (PNGWriter bytesForForm: f)]"


# an Agent window whose provider streams a delta every 25 ms (a ScriptedProvider made here, as rfb_measure.py's)
AGENT = ("(Smalltalk includesKey: #RfbPacedProvider) ifFalse: [ScriptedProvider subclass: #RfbPacedProvider "
         "instanceVariableNames: 'deltas pace' classVariableNames: '' package: 'Tests-Agent'. "
         "(Smalltalk at: #RfbPacedProvider) compile: 'deltas: d pace: ms deltas := d. pace := ms'. "
         "(Smalltalk at: #RfbPacedProvider) compile: 'send: i tools: t onText: tb onItem: ib deltas do: [:d | "
         "(Delay forMilliseconds: pace) wait. tb value: d]. ^Dictionary new at: ''input_tokens'' put: 1; at: "
         "''output_tokens'' put: 1; at: ''total_tokens'' put: 2; yourself']. "
         "AgentWindow account: (ApiKeyAccount new configure: (Dictionary new at: 'provider' put: 'host'; at: 'baseUrl' "
         "put: 'https://models.example'; at: 'model' put: 'scripted'; at: 'apiKey' put: 'kkk-rfbtest-0000'; yourself); "
         "yourself). Smalltalk at: #RfbAgent put: (AgentWindow openOn: (AgentConversation new provider: ((Smalltalk at: "
         "#RfbPacedProvider) new deltas: ((1 to: 400) collect: [:i | #('the ' 'quick ' 'brown ' 'fox ' 'jumps ' "
         "'over ' 'a ' 'lazy ' 'dog, ' 'and ' 'then ' 'it ' 'streams ' 'on. ') at: i - 1 \\\\ 14 + 1]) pace: 25; yourself); "
         "yourself) origin: nil in: (40 @ 70 extent: 560 @ 300)). AgentWindow account: nil. 1")
STATS = ("[:s | (s at: 'comparedArea') printString, ' ', (s at: 'changedArea') printString] value: "
         "RfbServer current source statistics")


def stats():
    return [int(x) for x in ctl('eval', STATS).strip("'").split()]


def changed_blocks(before, c):
    """Of the last update's pixel rectangles, the area of their parts in 16x16 blocks (of the screen) that changed."""
    W, area = c.width * 4, 0
    for e, (x, y, w, h) in c.last_rects:
        if e < 0 or e == 1:
            continue
        for by in range(y // 16 * 16, y + h, 16):
            for bx in range(x // 16 * 16, x + w, 16):
                x0, x1, y0, y1 = max(bx, x), min(bx + 16, x + w), max(by, y), min(by + 16, y + h)
                if any(before[r * W + x0 * 4:r * W + x1 * 4] != c.fb[r * W + x0 * 4:r * W + x1 * 4] for r in range(y0, y1)):
                    area += (x1 - x0) * (y1 - y0)
    return area


def in_sync(name, *clients, tries=12):
    """Each client's framebuffer, settled, equals the image's screenshot (the screen can change meanwhile: the top
    bar's readout, a blinking caret; then again)."""
    for c in clients:
        n, first = -1, 'no screenshot'
        for _ in range(tries):
            ctl('eval', SHOOT)
            time.sleep(0.6)
            settle(c)
            shot = ctl('eval', FETCH).strip("'")
            if shot == 'none':
                continue
            n, first = c.differences(*read_png(base64.b64decode(shot)), from_row=top_rows)
            if n == 0:
                break
        if n == 0:
            ok('%s (%s)' % (name, c.label))
        else:
            fail('%s (%s): %d pixels differ, first %s' % (name, c.label, n, first))


try:
    top_rows = int(float(ctl('eval', TOP)))
    source = ctl('eval', "RfbServer current source printString").strip("'")
    if source.startswith('an RfbDiffSource on RfbTapSource'):
        ok('the screen comes from the frame tap (%s windows open)' % ctl('eval', 'World current windows size'))
    else:
        fail('the screen comes from %s, not the frame tap' % source)
    print('     comparing below the top bar: from row %d' % top_rows)
    t0 = time.time()
    a = connect('RFB 3.3, ZRLE', '3.3', 'vnc', password, ['zrle', 'copyrect', 'cursor', 'desktopsize', 'lastrect'])
    first_ms, first_bytes = (time.time() - t0) * 1000, a.bytes_read
    ok('RFB 3.3, VNC authentication: %dx%d %r' % (a.width, a.height, a.name))
    if a.cursor and a.cursor[1][0] > 0:
        ok('the Cursor pseudo-encoding brings the pointer (%dx%d)' % a.cursor[1])
    else:
        fail('no cursor shape')
    b = connect('RFB 3.8, Raw RGBX', '3.8', 'vencrypt', token, ['raw'], rgbx=True)
    ok('RFB 3.8, VeNCrypt-Plain with the session token, Raw in RGBX')
    if b.offered == [19, 2]:
        ok('3.8 offers VeNCrypt and VNC authentication, not None')
    else:
        fail('3.8 offers %r' % b.offered)
    in_sync('first frame equals the screenshot', a, b)
    print('     a full ZRLE frame: %d bytes in %.0f ms (Raw: %d)' % (first_bytes, first_ms, a.width * a.height * 4))

    # ZRLE in other formats: CPIXELs in a pixel's high three bytes, and 16 bits a pixel (a CPIXEL is the whole pixel)
    for label, pf in [('ZRLE, 32/32 shifts 24/16/8', PixelFormat(32, 32, False, (255, 255, 255), (24, 16, 8))),
                      ('ZRLE, RGB565 big-endian', PixelFormat(16, 16, True, (31, 63, 31), (11, 5, 0)))]:
        x = connect(label, '3.8', 'vencrypt', token, ['zrle', 'lastrect'], pf=pf)
        in_sync('first frame equals the screenshot', x)
        x.close()

    # what the viewers send (the scope's probe of them): the server picks ZRLE from their lists and ignores the rest
    ss = connect('Screen Sharing', '3.3', 'vnc', password, SCREEN_SHARING_ENCODINGS, pf=SCREEN_SHARING_FORMAT)
    tv = connect('TigerVNC', '3.8', 'vnc', password, TIGERVNC_ENCODINGS, pf=TIGERVNC_FORMAT)
    viewers = [ss, tv]
    in_sync('first frame equals the screenshot', *viewers)

    ctl('type', '@w1.text', '\nTyped for RFB: the quick brown fox', '--end')
    in_sync('after typing', a, b, *viewers)

    ctl('drag', '@w1', '37', '23')
    in_sync('after a window move', a, b, *viewers)

    # a window dragged by its title bar through RFB, held, in steps: its pixels come as CopyRect (the compositor's
    # moves, through the frame tap), what it uncovers as pixels, and the screen is right for every viewer
    scale = float(ctl('eval', 'World current displayScale'))
    bx = json.loads(ctl('bounds', '@w1'))
    gx, gy = int((bx['x'] + bx['w'] / 2) * scale), int((bx['y'] + 8) * scale)
    a.pointer(0, gx, gy)
    a.pointer(1, gx, gy)
    settle(a, 0.3)
    for i in range(1, 13):
        a.pointer(1, gx - 6 * i, gy + 4 * i)
        settle(a, 0.06)
    a.pointer(0, gx - 72, gy + 48)
    settle(a, 0.5)
    if 1 in a.encodings_seen:
        ok('a window dragged through RFB comes as CopyRect')
    else:
        fail('a window dragged through RFB: no CopyRect (%r)' % sorted(a.encodings_seen))
    in_sync('after a window dragged through RFB', a, *viewers)

    # keys through RFB (RfbInput), into the Workspace: it has the keyboard focus after a click
    ctl('click', '@w1.text')
    ctl('select', '@w1.text', 'end')
    for ch in ' rfbkeys':
        a.tap(ord(ch))
    time.sleep(1)
    text = ctl('snapshot', '@w1.text')
    if 'rfbkeys' in text:
        ok('keys sent through RFB reach the Workspace')
    else:
        fail('keys sent through RFB: the Workspace has %r' % text[-200:])
    in_sync('after keys through RFB', a, *viewers)

    # each viewer's own modifier keys (RfbInput's key profiles, picked from SetEncodings): Screen Sharing (Apple's
    # encodings) sends Command as Alt_L and Option as Meta_L; TigerVNC Command as Mode_switch and Option as Alt_L. In the
    # Workspace Option-Backspace deletes a word, an Option-composed character is text, Command-A selects all and the next
    # key replaces it.
    profiles = ctl('eval', '(RfbServer current connections collect: [:c | c keyProfile]) asArray printString')
    if profiles.count('apple') == 1 and profiles.count('standard') == 3:
        ok('Screen Sharing gets the apple key profile, the others the standard one: %s' % profiles)
    else:
        fail('key profiles of a, b, Screen Sharing, TigerVNC: %s' % profiles)

    def chord(c, modifier, keysym):
        c.key(modifier, True)
        c.tap(keysym)
        c.key(modifier, False)

    def workspace():
        time.sleep(1)
        return ctl('snapshot', '@w1.text')

    BACKSPACE = 0xff08
    for ch in ' alpha beta':
        ss.tap(ord(ch))
    chord(ss, SCREEN_SHARING_OPTION, BACKSPACE)
    chord(ss, SCREEN_SHARING_OPTION, 0xe9)
    ss.tap(ord('x'))
    text = workspace()
    if 'alpha' in text and 'beta' not in text and ('\u00e9x' in text or '\\u00e9x' in text):
        ok('Screen Sharing: Option (Meta_L) is alt: Option-Backspace deletes a word, Option-e is text')
    else:
        fail('Screen Sharing, Option: the Workspace has %r' % text[-200:])
    chord(ss, SCREEN_SHARING_COMMAND, ord('a'))
    ss.tap(ord('q'))
    text = workspace()
    if 'alpha' not in text and 'rfbkeys' not in text and 'q' in text:
        ok('Screen Sharing: Command (Alt_L) is cmd: Command-A selects all')
    else:
        fail('Screen Sharing, Command-A: the Workspace has %r' % text[-200:])
    for ch in ' gamma delta':
        tv.tap(ord(ch))
    chord(tv, TIGERVNC_OPTION, BACKSPACE)
    text = workspace()
    if 'gamma' in text and 'delta' not in text:
        ok('TigerVNC: Option (Alt_L) is alt: Option-Backspace deletes a word')
    else:
        fail('TigerVNC, Option: the Workspace has %r' % text[-200:])
    chord(tv, TIGERVNC_COMMAND, ord('a'))
    tv.tap(ord('z'))
    text = workspace()
    if 'gamma' not in text and 'z' in text:
        ok('TigerVNC: Command (Mode_switch) is cmd: Command-A selects all')
    else:
        fail('TigerVNC, Command-A: the Workspace has %r' % text[-200:])
    for v in viewers:
        sent, offered = sorted(v.encodings_seen), set(v.encodings) | {0}
        if 16 in v.encodings_seen and set(sent) <= offered:
            ok('%s got only encodings it offered: %r' % (v.label, sent))
        else:
            fail('%s offered %r and got %r' % (v.label, v.encodings, sent))
        v.close()

    # b asks for nothing while the screen changes, then gets it all at once
    ctl('type', '@w1.text', ' while b was away', '--end')
    ctl('drag', '@w1', '-20', '10')
    before = b.updates
    in_sync('a client that was away catches up', b)
    print('     in %d updates' % (b.updates - before))

    # the Agent streaming into a paragraph that is laid out again with each delta (all of it damaged): only the 16x16
    # blocks that changed are sent (RfbDiffSource), and they make the screen
    ctl('eval', AGENT)
    settle(a, 2)
    compared0, changed0 = stats()
    ctl('eval', "(Smalltalk at: #RfbAgent) content conversation ask: 'Stream something.'. 1")
    sent, changed, updates = 0, 0, 0
    end = time.time() + 3
    while time.time() < end:
        fb = bytes(a.fb)
        if a.update(incremental=True, timeout=max(0.01, end - time.time())):
            updates += 1
            sent += sum(r[2] * r[3] for e, r in a.last_rects if e >= 0 and e != 1)
            changed += changed_blocks(fb, a)
    compared1, changed1 = stats()
    ctl('eval', "(Smalltalk at: #RfbAgent) content conversation stop. 1")
    print('     streaming: %d updates, %d pixels damaged, %d in changed blocks, %d sent, of which %d in blocks that changed'
          % (updates, compared1 - compared0, changed1 - changed0, sent, changed))
    if updates >= 10 and sent * 3 <= compared1 - compared0 and changed * 2 >= sent:
        ok('a streamed paragraph sends only the blocks that changed')
    else:
        fail('a streamed paragraph: %d updates, %d pixels damaged, %d sent, %d in blocks that changed'
             % (updates, compared1 - compared0, sent, changed))
    in_sync('after streaming', a)
    ctl('eval', "(Smalltalk at: #RfbAgent) close. 1")

    try:
        connect('wrong', '3.8', 'vnc', 'wrong!!', ['raw'])
        fail('a wrong password was accepted')
    except RfbError as e:
        if 'authentication failed' in str(e):
            ok('a wrong password is refused: ' + str(e))
        else:
            fail('wrong password: ' + str(e))
    t0 = time.time()
    c = connect('c', '3.3', 'vnc', password, ['zrle'])
    waited = time.time() - t0
    if waited >= 0.8:
        ok('the next attempt waited %.1f s' % waited)
    else:
        fail('no backoff after a failure: %.2f s' % waited)

    extra = [c, connect('d', '3.8', 'vencrypt', token, ['zrle'])]
    try:
        connect('e', '3.8', 'vencrypt', token, ['zrle'])
        fail('a fifth client was let in')
    except RfbError as e:
        if 'too many' in str(e):
            ok('a fifth client is refused: ' + str(e))
        else:
            fail('fifth client: ' + str(e))
    for x in extra + [a, b]:
        x.close()
except Exception as e:
    fail('%s: %s' % (type(e).__name__, e))
sys.exit(1 if fails else 0)
EOF
status=$?
[ $status -eq 0 ] || { echo "--- image log"; tail -30 "$DIR/$SAMALTAK_SESSION.log"; }
exit $status
