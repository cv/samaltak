# Numbered primitive cutover

The remove-98 cutover covers the 98 **Adapter** and **Extend** IDs in the
[primitive audit](ffi-primitive-audit.md). The existing Smalltalk API
routes hosted calls through approved typed downcalls instead of numbered
adapters. The native backends remain. See the
[retained-primitives report](vm-primitives-retained.html) for the Keep set.

| Family | Reserved IDs | Count |
| --- | --- | ---: |
| Core | 20–31, 52, 61, 152–153, 169–170, 172 | 19 |
| Window/input | 400, 402–403, 405, 410–413, 415, 417–418, 420–421 | 13 |
| GPU | 430–456, 458–461 | 31 |
| Files | 500–514 | 15 |
| Socket/TLS/PTY | 540–555, 561–562, 564–565 | 20 |

## Operation contract

- Use exact, approved signatures in `vm:core` or `platform`. An approved
  export ID is not a numbered primitive slot and does not confer launcher
  authority. The generated entries follow the Lowtalk declarations.
- Preserve each public operation's input admission, results, error mapping,
  ownership and readiness behavior. Carry data as checked slices, counts or
  explicit records, not pointers or OOPs. Copy before any asynchronous handoff.
- A rejection before native entry (`false` on the private invoke protocol)
  is not a completed operation. It may select a supported nonnative path,
  but not a retired numbered entry. Zero, nil, errors, pending status and
  partial progress after native entry are all completions; never replay them.
  An optimizing JIT guard miss can run the normal prepared send without
  changing the operation's contract.
- Capture results that consume state or observe changing state once. Preserve
  absent versus present-empty, release native ownership on unwind, and don't
  impose a byte ceiling on a formerly uncapped operation. See
  [bounded and owned output](ffi-owned-output.md).

Hosted `NO_PLATFORM=1` still supports core downcalls but has no SDL routes.
The simulator and UEFI cannot run the hosted adapters. Portable computation
and target-specific services are separate from the hosted route; a firmware
build does not by itself demonstrate runtime behavior.

## Images and bootstrapping

The retired numbers stay reserved: they are neither reusable nor aliases for
the FFI exports. A compiled method can have a numeric header even after the
number and name disappear from the VM registry. Rejecting that lookup safely
is not the same as supporting the old image.

Use a fresh runtime image built from the cutover sources with its matching
VM. Keep a pre-cutover VM with any older snapshots you need to open; export
the application source or data there before moving to a fresh image. The
repository bootstrap seed is a build input, not an upgrade path for saved
runtime images. Rebinding an FFI descriptor after snapshot restore
reauthorizes the call; it does not restore native resources or rewrite a
compiled method's primitive header.

## Verification scope

With a matching hosted VM and full image, check the live registry and
missing numeric headers in all three execution tiers:

```sh
python3 tests/vm/ffi_cutover.py check build/samaltak.image vm/build/samaltak \
  --backend sdl --logs build/ffi-registry
```

Use `--backend no-platform` for a separate `NO_PLATFORM=1` VM. The
`coverage` subcommand checks native-entry traces from successful canonical
calls in each tier; it does not run the fixtures. Keep headless, real
window/GPU CI and no-platform evidence separate. Binding alone is not proof
of native entry.

## Performance decision

This cutover removes duplicate dispatch, not a proven performance-neutral
substitution. Same-VM Linux x86-64 release trials at `de2f6cf` showed slower
interpreter or baseline cases for file metadata, fraction part and short
writes, even where optimizing JIT cases improved. For example, the 4 KiB file-position pilot measured typed/numbered
wall-time ratios of 1.070 (interpreter), 1.025 (baseline) and 0.969 (opt).
Short and long environment values behaved differently; a fixed ASCII
workload did not represent the API. A separate fused-dispatch experiment
recorded at `ff327a9` brought file metadata close to the numbered controls,
but all 21 simultaneous 95% intervals crossed 1.0. Those trials inform the trade-off; none measures
this cutover or establishes parity.
