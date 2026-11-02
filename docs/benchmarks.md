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
    vm/tests/bench/awfy.sh --pharo ...                  # $PHARO_VM, $PHARO_IMAGE (default ~/.cache/pharo12)
    vm/tests/bench/awfy.sh --summary results/*.csv      # median over invocations

Output: `benchmark,iteration,microseconds` per iteration; `# stats` lines with the VM statistics delta over all iterations (every counter the VM answers, unnamed ones as `counterN`); a summary of first iteration, steady state (median of the last half) and total. `-o` saves all of it.

Defaults: 30 iterations; inner iterations (`inner()` in `awfy.sh`) such that a steady-state iteration takes about 100 ms on the interpreter. CD (100 aircraft, 330 ms), Havlak (1, 710 ms), Mandelbrot (500, 500 ms) and NBody (250000 steps, 750 ms) run at the smallest non-trivial size upstream verifies. `--suite all` takes 2 minutes on the interpreter.

Changes from upstream (the Smalltalk variant, SOM class syntax with Pharo method bodies): class files converted to chunk format, class-side fields as class variables (as upstream's Pharo loader); `Scheduler` (Richards) and `Simulator` (CD) renamed `RBScheduler` and `CDSimulator`, Samaltak has those globals; Json's `isTrue || isFalse` (unused) written `isTrue | isFalse`; the harness prints CSV and VM statistics and does not exit; `awfy/Samaltak.st` adds the Pharo methods `Integer>>&` and `Number>>%`.

Steady state, ms, median of 3 invocations (`vm/tests/bench/results/samaltak-{none,baseline,opt}-2026-11-02-*.csv`, `pharo12-cog-2026-11-02-*.csv`; `baseline`'s DeltaBlue, Havlak, Json, Mandelbrot and Sieve `samaltak-baseline-2026-11-02b-*.csv`, interleaved with `samaltak-baseline-before-2026-11-02b-*.csv`, 1-minute load 2.5–3), M2 Max:

| benchmark | Samaltak `--jit none` (interpreter) | `--jit baseline` | `--jit opt` | Pharo 12 (Cog JIT) |
|---|---|---|---|---|
| Bounce | 110.1 | 22.3 | 10.9 | 31.4 |
| CD | 329.1 | 84.2 | 47.6 | 189.2 |
| DeltaBlue | 102.1 | 27.1 | 12.7 | 39.5 |
| Havlak | 709.8 | 203.6 | 75.0 | 355.3 |
| Json | 92.0 | 33.5 | 8.8 | 54.9 |
| List | 119.4 | 17.0 | 11.9 | 23.4 |
| Mandelbrot | 505.5 | 189.0 | 113.1 | 343.1 |
| NBody | 752.2 | 318.4 | 137.3 | 334.0 |
| Permute | 109.8 | 21.2 | 13.6 | 33.2 |
| Queens | 113.2 | 20.8 | 12.5 | 42.2 |
| Richards | 102.9 | 17.5 | 9.5 | 22.3 |
| Sieve | 99.8 | 32.3 | 21.9 | 54.4 |
| Storage | 116.7 | 35.4 | 21.5 | 52.9 |
| Towers | 89.8 | 13.8 | 7.8 | 16.5 |

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

Steady state (median of the last half of 30 iterations) and first iteration, ms, median of 3 invocations interleaved `opt`, `baseline`, Pharo 12 (`vm/tests/bench/results/{samaltak-opt,samaltak-baseline,pharo12-cog}-realworld-2026-11-02-*.csv`; Pharo's second invocation rerun, its 1-minute load had passed 5), M2 Max. 1-minute load during the runs 2.2–4.9, median 3.2 (a run adds about 1); no other VM running. KNucleotide, Strings, Dictionaries, OrderedCollections, Enumeration, Exceptions, Megamorphic and Perform: `samaltak-{opt,baseline}-realworld-2026-11-02b-*.csv`, interleaved with `samaltak-{opt,baseline}-realworld-before-2026-11-02b-*.csv`, 1-minute load at most 3 before each invocation.

| workload | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo |
|---|---|---|---|---|---|---|---|---|
| BinaryTrees | 270 | 448 | 558 | 0.48 | 258 | 444 | 611 | 0.42 |
| Fasta | 389 | 552 | 543 | 0.72 | 391 | 555 | 560 | 0.70 |
| KNucleotide | 299 | 386 | 714 | 0.42 | 308 | 386 | 1315 | 0.23 |
| ReverseComplement | 258 | 467 | 673 | 0.38 | 271 | 476 | 425 | 0.64 |
| SpectralNorm | 424 | 591 | 715 | 0.59 | 424 | 590 | 714 | 0.59 |
| Pidigits | 459 | 469 | 952 | 0.48 | 464 | 474 | 1237 | 0.37 |
| Strings | 388 | 753 | 665 | 0.58 | 407 | 753 | 729 | 0.56 |
| Dictionaries | 280 | 365 | 864 | 0.32 | 309 | 401 | 1126 | 0.27 |
| OrderedCollections | 191 | 218 | 633 | 0.30 | 198 | 221 | 684 | 0.29 |
| Sorting | 497 | 563 | 683 | 0.73 | 511 | 562 | 685 | 0.75 |
| Enumeration | 203 | 313 | 500 | 0.41 | 229 | 318 | 532 | 0.43 |
| PrintParse | 564 | 806 | 849 | 0.66 | 597 | 807 | 877 | 0.68 |
| Exceptions | 436 | 465 | 676 | 0.65 | 446 | 468 | 691 | 0.64 |
| Megamorphic | 102 | 103 | 682 | 0.15 | 106 | 101 | 688 | 0.15 |
| DeepRecursion | 250 | 271 | 686 | 0.36 | 255 | 272 | 859 | 0.30 |
| Perform | 278 | 323 | 697 | 0.40 | 280 | 324 | 684 | 0.41 |
| geometric mean | | | | 0.45 | | | | 0.43 |

`opt` takes 0.45 of Pharo 12's time (first iterations 0.43), `baseline` 0.59 (0.54); on AWFY 0.34 and 0.65. `opt` wins all 16, Sorting by the least (0.73). Part of the margin is GC: per iteration Pharo spends 379 ms in full GCs on ReverseComplement (its 10 MB Strings; Samaltak 12 ms), 465 ms in GC on DeepRecursion (53 ms), 231 ms on BinaryTrees (49 ms) and 258 ms scavenging on Pidigits (under 1 ms).

Losses, from `Profiler from:to:` over 6 steady iterations and the VM statistics per iteration. The profiles are taken with allocation sampling off (`Profiler default allocationInterval: 0`): with it on, a CPU tick due at an allocation sample is recorded at the allocating send, so allocation-heavy code shows up in `Behavior>>new:`. `opt` loses nowhere; `baseline` on two:

- **Strings** (`baseline` 1.13×, `opt` 0.58×). Case conversion is `collect:` through a WriteStream (`asLowercase` and `asUppercase` 30 % of the samples), and the searches (`copyReplaceAll:with:` 16 %, `substrings:` 13 %, `occurrencesOf:` 6 %) are Smalltalk loops whose `Character>>=` is a send in baseline code (20 % of the samples). Pharo 12 converts case and searches characters and substrings in primitives (MiscPrimitivePlugin). `opt` takes half the time; `Character>>=` is still 12 % of its samples.
- **Fasta** (`baseline` 1.02×, `opt` 0.72×). `WriteStream>>nextPut:` (37 % of the samples) stores each of the 10M characters with a C call of the `streamAt:put:` primitive (10.2M primitive calls per iteration), and the random numbers and the search through the cumulative probabilities (44 %) run as baseline code; `opt` inlines both.

`baseline`'s first iteration of ReverseComplement (1.12×) is Pharo's GC starting late: Pharo's first iteration takes 425 ms, the following ones about 670, 380 of them in 11 full GCs.
