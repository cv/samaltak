#!/bin/sh
# The image's remote display (RfbServer, docs/remote.md: the frame tap's screen, hosted and on UEFI) seen by RFB clients (tests/remote/rfb_client.py): RFB 3.3 with
# VNC authentication and ZRLE (as macOS Screen Sharing), RFB 3.8 with VeNCrypt-Plain and Raw in another pixel format,
# None never offered; the decoded framebuffer equals the image's own screenshot pixel for pixel at first, after typing,
# after a window move, after keys sent through RFB, and for a client that asked for nothing for a while; a wrong
# password is refused and makes the next attempt wait; a fifth client is refused. Below the top bar: its readout of
# the compositor's frame times is redrawn twice a second whenever frames were presented (so, for ever) and its REMOTE
# tag flashes with each samaltak-ctl command, so no screenshot is of the same instant as a frame sent.
# usage: tests/remote/rfb_test.sh [--uefi] [image]   (hosted: default build/samaltak.image; --uefi: the VM in QEMU,
#        samaltak-ctl open --uefi --vnc n --vnc-server image: the image's server forwarded from 127.0.0.1:5900+n)
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
  $CTL open --uefi --window-size 1024x768 --vnc "$n" --vnc-server image >"$WORK/open.log" 2>&1 || { echo "FAIL open --uefi"; cat "$WORK/open.log"; exit 1; }
  PORT=$((5900 + n))
  cp "$DIR/$SAMALTAK_SESSION.vnc-password" "$WORK/password"
else
  printf 'rfb%04d\n' $(($$ % 10000)) > "$WORK/password"
  $CTL open --hidden --image "$IMAGE" --window-size 640x400 --display-port 0 --display-password-file "$WORK/password" >"$WORK/open.log" 2>&1 \
    || { echo "FAIL open"; cat "$WORK/open.log"; exit 1; }
  PORT=$(cat "$DIR/$SAMALTAK_SESSION.display-port")
fi
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$DIR/$SAMALTAK_SESSION.json" > "$WORK/token"
$CTL eval 'SourceFiler default enabled: false. 1' >/dev/null
i=0; until $CTL wait '@w1' 10000 >/dev/null 2>&1 || [ $i -ge 300 ]; do i=$((i + 1)); sleep 0.2; done
# the Workspace and the System Browser over it: the Process Browser's columns and the Mandelbrot window change by themselves
$CTL eval '(World current windows reject: [:w | w title = '\''Workspace'\'' or: [w title beginsWith: '\''System Browser'\'']]) do: [:w | w close]. 1' >/dev/null
$CTL wait idle 5000 >/dev/null

python3 -u - "$PORT" "$WORK" "$CTL" <<'EOF'
import base64, os, subprocess, sys, time
sys.path.insert(0, 'tests/remote')
from rfb_client import RfbClient, RfbError, read_png

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


def connect(label, version, auth, secret, encodings, rgbx=False):
    c = RfbClient('127.0.0.1', port)
    c.label = label
    c.handshake(version, auth, secret)
    if rgbx:
        c.set_pixel_format_rgbx()
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
    source = ctl('eval', 'RfbServer current source class name').strip("#'")
    if source == 'RfbTapSource':
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

    ctl('type', '@w1.text', '\nTyped for RFB: the quick brown fox', '--end')
    in_sync('after typing', a, b)

    ctl('drag', '@w1', '37', '23')
    in_sync('after a window move', a, b)

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
    in_sync('after keys through RFB', a)

    # b asks for nothing while the screen changes, then gets it all at once
    ctl('type', '@w1.text', ' while b was away', '--end')
    ctl('drag', '@w1', '-20', '10')
    before = b.updates
    in_sync('a client that was away catches up', b)
    print('     in %d updates' % (b.updates - before))

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
