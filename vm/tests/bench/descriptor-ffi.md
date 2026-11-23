# Headless descriptor-FFI microbenchmark

Use separately built, **platform-capable** VMs and their matching full images, with the same build options. On Linux with SDL3, OpenSSL and shaderc installed:

```sh
# If there is no pinned base already:
git worktree add --detach /tmp/samaltak-ffi-base <base-revision>
make -C /tmp/samaltak-ffi-base -j2 CC=cc NO_PGO=1 image
# Build the branch the same way after translating its VM sources.

taskset -c 0 python3 vm/tests/bench/descriptor-ffi.py \
  /tmp/samaltak-ffi-base/vm/build/samaltak /tmp/samaltak-ffi-base/build/samaltak.image \
  vm/build/samaltak build/samaltak.image \
  --jit none opt --runs 7 --warmup 20000 --iterations 100000 \
  > /tmp/descriptor-ffi.csv 2> /tmp/descriptor-ffi-summary.txt
```

Choose a CPU from your current affinity list; omit `taskset` if unavailable. Runs use a 16 MiB eden. `--jit opt` uses default thresholds (method 2, OSR 50, optimizing 1000), a 64 MiB JIT cache and default flags; `--jit none` disables method JIT, not FFI adapters. The runner alternates base/branch order and starts a VM for each case. Every invocation uses `--headless`, removes display endpoints from the environment, and selects a nonexistent SDL video driver.

- **scale / ime**: migrated GPU facade with handle `-1`, which the real platform target rejects before touching SDL video. Includes the GPUError path. This does **not** measure successful window operations.
- **close**: migrated PTY facade on a real terminal after its child has exited and been reaped. First call only; spawning and waiting are outside the timer.
- **foreground / resize**: direct primitives on base vs explicit descriptor calls on branch. Default facade calls use direct primitives for these two operations. Both paths use a real PTY after its child reports readiness; resize requests its current dimensions. The first explicit call includes bind; steady calls reuse the binding and argument Array.
- **dynamic** (branch only): grant one locally built `int32_t bench_add(int32_t, int32_t)`. Measure first bind and first invoke independently, repeated public bind, and invoke with one binding using either a reused argument Array or a newly allocated one. Startup (including `dlopen`) is outside these measurements.
- **control**: same timing and loop with no native operation. It is not subtracted.

After timing scale, IME, or close, the branch process replaces that case’s legacy fallback with a failing method and checks the facade again. This detects an unavailable FFI path. The process never saves its image.

`first` rows are a **single** facade call in a fresh process, not startup time; the branch can bind a descriptor and publish a native stub in that call. First-use timings include any first-call Smalltalk/JIT overhead and have microsecond resolution. `steady` rows are timed loops after warmup; results include dispatch, GC, and scheduling, not just native call time. Allocation is the delta in VM-managed bytes allocated over the loop (including counter overhead), not retained heap, native allocation or executable pages. `-1` bytes means allocation was not sampled. The summary reports medians and observed min/max ranges in ns/call.

No batch downcall is used by these operations.

## Measured example

Linux x86-64 (AMD EPYC 7B13), pinned to logical CPU 0; platform GCC 12.2
builds (`-O2 -g -flto=auto`, no PGO, SDL 3.2.24). Seven fresh processes per
case and tree, 20,000 warmup and 100,000 timed calls per steady phase. Base
was the bootstrap shepherd's independent `99cfe6d` VM/image. Candidate
was the immutable hosted trial `089283d83fae` (source fingerprint, based on
`e9420de` plus working-tree fixes), not the subsequent external-callback build.
Other work was running on the host, so these are medians of wall-clock samples,
not a precise estimate of intrinsic stub cost.

| Case | JIT | First base → FFI (µs) | Steady base → FFI (µs/call) | VM allocation base → FFI (B/call) |
|---|---|---:|---:|---:|
| Scale, missing window | none | 60 → 132 | 7.68 → 10.55 | 1044 → 1686 |
| IME, missing window | none | 61 → 135 | 8.29 → 11.25 | 1044 → 1799 |
| PTY close | none | 145 → 334 | — | — |
| PTY foreground, explicit binding | none | 6 → 97 | 3.85 → 5.44 | <1 → <1 |
| PTY resize, explicit binding | none | 7 → 92 | 3.92 → 5.16 | <1 → <1 |
| Scale, missing window | opt | 117 → 1733 | 9.88 → 11.27 | 1044 → 1492 |
| IME, missing window | opt | 116 → 341 | 9.46 → 11.64 | 1044 → 1605 |
| PTY close | opt | 263 → 625 | — | — |
| PTY foreground, explicit binding | opt | 13 → 132 | 4.75 → 5.56 | <1 → <1 |
| PTY resize, explicit binding | opt | 10 → 150 | 4.69 → 5.61 | <1 → <1 |

The opt cold scale samples on the branch ranged from 291 to 11,441 µs.
A separate nine-run sample on the earlier `4380a31967ea` trial put that
median at 338 µs. Control was 211 → 245 ns/call in none and 14 → 58 ns/call
in opt. The window miss paths include exception costs and do not predict costs
on live windows.

| Dynamic phase | JIT none median | JIT opt median | VM allocation (none / opt) |
|---|---:|---:|---:|
| First bind | 26 µs | 79 µs | — |
| First invoke | 33 µs | 38 µs | — |
| Warm invoke, reused arguments | 1.17 µs | 0.93 µs | <1 / <1 B |
| Warm invoke, fresh arguments | 1.27 µs | 1.00 µs | 32 / 32 B |
| Repeated bind | 10.95 µs | 2.99 µs | 141 / 137 B |

In a separate nine-run, 200,000-iteration opt sample on the same binary,
warm dynamic invoke was 307 ns with reused args (292–323 ns) and 336 ns with
fresh args (325–353 ns), with the same allocation. Reuse the binding and
argument storage when measuring a hot loop; rebinding and facade error handling
are separate costs.
