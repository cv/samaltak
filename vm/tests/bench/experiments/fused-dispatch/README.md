# Fused dispatch experiment (v4)

The source-only [patch](fused-v4.patch) applies to `227275e`. Nothing in this
directory is built by normal targets or CI. To try it, manually apply it and
regenerate the VM in a disposable worktree. Even in that VM, fused dispatch
requires `SAMALTAK_FFI_DIRECT=1` at startup; existing dedicated primitives
remain the default.

Scope: float fraction part (52) and file size/position (504/505). The
`prim_fn` thunk uses the VM's stack, result and status cells; the native
target sees only an unboxed scalar in its x86-64 SysV/AArch64 ABI lane
(`double → double` or `int64_t → int64_t`). Admission checks primitive
marker 266, immutable exact fallback bytecode/literals, frame shape, the
approved descriptor and prepared binding. The thunk rechecks the weak
owner, slot serial and binding token before argument conversion. A guard
failure falls back; a negative file result is a successful Smalltalk
`nil`, not rejection. Cold/collecting boxing uses existing GC-aware
helpers. The optional fused exit counters are written by the emitted code,
not by the prepared wrapper or a C result callback.

## Build and prove (Linux x86-64, no display)

From the repository root, with the usual hosted VM build dependencies
(GCC/GNU make, SDL3, OpenSSL and shaderc; see `vm/Makefile`), in Bash:

```bash
set -euo pipefail
exp="$PWD/vm/tests/bench/experiments/fused-dispatch"
trial="$(mktemp -d)/tree"
git worktree add --detach "$trial" 227275e
cd "$trial"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY PACKAGES NO_PLATFORM PGO_GEN
unset SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_DIRECT SAMALTAK_FFI_DIRECT_TRACE \
      SAMALTAK_FFI_NATIVE_TRACE SAMALTAK_FFI_BOX_FULL_GC SAMALTAK_FFI_TEST_EXPORTS
export SDL_VIDEO_DRIVER=ffi_no_video SDL_VIDEODRIVER=ffi_no_video
pkg-config --exists sdl3 openssl shaderc

bootvm=vm/build/fused-bootstrap/samaltak
vm=vm/build/fused-v4/samaltak
image=build/fused-v4.image
make -C vm -j4 BUILD=build/fused-bootstrap NO_PGO=1
test -f vm/build/fused-bootstrap/.variant-platform
boot/build-image.sh src build/fused-base-seed.image "$bootvm"
"$bootvm" build/fused-base-seed.image --headless --stage2 build/fused-base.image

git apply --check "$exp/fused-v4.patch"
git apply "$exp/fused-v4.patch"
vmgen() {
    mkdir -p "$3"
    "$1" "$2" --headless --eval "[
        VMTranslator generateVMInto: '$3'. 'ok'
    ] on: Error do: [:e |
        Smalltalk vm stderrWrite: e messageText, (String with: Character lf).
        Smalltalk quit: 1]" | grep -Fx "'ok'"
    test -s "$3/sources.mk"
}
# The patched Lowtalk must be in the translation seed, not the base image.
boot/build-image.sh src build/fused-translation.image "$bootvm"
vmgen "$bootvm" build/fused-translation.image build/fused-gen
mv vm/gen build/feature-gen
cp -a build/fused-gen vm/gen
make -C vm -j4 BUILD=build/fused-v4 NO_PGO=1
test -f vm/build/fused-v4/.variant-platform
boot/build-image.sh src build/fused-seed.image "$vm"
"$vm" build/fused-seed.image --headless --stage2 "$image"
vmgen "$vm" "$image" build/fused-regen
diff -qr build/fused-gen build/fused-regen

cases=(--case file-position-1 --case file-position-4096 --case file-position-1048576
       --case file-size-1 --case file-size-4096 --case file-size-1048576 --case float-fraction)
paired=(python3 vm/tests/bench/ffi-paired.py --vm "$vm" --image "$image")
"${paired[@]}" --logs build/fused-proof --direct-route --proof-only "${cases[@]}"
python3 tests/vm/ffi_direct_test.py "$vm" "$image" build/fused-gc
python3 tests/vm/ffi_direct_test.py "$vm" build/fused-base.image build/fused-old --old-image
```

The paired proof checks each arm separately across all 21 case/tier strata:
1024 exact native entries and one publication with 1023 or 1024 fused
successes (one cold call allowed), zero rejects; the dedicated control must
have no native entries and all-zero fused counters. The stress proof also
checks forced full GC, replacement, eager deopt, wrong argument fallback,
and closed-file `nil`. An unmarked image must have zero fused events.

## Benchmark

On an otherwise idle host, in the same shell. Optionally pin the runner
with `--cpu N` for an available isolated core. It reruns proof before timing.
Use a fresh log directory for each run:

```bash
"${paired[@]}" --logs build/fused-timing --direct-route "${cases[@]}" \
    --sessions 17 --pairs 4 --calls 4096 --warmup 4096
```

## Evidence

On the matched x86-64 release VM/image, all **21 strata were inconclusive**:
every simultaneous 95% interval crossed 1.0. Wall candidate/dedicated
ratios (smaller is better):

| Case | Interpreter | Baseline | Opt |
|---|---:|---:|---:|
| File size, 4 KiB | 1.0018 [0.9972, 1.0094] | 1.0021 [0.9897, 1.0105] | 1.0019 [0.9971, 1.0120] |
| File position, 4 KiB | 0.9918 [0.9780, 1.0094] | 1.0011 [0.9893, 1.0061] | 0.9985 [0.9895, 1.0099] |
| Float fraction | 1.0108 [0.9662, 1.0567] | 1.0134 [0.9814, 1.0488] | 1.0292 [0.9754, 1.0637] |

[ratios.csv.gz](ratios.csv.gz) retains all 1,428 observed pair ratios (17
fresh sessions × 4 balanced AB/BA pairs × 21 strata) plus each arm's wall
ticks in microseconds. Recompute the medians and intervals with the same
sign/order-statistic CI and ±1 µs quantization bounds as the runner:

```bash
python3 - "$exp/ratios.csv.gz" <<'PY'
import csv, gzip, runpy, statistics, sys
from collections import defaultdict

ci = runpy.run_path("vm/tests/bench/ffi-paired.py")["median_interval"]
samples = defaultdict(lambda: defaultdict(list))
with gzip.open(sys.argv[1], "rt", newline="") as f:
    for row in csv.DictReader(f):
        c, d = (int(row[k]) for k in ("wall_candidate_us", "wall_direct_us"))
        assert float(row["wall_candidate/direct"]) == c / d
        samples[row["case"], row["mode"]][row["session"]].append(
            (c / d, (c - 1) / (d + 1), (c + 1) / (d - 1)))
assert len(samples) == 21
for (case, mode), sessions in samples.items():
    assert len(sessions) == 17 and all(len(pairs) == 4 for pairs in sessions.values())
    point, low, high = zip(*(map(statistics.median, zip(*p)) for p in sessions.values()))
    lo = ci(low, .05 / len(samples))[0]
    hi = ci(high, .05 / len(samples))[1]
    assert lo < 1 < hi
    print(f"{case:24} {mode:8} {statistics.median(point):.4f} [{lo:.4f}, {hi:.4f}]")
PY
```
