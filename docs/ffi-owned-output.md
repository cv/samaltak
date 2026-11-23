# Bounded FFI output

These result protocols are for approved built-ins using prepared FFI.
They expose neither native pointers nor callbacks to the image. A facade
may take an alternate path only on rejection before native entry; it never
replays a completed operation.

## Known capacity

A `writableBytesWithLength` argument is
`{exactMutableByteArray. oneBasedOffset. length}`. Offset and length are
SmallIntegers. A zero-length slice can start one past the end. The wrapper
checks the whole argument list before calling the target. It passes
`uint8_t *` (or `void *`) and `uint64_t` length in two native slots. The
length is the exact capacity, not a rounded allocation size. This type
cannot be used in launcher grants or the legacy word FFI.

Only vetted native code gets the pointer. It may write within that slice
synchronously, but may not retain the pointer, hand it off, allocate VM
objects, safepoint or reenter Smalltalk. Use an immediate status or byte
count; a wider integer result is valid only if the target guarantees every
value fits a SmallInteger. This rules out allocation/boxing failure being
mistaken for a pre-entry rejection after a side effect. A completed short
read, zero-byte read, and family-specific negative status are not
invocation rejections.

Define the wire layout per export: explicit byte offsets, sizes, integer
width and endianness, and text encoding. Do not copy padding from a C
struct. Check capacity before performing an operation that consumes state
or creates a resource. A fixed signed file-stat record and an atomic GPU
handle/width/height record can each use one call and one buffer; their
status explains whether a record was written. Validate array stride and
count before allocating an image Array.

## Shared bounded owner

`FFIOwnedOutput captureUpTo: maxBytes do: [:ticket | ...]` reserves a
fresh ticket before entering the producer. The block must directly return
the result of exactly one prepared producer invocation with the ticket
as a `u64` argument and an `i32` result. No sizing call runs the producer.
The image helper interprets its result as follows:

| Producer result | Image result |
| --- | --- |
| `false` (wrapper rejected the call before native entry) | `false` |
| `0` | `nil`, completed and absent |
| `1` | exact-length ByteArray; empty is present |
| Negative integer | the same completed operation status |

An unavailable reservation can also return `false` before producer entry.
A post-entry missing payload, malformed status or copy failure raises
`FFIError`. Use this owner only where its bounds cover the operation's
contract. Otherwise use a different result protocol; don't truncate a
result or rerun the operation.

The producer claims its ticket with `ownedCanProduce:` before doing the
operation. A second claim always fails, even if the first found no result.
Publish one payload; for absent/failure don't publish. Native methods use:

- `ownedPublish:from:size:` to copy counted bytes. The source remains the
  producer's responsibility on both success and failure, including sources
  allocated by SDL or any allocator other than libc.
- `ownedAdopt:from:size:capacity:` to transfer an exclusive libc allocation.
  Pass the base pointer, logical byte length, and actual allocation length,
  with size ≤ capacity ≤ reserved bytes. On failure the caller still owns
  it. Zero capacity requires a null pointer. No interior pointer, callback,
  or image address is stored.

The shared table allows 16 tickets and reserves at most 64 MiB across them.
Reserve the smallest known upper bound, including any wire header.
A producer must still respect family limits (e.g., 20 MiB for clipboard
MIME bytes). Use encoding appropriate to the operation: VM OS text uses
`PlatformFFI textFromBytes:` for surrogateescape, not replacement decoding;
raw shader or MIME bytes need no text decoder.

Reserve writes the ticket into an all-zero eight-byte slice, little-endian,
only on success. The image installs `ensure:` *before* reservation, so an
unwind can read the ticket and release it even if interrupted just after a
reserve or producer call. The image reads the sealed size, allocates its
ByteArray, and copies into a slice of exactly that size. Release also
cancels an unclaimed or partially completed ticket. No result allocation
keeps a native pointer into the heap.

Table operations run on the VM thread and acquire no locks. A ticket is
a nonzero 62-bit process-masked generation; no generation repeats in the
process. Moving GC and binding invalidation don't affect owned bytes;
there is no heap reference to update. A new VM starts
with an empty native table and a new random mask: reopening an image can
rebind descriptors but does not resurrect any payload. Release of an
invalid ticket is harmless.

The shared budget is not a general downcall limit. Clipboard MIME data
uses this owner within its own 20 MiB limit.

## Paged platform output

Clipboard text (410), event text (412) and compiled shader bytes (461)
use [`FFIPagedPlatformOutput capture:`](../src/System-Support/FFIPagedPlatformOutput.st).
The producer captures the operation once. It takes a fresh, zeroed
16-byte writable receipt for two little-endian u64 words: the ticket and
the payload byte length. An all-zero receipt with success denotes empty
output without a ticket. Event metadata is written separately into a
fixed 80-byte header; the producer takes ownership of the queued text
when it dequeues the event.

The helper copies into an exact ByteArray in checked slices of at most
1 MiB, using the ticket to access the same native result throughout.
It reads the receipt in `ensure:` to release any ticket, even if the
producer unwinds before returning status. Stale or released tickets are
rejected.

This owner allows 16 live results without a shared byte budget. Native
allocation, heap space and the ByteArray representation still limit
sizes. Tickets are process-local, not snapshot state. A failure copying
or decoding a result does not rerun the producer.

## Owned text (tag 15)

An approved `ownedText` target receives a hidden native text-buffer
record. The result bytes are owned by that record, never a pointer into
the Smalltalk heap or an environment table. After input borrows end, the
wrapper boxes a String with the VM's UTF-8/surrogateescape codec and
releases any native allocation. A null result denotes absence; a present
zero-byte result is an empty String. Neither is pre-entry rejection.

## Owned integer result (tag 11)

`ownedIntegerMagnitude` is a result tag for exact, approved `vm:core`
prepared calls with two `integerMagnitude` arguments. It is not a general
aggregate or pointer ABI and is unavailable to launcher grants and the
legacy word FFI. Each borrowed magnitude consumes two machine lanes.
The wrapper passes a fifth, hidden argument pointing to a native stack
record. The producer writes a status and normalized signed limb count;
the result uses four inline limbs or one owned native allocation and
does not alias either input.

After native return, both borrows are dead. The collecting wrapper boxes
a SmallInteger or synchronizes the pending frame before allocating a
LargeInteger, copies the owned limbs once, and frees any native allocation.
The VM heap and object representation bound the result; there is no byte
serialization cap. `false` means pre-entry rejection, `nil` a completed
allocation/size failure, and `true` a completed division-by-zero status.
The facade translates completed failures without another downcall.

## Verification

With an image and hosted VM built with the test export enabled
(`-DSAMALTAK_FFI_TEST_EXPORTS=1` when compiling the VM):

```sh
tests/vm/owned_ffi_test.sh build/samaltak.image /path/to/test-vm
```

The fixture is also runtime-gated. The test uses the prepared path in
interpreter, baseline and optimizing modes. It has no display work. Add
`--trace` to check the number of native producer entries if built with
approved-target tracing.

The [owned integer fixture](../tests/vm/bigint_owned_ffi_test.sh) takes
`IMAGE VM LOG_DIR` and checks arithmetic completions and forced post-native
GC. The [paged shader fixture](../tests/vm/gpu_shader_paged_test.st) uses
a synthetic result above 64 MiB on a display-denied, SDL-hosted test-export
build. It checks bounds, stale/released tickets and exact paged copy; it
does not run a real shader compilation. See the
[cutover contract](ffi-migrations.md) for operation-level verification.
