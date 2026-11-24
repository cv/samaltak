# Canonical FFI proof and paired benchmarks

Headless CI checks exact typed-entry counts for the canonical APIs in the
interpreter, baseline JIT and optimizing JIT. The driver uses real fixture
resources and checks outcomes; setup, teardown and diagnostic output do not
count toward an operation's trace. The display CI job runs the same proof
mechanism with `--display-ci` on window and GPU workloads. CI does not time
either suite.

```sh
python3 vm/tests/bench/ffi-paired.py \
  --vm vm/build/samaltak --image build/samaltak.image \
  --proof-only --logs build/ffi-proof
```

For timing, build the previous checkout separately (e.g. pre-cutover
`ff327a9d0a87cad09035b009babef6a6a71b9ed5`). Pass **both** artifacts from each
revision, never a mixed VM/image pair. The harness sends the same selectors to
both images. By default the previous pair must have no typed entry for the
timed operation; use `--old-route typed` to compare two revisions that both
use typed FFI.

```sh
python3 vm/tests/bench/ffi-paired.py \
  --vm vm/build/samaltak --image build/samaltak.image \
  --old-vm /path/to/previous/vm/build/samaltak \
  --old-image /path/to/previous/build/samaltak.image \
  --case file-position-4096 --logs build/ffi-paired
```

Use an empty log directory. The runner records artifact hashes, raw output and
per-arm counters, with independent warmup in each process and balanced
old/new order. It emits new/old wall and CPU ratios plus allocation and GC
summaries. Use a quiet host; `--require-at-par` rejects both slower and
inconclusive strata. Display benchmarks are gated to display CI.

A pre-cutover saved image may contain compiled methods referencing now-retired
primitive numbers and descriptors for older native signatures. Use its
matching VM to open it and export application source/data, then rebuild or
import into a fresh cutover image. Rebinding a snapshot from the **same** cutover
revision is tested separately.
