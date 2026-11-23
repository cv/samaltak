# Remote control and its token; the remote display

The control service (`ControlServer`, System-Remote) lets a client evaluate any Smalltalk in the image, which holds the
agent's API key and a GitHub token in memory (docs/agent.md, docs/github.md). So it runs only requests that carry its
token: a per-session secret, 128 random bits. `tools/samaltak-ctl` (tools/README.md) is its client; the protocol is JSON
lines over TCP, every request with `"auth": "<token>"`.

## The service

- **Who may connect.** `--control-host` names the address it listens on, `127.0.0.1` by default; `0.0.0.0` (every
  address) is for a VM with no loopback reached through a forwarded port (UEFI in QEMU: `make uefi-control`) and for a
  bare-metal machine. Every address still needs the token.
- **The check.** A request without `auth`, or with another token, is answered
  `{"id": …, "ok": false, "code": 4, "error": "unauthorized: …"}` and runs nothing; the connection stays open.
  `ControlServer>>authorizes:` compares in constant time (the same work whatever was sent, so the timing tells nothing
  about how much of it was right); blanks and dashes do not count, so a token typed in groups is the same token.
  `ControlConnection` takes `auth` out of the request before a command sees it: no handler, printString or log has it.
- **Where the token comes from**, in this order: `--control-token-file path` (the file's contents; `samaltak-ctl open`
  writes one, mode 0600: ps shows its name, never the token), `$SAMALTAK_CONTROL_TOKEN`, `--control-token token` (for
  `samaltak.args` on UEFI, where nothing shows a command line; on a host the VM warns that ps shows it to everyone).
  One shorter than 16 characters is refused: the service does not listen (`control: the token has fewer than 16
  characters: not listening`).
- **Without one** the image makes one (`SecureRandom`) and shows it once, in groups of four: on the console,
  `control: token 1a2b-3c4d-… (made at start, shown once: …)` (on UEFI also on the firmware's screen when the console is a
  serial port), and when the World opens as a toast for five minutes. That is how an operator at a bare-metal machine
  learns it. A token the service was given is never printed.
- **One token a session** (`SessionToken`, System-Remote): the control service and the remote display take the same
  token, read or made once (`SessionToken current`) and shown once, so either works without the other; an image resumed
  from a snapshot reads or makes it again.
- **The display password**, for VNC authentication (RFB security type 2: at most 8 characters, DES, weak: whoever sees
  one exchange can find it offline), is a separate secret, **never derived from the token**: `--display-password-file
  path` (its first line), else 8 characters made with `SecureRandom` (`SessionToken displayPassword`) and shown once
  beside the token, `display: password …` on the console and a toast. ctlSession and crashLog redact it like the token.

## samaltak-ctl

- `open` makes the token (Node's `crypto.randomBytes`) and keeps it in the session file
  `$TMPDIR/samaltak-ctl/<session>.json`, mode 0600, written whole through a temporary file. Hosted, it reaches the VM in
  `<session>.token` (0600) named by `--control-token-file`; the file stays while the session does (Rebuild & reboot execs
  a VM with the same arguments, which reads it again) and `close` removes it. `open --uefi` gives it to
  `make uefi-control` in the environment (`UEFI_CONTROL_TOKEN`), which writes it into `samaltak.args` on the ESP
  (0600): no command line has it.
- `connect [--host h] --port n --token-file f` makes a session for an image something else started (`f`: `-` reads
  stdin): it pings with the token and writes the session file only if the image accepts it (else exit 1 with the
  image's `unauthorized`). The host defaults to `127.0.0.1`, the end of an SSH tunnel. Screenshots of a connected
  session come back in the response, as on UEFI. `close` forgets a connected session; `close --quit` quits the image
  first.
- Every command sends the session's token. The samaltak.* pi functions redact it (ctlSession, crashLog), as they redact
  API keys and GitHub tokens.

## A bare-metal machine (the DGX Spark)

The VM on the Spark (docs/uefi.md, Real hardware) runs no operating system: no sshd, no TLS on the control channel. To
drive it from another machine:

1. **The stick.** `make usb-image USB_CONTROL=1` adds `--control --control-host 0.0.0.0 --control-port 7341` to
   `samaltak.args` (with `USB_ARGS` as before, e.g. `--headless` for no World). Either let the image make the token at
   each boot (the default), or fix one: `openssl rand -hex 16 > ~/.samaltak-spark-token; chmod 600 ~/.samaltak-spark-token`,
   then `make usb-image USB_CONTROL=1 USB_CONTROL_TOKEN_FILE=~/.samaltak-spark-token` writes it into `samaltak.args` (never
   on a command line; the summary line shows `<token>`; `usb.img` is made 0600). Anyone who can read the stick can read
   that token.
2. **Boot.** The console shows `control: listening on 0.0.0.0:7341` and, for a token it made, `control: token …`; the
   World shows that token in a toast. Its address: the DHCP lease (FirmwareDiagnostics' `dhcp` line with
   `USB_DIAG=1`, or the router's lease table).
3. **Connect.** Put the token in a file only you can read (`umask 077; cat > ~/.spark-token`, paste, Ctrl-D; the dashes
   may stay), then `tools/samaltak-ctl --session spark connect --host <spark-address> --port 7341 --token-file
   ~/.spark-token`, and drive it: `tools/samaltak-ctl --session spark eval 'Smalltalk vmBanner'`, `screenshot`,
   `agent-config --from-pi`, … `close` forgets the session; `close --quit` ends the VM.
4. **The network.** The token keeps out whoever merely reaches the port, not someone who reads the traffic: requests,
   the token in each and the answers (an API key sent with `agent-config`) cross the network in clear. Keep the Spark on a
   network you trust (a direct cable, or an isolated VLAN), and reach it from elsewhere through an SSH tunnel to a machine
   beside it: `ssh -N -L 7341:<spark-address>:7341 <jump-host>`, then `connect --port 7341` (host 127.0.0.1); only the hop
   from the jump host to the Spark is then in clear. TLS for the control channel is not done.

## Remote display (VNC)

The image can serve its own screen and take input over RFB, the VNC protocol (`RfbServer`, System-Remote): the way to see
the World on a bare-metal machine from another one, and under QEMU an alternative to QEMU's own VNC server. It is
started by `--display`, listens on `--display-host` (`127.0.0.1` by default, like the control service) and
`--display-port` (5900); `--display-vnc-auth` offers VNC authentication with the password from
`--display-password-file`, else one it makes and shows once (`display: password …`, on the console and, on UEFI, on the
screen). That password is 8 random characters of its own, never derived from the control token.

**Starting it.**

- UEFI in QEMU: `make uefi-ui UEFI_DISPLAY=1 UEFI_GPU=virtio-gpu-pci UEFI_SCREEN=1920x1080` (or `uefi-control`)
  boots with `--display --display-host 0.0.0.0 --display-vnc-auth` and the password file `UEFI_DISPLAY_PASSWORD_FILE`
  (by default `~/.samaltak-vnc` where present) copied to the ESP (0600), and QEMU without a display (`-display none`)
  forwarding the host's `127.0.0.1:5900+N` to the guest's port 5900. `UEFI_VNC=N` still means QEMU's own VNC server
  (the fallback, its password `UEFI_VNC_PASSWORD`, also `~/.samaltak-vnc`); `UEFI_DISPLAY` wins when both are given.
  The same file for both means a viewer's saved password works with either server.
- `samaltak-ctl open --uefi --vnc N` does that: the image's server is the default (`--vnc-server image`, or
  `$SAMALTAK_VNC_SERVER`), `--vnc-server qemu` QEMU's. The password: `--vnc-password-file f`, else `$UEFI_VNC_PASSWORD`,
  else `~/.samaltak-vnc` where present, else one made for the session in `<session>.vnc-password` (0600); it prints
  the file's name, never the password. `samaltak.vncWorld({ action: "restart" })` opens the operator's World on the
  image's server (`server: "qemu"` for QEMU's).
- A bare-metal machine: `make usb-image USB_DISPLAY=1 USB_DISPLAY_PASSWORD_FILE=f` listens on every address, port
  5900, with VNC authentication (never without: without `f` the image makes a password at each boot and shows it on the
  screen). Anyone who can read the stick can read `f`'s copy on its ESP.

**Connecting**, through an SSH tunnel to the machine running QEMU (or to a jump host beside a bare-metal one):

- macOS Screen Sharing: `ssh -N -L 5901:127.0.0.1:5901 <host>` (bare metal: `ssh -N -L 5901:<spark>:5900
  <jump-host>`), then `open vnc://localhost:5901` and the password. Use a local port other than 5900, which a Mac with
  Screen Sharing turned on keeps for itself. Screen Sharing speaks RFB 3.3 and VNC authentication only, in 32-bit BGRX,
  the server's own format.
- TigerVNC: the same tunnel, then `vncviewer localhost::5901` (two colons: a port). It picks VNC authentication; it
  could also use VeNCrypt Plain with the control token as the password (user: anything).
- Keys arrive as X keysyms and become the image's key codes and modifiers (`RfbInput`): Command is cmd whichever way a
  viewer sends it (Screen Sharing: Meta_L; TigerVNC: Mode_switch), Option is alt, and the characters Option composes
  (é) are typed as text; Control and Shift as usual. The pointer is drawn by the viewer; middle button and wheel work.
- The clipboard goes both ways in Latin-1 (RFB's classic cut text): what a viewer sends becomes the image's clipboard,
  and what the image copies is sent to the viewers, characters beyond Latin-1 as `?`. Screen Sharing sends no clipboard
  to servers other than Apple's; TigerVNC does. Cut text goes only to authenticated viewers and is never logged.

**Security.** VNC authentication is weak: DES of a challenge with an 8-character password, so anyone who records one
exchange can search the password offline. And the session is not encrypted: the screen, every key typed (a password
typed or a key pasted into the World too) and the clipboard cross the network in clear. So, as for the control service:
keep the default `127.0.0.1` where an SSH tunnel can reach it (QEMU's forward is bound to the host's 127.0.0.1), and put
a bare-metal machine on a network you trust (a direct cable, an isolated VLAN), reached from elsewhere only through an
SSH tunnel to a machine beside it. Each failed authentication makes the next attempt wait longer (1 s, doubling).
Encryption (an RSA-AES security type or VeNCrypt over a TLS server side) is not done.

## Tests

`tests/remote/auth_test.sh` (test-tools, hosted; and in test-uefi on the VM on UEFI, `--session uefi-test`): a request
without the token, with a wrong one or one a character short is refused with code 4 and runs nothing; the session's
token works, also through `connect` with the token in groups; a wrong token makes no session; the session file is
0600; the token is in no process's command line (ps) and not in the session's log. Hosted also: an image started
without a token makes one, shows it, and `connect` with what it showed works (`close --quit` quits it); a token too
short is refused. `ControlServerTest` (Tests-Remote) checks the same in the image: rejection, constant-time
`authorizes:` on near misses, and that commands never see `auth`. test-uefi's own requests from the guest to itself
through the host (ping, a megabyte each way) carry `ControlServer current token`.

`tests/remote/rfb_test.sh` (test-tools, hosted; and in test-uefi, `--uefi`: `samaltak-ctl open --uefi --vnc n`) is the
remote display seen by RFB clients (`tests/remote/rfb_client.py`): RFB 3.3 with VNC authentication and ZRLE, 3.8 with
VeNCrypt-Plain and Raw in another byte order, ZRLE with its CPIXELs in a pixel's high bytes and in 16-bit RGB565, and
two clients that negotiate as the viewers do (rfb_client.py's `SCREEN_SHARING_*`: RFB 3.3, VNC authentication, shared,
depth 32 BGRX, its encodings with Apple's unknown ones; `TIGERVNC_*`: 3.8, its encodings and pseudo-encodings), each sent
only rectangles in encodings it offered. Each decoded framebuffer equals the image's screenshot pixel for pixel at
first, after typing, after a window move, after keys sent through RFB and after an Agent window streamed text into a
paragraph laid out again with each delta (which also checks that what was sent is mostly the 16x16 blocks that changed
and at most a third of what was damaged); a client that asked for nothing catches up; a
wrong password is refused with backoff; a fifth client is refused. The client decodes CPIXELs by the viewers' rule (3
bytes when a 32-bit true-colour pixel's channels fit in three of its bytes, whatever its depth), so a server that
followed RFC 6143's depth rule would fail it.

## Measurements

The image's server against QEMU's VNC server on the same World (2026-11-23): the DGX Spark, QEMU/KVM, the UEFI World at
1920x1080 on virtio-gpu with 4 vCPUs pinned to the big cores (`open --uefi --window-size 1920x1080 --vnc n` with
`UEFI_GPU=virtio-gpu-pci`, as `samaltak.vncWorld` opens it; `--vnc-server qemu` for QEMU's), a fresh session for each
run; the machine shared (load 10-21). The viewer is `tests/remote/rfb_measure.py` (rfb_client.py over loopback: RFB 3.8,
VNC authentication, ZRLE, CopyRect, Cursor, DesktopSize, LastRect in the server's format, the next incremental request
as soon as an update has come, as the viewers do). Keys and the pointer are RFB events, so they take each server's own
input path (QEMU's: its USB keyboard and virtio tablet). Each interaction lasts 10 s. The numbers are medians of 5
runs (image) and 3 (QEMU). CPU is QEMU's process (user + system) in % of one core: the guest's vCPUs, so the image's
own server, and QEMU's VNC server. "Before" is the server that sent each damaged rectangle whole; "image" sends only the
16x16 blocks that changed (RfbDiffSource, below). The image's columns were measured again without the NIC's spin
(below), on 913de31 with it gone, interleaved with runs of 913de31 itself.

| interaction | before: B/s | image: B/s | updates/s | B an update (median) | CPU | QEMU: B/s | updates/s | B an update (median) | CPU |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| idle, the World as it opens | 107 K | 5.7 K | 2.3 | 2.1 K (424) | 7 % | 3.7 K | 4.9 | 763 (700) | 7 % |
| idle, Mandelbrot and Process Browser closed | 0 | 126 | 0.1 | 1.3 K | 2 % | 60 | 0.2 | 298 | 2 % |
| typing, 16 keys/s into the Workspace | 36 K | 34 K | 18.4 | 1.9 K (214) | 20 % | 48 K | 17.0 | 2.8 K (182) | 12 % |
| scrolling the class list, 10 notches/s | 56 K | 54 K | 12.8 | 4.2 K (4.4 K) | 18 % | 51 K | 11.9 | 4.3 K (4.7 K) | 10 % |
| dragging the Inspector, 60 moves/s | 452 K | 575 K | 43.3 | 13.3 K (13.1 K) | 43 % | 298 K | 22.0 | 13.4 K (14.9 K) | 18 % |
| the Agent window streaming, 40 deltas/s | 89 K | 14 K | 40.5 | 358 (309) | 19 % | 13.6 K | 24.2 | 555 (467) | 12 % |

| | image | QEMU |
| --- | --- | --- |
| a key to its pixels (one every 300 ms: KeyEvent sent → end of the first update that changes the Workspace) | 18 ms (12-24 over the runs, p90 15-27; with the spin: 30) | 82 ms (82-97) |
| full-screen update (a non-incremental request of the whole screen → its last byte) | 62 ms, 127 KB (with the spin: 64) | 97 ms (94-114), 125 KB |
| first connect (TCP connect → the first full update) | 0.34 s, 206 KB | 0.32 s, 200 KB |

**Only the blocks that changed.** The compositor's damage is in quads' bounds: text laid out again damages a whole
paragraph, of which few pixels change, and the Process Browser redraws its list every second with the same pixels.
RfbDiffSource (System-Remote), between the frame tap and the connections, keeps one copy of the screen for all viewers
(BGRA8 whatever their pixel formats, 8 MB at 1920x1080, made when the first viewer comes and dropped when the last goes).
When a connection's writer is about to send, it reads what was damaged since anyone last did (once for all viewers),
compares it with the copy in 16x16 blocks (`ByteArray>>indexOfMismatchAt:with:at:size:`, 16 bytes at a time, skipping
blocks of a 16-row band already known to differ), copies it in and gives every connection the blocks that differ, joined
into runs (each connection's RfbDamage merges them further where a rectangle's header costs more than the unchanged pixels
between). Pixels are sent from the copy, so a viewer always has the copy less the damage it has yet to take: right for
several viewers and for a slow one whose damage merges meanwhile. A move moves the copy too (CopyRect stays right), and a
new size makes the copy anew. That makes streaming 7 times and the idle World 22 times fewer bytes, at or near QEMU's,
and cuts the server's own time by about four streaming and idle (0.3 ms an update streaming, 1.6 idle, comparing
included; before: 1.4 and 5.9).

**Without the NIC's spin.** For 20 ms after any frame came or went, the NIC's driver (`PciNetworkInterface`, and
`UefiSnp` for the firmware's) looked for a frame without pause, as the firmware's timer ticks every 10 ms: every RFB
input event and update kept a vCPU busy. Now it looks without pause only for 1 ms after a frame went out, until one
comes (an ACK or the next request is due), and otherwise, for 100 ms, at every tick of the firmware's timer, set to
tick every millisecond meanwhile (`Firmware>>fineTicks:`; docs/uefi.md, Network); the vCPU halts in between. With the
spin (913de31) the guest took 13, 2, 69, 66, 95 and 73 % in the table's rows, with 17.6, 12.7, 39.0 and 33.5 updates/s
typing, scrolling, dragging and streaming, and a key took 30 ms (29-41) to its pixels. The finer timer also makes the
60 Hz refresh clock punctual: so the lower latency and the updates dragging and streaming gain. 1 ms ticks cost
about 2 points of a core while they last. TCP throughput is the same: 8 MB over HTTPS from the host in 65-170 ms
either way, 1 MB each way through the control service in about 110 ms.

**Where the image's CPU goes.**

- The server itself costs little. RfbConnection's statistics and RfbDiffSource's (`totalMs` and `diffMs`: finding what
  changed, making and sending updates) give 0.8 ms an update typing, 0.3 streaming, 2.0 scrolling and 4.2 dragging: 1-2 %
  of a core, 16 % dragging.
- The rest is the input and the drawing. With `--silent` (the client asks for no updates; the same input and
  drawing, nothing encoded) the guest takes 17 % typing, 15 % scrolling, 33 % dragging (at 59 frames/s) and 10 %
  streaming; with the spin it took 41, 29, 108 and 10, with QEMU's server 14, 10, 20 and 10. QEMU's input comes
  through its USB keyboard and tablet, with no network frames.
- The bytes are now QEMU's or fewer, but for dragging (more updates a second than QEMU's, each as large).

**Against the targets** (the remote display's scope, Performance targets):

- typing, ≤ 1 KB a frame: met. The median update is 216 B; the mean of 1.9 KB includes the top bar's readout and the
  line scrolling.
- typing, encode ≤ 0.5 ms a frame: 0.8 ms an update, making and sending. Close, but not met.
- typing latency, ≤ 1 frame + RTT + 10 ms: met. 18 ms on loopback (QEMU's: 82 ms).
- idle with a client, no CPU: met for a still World (no updates, 2 %, as with QEMU's). A World that redraws costs
  6 KB/s and 7 % (QEMU's server sends 3.7 KB/s).
- dragging, ≥ 15 updates/s of 20-60 KB: met. 43.3 updates/s of 13 KB (QEMU's: 22).
- full-screen update, ≤ 150 ms (≤ 50 ms with primitives): 62 ms for 127 KB.
- first connect, the whole screen within 0.5 s: 0.34 s.

**For phase 2**, by these numbers:

1. CopyRect for window drags (the compositor knows the move): fewer bytes than 500 KB/s, and less than 4.2 ms an update.
2. The ZRLE tile primitive (D12) is not needed for these targets: a full screen takes 62 ms.
