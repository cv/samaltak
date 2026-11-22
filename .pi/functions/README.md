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
| `samaltak.build` | `make` (target `all`, `image`, `vm`, `uefi`, `translate`) into OUT with a timeout; ok, seconds, image builder warnings (undeclared variables, layering), errors; translate also the translator's result and the vm/gen files that changed | `build()`, `build({ target: "uefi" })`, `build({ out: "build/dev" })`, `build({ target: "translate" })` after changing src/VM-* or a rebase that did |
| `samaltak.suite` | `tests/st_suite.sh` on packages or classes, optionally after a build; summary and FAIL/ERROR lines | `suite({ tests: ["Tests-Crypto"], build: true })`, `suite({ tests: ["JitOptRuntimeTest"], vmArgs: ["--jit", "opt", "--jit-threshold", "0"] })` |
| `samaltak.evalImage` | one headless `--eval`, errors caught and returned as `error` (an uncaught error hangs a headless VM) | `evalImage({ expr: "SHA256 hash: 'abc'" })`, `evalImage({ expr, build: true, timeoutS: 120 })` |
| `samaltak.uefiEval` | boot the image on UEFI in QEMU (`make uefi-run`) with an expression or VM args, optional ext4 disks; console and the VM's exit status | `uefiEval({ expr: "SecureRandom default nextBytes: 4" })`, `uefiEval({ args: "--headless --test FileTest" })`, `uefiEval({ expr, disks: [{ dir: "/tmp/notes" }] })` |
| `samaltak.ctlSession` | drive an image through `tools/samaltak-ctl`: open (hosted, windowed on a private Xvfb, or `--uefi`), steps, close | `ctlSession({ open: ["--headless"], steps: [["eval", "3 + 4"]] })`, `ctlSession({ open: ["--uefi", "--headless"], disks: [{ dir: "/tmp/notes" }], steps: [["agent-config", "--from-pi"], ["eval", "..."]] })` |
| `samaltak.gate` | the push gate (AGENTS.md) under Xvfb + lavapipe, in the background, on a snapshot of HEAD in its own worktree; `["auto"]` picks the stages from the changed paths (test-uefi, the JIT stages for src/VM-* and vm/, test-nv for NV work on a GPU machine) | `gate({ action: "start", targets: ["auto"] })`, then `gate()` (waits up to 280 s) until `state` is `passed`; `gate({ action: "status", targets: ["auto"] })` shows the choice; `gate({ action: "stop" })` |
| `samaltak.push` | push to origin/main: rebase (aborts on conflicts), conflict-marker and whitespace checks, a passed gate of the same change, retries | `push({ dryRun: true })`, `push()`, `push({ autostash: true })` |
| `samaltak.bench` | A/B benchmarks for performance work: awfy.sh benchmarks of this tree against origin/main (built once in `$TMPDIR/samaltak-bench/<sha>`), interleaved rounds, pinned to a big core, CPU time; steady medians, change, regressions beyond 5 % and the spread | `bench({ benchmarks: ["Json", "Richards"], vmArgs: "--jit opt" })`, `bench({ benchmarks: ["MicroStrings"], against: "HEAD~1", rounds: 5 })` |
| `samaltak.crashLog` | why a VM died: a samaltak-ctl session's log (or any log): alive, the fatal line, exit status, the stack around it with repeated frames collapsed, the last test errors | `crashLog({ session: "vnc" })`, `crashLog({ file: "build/uefi-arm64/console.log" })` |
| `samaltak.vncWorld` | the operator's screen-shared UEFI World (samaltak-ctl session `vnc`, `UEFI_VNC=1`, virtio-gpu 1920x1080): status, restart (log kept, build, open, agent and GitHub configs, Screen Sharing on the viewer's Mac), close; dryRun | `vncWorld()`, `vncWorld({ action: "restart", viewerHost: "192.168.86.56" })` (only when asked), `vncWorld({ action: "restart", session: "vnc-test", display: 7, configs: [] })` to try things |
| `samaltak.syncUpstream` | merge upstream (schani/samaltak) into the fork: new commits, VM touched, overlap, a trial merge's conflicts; without dryRun the real merge commit on origin/main, conflicts left to resolve; the gate stages it needs | `syncUpstream()` (dry run), `syncUpstream({ dryRun: false })` in a clean worktree at origin/main |
| `samaltak.mergePRs` | the in-image agent's pull requests: check combines them on origin/main (conflicts per PR) and can keep the combination on a branch to gate; merge rebase-merges them in order, rebasing a conflicting PR's branch with the gated resolution, and verifies main | `mergePRs()`, `mergePRs({ branch: "prs/combined" })`, then after the gate `mergePRs({ action: "merge", combined: "prs/combined" })` |

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
  OUT is up, and on a timeout kills only the QEMU it started. Never `pkill -f` a pattern: it can match your own shell, and other agents' VMs (`pkill -f 'samaltak.image --headless --test'`
  ended three gates' test runs at once: a VM with a display quits on SIGTERM, with status 143 and a line naming the sender).
- `agent-config --from-pi` resolves pi's API key, through 1Password's `op` where pi's config says so; that can wait
  for the operator's approval (`authorization timeout`). `ctlSession` notifies the operator first. Never print a key.
- `github-config --from-gh` sends `gh auth token` (no approval needed) as the image's GitHub token (docs/github.md);
  `ctlSession` redacts GitHub tokens (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`) as it does API keys.
- AgentItems: print `item text`, not `printString` (cut short).
- vm/gen is generated: after a rebase or merge that touched src/VM-*, `build({ target: "translate" })` and commit what
  `gen` lists; resolve vm/gen conflicts by translating, never by hand.
- The gate: `gate()` with no run of HEAD's tree starts one; with a failed one it reports it (start runs it again).
  Gate ids are local times; `gate({ action: "status" })` lists them.
- Benchmarks on the DGX Spark: an unpinned VM runs on an A725 core about half as fast as on an X925, so `bench` pins
  to one big core; the machine is shared, so look at `loadBefore` and the spread, and rerun a regression alone.
- Upstream (remote `upstream`, schani/samaltak) comes in by merge commits only (the fork's history is published);
  `push` pushes a merge on top of origin/main as it is. `gh` defaults to upstream in this clone: pass `-R cv/samaltak`.
- A dead samaltak-ctl session's log is overwritten when the session opens again: `crashLog` it first (`vncWorld`
  restart copies it to `$TMPDIR/samaltak-ctl/<session>-<time>.log`).
