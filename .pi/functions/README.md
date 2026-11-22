# Project functions (pi / pit)

Typed TypeScript functions for agents working on Samaltak in pi with the pit extension, namespace `samaltak`. Each
file in `samaltak/` is one function; its doc comment and leading comments are the full reference. They run in the
caller's current directory, so each git worktree uses its own build. Prefer them to hand-written shell: they encode
the timeouts, isolation and checks that hand-run sequences kept getting wrong.

pi loads project functions only from a trusted project (`~/.pi/agent/trust.json`), and trust is decided when the pi
process starts: after trusting a new worktree, restart pi (a `/reload` sent with `agents.send` arrives as plain text).
Check with `context.get().projectFunctions`.

| Function | For | Typical calls |
| --- | --- | --- |
| `samaltak.build` | `make` (target `all`, `image`, `vm`, `uefi`) into OUT with a timeout; ok, seconds, image builder warnings (undeclared variables, layering), errors | `build()`, `build({ target: "uefi" })`, `build({ out: "build/dev" })` |
| `samaltak.suite` | `tests/st_suite.sh` on packages or classes, optionally after a build; summary and FAIL/ERROR lines | `suite({ tests: ["Tests-Crypto"], build: true })`, `suite({ tests: ["JitOptRuntimeTest"], vmArgs: ["--jit", "opt", "--jit-threshold", "0"] })` |
| `samaltak.evalImage` | one headless `--eval`, errors caught and returned as `error` (an uncaught error hangs a headless VM) | `evalImage({ expr: "SHA256 hash: 'abc'" })`, `evalImage({ expr, build: true, timeoutS: 120 })` |
| `samaltak.uefiEval` | boot the image on UEFI in QEMU (`make uefi-run`) with an expression or VM args, optional ext4 disks; console and the VM's exit status | `uefiEval({ expr: "SecureRandom default nextBytes: 4" })`, `uefiEval({ args: "--headless --test FileTest" })`, `uefiEval({ expr, disks: [{ dir: "/tmp/notes" }] })` |
| `samaltak.ctlSession` | drive an image through `tools/samaltak-ctl`: open (hosted, windowed on a private Xvfb, or `--uefi`), steps, close | `ctlSession({ open: ["--headless"], steps: [["eval", "3 + 4"]] })`, `ctlSession({ open: ["--uefi", "--headless"], disks: [{ dir: "/tmp/notes" }], steps: [["agent-config", "--from-pi"], ["eval", "..."]] })` |
| `samaltak.gate` | the push gate (AGENTS.md) under Xvfb + lavapipe, in the background, on a snapshot of HEAD in its own worktree | `gate({ action: "start", targets: ["test-core", "test-uefi"] })`, then `gate()` (waits up to 280 s) until `state` is `passed`; `gate({ action: "status" })`, `gate({ action: "stop" })` |
| `samaltak.push` | push to origin/main: rebase (aborts on conflicts), conflict-marker and whitespace checks, a passed gate of the same change, retries | `push({ dryRun: true })`, `push()`, `push({ autostash: true })` |

## Notes

- Timeouts: a typescript tool call defaults to 30 s and allows at most 300 s. Give the call a `timeoutMs` above the
  function's `timeoutS` (evalImage 25 s, suite 280 s, uefiEval 240 s by default); split longer work (the gate's
  `wait` returns after at most 280 s, call it again).
- Build directories: OUT (`out`) defaults to `build`. A second build directory such as `build/dev` keeps a dev build
  from replacing an image something else is using. `vm/build` is shared and incremental.
- The gate: test-core takes about 6.5 min, test-core and test-uefi about 7.5 min, plus about 30 s to build in its
  fresh worktree. It tests HEAD's committed tree only (not uncommitted or untracked files) and runs one at a time per
  directory. A failure blocks only if the test passes on origin/main: rerun it alone with `suite` before suspecting
  your change (JIT tests have failed under load). `push` accepts a passed run of the same tree, or of the same change
  when the commits that landed since touch none of your files.
- Rebase conflicts usually come from shared lists (README's docs list, `src/packages.txt`, the Makefile's UEFI_TESTS):
  keep both sides, then gate again. `push` refuses conflict markers and whitespace errors.
- QEMU: one QEMU per build directory; `uefiEval` refuses while a `ctlSession --uefi` (or another run) of the same
  OUT is up, and on a timeout kills only the QEMU it started. Never `pkill -f` a pattern: it can match your own shell.
- `agent-config --from-pi` resolves pi's API key, through 1Password's `op` where pi's config says so; that can wait
  for the operator's approval (`authorization timeout`). `ctlSession` notifies the operator first. Never print a key.
- `github-config --from-gh` sends `gh auth token` (no approval needed) as the image's GitHub token (docs/github.md);
  `ctlSession` redacts GitHub tokens (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`) as it does API keys.
- AgentItems: print `item text`, not `printString` (cut short).
