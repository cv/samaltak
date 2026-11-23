# Whole-call FFI specialization

Run the hosted proof without a display:

```sh
tests/vm/wrapped_ffi_specialization_test.sh build/samaltak.image vm/build/samaltak
```

The runner checks that the warm primitive path has no resolver, encoder, argument
tag loop, or word bridge. An independent native export inspects the running
launcher's return PC to verify the target immediate and inline i32 result boxing.
Other checks exercise mixed typed registers, integer limits, strict rejection
with no native entry, bounded byte borrows across GC, allocating return boxing,
restored grants, and native side effects under eager deoptimization. The live
PTY test traps legacy and Array sends and checks allocation and terminal size.

```sh
vm/tests/bench/wrapped-ffi.py --cpu 0 > wrapped-ffi.csv
```

Use an available idle CPU (omit `--cpu` where affinity is unsupported). Each
mode runs all variants in the same process against the same VM, image, and
live PTY. `directForeground`/`directResize` call the platform primitives;
`wrapped*` call the production facade; `prior*` run the descriptor/Array
facade using the generic primitives. Resize alternates 25×81 and 24×80.
The scalar varies every input, checks the sum and exact native call count,
and compares direct arguments, a fresh public argument Array, and the generic
bridge. The scalar “direct” is the prepared generated launcher, not a PTY
primitive. Cold binds, preflight, warmup, and the first full batch are excluded
from the steady summaries. CSV includes each batch; paired ratios compare
variants within one round.

## Hosted x86-64 sample

Linux on an AMD EPYC 7B13, CPU 0, 10 steady rounds of 50,000 calls per
variant and mode; 32,000 warmup calls per variant, then one discarded
50,000-call batch. Median ns/call:

| Mode | Operation | Direct | Wrapped | Prior | Paired wrapped/direct |
| --- | --- | ---: | ---: | ---: | ---: |
| none | PTY foreground | 811.0 | 894.0 | 1068.1 | 1.103× |
| none | PTY resize | 1025.8 | 1120.5 | 1331.8 | 1.092× |
| none | Dynamic scalar | 31.6 | 60.3 | 151.2 | 1.943× |
| opt | PTY foreground | 806.0 | 837.2 | 993.7 | 1.038× |
| opt | PTY resize | 1040.8 | 1084.9 | 1226.7 | 1.042× |
| opt | Dynamic scalar | 31.1 | 31.3 | 122.2 | 1.205× |

For the scalar, “wrapped” here means the public Array path. Taking ratios
within each round, the direct scalar launcher took 21% (none) and 20% (opt)
of the time of the prior bridge. PTY wrappers and the direct scalar measured
under 1 B/call (including measurement and loop overhead); the prior foreground
and resize paths measured about 24 and 40 B/call. The public scalar Array
measured about 24 B/call.
