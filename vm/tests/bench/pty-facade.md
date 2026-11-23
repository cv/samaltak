# Headless legacy PTY facade attribution

On Linux with SDL3, OpenSSL and shaderc installed, build the platform VM and
matching image from a clean checkout, then run:

```sh
make -j2 CC=cc NO_PGO=1 image
vm/tests/bench/pty-facade.py > /tmp/pty-facade.csv 2> /tmp/pty-facade.txt
```

The runner pins itself and its children to CPU 0 (`--cpu` overrides it).
Keep the CPU and its SMT sibling idle. It prints artifact hashes, medians,
min/max ranges and per-round ratios to direct. CSV includes warmup and
discarded batches; use only `phase=steady` for the medians. Pair by JIT, op
and round. One VM and one real PTY per JIT mode; no video, saved images, or
timed process startup. The child is ready and blocked on input. Constant
resize uses the PTY's existing dimensions.

The driver reconstructs the facade from the bundled reference fixture
(extracted from `d124cd9^`) in memory; no Git history is needed. The direct
rows use the image's `legacyForeground:` and `legacyResize:rows:columns:`;
the driver checks their primitive names. The facade rows use a private
benchmark binding over `ffiBind`/`ffiInvoke` to retain the old Array/word
bridge. The production `primForeground:` and `primResize:rows:columns:`
wrappers are not replaced or timed here; use `wrapped-ffi.py` for those.
Each variant uses the same loop, caller block shape and one outer send to
the PTY class. FFI ablations retain a helper send with the same arity.
Control is not subtracted.

| Variant | What runs |
|---|---|
| control | A method returning a constant or existing object without native code |
| direct | The current legacy primitive |
| prebound_reused | Cached binding and reused argument Array; no lookup or handler |
| prebound_fresh | As above, with a new argument Array on every call |
| lookup | Fresh arguments and the original `bindingFor:` cache hit |
| on_do | Lookup plus the historical `on:do:`; pass nil instead of a fallback block |
| original | Full historical path, including constructing the (unused) nonlocal-return fallback block |
| forced_fallback | Same path, but an invalid argument is rejected before native entry; the fallback calls the legacy primitive with the valid tuple |

Descriptor bindings, including each method's literal identity, are populated
before measurement. The original is also invoked with its legacy fallback
trapped to rule out silently measuring fallback. Each variant/op receives
four interleaved warmup batches and one full-size discarded batch before
steady timing. Steady orders balance slot position and pair order across
rounds. Times include execution, GC and scheduling; bytes count VM-managed
allocations, including counter overhead, not retained memory or native pages.
Deltas are not guaranteed additive: JIT optimization and collection may
change between variants.

## Candidate

The bundled fixture caches a legacy binding per site and uses its
non-signaling `tryInvoke:` with either fresh arguments (`--candidate fresh`)
or last-tuple memoization (`--candidate memo`). The image is not saved.

```sh
vm/tests/bench/pty-facade.py --candidate fresh > /tmp/pty-fresh.csv 2> /tmp/pty-fresh.txt
vm/tests/bench/pty-facade.py --candidate memo --vary-resize --rounds 12 --iterations 50000 \
  > /tmp/pty-memo-varied.csv 2> /tmp/pty-memo-varied.txt
```

The separate `--vary-resize` case alternates 24×80 and 25×81 on the same PTY,
checking both writes with the child's `stty size` before timing. Timing
includes the kernel's resize notification work; compare only within this
case. For a custom method-only fixture use `--candidate-file` and
`--candidate-selectors`. Candidate methods should fall back to
`legacyForeground:` and `legacyResize:rows:columns:`. Preflight traps these
selectors to detect silent fallback on valid arguments, then restores the
original methods before timing.

## Historical measurements

Linux x86-64 (AMD EPYC 7B13), pinned to CPU 0. Platform GCC build at
`7492e2a`; one candidate image (with the fresh binding path filed in) for
all variants in each JIT mode. The constant-size run used 18 rounds of
100,000 calls per variant/op; each had 40,000 interleaved warmup calls and
one discarded full batch. Times are median µs/call; the value after the
slash is median VM B/call.

| Variant | Opt foreground | Opt resize | Interpreter foreground | Interpreter resize |
|---|---:|---:|---:|---:|
| Control | 0.018 / 0.02 | 0.019 / 0.02 | 0.099 / 0.06 | 0.100 / 0.06 |
| Direct | 1.069 / 0.22 | 1.064 / 0.22 | 1.066 / 0.44 | 1.056 / 0.43 |
| Prebound, reused args | 1.207 / 0.24 | 1.222 / 0.24 | 1.338 / 0.58 | 1.324 / 0.58 |
| Prebound, fresh args | 1.211 / 24.26 | 1.207 / 40.27 | 1.345 / 24.67 | 1.518 / 40.79 |
| Cached lookup | 1.286 / 24.28 | 1.309 / 40.30 | 1.673 / 217.59 | 1.925 / 233.90 |
| `on:do:` | 1.475 / 265.00 | 1.511 / 281.09 | 1.780 / 458.64 | 1.806 / 474.59 |
| Full original | 1.577 / 449.28 | 1.591 / 489.40 | 1.893 / 642.53 | 1.863 / 682.60 |
| Forced fallback | 4.440 / 2913.80 | 4.375 / 2979.51 | 4.315 / 1803.15 | 4.320 / 1867.05 |
| Fixed, fresh args | 1.261 / 24.28 | 1.255 / 40.30 | 1.572 / 24.76 | 1.603 / 40.83 |

| Mode / operation | Original / direct | Fixed / direct | Fixed / original |
|---|---:|---:|---:|
| Opt foreground | 1.465× | 1.182× [0.959–1.220] | 0.800× |
| Opt resize | 1.487× | 1.176× [0.923–1.230] | 0.788× |
| Interpreter foreground | 1.775× | 1.273× [1.196–1.843] | 0.718× |
| Interpreter resize | 1.733× | 1.296× [1.245–1.857] | 0.743× |

Ratios are calculated within each round, then summarized by median, with
observed ranges shown for fixed/direct. In opt, adding the handler costs
about 0.2 µs and 241 B/call at the median, and constructing the fallback block
adds another 184–208 B/call. Fresh argument arrays account for 24–40 B.
The fixed facade cuts optimized time by about a fifth and most allocation
relative to original, but stays about 18% slower than direct.

The alternate-size runs used 12 paired rounds of 50,000 calls. Each
candidate has its own same-VM direct control:

| Mode / candidate | Direct (µs / B) | Candidate (µs / B) | Candidate / direct |
|---|---:|---:|---:|
| Opt fresh | 1.304 / 0.27 | 1.535 / 40.36 | 1.179× [1.151–1.226] |
| Opt memo | 1.329 / 0.27 | 1.563 / 40.36 | 1.174× [1.088–1.239] |
| Interpreter fresh | 1.305 / 0.52 | 1.636 / 41.18 | 1.249× [1.207–1.431] |
| Interpreter memo | 1.332 / 0.54 | 1.726 / 41.29 | 1.307× [1.262–1.359] |

The historical and fixed success paths passed with their legacy fallback
methods temporarily replaced by unconditional errors; only then were the
real methods restored for timing. The forced-fallback path separately
proved FFI rejected its invalid handle before native entry. The alternating
case checked both actual slave dimensions, not just the return value.
