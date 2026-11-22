# Remote control and its token

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

## Tests

`tests/remote/auth_test.sh` (test-tools, hosted; and in test-uefi on the VM on UEFI, `--session uefi-test`): a request
without the token, with a wrong one or one a character short is refused with code 4 and runs nothing; the session's
token works, also through `connect` with the token in groups; a wrong token makes no session; the session file is
0600; the token is in no process's command line (ps) and not in the session's log. Hosted also: an image started
without a token makes one, shows it, and `connect` with what it showed works (`close --quit` quits it); a token too
short is refused. `ControlServerTest` (Tests-Remote) checks the same in the image: rejection, constant-time
`authorizes:` on near misses, and that commands never see `auth`. test-uefi's own requests from the guest to itself
through the host (ping, a megabyte each way) carry `ControlServer current token`.
