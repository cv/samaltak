# Agent instructions

- Run `make test` to execute the full test suite. GitHub Actions runs its stages (`make test-core`, `test-jit-*`, `test-tools`, `test-uefi`) as parallel jobs on pushes to `main` and pull requests targeting `main`, using Xvfb and software Vulkan (lavapipe).
- Self-contained improvements must always be pushed to `main` immediately.
- Gate for pushing to `main`: run this locally, then push.
  - `make test-core`;
  - for changes to the VM or its JIT (`src/VM-*`) also `make test-jit-baseline` and `make test-jit-opt`;
  - for performance work, the benchmarks the change targets and a few it could plausibly hurt, against `origin/main`.

  A test failure blocks only if the test passes on `origin/main`; a benchmark regression only if it reproduces and exceeds 5 %. GitHub Actions runs the other stages after the push: fix a failure your push caused at once.
- On a machine without a GPU, don't run display tests locally, not even under Xvfb with software Vulkan: run the tests that need no display (`tests/st_suite.sh build/samaltak.image -- <classes or packages>`) and leave the rest to GitHub Actions.
