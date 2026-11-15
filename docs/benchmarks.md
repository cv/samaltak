# Benchmarks

Same suite in three systems, methods compiled normally in each (`vm/tests/bench/suite-*.st`), on an Apple M2 Max, best of five to seven runs. Milliseconds, lower is better.

| benchmark | Samaltak (interpreter) | GNU Smalltalk 3.2.5 (interpreter) | Pharo 12 (Cog JIT) |
|---|---|---|---|
| `fib: 30` | 25 | 45 | 10 |
| loop 30M (`r := r + i`) | 120 | 171 | 64 |
| sends 10M (`self id: r`) | 102 | 167 | 22 |
| blocks 10M (`b value: r`) | 118 | 172 | 30 |
| floats 3M | 33 | 246 | 39 |
| Dictionary 300k (`at:put:`, `at:`) | 102 | 1653 | 227 |
| strings 300k (`printString` into a stream) | 150 | 222 | 63 |
| allocation 3M (`Array new: 4`) | 64 | 992 | 24 |
| `1000 factorial` ×30 | 2 | 6 | 7 |

All three do large-integer arithmetic in C (GMP, LargeIntegersPlugin, Samaltak's LargeIntegerPrimitives). Pharo compiles to native code, so it is a ceiling rather than a peer.

Run:

    vm/build/samaltak build/samaltak.image --headless --eval "$(cat vm/tests/bench/suite-samaltak.st)"
    gst vm/tests/bench/suite-gst.st
    Pharo --headless Pharo.image eval "$(cat vm/tests/bench/suite-pharo.st)"

## Are We Fast Yet

The suite for comparing JIT variants ([jit.md](jit.md)): the 14 [Are We Fast Yet](https://github.com/smarr/are-we-fast-yet) benchmarks (Marr, Daloze, Mössenböck, DLS 2016; MIT, `awfy/LICENSE.md`), the micro suite above (`Micro*`) and two Samaltak workloads: `Recompile` (compile every method of Kernel-Collections without installing it; checks the bytecodes match) and `TextRendering` (40 lines of text on a 900×500 Canvas, then `displayList`). The sources in `vm/tests/bench/awfy/` are filed into a built image; each benchmark runs in its own VM process. Pharo 12 runs the same sources except the Samaltak workloads.

    vm/tests/bench/awfy.sh [--suite awfy|micro|workloads|realworld|all] [-n 30] [--vm-args '--jit none|baseline|opt'] [Bench[:inner] ...]
    vm/tests/bench/awfy.sh --pharo ...                  # $PHARO_VM, $PHARO_IMAGE (default ~/.cache/pharo14)
    vm/tests/bench/awfy.sh --summary results/*.csv      # median over invocations

Output: `benchmark,iteration,microseconds` per iteration; `# stats` lines with the VM statistics delta over all iterations (every counter the VM answers, unnamed ones as `counterN`); a summary of first iteration, steady state (median of the last half) and total. `-o` saves all of it.

Defaults: 30 iterations; inner iterations (`inner()` in `awfy.sh`) such that a steady-state iteration takes about 100 ms on the interpreter. CD (100 aircraft, 330 ms), Havlak (1, 710 ms), Mandelbrot (500, 500 ms) and NBody (250000 steps, 750 ms) run at the smallest non-trivial size upstream verifies. `--suite all` takes 2 minutes on the interpreter.

Changes from upstream (the Smalltalk variant, SOM class syntax with Pharo method bodies): class files converted to chunk format, class-side fields as class variables (as upstream's Pharo loader); `Scheduler` (Richards) and `Simulator` (CD) renamed `RBScheduler` and `CDSimulator`, Samaltak has those globals; Json's `isTrue || isFalse` (unused) written `isTrue | isFalse`; the harness prints CSV and VM statistics and does not exit; `awfy/Samaltak.st` adds the Pharo methods `Integer>>&` and `Number>>%`.

Steady state (median of the last half of 30 iterations) and first iteration, ms, median of 3 invocations interleaved `opt`, `baseline` and Pharo 12, the interpreter (`none`) after them (`vm/tests/bench/results/{samaltak-opt,samaltak-baseline,pharo12-cog,samaltak-none}-2026-11-07-*.csv`), 1-minute load at most 3 before each invocation, M2 Max:

| benchmark | `none` | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo | first `baseline` / Pharo |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bounce | 115.6 | 10.3 | 22.1 | 33.2 | 0.31 | 0.67 | 12.2 | 22.5 | 33.2 | 0.37 | 0.68 |
| CD | 351.8 | 50.3 | 90.0 | 210.0 | 0.24 | 0.43 | 72.6 | 92.4 | 218.8 | 0.33 | 0.42 |
| DeltaBlue | 117.4 | 14.7 | 32.2 | 45.4 | 0.32 | 0.71 | 77.9 | 36.1 | 90.8 | 0.86 | 0.40 |
| Havlak | 777.5 | 78.2 | 205.5 | 376.4 | 0.21 | 0.55 | 114.4 | 232.0 | 438.4 | 0.26 | 0.53 |
| Json | 96.5 | 9.0 | 35.9 | 58.1 | 0.15 | 0.62 | 40.7 | 39.8 | 64.1 | 0.63 | 0.62 |
| List | 123.4 | 12.1 | 17.9 | 24.3 | 0.50 | 0.74 | 12.8 | 18.4 | 24.3 | 0.53 | 0.76 |
| Mandelbrot | 535.3 | 120.3 | 210.1 | 376.1 | 0.32 | 0.56 | 123.0 | 209.8 | 378.2 | 0.33 | 0.55 |
| NBody | 780.9 | 147.2 | 332.8 | 357.4 | 0.41 | 0.93 | 150.1 | 332.2 | 393.9 | 0.38 | 0.84 |
| Permute | 113.0 | 13.7 | 21.8 | 34.6 | 0.40 | 0.63 | 15.4 | 21.9 | 33.5 | 0.46 | 0.65 |
| Queens | 116.3 | 12.3 | 19.9 | 44.3 | 0.28 | 0.45 | 14.2 | 20.8 | 43.5 | 0.33 | 0.48 |
| Richards | 106.3 | 9.9 | 18.0 | 23.5 | 0.42 | 0.77 | 12.8 | 18.9 | 24.3 | 0.53 | 0.78 |
| Sieve | 103.4 | 17.8 | 34.0 | 56.3 | 0.32 | 0.60 | 26.8 | 35.1 | 67.4 | 0.40 | 0.52 |
| Storage | 121.1 | 25.3 | 37.4 | 58.2 | 0.43 | 0.64 | 29.4 | 38.5 | 72.4 | 0.41 | 0.53 |
| Towers | 93.9 | 8.1 | 14.2 | 17.0 | 0.48 | 0.84 | 9.8 | 14.4 | 17.3 | 0.57 | 0.83 |
| geometric mean | | | | | 0.33 | 0.64 | | | | 0.43 | 0.60 |

The micro suite (`--suite micro`: the first table's benchmarks as AWFY benchmarks), the same way (`...-micro-2026-11-07-*.csv`):

| benchmark | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo | first `baseline` / Pharo |
|---|---|---|---|---|---|---|---|---|---|---|
| MicroFib | 4.4 | 5.2 | 10.2 | 0.43 | 0.51 | 4.5 | 5.2 | 10.2 | 0.44 | 0.51 |
| MicroLoop | 27.7 | 32.7 | 64.4 | 0.43 | 0.51 | 27.8 | 33.0 | 64.6 | 0.43 | 0.51 |
| MicroFloats | 5.7 | 20.7 | 38.8 | 0.15 | 0.53 | 6.1 | 20.8 | 38.3 | 0.16 | 0.54 |
| MicroSends | 12.1 | 22.2 | 22.8 | 0.53 | 0.97 | 12.8 | 22.3 | 22.8 | 0.56 | 0.98 |
| MicroBlocks | 14.7 | 29.3 | 30.7 | 0.48 | 0.95 | 15.9 | 29.5 | 30.4 | 0.52 | 0.97 |
| MicroDict | 16.9 | 29.8 | 140.8 | 0.12 | 0.21 | 17.6 | 39.3 | 245.4 | 0.07 | 0.16 |
| MicroStrings | 23.2 | 36.8 | 61.3 | 0.38 | 0.60 | 27.7 | 38.4 | 79.3 | 0.35 | 0.48 |
| MicroAlloc | 12.4 | 21.1 | 35.1 | 0.35 | 0.60 | 16.6 | 23.6 | 64.1 | 0.26 | 0.37 |
| MicroFactorial | 1.8 | 1.8 | 10.6 | 0.17 | 0.17 | 3.7 | 1.9 | 10.9 | 0.34 | 0.17 |
| geometric mean | | | | 0.30 | 0.49 | | | | 0.30 | 0.44 |

`opt` takes 0.33 of Pharo 12's time on AWFY (first iterations 0.43), `baseline` 0.64; on the micro suite 0.30 and 0.49. Both win every benchmark. `baseline` comes closest on NBody (0.93: Float arithmetic out of line, accessors sent), MicroBlocks (0.95) and MicroSends (0.97): a block call or a send per turn, the code Cog makes for them; `opt`'s first iteration on DeltaBlue (0.86), most of it compiling.

### x86-64

The same benchmarks on Linux x86-64: an AMD EPYC 7B13 (Zen 3) cloud VM with 2 vCPUs, the VM built with gcc -O2 (no profile); CPU time (`--cpu`), steady state as above, one invocation per mode, `none` 10 iterations, `baseline` and `opt` 30 (`vm/tests/bench/results/samaltak-x86-{none,baseline,opt}-2026-11-14.csv`), beside arm64's ratios from the table above (M2 Max):

| benchmark | `none` | `baseline` | `opt` | `baseline` / `none` | `opt` / `none` | arm64 `baseline` / `none` | arm64 `opt` / `none` |
|---|---|---|---|---|---|---|---|
| Bounce | 309.9 | 42.3 | 14.4 | 0.14 | 0.05 | 0.19 | 0.09 |
| CD | 728.1 | 178.3 | 97.8 | 0.24 | 0.13 | 0.26 | 0.14 |
| DeltaBlue | 323.5 | 58.6 | 22.6 | 0.18 | 0.07 | 0.27 | 0.13 |
| Havlak | 1310.4 | 414.6 | 128.3 | 0.32 | 0.10 | 0.26 | 0.10 |
| Json | 171.3 | 70.3 | 20.5 | 0.41 | 0.12 | 0.37 | 0.09 |
| List | 248.7 | 32.8 | 17.4 | 0.13 | 0.07 | 0.15 | 0.10 |
| Mandelbrot | 745.9 | 199.6 | 146.5 | 0.27 | 0.20 | 0.39 | 0.22 |
| NBody | 1601.7 | 503.7 | 223.7 | 0.31 | 0.14 | 0.43 | 0.19 |
| Permute | 198.6 | 34.3 | 22.7 | 0.17 | 0.11 | 0.19 | 0.12 |
| Queens | 199.0 | 35.7 | 17.8 | 0.18 | 0.09 | 0.17 | 0.11 |
| Richards | 169.2 | 35.3 | 18.5 | 0.21 | 0.11 | 0.17 | 0.09 |
| Sieve | 236.7 | 46.2 | 33.9 | 0.20 | 0.14 | 0.33 | 0.17 |
| Storage | 213.1 | 54.3 | 31.9 | 0.25 | 0.15 | 0.31 | 0.21 |
| Towers | 149.0 | 22.9 | 13.1 | 0.15 | 0.09 | 0.15 | 0.09 |
| geometric mean | | | | 0.21 | 0.11 | 0.24 | 0.13 |

Over its interpreter each JIT gains as much on x86-64 as on arm64; this machine runs the interpreter 1.9× slower than the M2 Max. Compiling (the runs' counters): `baseline` 10.1 µs a method, 0.45 µs per bytecode byte; `opt` 0.78 ms a unit, 8.6 KB of code (the M2 Max: 4.3 µs, 0.20 µs, 0.34 ms, 6.1 KB). x86-64's code is about a third bigger than arm64's: two-operand instructions take a `mov` more, branches to out-of-line paths 6 bytes, nil, true and false a pc-relative word, 64-bit constants 10 bytes.

Against Pharo 12 on the same machine (its Linux x86-64 VM, Cog), all three suites: CPU time (`--cpu`; `awfy/PharoCPU.st` reads the thread's clock as on macOS), steady state as above, median of 3 invocations interleaved `opt`, `baseline`, Pharo (`vm/tests/bench/results/{samaltak-x86-opt,samaltak-x86-baseline,pharo12-cog-x86}{,-micro,-realworld}-2026-11-15-*.csv`), beside arm64's ratios from the tables of this document (M2 Max). Geometric means:

| | x86-64 `opt` / Pharo | arm64 `opt` / Pharo | x86-64 `baseline` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|
| Are We Fast Yet (14) | 0.43 | 0.33 | 0.82 | 0.64 |
| Micro (9) | 0.25 | 0.30 | 0.44 | 0.49 |
| CLBG (6 of the real-world workloads) | 0.48 | 0.50 | 0.63 | 0.66 |
| the other real-world workloads (10) | 0.46 | 0.37 | 0.58 | 0.46 |
| all 39 | 0.39 | 0.35 | 0.62 | 0.55 |

| Are We Fast Yet | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | arm64 `opt` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|---|---|---|
| Bounce | 15.6 | 36.1 | 44.3 | 0.35 | 0.81 | 0.31 | 0.67 |
| CD | 99.7 | 182.0 | 198.9 | 0.50 | 0.92 | 0.24 | 0.43 |
| DeltaBlue | 21.8 | 57.3 | 59.3 | 0.37 | 0.97 | 0.32 | 0.71 |
| Havlak | 137.9 | 418.2 | 404.4 | 0.34 | 1.03 | 0.21 | 0.55 |
| Json | 20.5 | 71.3 | 36.1 | 0.57 | 1.98 | 0.15 | 0.62 |
| List | 17.2 | 32.9 | 55.6 | 0.31 | 0.59 | 0.50 | 0.74 |
| Mandelbrot | 148.1 | 199.7 | 300.3 | 0.49 | 0.67 | 0.32 | 0.56 |
| NBody | 224.2 | 503.9 | 517.4 | 0.43 | 0.97 | 0.41 | 0.93 |
| Permute | 29.5 | 34.4 | 52.3 | 0.57 | 0.66 | 0.40 | 0.63 |
| Queens | 17.7 | 38.6 | 59.1 | 0.30 | 0.65 | 0.28 | 0.45 |
| Richards | 30.9 | 34.8 | 37.8 | 0.82 | 0.92 | 0.42 | 0.77 |
| Sieve | 33.3 | 46.3 | 88.7 | 0.38 | 0.52 | 0.32 | 0.60 |
| Storage | 30.9 | 54.7 | 91.6 | 0.34 | 0.60 | 0.43 | 0.64 |
| Towers | 12.9 | 24.4 | 27.9 | 0.46 | 0.87 | 0.48 | 0.84 |
| geometric mean | | | | 0.43 | 0.82 | 0.33 | 0.64 |

| Micro | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | arm64 `opt` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|---|---|---|
| MicroFib | 6.2 | 8.3 | 10.8 | 0.58 | 0.77 | 0.43 | 0.51 |
| MicroLoop | 29.1 | 38.7 | 115.0 | 0.25 | 0.34 | 0.43 | 0.51 |
| MicroFloats | 10.7 | 18.9 | 60.6 | 0.18 | 0.31 | 0.15 | 0.53 |
| MicroSends | 9.8 | 32.0 | 38.9 | 0.25 | 0.82 | 0.53 | 0.97 |
| MicroBlocks | 19.3 | 54.3 | 47.4 | 0.41 | 1.14 | 0.48 | 0.95 |
| MicroDict | 28.7 | 51.3 | 232.9 | 0.12 | 0.22 | 0.12 | 0.21 |
| MicroStrings | 45.4 | 63.7 | 98.4 | 0.46 | 0.65 | 0.38 | 0.60 |
| MicroAlloc | 16.9 | 35.3 | 82.7 | 0.20 | 0.43 | 0.35 | 0.60 |
| MicroFactorial | 1.7 | 1.8 | 14.2 | 0.12 | 0.12 | 0.17 | 0.17 |
| geometric mean | | | | 0.25 | 0.44 | 0.30 | 0.49 |

| Real-world | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | arm64 `opt` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|---|---|---|
| BinaryTrees | 421.3 | 720.4 | 925.5 | 0.46 | 0.78 | 0.45 | 0.79 |
| Fasta | 538.1 | 701.0 | 742.2 | 0.73 | 0.94 | 0.72 | 0.83 |
| KNucleotide | 623.5 | 784.1 | 1210.7 | 0.51 | 0.65 | 0.51 | 0.61 |
| ReverseComplement | 446.0 | 689.8 | 1235.0 | 0.36 | 0.56 | 0.35 | 0.55 |
| SpectralNorm | 729.1 | 845.6 | 1008.9 | 0.72 | 0.84 | 0.55 | 0.81 |
| Pidigits | 427.3 | 436.2 | 1579.0 | 0.27 | 0.28 | 0.48 | 0.45 |
| Strings | 431.7 | 559.4 | 1086.1 | 0.40 | 0.52 | 0.37 | 0.46 |
| Dictionaries | 522.8 | 879.3 | 1735.5 | 0.30 | 0.51 | 0.32 | 0.43 |
| OrderedCollections | 317.0 | 394.5 | 1140.9 | 0.28 | 0.35 | 0.28 | 0.32 |
| Sorting | 819.2 | 1172.9 | 1214.5 | 0.67 | 0.97 | 0.70 | 0.77 |
| Enumeration | 376.5 | 613.2 | 916.7 | 0.41 | 0.67 | 0.39 | 0.63 |
| PrintParse | 1073.1 | 1556.8 | 1363.6 | 0.79 | 1.14 | 0.57 | 0.85 |
| Exceptions | 823.7 | 818.4 | 1892.8 | 0.44 | 0.43 | 0.63 | 0.68 |
| Megamorphic | 320.6 | 265.6 | 281.6 | 1.14 | 0.94 | 0.15 | 0.15 |
| DeepRecursion | 346.2 | 405.2 | 1284.9 | 0.27 | 0.32 | 0.32 | 0.36 |
| Perform | 512.4 | 606.7 | 1249.7 | 0.41 | 0.49 | 0.33 | 0.39 |
| geometric mean | | | | 0.46 | 0.60 | 0.41 | 0.52 |

`opt` wins 38 of the 39; it loses Megamorphic (1.14: Pharo's x86 VM takes 282 ms where its arm64 one takes 704, Samaltak 321 where it takes 107; a fifth of its samples are in the shared megamorphic stub; its table is not the cause: 1024 or 16384 entries instead of 4096 change nothing). `baseline` loses Json (1.98), Havlak, MicroBlocks and PrintParse (1.03–1.14). Pharo runs these benchmarks 1.43× slower here than on the M2 Max, `opt` 1.58× and `baseline` 1.61× (built here with gcc and no profile, there with clang and its profile). The machine is shared: every VM had invocations that ran up to twice as slow (Pharo's Bounce 44, 87 and 44 ms); the best of the 3 invocations instead of their median moves no geometric mean by more than 0.02.

Pharo 14 (its Linux x86-64 download of 2026-11-14, `Pharo-14.0.0+SNAPSHOT.build.790`), the same way (`vm/tests/bench/results/pharo14-cog-x86{,-micro,-realworld}-2026-11-15-*.csv`), against the Samaltak medians above. Its Cog runs these benchmarks as fast as Pharo 12's (geometric mean 0.99 of Pharo 12's time; Json 1.17, Sorting and Enumeration 0.85, the rest within 12 %):

| | `opt` / Pharo 14 | `baseline` / Pharo 14 | `opt` / Pharo 12 | `baseline` / Pharo 12 |
|---|---|---|---|---|
| Are We Fast Yet (14) | 0.43 | 0.82 | 0.43 | 0.82 |
| Micro (9) | 0.25 | 0.44 | 0.25 | 0.44 |
| CLBG (6) | 0.48 | 0.63 | 0.48 | 0.63 |
| the other real-world workloads (10) | 0.47 | 0.60 | 0.46 | 0.58 |
| all 39 | 0.40 | 0.63 | 0.39 | 0.62 |

`opt` loses Megamorphic to Pharo 14 too (1.23); `baseline` Json (1.69), Havlak and Sorting (1.14), MicroBlocks, PrintParse, Megamorphic and NBody (1.01–1.07).

## Real-world workloads

AWFY brings its own collections (`Vector`, `SomDictionary`, `SomSet` in `awfy/Core.st`), so it measures the compiler and VM, not the class library, its primitives or the GC at scale. These 16 workloads (`awfy/RealWorld.st`, `--suite realworld`, not part of `all`) are written once against each system's own class library; Pharo 12 runs the same source. Each answers a checksum that `verifyResult:` compares with one constant for both systems; at small sizes all 16 also answer the same on both. Sizes give 0.45–1 s per iteration on Pharo 12; an invocation takes 3 minutes under `opt`, 3.5 under `baseline`, 6 on Pharo.

| workload | what |
|---|---|
| BinaryTrees | CLBG binary-trees, depth 17; its long-lived tree 20 deep (2M nodes live throughout) |
| Fasta | CLBG fasta, n = 1,000,000, into a WriteStream |
| KNucleotide | CLBG k-nucleotide on fasta 75,000 read with `nextLine`: `copyFrom:to:` keys into Dictionaries of up to 375,000 Strings, frequencies sorted and printed with `printShowingDecimalPlaces:` |
| ReverseComplement | CLBG reverse-complement on fasta 1,000,000 (10 MB): `nextLine`, `reversed`, `collect:` through a table, 60-character lines |
| SpectralNorm | CLBG spectral-norm, n = 1000: Float arithmetic |
| Pidigits | CLBG pidigits, 4000 digits: LargeInteger `+`, `*`, `//` |
| Strings | 40,000 lines written with a WriteStream, then `lines`, `substrings:`, `asUppercase`, `asLowercase`, `sameAs:`, `<`, `beginsWith:`, `capitalized`, `join:`, `copyReplaceAll:with:`, `occurrencesOf:`, `includesSubstring:`, `indexOf:`, `,`, `format:` |
| Dictionaries | 200,000 String keys: Dictionary and Set insertion, hits, misses, updates, removal, enumeration; their Symbols (`asSymbol`) as keys of an IdentityDictionary and a Dictionary |
| OrderedCollections | 10 rounds of growth at both ends to 400,000, a FIFO rotated 400,000 times (`removeFirst`, `addLast:`) and a LIFO drain; breadth-first search on a 1000×1000 grid; `add:beforeIndex:`, `removeAt:` |
| Sorting | `sort:` with sort blocks on 200,000 Integers (both orders), Floats, digit Strings, Strings case-insensitively and two-key records; `asSortedCollection:`; SortedCollection `add:`, `removeFirst` |
| Enumeration | 200,000 order records, 5 passes of `select:`, `collect:`, `inject:into:`, `detect:ifNone:`, `reject:`, `count:`, `anySatisfy:`, `allSatisfy:`, `detectMax:`, `with:collect:`, `withIndexDo:`, a grouping into a Dictionary of OrderedCollections, `asSet`, `asBag` |
| PrintParse | 100,000 Integers printed (decimal, hex, padded) and read back; Floats printed and read back; CSV lines built and split |
| Exceptions | 40,000 × 14 cases: `return:`, `pass`, `retry`, `resume:` of a Warning, `outer`, `ensure:` and `ifCurtailed:` on normal and exceptional exits, a non-local return through `ensure:`, MessageNotUnderstood, ZeroDivide, a signal 20 frames deep, an ExceptionSet |
| Megamorphic | 40 random expression trees over 22 node classes, 20 passes: `evalIn:` (all classes at each send site) and a visitor (double dispatch) |
| DeepRecursion | linked lists built, mapped, summed and measured recursively 100, 1000, 10,000 and 100,000 deep (500,000 activations per depth and operation); a recursive flood fill 90,000 deep |
| Perform | 800,000 runs of a stack-machine program whose 26 instructions are selectors (`perform:`, `perform:with:`, `perform:with:with:`, `perform:withArguments:`); records copied through accessor selectors, with `respondsTo:` |

No shims: `RealWorld.st` runs unchanged on both, with the harness's platform files (`awfy/Samaltak.st`, `awfy/Pharo.st`) as for AWFY. Two Pharo 12 differences are avoided by selectors both have: `Character>>asInteger` (Pharo 12 has no `Character>>value`; `Object>>value` answers the Character) and `printStringBase:` (no `Integer>>printString:`). Pharo prints Floats from 10^6 on as `1.0e6`, Samaltak as `1000000.0`; PrintParse's Floats stay below 10^6. CLBG fannkuch-redux is left out: Array and SmallInteger code only, as AWFY's Permute.

Steady state (median of the last half of 30 iterations) and first iteration, ms, median of 3 invocations interleaved `opt`, `baseline`, Pharo 12 (`vm/tests/bench/results/{samaltak-opt,samaltak-baseline,pharo12-cog}-realworld-2026-11-07-*.csv`; `baseline`'s second invocation run again: swapping had slowed half of its PrintParse iterations tenfold), 1-minute load at most 3 before each invocation, M2 Max.

| benchmark | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo | first `baseline` / Pharo |
|---|---|---|---|---|---|---|---|---|---|---|
| BinaryTrees | 270.2 | 474.4 | 597.0 | 0.45 | 0.79 | 265.1 | 462.8 | 655.3 | 0.40 | 0.71 |
| Fasta | 406.0 | 468.8 | 565.7 | 0.72 | 0.83 | 418.4 | 469.8 | 604.5 | 0.69 | 0.78 |
| KNucleotide | 459.9 | 551.2 | 908.3 | 0.51 | 0.61 | 480.7 | 540.9 | 1598.8 | 0.30 | 0.34 |
| ReverseComplement | 253.8 | 400.9 | 724.4 | 0.35 | 0.55 | 269.0 | 405.0 | 449.0 | 0.60 | 0.90 |
| SpectralNorm | 405.6 | 589.4 | 731.4 | 0.55 | 0.81 | 409.6 | 590.7 | 732.8 | 0.56 | 0.81 |
| Pidigits | 527.2 | 498.6 | 1102.3 | 0.48 | 0.45 | 537.8 | 529.5 | 1469.2 | 0.37 | 0.36 |
| Strings | 258.0 | 322.5 | 695.2 | 0.37 | 0.46 | 271.6 | 321.9 | 806.3 | 0.34 | 0.40 |
| Dictionaries | 312.2 | 426.1 | 981.1 | 0.32 | 0.43 | 539.2 | 721.0 | 2016.8 | 0.27 | 0.36 |
| OrderedCollections | 187.3 | 218.6 | 678.8 | 0.28 | 0.32 | 203.7 | 231.6 | 771.7 | 0.26 | 0.30 |
| Sorting | 590.6 | 657.5 | 849.3 | 0.70 | 0.77 | 601.0 | 648.2 | 870.6 | 0.69 | 0.74 |
| Enumeration | 204.4 | 328.8 | 525.3 | 0.39 | 0.63 | 288.2 | 360.0 | 561.4 | 0.51 | 0.64 |
| PrintParse | 495.1 | 740.4 | 868.0 | 0.57 | 0.85 | 536.2 | 749.2 | 879.1 | 0.61 | 0.85 |
| Exceptions | 460.3 | 494.9 | 732.5 | 0.63 | 0.68 | 471.6 | 497.9 | 971.2 | 0.49 | 0.51 |
| Megamorphic | 106.6 | 106.1 | 704.3 | 0.15 | 0.15 | 114.8 | 106.9 | 710.7 | 0.16 | 0.15 |
| DeepRecursion | 251.9 | 285.2 | 785.6 | 0.32 | 0.36 | 263.4 | 297.7 | 1111.9 | 0.24 | 0.27 |
| Perform | 263.4 | 310.9 | 804.3 | 0.33 | 0.39 | 265.8 | 311.7 | 763.9 | 0.35 | 0.41 |
| geometric mean | | | | 0.41 | 0.52 | | | | 0.39 | 0.48 |

`opt` takes 0.41 of Pharo 12's time (first iterations 0.39), `baseline` 0.52 (0.48). Both win all 16, `opt` Sorting by the least (0.70), `baseline` PrintParse (0.85). Part of the margin is GC: per iteration Pharo spends 430 ms in full GCs on ReverseComplement (its 10 MB Strings; Samaltak 10 ms), 552 ms in GC on DeepRecursion (56 ms), 261 ms on BinaryTrees (54 ms) and 282 ms scavenging on Pidigits (under 1 ms).

Pidigits is LargeInteger arithmetic in C. Its iterations take about 495 or about 528 ms, under either tier, switching within a run; `opt`'s invocations happened to spend more of their last 15 iterations at 528 (median 527 against `baseline`'s 499). Megamorphic ties (106.6 and 106.1 ms): every send is megamorphic, so `opt` inlines nothing.

## Against C

Basic C versions of the eight Shootout (CLBG) programs the suites run (`vm/tests/bench/clbg/*.c`: the six above and AWFY's Mandelbrot and NBody) do the Smalltalk versions' work, same sizes, same algorithm, same checksum: `malloc`/`free` per node in binary-trees, GMP in pidigits, a growing buffer where Smalltalk has a WriteStream, an open-addressing hash table of positions in k-nucleotide; inputs made before timing, as the benchmarks' `initialize`. `vm/tests/bench/clbg.sh [-n 10] [-o file] [program ...]` builds them with `cc -O2` and prints what `awfy.sh` prints. On the x86-64 machine above (gcc 12, CPU time, median of 3 invocations of 10 iterations, `vm/tests/bench/results/c-gcc-O2-x86-2026-11-15-*.csv`), against the Samaltak and Pharo 12 medians of the x86-64 tables:

| program | C | `opt` | `baseline` | Pharo 12 | `opt` / C | `baseline` / C | Pharo / C |
|---|---|---|---|---|---|---|---|
| BinaryTrees | 649.0 | 421.3 | 720.4 | 925.5 | 0.6 | 1.1 | 1.4 |
| Fasta | 162.6 | 538.1 | 701.0 | 742.2 | 3.3 | 4.3 | 4.6 |
| KNucleotide | 65.1 | 623.5 | 784.1 | 1210.7 | 9.6 | 12.0 | 18.6 |
| ReverseComplement | 27.0 | 446.0 | 689.8 | 1235.0 | 16.5 | 25.5 | 45.7 |
| SpectralNorm | 56.2 | 729.1 | 845.6 | 1008.9 | 13.0 | 15.1 | 18.0 |
| Pidigits | 131.0 | 427.3 | 436.2 | 1579.0 | 3.3 | 3.3 | 12.1 |
| Mandelbrot | 43.0 | 148.1 | 199.7 | 300.3 | 3.4 | 4.6 | 7.0 |
| NBody | 33.0 | 224.2 | 503.9 | 517.4 | 6.8 | 15.3 | 15.7 |

`opt` beats the C binary-trees: allocating from eden and scavenging costs less than `malloc` and `free`. At the benchmarks game's size (depth 21: 611 M nodes, `-DMAX_DEPTH=21 -DEXPECTED=611669342`, `BinaryTrees new run: 21 liveDepth: 20`) an iteration takes `opt` 13.4 s, 5.1 of them in 1149 scavenges and 26 full GCs; Pharo 12 23.5 s, 13.5 in its GCs; C 16.4 s.

The listings of the optimized SpectralNorm and Fasta loops show where the rest goes. A Float result is encoded as a SmallFloat64 after every operation (about 15 instructions), even where the next operation takes the double from its register. In a method whose arithmetic saw Floats, SmallInteger operations get a Float path too, loop counters included (`j + 1`, `i + j - 2`, `last * 3877 + 29573 \\ 139968`): tag checks on every operand. Comparisons with a Float path make `true` or `false` and test it instead of branching on the flags. Loop variables come from their frame slots at every use.

## Compile speed

How fast each JIT compiles the same code (`vm/tests/bench/compile-speed.sh`, `vm/tests/bench/results/compile-speed-2026-11-08.csv`; M2 Max, a fresh VM process per round, 1-minute load ≤ 3). Corpus: the 630 methods of the AWFY benchmark classes (`Core` and the 14 benchmarks), identical sources, each behind an early exit, `probeNil ifNil: [^0]. <the body>` (`compile_speed.py gen`): sent with nil it runs in O(1), while the JIT compiles every bytecode. The table is the 591 methods with no real block on either system, 30 rounds: Pharo's CompiledBlocks are compiled when they run, which here they do not. Bytes and instructions are each system's own bytecode. `opt` runs with `--jit-flags eager` and inlines only where a receiver's class is known statically (32 % more bytecode than the methods'; 57 of 593 units).

| | µs / method | µs / bytecode byte | µs / instruction | machine-code bytes / bytecode byte |
|---|---|---|---|---|
| `baseline` | 3.08 | 0.118 | 0.158 | 32.3 |
| Pharo 12 Cog | 3.26 | 0.133 | 0.140 | 20.7 |
| `opt`, no feedback | 18.6 | 0.71 | 0.95 | 35.0 |

`baseline` compiles as fast as Cog: 3.28 against 3.33 µs a method by the wall clock of the compiling send, 6 % less per method and 11 % less per bytecode byte by the counters (Cog's counts whole milliseconds), 13 % more per instruction (Samaltak has fewer, bigger instructions for the same source), and it emits 1.6× the machine code. Over all 630 methods: 3.46 against 3.63 µs a method. With real feedback (AWFY, default thresholds, 30 iterations, median of 3, `results/samaltak-opt-compile-2026-11-08-*.csv`) `opt` takes 170 ms for 507 units (methods, blocks, loops), 336 µs a unit: 56 bytecode bytes of its own and 330 inlined (a scratch VM build counted what the SSA builder translated, `results/compile-speed-2026-11-08-opt-units.txt`), so 6.0 µs per byte of the unit, 0.87 µs per byte with the inlined ones (about 7× `baseline`), 6.1 KB of machine code a unit, 16 bytes per byte with the inlined ones. Share of the AWFY first iteration (14 benchmarks, 5 rounds, the VMs' counters): `baseline` 3.3 of 1082 ms (0.3 %), Cog 4.0 of 1765 ms (0.2 %), `opt` 128 of 665 ms (19 %; DeltaBlue 72 %, Json 69 %).

Method. Samaltak: its counters around the compiler (`jitCompileMicroseconds`, `optCompileMicroseconds`). Cog: Pharo 12's own, `Smalltalk vm parameterAt:` 75–78 (methods and blocks, microseconds summed around `cogselector` and `cogFullBlockMethodnumCopied`, reported in whole milliseconds, so the mean of the rounds), with a 32 MB code zone (`--codeSize`) so that nothing compacts; the default 1.25 MB zone does. Probes are sent six times from interpreted drivers (Cog compiles at the second send, `baseline` and `opt` at the third). Two independent checks: the compiling send's wall clock, its time minus the last sends': Cog 3.33 µs a method against its counter's 3.26, `baseline` 3.28 against 3.08 (the send path and installing the code are outside its counter), `opt` 24.2 against 22.0 by its two compilers; native sampling (`sample`, 1 ms, thousands of rounds in one process, code dropped between rounds): `cogselector` 28.6 % of the samples against 28.3 % of the run by the counter, `jit_runtime_compile` 75.2 against 70.4 % (the counter leaves out its clock reads). These methods compile in a row; one at a time in the AWFY runs, with tier-up counters under `opt`, the lower tier took 4.3 µs a method, 0.20 µs per bytecode byte.

    vm/tests/bench/compile-speed.sh [corpus|awfy|all] [-n 30] [-a 5] [-o results.csv]   # needs vm/build/samaltak, build/samaltak.image and Pharo 14 ($PHARO_VM, $PHARO_IMAGE)
