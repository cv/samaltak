# Agent instructions

- Run `make test` to execute the full test suite. GitHub Actions runs its stages (`make test-core`, `test-jit-*`, `test-tools`) as parallel jobs on pushes to `main` and pull requests targeting `main`, using Xvfb and software Vulkan (lavapipe).
- Self-contained improvements must always be pushed to `main` immediately.
