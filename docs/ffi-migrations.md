# Numbered primitive cutover

The Smalltalk API routes the original remove-98 operations and four
additional hosted process operations through approved typed downcalls
rather than numbered adapters. The native backends remain. The separate
image display cutover brings the total to 109 removed slots: 102 migrated
to FFI and seven to image code. See the [primitive audit](ffi-primitive-audit.md)
and the [149 Keep IDs](vm-primitives-retained.html).

## Original remove-98 scope

| Family | Reserved IDs | Count |
| --- | --- | ---: |
| Core | 20–31, 52, 61, 152–153, 169–170, 172 | 19 |
| Window/input | 400, 402–403, 405, 410–413, 415, 417–418, 420–421 | 13 |
| GPU | 430–456, 458–461 | 31 |
| Files | 500–514 | 15 |
| Socket/TLS/PTY | 540–555, 561–562, 564–565 | 20 |

The original coverage split is 59 hosted headless and 39 display operations;
the 19 no-platform core operations are part of the 59, not additional.
These count old operations, not exports. The original manifest lists 99
typed-entry witnesses: 443 (begin render pass) has separate entries for
load and clear.

## Hosted process scope (separate)

| Reserved ID | Operation contract |
| --- | --- |
| 515 | Spawn by PATH with the supplied argv, inheriting the environment and standard streams; return the PID. |
| 516 | Wait with a POSIX PID selector, not a PTY handle. At the typed boundary, pending differs from failure and from completion (exit status or 128 plus signal); `File primWait:blocking:` returns nil for pending or failure. |
| 518 | Keep `execvp` PATH and executable-format semantics. Success replaces the VM process; a return from the backend is failure. |
| 560 | Spawn a PTY child with argv, optional environment and directory, and terminal size; return the handle and PID together. Inheriting the environment is distinct from passing an empty environment list. |

Validate argument records and reject embedded NULs before any launch or
replacement. Do not retry a native failure through another path.

## Guest display scope (not FFI)

Slots 200–206, from `displayOpen` through `displayFlush`, are reserved.
The [Smalltalk-80 guest](../st80/README.md) owns the display and rasterizes in
Smalltalk. The simulator presents published frames and supplies input
through an image-object protocol, without a numbered or native call boundary.

## Typed downcall contract

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
The simulator and UEFI cannot run the hosted adapters. A firmware build
does not by itself demonstrate runtime behavior.

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
