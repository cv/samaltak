# Approved FFI candidate comparisons

Run on a quiet machine with a matching release VM and image. Use a fresh
evidence directory per invocation. Headless file pilot:

```sh
python3 vm/tests/bench/ffi-paired.py \
  --vm vm/build/samaltak --image build/samaltak.image \
  --logs /tmp/ffi-pilot --require-at-par \
  --case file-position-1 --case file-position-4096 --case file-position-1048576 \
  --case file-size-1 --case file-size-4096 --case file-size-1048576 \
  --case float-fraction
```

Without `--case`, run the whole headless suite (including real file I/O,
numerics, redirected UTF-8 streams, loopback sockets and a PTY). Use `--cpu`
on a reserved Linux CPU when available. `--eden` controls GC pressure for both
arms. A separate low-eden run helps expose allocation overhead. The headless
CI job uses `--proof-only`; the display job also captures one non-gating
timing session. Shared CI CPUs are not performance evidence. Display
fixtures require the GitHub Actions X11/Vulkan job and `--display-ci`.
GPU timings measure CPU command encoding, not GPU execution or frame rate.

Each measured pair uses the same VM process, input state, loop shape and
primitive/candidate selectors. The candidate includes the actual facade,
argument adaptation, native call and result adaptation. Both arms are warmed
and adjacent; each fresh process uses randomly ordered, equal numbers of AB
and BA pairs. There is one process per case, mode and session; strata are
shuffled between sessions. No system-wide or per-call selection switch, no
benchmark-only binding in the timed candidate, no patched fallback. For
stream cases both arms write to the same regular-file sink, with a 2 MiB
output budget per arm and exact payload/line-count checks outside timing.

Before timing, isolated proof runs enable `SAMALTAK_FFI_NATIVE_TRACE=1`
on these same selectors and inputs. The registry resolves each reviewed export
to an ABI-identical typed forwarding function in these diagnostic processes;
it logs after the prepared wrapper has accepted its arguments. The direct
control must have zero native entries and the candidate must produce the
exact expected count **for each export**. Proof and timing use separate
processes so instrumentation is not charged to either arm. Binding or
optimized call-site hits alone are not positive native-entry evidence.

`plan.json` records the inputs, host/modes and artifact SHA-256s;
`pairs.csv` keeps every wall/CPU duration and allocation, GC and JIT delta;
`ratios.csv` keeps every candidate/direct ratio. The summary reports the
median of per-process median wall ratios and a nonparametric, sign-based
order-statistic interval over the fresh process medians. This avoids
treating multiple pairs within one VM as independent; independence of
sessions still requires quiet, repeated measurements. The intervals use a
Bonferroni adjustment over selected cases and all three JIT modes and
allow each arm ±1 µs for timestamp quantization. The summary also shows AB/BA medians (inspect for carryover), CPU ratios and
allocation/GC deltas. Increase `--calls` if batches are too short, and
repeat on representative release hosts.

At-par requires the simultaneous upper bound to be **≤ 1.0** in every
required stratum; a lower bound > 1.0 shows a slowdown. Everything else
(including insufficient samples) is inconclusive and blocks
`--require-at-par`. A pass is necessary, not sufficient: check semantics,
backend coverage, independent confirmation and a representative user workload
before proposing a default. A raw bound-call benchmark cannot qualify a route.

## Owned arithmetic and paged shader checks

Headless CI runs the exact bigint semantics and forced-GC matrix via
`make test-ffi-bigint-owned`, with logs under `build/ffi-bigint-owned-logs/`.
For an existing AArch64 Linux cross build, run the same harness with a
matching stage2 image: `tests/vm/bigint_owned_ffi_test.sh IMAGE QEMU_VM_WRAPPER LOG_DIR`.

The paired runner also proves the real owned-add candidate (ID 20). To
reproduce just that proof on a matched hosted build:

```sh
python3 vm/tests/bench/ffi-paired.py \
  --vm vm/build/samaltak --image build/samaltak.image \
  --logs /tmp/ffi-owned-add-proof --proof-only \
  --case bigint-20-cancel --case bigint-20-mixed \
  --case bigint-20-256b --case bigint-20-8192b
```

`make test-ffi-gpu-paged` is a separate opt-in target, also run in hosted
Linux CI. With display denied, it checks copying and releasing a shader
payload larger than 64 MiB. It enables `SAMALTAK_FFI_TEST_EXPORTS` only under
`vm/build/ffi-test-exports/` and checks that the normal VM denies the fixture.
Real draws run in `GPUFFIRegressionTest` in display CI.

## Isolated workload trials

No new default routes are published. For file metadata trials only, start a
separate VM on a disposable copy of an image with `SAMALTAK_FFI_TRIAL=1`.
After startup and at a quiescent workload boundary:

```smalltalk
FFITrial withInstalled: #primPosition: on: File class do: [
    FFITrial withInstalled: #primSize: on: File class do: [
        "Run the real workload and stop/drain its worker processes here."
    ]]
```

For an interactive trial, use `install:on:` and `uninstall:on:` at
quiescent boundaries. Do not edit participating methods, install from
bootstrap, or roll back while a participating send is still active. The
installer checks an explicit allowlist, verifies the original primitive
identity and target availability, stages a preserved primitive alias, then
publishes copies of the original candidate with only the audited pre-entry
fallback literal changed. Both regular sends and sibling sends work in the
trial. Uninstall restores the original method identities and invalidates
method/JIT caches; normal snapshots remove trials rather than auto-enabling
them on resume. An explicit trial is not a production publication decision.

If a route qualifies in future, the image source can publish the verified
candidate body under the original selector, preserve the old primitive
under the legacy alias, and point pre-entry misses there. Seeded prepared
sites can bind lazily at first use; no feature switch, boot-time downcall,
or replacement of bootstrap-critical primitives is required.
