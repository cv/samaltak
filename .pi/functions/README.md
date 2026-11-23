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
| `samaltak.suite` | `tests/st_suite.sh` on packages or classes (sharded over VMs: SAMALTAK_TEST_JOBS), optionally after a build; summary and FAIL/ERROR lines | `suite({ tests: ["Tests-Crypto"], build: true })`, `suite({ tests: ["JitOptRuntimeTest"], vmArgs: ["--jit", "opt", "--jit-threshold", "0"] })` |
| `samaltak.evalImage` | one headless `--eval`, errors caught and returned as `error` (an uncaught error hangs a headless VM) | `evalImage({ expr: "SHA256 hash: 'abc'" })`, `evalImage({ expr, build: true, timeoutS: 120 })` |
| `samaltak.uefiEval` | boot the image on UEFI in QEMU (`make uefi-run`) with an expression or VM args, optional ext4 disks; console and the VM's exit status | `uefiEval({ expr: "SecureRandom default nextBytes: 4" })`, `uefiEval({ args: "--headless --test FileTest" })`, `uefiEval({ expr, disks: [{ dir: "/tmp/notes" }] })` |
| `samaltak.ctlSession` | drive an image through `tools/samaltak-ctl`: open (hosted, windowed on a private Xvfb, or `--uefi`), steps, close | `ctlSession({ open: ["--headless"], steps: [["eval", "3 + 4"]] })`, `ctlSession({ open: ["--uefi", "--headless"], disks: [{ dir: "/tmp/notes" }], steps: [["agent-config", "--from-pi"], ["eval", "..."]] })` |
| `samaltak.gate` | the push gate (AGENTS.md) under Xvfb + lavapipe, in the background, on a snapshot of HEAD in its own worktree; `["auto"]` picks the stages from the changed paths (test-uefi, the JIT stages for src/VM-* and vm/, test-nv for NV work on a GPU machine) | `gate({ action: "start", targets: ["auto"] })`, then `gate()` (waits up to 280 s) until `state` is `passed`; `gate({ action: "status", targets: ["auto"] })` shows the choice; `gate({ action: "stop" })` |
| `samaltak.push` | push to origin/main: rebase (aborts on conflicts), conflict-marker and whitespace checks, a passed gate of the same change, retries | `push({ dryRun: true })`, `push()`, `push({ autostash: true })` |
| `samaltak.bench` | A/B benchmarks for performance work: awfy.sh benchmarks of this tree against origin/main (built once in `$TMPDIR/samaltak-bench/<sha>`), interleaved rounds, pinned to a big core, CPU time; steady medians, change, regressions beyond 5 % and the spread | `bench({ benchmarks: ["Json", "Richards"], vmArgs: "--jit opt" })`, `bench({ benchmarks: ["MicroStrings"], against: "HEAD~1", rounds: 5 })` |
| `samaltak.crashLog` | why a VM died: a samaltak-ctl session's log (or any log): alive, the fatal line, exit status, the stack around it with repeated frames collapsed, the last test errors | `crashLog({ session: "vnc" })`, `crashLog({ file: "build/uefi-arm64/console.log" })` |
| `samaltak.vncWorld` | the operator's screen-shared UEFI World (samaltak-ctl session `vnc`, display 1: the image's own RFB server, or QEMU's VNC server with `server: "qemu"`, the fallback; virtio-gpu 1920x1080, 4 vCPUs pinned to the big cores: `affinity`, `cpus`; docs/uefi.md, Pinning): status, restart (log kept, build, open, agent and GitHub configs, Screen Sharing on the viewer's Mac), close; dryRun | `vncWorld()`, `vncWorld({ action: "restart", viewerHost: "192.168.86.56" })` (only when asked), `vncWorld({ action: "restart", session: "vnc-test", display: 7, configs: [] })` to try things |
| `samaltak.syncUpstream` | merge upstream (schani/samaltak) into the fork: new commits, VM touched, overlap, a trial merge's conflicts; without dryRun the real merge commit on origin/main, conflicts left to resolve; the gate stages it needs | `syncUpstream()` (dry run), `syncUpstream({ dryRun: false })` in a clean worktree at origin/main |
| `samaltak.mergePRs` | the in-image agent's pull requests: check combines them on origin/main (conflicts per PR) and keeps the combination, or its conflict-free part plus the commands for the rest, on a branch to gate; merge lands each PR's own resolved commits (rebased onto the base as the previous merge left it, force-with-lease on its branch) by the method the repository allows: rebase, else squash (one commit, "Area: what changed (#N)" from the PR's title and a short body from its description, or `messages` per PR; subjects over 72 characters warned about), else a merge commit; it verifies the base against the combination after each PR and at the end; `base` for a scratch branch; dryRun | `mergePRs()`, `mergePRs({ branch: "prs/combined" })`, after the gate `mergePRs({ action: "merge", combined: "prs/combined", dryRun: true })`, then without dryRun |

## Notes

- test-core checks that every file here parses as TypeScript (`tests/tools/pi_functions_test.sh`, with bun or node's
  type stripping): pi cannot load a file it cannot parse (gate.ts once had a shell `${...}` inside a template literal).
- Timeouts: a typescript tool call defaults to 30 s and allows at most 300 s. Give the call a `timeoutMs` above the
  function's `timeoutS` (evalImage 25 s, suite 280 s, uefiEval 240 s by default); split longer work (the gate's
  `wait` returns after at most 280 s, call it again).
- Build directories: OUT (`out`) defaults to `build`. A second build directory such as `build/dev` keeps a dev build
  from replacing an image something else is using. `vm/build` is shared and incremental.
- The gate builds once in its fresh worktree, then runs its stages at once (`tests/stages.sh`: each stage a make
  process with its own log, printed when it ends with a line `stage <target>: passed|FAILED (exit N) in N s`, then
  `stages: all passed|FAILED: ...`), and every Smalltalk suite sharded over several VMs (`tests/st_suite.sh`,
  SAMALTAK_TEST_JOBS, default min(nproc / 2, 8); 1: one VM), each VM on an Xvfb of its own, and test-uefi's QEMU boots
  at once (UEFI_TEST_JOBS, each in `OUT/uefi-<arch>/run-<part>`, kept when one fails). The log ends with a timeline:
  each stage's span, then the build's and the slowest stage's steps (the critical path); all stages' with
  `tests/timeline.sh build/gate-runs/<id>.timeline all`. Shards are balanced by the
  class times in this directory's `build/test-times` (the gate's runs keep them up to date). All test VMs and test-uefi's
  QEMUs on the machine share SAMALTAK_TEST_SLOTS slots (default 3/4 of the CPUs, 15 on the DGX Spark, at most one per
  3 GB available; flock files in `/tmp/samaltak-test-slots-<uid>`), so concurrent gates wait for each other's VMs
  instead of each starting 8 per stage; a suite's shard with its longest class and the RFB scenarios (the critical path) get the next
  free slot first, and a fifth more slots kept for them (SAMALTAK_TEST_SLOTS_RESERVED). test-core's and test-tools's parts (the suites beside the main one, the scenarios) run at once too.
  Timings are shared by the machine's worktrees (`~/.cache/samaltak/test-times`), so a fresh worktree's first run
  is balanced. The gate's VM comes from `~/.cache/samaltak/build` when its `vm/` was built before (the log says
  `build-cache: the VM from the cache`; tests/build-cache.sh), so a re-run or a rebase that left `vm/` alone skips
  the VM's compile. Flakes: every stage's result goes into `~/.cache/samaltak/gate-ledger.tsv`; a failed stage first
  names lines that failed in earlier gates (`flakes: known: ...`), and `tests/flakes.sh` lists the failures by
  frequency and how many of their trees also passed (a flake). It tests HEAD's committed tree only
  (not uncommitted or untracked files) and runs one at a time per directory. A failure blocks only if the test passes on origin/main: rerun it alone with `suite` before suspecting
  your change (JIT tests have failed under load). `push` accepts a passed run of the same tree, or of the same change
  when the commits that landed since touch none of your files.
- Rebase conflicts usually come from shared lists (README's docs list, `src/packages.txt`, the Makefile's UEFI_TESTS):
  keep both sides, then gate again. `push` refuses conflict markers and whitespace errors.
- QEMU: one QEMU per build directory; `uefiEval` refuses while a `ctlSession --uefi` (or another run) of the same
  OUT is up, and on a timeout kills only the QEMU it started. Never `pkill -f` a pattern: it can match your own shell, and other agents' VMs (`pkill -f 'samaltak.image --headless --test'`
  ended three gates' test runs at once: a VM with a display quits on SIGTERM, with status 143 and a line naming the sender).
- `agent-config --from-pi` resolves pi's API key, through 1Password's `op` where pi's config says so; that can wait
  for the operator's approval (`authorization timeout`). `ctlSession` notifies the operator first. Never print a key.
- The control service runs only requests with the session's token (docs/remote.md): `samaltak-ctl open` makes it and
  keeps it in the session file (0600); an image started elsewhere (a bare-metal Spark) needs a first step
  `["connect", "--host", H, "--port", P, "--token-file", F]`. `ctlSession` and `crashLog` redact the token (and a
  `control: token ...` line an image printed); never print one.
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
- Merging PRs: the combination is origin/main plus one segment of commits per PR, in merge order: commits made by
  `git cherry-pick -x` of the PR's commits (the "cherry picked from" line ties them to it), or with a line `PR: #N`.
  A conflict's resolution, and any edit it needs beyond the hunks (docs), goes into the segment of the PR being added:
  that PR's branch gets exactly its segment, so an earlier PR never lands a later one's changes. Gate the
  combination; `merge` refuses when main changed its files since (combine and gate again), accepts commits that
  landed on other files, and can be run again after it stops half way (`build/merge-prs/` records the PRs' original
  commits). Try changes to it with throwaway PRs on a scratch base: `base: "scratch/..."` (CI runs only on main).
- A dead samaltak-ctl session's log is overwritten when the session opens again: `crashLog` it first (`vncWorld`
  restart copies it to `$TMPDIR/samaltak-ctl/<session>-<time>.log`).
