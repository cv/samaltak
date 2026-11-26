# Remote control authentication

The control service grants full control of the image, including evaluating Smalltalk. It is off unless enabled and binds to loopback by default on hosted VMs. Requests and responses, including the bearer token, travel in **cleartext**. Use a trusted link or an encrypted tunnel (such as an SSH port forward to a loopback listener); don't expose the control port to an untrusted network.

## Starting and connecting

- `tools/samaltak-ctl open` generates a fresh token for each new session. It supplies the token through a private `--control-token-file` on hosted VMs, or through the guest's private boot arguments for `open --uefi`. Subsequent CLI commands use the session's token.
- When starting the image directly with `--control` and no supplied token, the server reads 16 bytes directly from `/dev/urandom` on hosted systems or from the firmware's UEFI `GetRNG` on UEFI. If that source fails, the listener does not start; there is no fallback. The server announces the generated token on the VM console, not in a desktop toast. On UEFI it may also echo it to the firmware text console. Treat console output and logs containing the token as secrets.
- To attach to an already running listener, use `tools/samaltak-ctl connect --port N --token-file FILE`. Use `--token-file -` to read from stdin, for example from a secret store. The CLI checks that an authenticated ping returns `controlAuth: 1` before accepting the session.

For manual provisioning, generate a fresh token in a private file. For example, on a hosted VM:

```sh
token_dir=$(mktemp -d)
(umask 077; openssl rand -hex 16 > "$token_dir/token") || exit 1
vm/build/samaltak build/samaltak.image --headless --control --control-port 7341 \
    --control-token-file "$token_dir/token" &
tools/samaltak-ctl connect --port 7341 --token-file "$token_dir/token"
```

Run `connect` once the server is listening. Keep any files needed for restart private and remove them when the session is retired. A token's format does not prove it was generated randomly: let the startup path generate it, or use a cryptographic random source like the command above. Don't choose one by hand.

## Wire protocol and snapshots

Every JSON request object must include a string field `auth`, even for `ping` or on a connection that has already sent a valid request. The token is exactly 32 ASCII hex digits, either contiguous or in four groups of eight separated by single hyphens. Uppercase ASCII hex and the permitted grouping are normalized. Token files may end with a newline; the newline is not part of the wire token.

The server rejects missing, malformed or incorrect authentication before dispatch (`ok: false`, `code: 4`). On success it removes `auth` before the command handler sees the request. An authenticated `ping` includes the numeric field `controlAuth: 1`. See the [command protocol](../tools/README.md#protocol) for response formats.

The server keeps a SHA-256 digest of the 32 lowercase ASCII digits as its verifier, not the token itself. This is not a guarantee that all copies are removed: an image snapshot can contain in-flight request payloads, and credentials can also exist in console logs, session files or boot media. Keep those artifacts private and rotate the token if it might have been exposed.
