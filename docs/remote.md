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
