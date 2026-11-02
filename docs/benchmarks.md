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

Defaults: 30 iterations; inner iterations (`inner()` in `awfy.sh`) such that a steady-state iteration takes about 100 ms on the interpreter. CD (100 aircraft, 350 ms), Havlak (1, 700 ms), Mandelbrot (500, 500 ms) and NBody (250000 steps, 750 ms) run at the smallest non-trivial size upstream verifies. `--suite all` takes 2 minutes on the interpreter.

Changes from upstream (the Smalltalk variant, SOM class syntax with Pharo method bodies): class files converted to chunk format, class-side fields as class variables (as upstream's Pharo loader); `Scheduler` (Richards) and `Simulator` (CD) renamed `RBScheduler` and `CDSimulator`, Samaltak has those globals; Json's `isTrue || isFalse` (unused) written `isTrue | isFalse`; the harness prints CSV and VM statistics and does not exit; `awfy/Samaltak.st` adds the Pharo methods `Integer>>&` and `Number>>%`.

Steady state, ms, median of 3 invocations (`vm/tests/bench/results/samaltak-{none,baseline,opt}-2026-10-28-*.csv`, `pharo12-cog-2026-10-28-*.csv`), M2 Max:

| benchmark | Samaltak `--jit none` (interpreter) | `--jit baseline` | `--jit opt` | Pharo 12 (Cog JIT) |
|---|---|---|---|---|
| Bounce | 104.2 | 22.2 | 11.0 | 32.0 |
| CD | 354.6 | 86.7 | 48.6 | 196.3 |
| DeltaBlue | 106.3 | 29.4 | 12.6 | 40.0 |
| Havlak | 698.8 | 227.8 | 73.9 | 337.1 |
| Json | 92.7 | 38.9 | 8.7 | 54.8 |
| List | 126.0 | 17.0 | 11.7 | 23.4 |
| Mandelbrot | 499.5 | 193.3 | 115.5 | 338.9 |
| NBody | 746.3 | 327.6 | 141.3 | 333.6 |
| Permute | 110.1 | 21.0 | 13.5 | 32.8 |
| Queens | 106.8 | 20.6 | 12.4 | 41.8 |
| Richards | 97.8 | 17.0 | 9.5 | 22.3 |
| Sieve | 93.2 | 34.6 | 21.9 | 54.1 |
| Storage | 111.4 | 35.3 | 24.1 | 52.9 |
| Towers | 91.2 | 13.6 | 7.8 | 16.4 |

## Real-world workloads

AWFY brings its own collections (`Vector`, `SomDictionary`, `SomSet` in `awfy/Core.st`), so it measures the compiler and VM, not the class library, its primitives or the GC at scale. These 16 workloads (`awfy/RealWorld.st`, `--suite realworld`, not part of `all`) are written once against each system's own class library; Pharo 12 runs the same source. Each answers a checksum that `verifyResult:` compares with one constant for both systems; at small sizes all 16 also answer the same on both. Sizes give 0.45–1 s per iteration on Pharo 12; an invocation takes 7 minutes under `opt`, 8.5 under `baseline`, 6 on Pharo.

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

Steady state (median of the last half of 30 iterations) and first iteration, ms, median of 3 invocations interleaved `opt`, `baseline`, Pharo 12 (`vm/tests/bench/results/{samaltak-opt,samaltak-baseline,pharo12-cog}-realworld-2026-10-28-*.csv`; `opt`'s third and Pharo's second invocation rerun on 2026-11-01, their 1-minute load had passed 5), M2 Max. 1-minute load during the runs 2.0–4.5, median 3.2 (a run adds about 1); no other VM running.

| workload | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo |
|---|---|---|---|---|---|---|---|---|
| BinaryTrees | 276 | 453 | 544 | 0.51 | 261 | 443 | 1225 | 0.21 |
| Fasta | 403 | 557 | 540 | 0.75 | 406 | 551 | 556 | 0.73 |
| KNucleotide | 300 | 406 | 711 | 0.42 | 309 | 400 | 1185 | 0.26 |
| ReverseComplement | 260 | 482 | 670 | 0.39 | 272 | 492 | 426 | 0.64 |
| SpectralNorm | 420 | 590 | 701 | 0.60 | 423 | 592 | 710 | 0.60 |
| Pidigits | 4601 | 4353 | 937 | 4.91 | 4634 | 4363 | 1237 | 3.75 |
| Strings | 470 | 1033 | 662 | 0.71 | 494 | 1030 | 731 | 0.68 |
| Dictionaries | 283 | 386 | 866 | 0.33 | 324 | 421 | 1136 | 0.29 |
| OrderedCollections | 210 | 245 | 636 | 0.33 | 223 | 242 | 693 | 0.32 |
| Sorting | 1232 | 2879 | 689 | 1.79 | 1236 | 2880 | 693 | 1.78 |
| Enumeration | 205 | 362 | 500 | 0.41 | 231 | 362 | 539 | 0.43 |
| PrintParse | 620 | 903 | 857 | 0.72 | 685 | 905 | 864 | 0.79 |
| Exceptions | 2199 | 1816 | 683 | 3.22 | 2204 | 1823 | 687 | 3.21 |
| Megamorphic | 110 | 99.5 | 681 | 0.16 | 116 | 101 | 691 | 0.17 |
| DeepRecursion | 339 | 274 | 681 | 0.50 | 337 | 284 | 870 | 0.39 |
| Perform | 1954 | 2086 | 703 | 2.78 | 1969 | 2082 | 688 | 2.86 |
| geometric mean | | | | 0.72 | | | | 0.66 |

`opt` takes 0.72 of Pharo 12's time (first iterations 0.66), `baseline` 0.96 (0.86); on AWFY 0.34 and 0.67. `opt` wins 12 of 16. Part of the margin is GC: per iteration Pharo spends 373 ms in full GCs on ReverseComplement (its 10 MB Strings; Samaltak 13 ms), 466 ms in GC on DeepRecursion (59 ms), 221 ms on BinaryTrees (53 ms) and 259 ms scavenging on Pidigits (4 ms).

Losses, from `Profiler from:to:` over 3 steady iterations under `opt` and the VM statistics per iteration. The profiles are taken with allocation sampling off (`Profiler default allocationInterval: 0`): with it on, a CPU tick due at an allocation sample is recorded at the allocating send, so allocation-heavy code shows up in `Behavior>>new:`.

- **Pidigits** (4.9× in the table, measured when LargeInteger arithmetic was Smalltalk: 5.7 GB allocated per iteration, most of it by `//` converting its operands to Arrays of 24-bit limbs). It is VM primitives now, as Pharo's LargeIntegersPlugin (LargeIntegerPrimitives: 32-bit limbs, schoolbook multiplication, Knuth's algorithm D): 457 ms under `opt`, 465 under `baseline`, Pharo 12 916 (0.50×; 30 iterations, 3 invocations each interleaved with the code before, 4579 ms; `vm/tests/bench/results/*-primitives-2026-11-02-*.csv`, `samaltak-opt-before-largeint-2026-11-02-*.csv`, 2026-11-02). 1.2 GB allocated per iteration, Pharo 2.8 GB. MicroFactorial: 1.6 ms, Pharo 7.1 (0.23×), before 5.8.
- **Exceptions** (3.2× in the table, measured when `signal`'s `thisContext` flushed the stack's frames into Contexts, 3.1M flushes per iteration, and the handler search and the unwinding walked the sender chain in Smalltalk; `opt` deoptimized once per loop iteration). Contexts are now views of their frames (implementation.md, Method execution) and the walks are primitives (195–197), as in Pharo 12: 457 ms under `opt`, 482 under `baseline`, Pharo 12 673 (0.68×; 30 iterations, 3 invocations each, `vm/tests/bench/results/*-contexts-2026-11-02-*.csv`, 2026-11-02). A signal and `return:`: 0.6 µs, Pharo 1.4 µs. Only `retry` still flushes (`restart` stores into the Context): 18 % of `opt`'s time.
- **Perform** (2.8× in the table, measured when every `perform:` missed its inline cache and went through the runtime and the interpreter: 58 ns per `perform:`, `baseline` 55). The perform methods' primitive is machine code now (docs/jit.md, Baseline): 285 ms under `opt`, 337 under `baseline`, Pharo 12 693 (0.41×; 30 iterations, 3 invocations each interleaved with the code before, `vm/tests/bench/results/*-perform*-2026-11-01-*.csv`, 2026-11-01). A loop of `perform:` of a selector from a variable: 2.8 ns per iteration under `opt`, 2.3 under `baseline` (a send: 2.2), Pharo 2.4.
- **Sorting** (1.8× in the table, measured when `String>>caseInsensitiveLessOrEqual:` compared two lowercase copies: 234 ns per comparison, Pharo 23 ns, a primitive with a case-insensitive order table). It now compares in place, byte strings in a primitive (`stringCaseInsensitiveCompare`; `caseInsensitiveLessOrEqual:` in a loop 17 ns, before 46): 500 ms under `opt`, Pharo 12 683 (0.73×; 30 iterations, 3 invocations each interleaved with the code before, 539 ms; `*-primitives-2026-11-02-*.csv`, `samaltak-opt-before-stringprim-2026-11-02-*.csv`, 2026-11-02).

`opt` is also slower than `baseline` on Megamorphic (11 %); not investigated. On DeepRecursion (24 % in the table) `opt` called `getenv` for each optimized frame it flushed: now 252 ms, `baseline` 275, Pharo 12 688 (the files above).
