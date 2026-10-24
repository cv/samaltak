# Benchmarks

Same suite in three systems, methods compiled normally in each (`vm/tests/bench/suite-*.st`), on an Apple M2 Max, best of five to seven runs. Milliseconds, lower is better.

| benchmark | Samaltak | GNU Smalltalk 3.2.5 (interpreter) | Pharo 12 (Cog JIT) |
|---|---|---|---|
| `fib: 30` | 25 | 45 | 10 |
| loop 30M (`r := r + i`) | 120 | 171 | 64 |
| sends 10M (`self id: r`) | 102 | 167 | 22 |
| blocks 10M (`b value: r`) | 118 | 172 | 30 |
| floats 3M | 33 | 246 | 39 |
| Dictionary 300k (`at:put:`, `at:`) | 102 | 1653 | 227 |
| strings 300k (`printString` into a stream) | 150 | 222 | 63 |
| allocation 3M (`Array new: 4`) | 64 | 992 | 24 |
| `1000 factorial` ×30 | 26 | 6 | 7 |

GNU Smalltalk and Pharo do large-integer arithmetic in C (GMP, LargeIntegersPlugin); Samaltak's is Smalltalk. Pharo compiles to native code, so it is a ceiling rather than a peer.

Run:

    vm/build/samaltak build/samaltak.image --headless --eval "$(cat vm/tests/bench/suite-samaltak.st)"
    gst vm/tests/bench/suite-gst.st
    Pharo --headless Pharo.image eval "$(cat vm/tests/bench/suite-pharo.st)"

## Are We Fast Yet

The suite for comparing JIT variants ([jit.md](jit.md)): the 14 [Are We Fast Yet](https://github.com/smarr/are-we-fast-yet) benchmarks (Marr, Daloze, Mössenböck, DLS 2016; MIT, `awfy/LICENSE.md`), the micro suite above (`Micro*`) and two Samaltak workloads: `Recompile` (compile every method of Kernel-Collections without installing it; checks the bytecodes match) and `TextRendering` (40 lines of text on a 900×500 Canvas, then `displayList`). The sources in `vm/tests/bench/awfy/` are filed into a built image; each benchmark runs in its own VM process. Pharo 12 runs the same sources except the Samaltak workloads.

    vm/tests/bench/awfy.sh [--suite awfy|micro|workloads|all] [-n 30] [--vm-args '--jit ...'] [Bench[:inner] ...]
    vm/tests/bench/awfy.sh --pharo ...                  # $PHARO_VM, $PHARO_IMAGE (default /tmp/pharo-dl)
    vm/tests/bench/awfy.sh --summary results/*.csv      # median over invocations

Output: `benchmark,iteration,microseconds` per iteration; `# stats` lines with the VM statistics delta over all iterations (every counter the VM answers, unnamed ones as `counterN`); a summary of first iteration, steady state (median of the last half) and total. `-o` saves all of it.

Defaults: 30 iterations; inner iterations (`inner()` in `awfy.sh`) such that a steady-state iteration takes about 100 ms on the interpreter. CD (100 aircraft, 340 ms), Havlak (1, 790 ms), Mandelbrot (500, 540 ms) and NBody (250000 steps, 780 ms) run at the smallest non-trivial size upstream verifies. `--suite all` takes 2 minutes on the interpreter.

Changes from upstream (the Smalltalk variant, SOM class syntax with Pharo method bodies): class files converted to chunk format, class-side fields as class variables (as upstream's Pharo loader); `Scheduler` (Richards) and `Simulator` (CD) renamed `RBScheduler` and `CDSimulator`, Samaltak has those globals; Json's `isTrue || isFalse` (unused) written `isTrue | isFalse`; the harness prints CSV and VM statistics and does not exit; `awfy/Samaltak.st` adds the Pharo methods `Integer>>&` and `Number>>%`.

Steady state, ms, median of 3 invocations (`vm/tests/bench/results/*-2026-10-24-*.csv`), M2 Max:

| benchmark | Samaltak (interpreter) | Pharo 12 (Cog JIT) |
|---|---|---|
| Bounce | 110 | 33 |
| CD | 342 | 214 |
| DeltaBlue | 107 | 45 |
| Havlak | 793 | 367 |
| Json | 107 | 56 |
| List | 121 | 24 |
| Mandelbrot | 539 | 377 |
| NBody | 778 | 374 |
| Permute | 115 | 34 |
| Queens | 116 | 44 |
| Richards | 101 | 23 |
| Sieve | 105 | 60 |
| Storage | 117 | 62 |
| Towers | 91 | 17 |
