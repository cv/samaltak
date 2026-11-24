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

## Another machine (the DGX Spark)

The Spark runs the Linux appliance (docs/linux-appliance.md): its `samaltak.args`, on the data volume, start the
control service and the RFB server on every address, with a control token and a VNC password made for the stick
(0600; kept as `OUT/linux-appliance/usb-control-token` and `usb-vnc-password`). To drive it from another machine:

1. **Connect.** Put the token in a file only you can read (`umask 077; cat > ~/.spark-token`, paste, Ctrl-D; the dashes
   may stay), then `tools/samaltak-ctl --session spark connect --host <spark-address> --port 7341 --token-file
   ~/.spark-token`, and drive it: `tools/samaltak-ctl --session spark eval 'Smalltalk vmBanner'`, `screenshot`,
   `agent-config --from-pi`, … `close` forgets the session; `close --quit` ends the VM.
2. **The network.** The token keeps out whoever merely reaches the port, not someone who reads the traffic: requests,
   the token in each and the answers (an API key sent with `agent-config`) cross the network in clear. Keep the Spark on a
   network you trust (a direct cable, or an isolated VLAN), and reach it from elsewhere through an SSH tunnel to a machine
   beside it: `ssh -N -L 7341:<spark-address>:7341 <jump-host>`, then `connect --port 7341` (host 127.0.0.1); only the hop
   from the jump host to the Spark is then in clear. TLS for the control channel is not done.

## Remote display (VNC)

The image can serve its own screen and take input over RFB, the VNC protocol (`RfbServer`, System-Remote): the way to see
the World on a bare-metal machine from another one, and under QEMU an alternative to QEMU's own VNC server. It is
started by `--display`, listens on `--display-host` (`127.0.0.1` by default, like the control service) and
`--display-port` (5900); `--display-vnc-auth` offers VNC authentication with the password from
`--display-password-file`, else one it makes and shows once (`display: password …`, on the
console). That password is 8 random characters of its own, never derived from the control token.

**Starting it.**

- UEFI in QEMU: `make uefi-ui UEFI_DISPLAY=1 UEFI_GPU=virtio-gpu-pci UEFI_SCREEN=1920x1080` (or `uefi-control`)
  boots with `--display --display-host 0.0.0.0 --display-vnc-auth` and the password file `UEFI_DISPLAY_PASSWORD_FILE`
  (by default `~/.samaltak-vnc` where present) written into `samaltak.args` (`--display-password`, mode 0600, as the
  control token: the image has no files on UEFI), and QEMU without a display (`-display none`)
  forwarding the host's `127.0.0.1:5900+N` to the guest's port 5900. `UEFI_VNC=N` still means QEMU's own VNC server
  (the fallback, its password `UEFI_VNC_PASSWORD`, also `~/.samaltak-vnc`); `UEFI_DISPLAY` wins when both are given.
  The same file for both means a viewer's saved password works with either server.
- `samaltak-ctl open --uefi --vnc N` does that: the image's server is the default (`--vnc-server image`, or
  `$SAMALTAK_VNC_SERVER`), `--vnc-server qemu` QEMU's. The password: `--vnc-password-file f`, else `$UEFI_VNC_PASSWORD`,
  else `~/.samaltak-vnc` where present, else one made for the session in `<session>.vnc-password` (0600); it prints
  the file's name, never the password. `samaltak.vncWorld({ action: "restart" })` opens the operator's World on the
  image's server (`server: "qemu"` for QEMU's).
- The appliance (the Spark): the same flags with `--display-password-file /data/vnc-password` on its data volume
  (docs/linux-appliance.md).

**Connecting**, through an SSH tunnel to the machine running QEMU (or to a jump host beside a bare-metal one):

- macOS Screen Sharing: `ssh -N -L 5901:127.0.0.1:5901 <host>` (bare metal: `ssh -N -L 5901:<spark>:5900
  <jump-host>`), then `open vnc://localhost:5901` and the password. Use a local port other than 5900, which a Mac with
  Screen Sharing turned on keeps for itself. Screen Sharing speaks RFB 3.3 and VNC authentication only, in 32-bit BGRX,
  the server's own format.
- TigerVNC: the same tunnel, then `vncviewer localhost::5901` (two colons: a port). It picks VNC authentication; it
  could also use VeNCrypt Plain with the control token as the password (user: anything).
- Keys arrive as X keysyms and become the image's key codes and modifiers (`RfbInput`): Command is cmd and Option alt
  whichever keysyms a viewer sends for them, Control and Shift as usual. The viewers disagree on the keysyms, so each
  connection has a key profile, picked from what the viewer lists in SetEncodings: Apple's own encodings (1002, 1011,
  1100-1110, which only macOS Screen Sharing sends; it also speaks RFB 3.3) make it `apple`, anything else
  `standard`:

  | key | Screen Sharing sends | TigerVNC sends | `apple` (Screen Sharing) | `standard` (TigerVNC, the others) |
  | --- | --- | --- | --- | --- |
  | ⌘ Command | Alt_L / Alt_R | Mode_switch | Alt_L/R → cmd | Mode_switch, Meta_L/R, Super_L/R → cmd |
  | ⌥ Option | Meta_L / Meta_R | Alt_L / Alt_R | Meta_L/R → alt | Alt_L/R → alt |
  | Control, Shift | Control_L/R, Shift_L/R | the same | ctrl, shift | ctrl, shift |

  Mode_switch and Super are cmd in both. A modifier's key code follows what it means (cmd: the GUI keys, alt: the Alt
  keys). Text comes with alt held but not with cmd or ctrl, so a character Option composes is typed when the viewer
  sends its keysym (é, 0xe9) and Option-e is alt-e when it sends e. `--display-keys apple` or `standard` forces a
  profile on every viewer (`auto`, the default: each its own), as does `RfbServer current keyProfile: #apple` (nil:
  by the viewer) on the running server, connected viewers too; an RfbInput's `altIsCmd: true` or `false` overrides
  what Alt_L/R mean (nil: the profile's). The pointer is drawn by the viewer; middle button and wheel work.
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
only rectangles in encodings it offered; each gets its key profile, and its own Command and Option work in the
Workspace (Screen Sharing: Alt_L-A selects all, Meta_L-Backspace deletes a word, Meta_L-é is text; TigerVNC:
Mode_switch-A and Alt_L-Backspace). Each decoded framebuffer equals the image's screenshot pixel for pixel at
first, after typing, after a window move, after a window dragged through RFB (which comes as CopyRect), after keys sent
through RFB and after an Agent window streamed text into a
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
own server, and QEMU's VNC server. "Before" is the server that sent each damaged rectangle whole; "blocks" sends only
the 16x16 blocks that changed (RfbDiffSource, below), measured without the NIC's spin (below), on 913de31 with it gone,
interleaved with runs of 913de31 itself (the idle rows again on fd1a733, where an idle World presents almost nothing,
below); "image" also sends CopyRect for dragged windows and scrolled lists (below), on
ce6dbbd (the machine's load 1-11).

| interaction | before: B/s | blocks: B/s | CPU | image: B/s | updates/s | B an update (median) | CPU | QEMU: B/s | updates/s | B an update (median) | CPU |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| idle, the World as it opens | 107 K | 0.6 K | 4 % | 262 | 0.4 | 656 (658) | 4 % | 3.7 K | 4.9 | 763 (700) | 7 % |
| idle, Mandelbrot and Process Browser closed | 0 | 146 | 2 % | 137 | 0.1 | 1.4 K | 2 % | 60 | 0.2 | 298 | 2 % |
| typing, 16 keys/s into the Workspace | 36 K | 34 K | 20 % | 20 K | 18.5 | 1.1 K (214) | 25 % | 48 K | 17.0 | 2.8 K (182) | 12 % |
| scrolling the class list, 10 notches/s | 56 K | 54 K | 18 % | 15 K | 12.8 | 1.2 K (1.3 K) | 19 % | 51 K | 11.9 | 4.3 K (4.7 K) | 10 % |
| dragging the Inspector, 60 moves/s | 452 K | 575 K | 43 % | 16 K | 32.7 | 464 (192) | 23 % | 298 K | 22.0 | 13.4 K (14.9 K) | 18 % |
| the Agent window streaming, 40 deltas/s | 89 K | 14 K | 19 % | 14 K | 40.7 | 355 (307) | 18 % | 13.6 K | 24.2 | 555 (467) | 12 % |

| | image | QEMU |
| --- | --- | --- |
| a key to its pixels (one every 300 ms: KeyEvent sent → end of the first update that changes the Workspace) | 18 ms (10-22 over the runs, p90 12-27; with the spin: 30; with the primitives below 15, 9-23) | 82 ms (82-97) |
| full-screen update (a non-incremental request of the whole screen → its last byte) | 39 ms, 127 KB (before ZRLE's fixes below: 62; with the spin: 64; with the primitives below: 19) | 97 ms (94-114), 125 KB |
| first connect (TCP connect → the first full update) | 0.29 s, 204 KB | 0.32 s, 200 KB |

**Only the blocks that changed.** The compositor's damage is in quads' bounds: text laid out again damages a whole
paragraph, of which few pixels change, and the Process Browser redrew its list every second with the same pixels.
RfbDiffSource (System-Remote), between the frame tap and the connections, keeps one copy of the screen for all viewers
(BGRA8 whatever their pixel formats, 8 MB at 1920x1080, made when the first viewer comes and dropped when the last goes).
When a connection's writer is about to send, it reads what was damaged since anyone last did (once for all viewers),
compares it with the copy in 16x16 blocks (the `pixelBlocksDiff` primitive, below: 16 bytes at a time, skipping
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

**An idle World presents (almost) nothing.** The World as it opens presented about 5 frames a second with nothing
happening: the Process Browser drew its table again at its 4 Hz refreshes for readings that jitter and for rows out of
view, and its stack list for new contexts of the same methods; the sleeping compositor and the UEFI refresh clock
started and ended Processes (a timed wait's watchdog, the clock's own) that came and went in its list; and the top bar's
ms/fps readout changed with every frame it rode along with, including the frames an RFB viewer's reads of the frame tap
made (a request marked the World changed), each of which brought the next read. Now the browser reads the CPU once a
second and shows a new reading only when it moved by a visible step (a point, or a fifth of it), draws a row again only
when what it shows changed and is in view, and LoadMeters a meter only when it looks different; the readout refreshes
only with frames presented for something else, and once, 3 s after the last, for the settled numbers; a request is no
change, the compositor sleeps on a Delay and the refresh clock parks its Process. Medians of 5 runs of fd1a733 and of
the same tree without these changes (f604588 with the NIC's and the JIT's commits after it), the same method; hosted:
the World as it opens on a private Xvfb at 1920x1080 (lavapipe), the frames the compositor presented and the VM's CPU
over 10 s, 15 s after opening:

| the World as it opens, idle | before | after |
| --- | --- | --- |
| RFB: bytes/s | 3.7 K | 0.6 K |
| RFB: updates/s | 5.3 | 0.6 |
| the guest's CPU (QEMU's process) | 10 % | 4 % |
| hosted: frames presented/s | 5.4 | 0.3 |
| hosted: the VM's CPU | 9.2 % | 6.2 % |

What remains is what moves: the Process Browser's readings that change visibly (mostly the cpu meter and the RFB
server's own CPU), about once a second, with the top bar riding along. With Mandelbrot and the Process Browser closed,
one update in 10 s: the readout settling after they closed. Mandelbrot draws nothing once it is done, the Transcript
and the Workspace only when written to, toasts fade and go; the System Monitor's charts scroll at 10 Hz while it is
open (it is not in the World as it opens).

**The server's own time.** RfbConnection's and RfbDiffSource's statistics (`totalMs` and `diffMs`: finding what
changed, making and sending updates), in ms an update, medians of 5 runs (with the NIC's spin, before 913de31's
successors: it does not change them):

| interaction | sending whole rectangles | changed blocks | and ZRLE without copies | and CopyRect | and primitives |
| --- | --- | --- | --- | --- | --- |
| idle, the World as it opens | 5.9 | 1.6 | 1.7 | 1.8 | 1.4 |
| typing | 0.8 | 0.8 | 0.6 | 0.6 | 0.3 |
| scrolling | 2.7 | 2.0 | 1.2 | 0.9 | 0.3 |
| dragging | 6.2 | 4.2 | 2.6 | 0.6 | 0.2 |
| the Agent streaming | 1.4 | 0.3 | 0.3 | 0.1 | 0.1 |

(The last column is without the NIC's spin, the others with it: the spin costs the server's own time nothing.)

Most of it was ZRLE. ZLib's streaming deflate copied the whole history it keeps (up to 96 KB) into a new input for each
rectangle, and its Huffman code lengths searched the list of nodes for the lightest two (quadratic in the alphabet,
for each block of each rectangle); the tiles' palettes were Dictionaries, and the runs were found twice. Now deflate
appends to a buffer it keeps (the `zlibMatches` primitive takes the length used) and moves its window once a megabyte,
the code lengths come from two queues, and a tile's palette is a small open-addressed table reused from tile to tile;
the output is the same, byte for byte. Measured by the clock in the image while dragging (13 rectangles an update):
the tiles take 0.75 ms an update, deflate 0.8 (of which 0.1 the matches and 0.3 choosing and writing the blocks'
codes), comparing with the copy 0.5. In the Profiler, allocation and `Delay` scheduling look larger than they are:
its CPU samples are taken when the timer Process wakes, which allocating 256 KB and scheduling a Delay make it do.

**Primitives.** Two loops moved into the VM. The `zrleTiles` primitive (ZrleCoder, the scope's D12) codes all of a
rectangle's tiles in one call: a tile's runs are found 16 bytes at a time (each pixel compared with the one before it,
ByteSearch's NEON or SSE2 mismatch search), the palette in a small open-addressed table, raw tiles packed by
PixelPacker, and each tile coded by RfbZrleEncoder's cost rule (raw, solid, packed palette, plain RLE, palette RLE). Its
bytes are the Smalltalk's (which stays where the primitive cannot run): checked on random tiles of every kind, on the
repository's screenshots and on the UEFI World's own screen, in 4-byte pixels with 3-byte CPIXELs from either end, with
4-byte CPIXELs, and in 16- and 8-bit formats. The `pixelBlocksDiff` primitive (PixelDiff) compares a damaged rectangle
with RfbDiffSource's copy in 16x16 blocks, marks the blocks that differ and copies it in, also in one call; the runs of
marked blocks are joined in Smalltalk as before. On the UEFI World's screen (1920x1080, by the image's clock) the
tiles take 2-3 ms instead of 19-36 (by format), comparing the whole screen 1.7 ms instead of 8.3; a full-screen update
takes 19 ms instead of 36 and a key 15 ms to its pixels instead of 22 (medians of 5 runs of each, interleaved, on
6e54bb6 and with the primitives). Over a minute of typing, scrolling, dragging and streaming, the Profiler finds the
tiles in 16 of the server's 259 ms (77 of 356 before), mostly copying out the result; deflate is the largest part left
(58 ms). The bytes, the updates a second and the guest's CPU stay as they were: the server's own time was a small part of
the guest's.

**CopyRect.** When the compositor draws a window's layer at the same size and opacity as in the last frame but moved by
whole device pixels (a window dragged, lifted and a little smaller or not), it tells the frame tap before presenting the
frame (`FrameTap>>moved:to:`, on UEFI the firmware screen's tap; hosted its own, `presented:moves:extent:`); the
listeners take the moves with the damage of the same frames. RfbDiffSource moves its copy's pixels, passes the move on to
the connections (a CopyRect where a client's pixels there are up to date, else damage), and compares the destination
again: a move is a hint, and what a window over the moved one, or damage at its origin not yet compared, makes differ
there is found and sent. A tall damaged rectangle whose sample rows (the middle three quarters of 12 rows that changed
and are not of one colour) are all found in the copy the same few rows lower or higher (at most 64; the last distance
first) is a scroll: the rows around them that moved too are moved the same way. Dragging so sends 16 KB/s instead of
575 (QEMU's 298), scrolling 15 instead of 54 (QEMU's 51), typing 20 instead of 34 (a new line scrolls the Workspace);
looking for a scroll costs 0.1-0.2 ms a tall rectangle that changed.

**Where the image's CPU goes.**

- The server itself costs little: the table above, 1-2 % of a core.
- The rest is the input and the drawing. With `--silent` (the client asks for no updates; the same input and
  drawing, nothing encoded) the guest takes 17 % typing, 15 % scrolling, 33 % dragging (at 59 frames/s) and 10 %
  streaming; with the spin it took 41, 29, 108 and 10, with QEMU's server 14, 10, 20 and 10. QEMU's input comes
  through its USB keyboard and tablet, with no network frames.
- The bytes are now QEMU's or fewer.

**Against the targets** (the remote display's scope, Performance targets):

- typing, ≤ 1 KB a frame: met. The median update is 214 B; the mean of 1.1 KB includes the line scrolling.
- typing, encode ≤ 0.5 ms a frame: met, with the primitives: 0.3 ms an update, finding what changed, making and
  sending (0.6 before them).
- typing latency, ≤ 1 frame + RTT + 10 ms: met. 18 ms on loopback (QEMU's: 82 ms).
- idle with a client, no CPU: met for a still World (no updates, 2 %, as with QEMU's). The World as it opens costs
  262 B/s and 4 %, an update every few seconds for readings that move (QEMU's server sends 3.7 KB/s).
- dragging, ≥ 15 updates/s of 20-60 KB: met, at 32.7 updates/s of 464 B (CopyRect; QEMU's: 22 of 13 KB).
- full-screen update, ≤ 150 ms (≤ 50 ms with primitives): 19 ms for 127 KB (39 before the primitives).
- first connect, the whole screen within 0.5 s: 0.29 s.

**For phase 2**, by these numbers:

1. The ZRLE tile primitive (D12) is done (above), and so is the block compare. What is left of an update's time is
   mostly deflate's Huffman codes for each block (its matches, counts and token writing are primitives already): about
   half of the server's samples now, still a small fraction of a core.
