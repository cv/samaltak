# Agent instructions

- Run `make test` to execute the full test suite. GitHub Actions runs its stages (`make test-core`, `test-jit-*`, `test-tools`, `test-uefi`) as parallel jobs on pushes to `main` and pull requests targeting `main`, using Xvfb and software Vulkan (lavapipe).
- Self-contained improvements must always be pushed to `main` immediately.
- Gate for pushing to `main`: run this locally, then push.
  - `make test-core`;
  - for changes to the VM or its JIT (`src/VM-*`) also `make test-jit-baseline` and `make test-jit-opt`;
  - for performance work, the benchmarks the change targets and a few it could plausibly hurt, against `origin/main`.

  A test failure blocks only if the test passes on `origin/main`; a benchmark regression only if it reproduces and exceeds 5 %. GitHub Actions runs the other stages after the push: fix a failure your push caused at once.
- Commit messages (every commit you write): the subject "Area: what changed", like upstream's (e.g. "Opt: value
  numbering past type switches, and again after hoisting"), at most ~72 characters, no lists or numbers-dumps in it. The
  body (optional, wrapped at ~72): 2-5 lines on what changed and why, with the one or two numbers that matter. Gate ids,
  test counts, step-by-step details and long lists belong in your report, not the commit. Keep commits focused so the
  subject can be short.
- `make test-nv` runs the NVIDIA GPU tests (NvGpuTest, docs/nv-rm.md) on a machine with one (the GB10); it is not part of `make test` or GitHub Actions.
- Never pick processes to kill or attach to by name or pattern (`pkill -f`, `killall`, `pgrep -x samaltak -n`): the machine is shared, and `samaltak.image --headless --test` or the newest `samaltak` is another agent's gate as often as yours (such kills cut short four gates' test runs). Use the PID of the process you started (`$!`, or `pgrep -P` of its parent).
- On a machine without a GPU, don't run display tests locally, not even under Xvfb with software Vulkan: run the tests that need no display (`tests/st_suite.sh build/samaltak.image -- <classes or packages>`) and leave the rest to GitHub Actions.
- Agents in pi (pit): prefer the project functions in `.pi/functions` (namespace `samaltak`: build, suite, evalImage, uefiEval, ctlSession, gate, push, bench, crashLog, vncWorld, syncUpstream, mergePRs) to hand-written shell for building, testing, QEMU, samaltak-ctl, the gate and pushing; `.pi/functions/README.md` is their manual.
