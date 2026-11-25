# Foreign function interface

`FFI bind:` accepts literal or computed descriptors. A call descriptor names a
registered native export and its exact C signature. `FFI bind:` resolves and
checks the export and prepares a generated call wrapper. An `FFIBinding` can
then invoke it synchronously many times.

See the [primitive audit](ffi-primitive-audit.md), the
[retained-primitives report](vm-primitives-retained.html), and the
[cutover contract](ffi-migrations.md) for scope and image compatibility.
[Bounded and owned output](ffi-owned-output.md) describes built-in protocols.
[The fork's performance primitives](ffi-fork.md) says what the FFI means for them.

```smalltalk
(FFI bind: #(call 'libm' 'sqrt' (f64) f64)) invoke: #(9.0)
"3.0"
```

## Call descriptors

The shape is `#(call library symbol argumentTypes resultType)`. The library and
symbol are case-sensitive names (Strings or Symbols, 1–127 ASCII bytes with no
NUL). The library is a logical name, not a path. `argumentTypes` is an Array of
zero to sixteen type Symbols, which together occupy at most sixteen native C
slots (a slice or text argument takes two); `resultType` is a type Symbol. A binding keeps its
immutable copy of the names and signature.

| Type | Value |
| --- | --- |
| `i32`, `i64` | Signed Integer of the given width |
| `u32`, `u64` | Unsigned Integer of the given width |
| `f64` | Float (C `double`) |
| `f32` | Float rounded to the nearest C `float`; a result answers a Float |
| `void` | Result only; answers `nil` |
| `byteSlice` | Argument only for `memcmp`; a read-only byte slice |
| `bytesWithLength` | Argument for a `syncBorrow` grant or registered built-in; a read-only byte slice with its length |
| `writableBytesWithLength` | Approved built-in argument: mutable byte slice with its length |
| `rawBytesWithLength` | Approved built-in argument: a whole non-pointer object (bytes, or 32- or 64-bit words as the CPU stores them: a `Bitmap`), not a slice; its address and byte size |
| `writableRawBytesWithLength` | Approved built-in argument: as `rawBytesWithLength`, of a mutable object the target may write within |
| `countedText` | Approved built-in argument: UTF-8/surrogateescaped String, or raw bytes from an exact ByteArray; pointer and byte count |
| `cText` | Approved built-in argument: String as above, but copied and NUL-terminated; embedded NUL rejected |
| `ownedText` | Approved built-in result: String copied from owned native bytes, or `nil` |
| `nonNegativeI64` | Approved built-in result: exact Integer, or `nil` for negative status |
| `integerMagnitude`, `ownedIntegerMagnitude` | Approved variable-width Integer [argument and result](ffi-owned-output.md#owned-integer-result-tag-11) |

An invalid descriptor, unavailable export or signature mismatch signals
`FFIError` at bind time. Integers must fit the declared width; `f64` and `f32`
require a Float.

A byte slice is an exact three-element Array `{aByteArray. oneBasedOffset. length}`
with an exact `ByteArray` and `SmallInteger` offset and length. The offset is at
least 1 and the length is nonnegative. The range must fit in the logical byte
size (not allocation padding); a zero-length slice may start one past the end.
Nil is not a slice, even at length zero. The explicit `memcmp` count must fit in
both slices. Only the sign of its result is significant.

Both text argument types occupy two native slots. The byte count excludes
any added terminator. Treat text input as a synchronous read-only borrow
and copy it before retaining it or passing it to a worker.

A `writableBytesWithLength` slice additionally rejects a read-only ByteArray,
even at length zero. It supplies a writable pointer and a `uint64_t` length
(two of the sixteen available native slots). All arguments are checked before the
VM enters the target. The target may write only within the validated range
and only on the calling VM thread before returning. It must not retain or
handoff the pointer, reenter the VM, or trigger a callback or GC. It must not
dereference an empty slice. Slices may overlap, so a target with several
slices must handle or reject overlap before using a non-overlap operation.
The image never sees the pointer; it sees writes
in the original ByteArray, including writes made by a target returning an
error status. The VM does not roll back those writes or retry the call.

The raw-object types pass an object itself, not a slice Array: no allocation per
call, and word objects too. They take two native slots, an address and a
`uint64_t` byte size (logical, not allocation padding), with `const` for the
read-only one; ranges inside the object are the target's to check. Pointer
objects, immediates and, for the writable type, read-only objects are rejected
before entry. The same rules as for writable slices apply: no retention,
reentry or GC; objects may be the same or overlap.

Only exact, declared built-in signatures can grant writable access.
`SAMALTAK_NATIVE_GRANTS` does not accept this type, and the legacy
`ffiBind`/`ffiInvoke` primitives (250/251) reject it. Both the Array and
positional prepared call paths use the same checked wrapper.

```smalltalk
| compare |
compare := FFI bind: #(call 'libc' 'memcmp' (byteSlice byteSlice u64) i32).
compare invoke: {{#[10 20 30]. 2. 2}. {#[20 30]. 1. 2}. 2}
"0"
```

## Invoking a binding

Send `invoke:` with an Array of the declared arity (use `#()` for no
arguments). Rejection signals `FFIError` before the target runs. A call that
reaches the target enters it exactly once. A native status such as zero or a
negative value, or `nil` for `void`, is a completed call, not a rejection.

Platform facades use the private positional protocol: `tryInvoke0`,
`tryInvoke1:`, `tryInvoke2:with:`, and so on up to sixteen arguments
(`tryInvoke16:with:…`). Like the
private Array form `tryInvoke:`, these sends answer `false` only for
pre-entry rejection. A facade may use a supported nonnative path on `false`.
It must not retry a completed call, even if it returned zero, an error
status or `nil`.

## Built-in exports

| Library | Export | Signature |
| --- | --- | --- |
| `libm` | `sin`, `cos`, `log`, `exp`, `atan`, `sqrt`, `fabs`, `trunc` | `(f64) f64` |
| `libm` | `ldexp` | `(f64 i32) f64` |
| `libm` | `ilogb` | `(f64) i32` |
| `libc` | `memcmp` | `(byteSlice byteSlice u64) i32` |

Examples of built-in `platform` exports on SDL builds follow. Prefer the
Smalltalk window and PTY APIs for argument and error handling.

| Export | Signature |
| --- | --- |
| `platform_windows_close`, `platform_windows_set_cursor`, `pty_close`, `pty_foreground` | `(i64) i32` |
| `platform_windows_display_scale`, `platform_windows_refresh_rate` | `(i64) f64` |
| `platform_windows_show` | `(i64 i32) i32` |
| `platform_windows_set_text_input_area` | `(i64 i64 i64 i64 i64 i64) i32` |
| `pty_resize` | `(i64 i64 i64) i32` |

### Declaring a built-in export

Mark a typed Lowtalk function on `FFIPrimitives` (`vm:core`) or
`SDLPlatform` (`platform`):

```smalltalk
nativeFractionPart: value
    <function>
    <approvedFFI: 52 symbol: 'core_float_fraction_part' arguments: #(6) result: 6>
    <var: #value type: 'double'>
    <returns: 'double'>
    "Typed implementation here."
```

The stable registry ID is 1024 plus the declaration key. Use the original
primitive ID as the key and a separate key for additional variants. The
translator rejects duplicate keys, duplicate logical names within a library,
legacy platform names, incompatible C prototypes, and signatures exceeding
sixteen C slots. These are prepared calls only: an exact library, symbol,
argument signature and result tag must match. No lookup falls through from
these libraries to launcher grants. `vm:core` is not a valid launcher alias;
the existing alias `core` retains its meaning. `NO_PLATFORM` and UEFI do not
expose SDL targets. `<approvedFFITest>` requires a VM built with
`SAMALTAK_FFI_TEST_EXPORTS`.

Return tag 12 (`nonNegativeI64`) is an approved, prepared result policy for
`int64_t` exports. The launcher returns `nil` after a negative native result
and boxes a nonnegative result exactly. Only pre-entry rejection returns
the zero sentinel (`tryInvoke*` replies `false`). The signed `i64` result
policy preserves the negative status rather than mapping it to `nil`.

A facade can avoid a separate cache by compiling a literal binding at its
call site:

```smalltalk
ffiSqrtOf: aFloat
    <ffiSite>
    | result |
    result := (self ffiSite: #(call 'libm' 'sqrt' (f64) f64)) tryInvoke1: aFloat.
    result == false ifTrue: [^FFIError signal: 'sqrt invocation rejected'].
    ^result
```

In an annotated method, `self ffiSite: <literal descriptor>` embeds an
immutable, initially unprepared `FFIBinding` in the method. Invocation uses
the existing prepared wrapper and process-local token; restoring an image
does not restore a native target. Fall back only when invocation answers
`false`, never on a completed native status.

## Launcher grants

For another library, start the VM with `SAMALTAK_NATIVE_GRANTS` in its
environment. The manifest has one `alias|symbol|result(arg1,arg2,...)|/absolute/path`
row per export, with no spaces in the signature. Use `()` for no arguments.
The manifest is limited to 32 rows and 4096 bytes. Aliases use ASCII letters,
digits, `_`, `.` and `-`; symbols are C identifiers. The aliases `libm`,
`libc` and `platform` are reserved; `vm:core` is built-in only. An alias/symbol
pair may occur only once.
Scalar grants take scalar arguments and return a scalar or `void`. Invalid
manifests or unresolved grants abort VM startup with exit status 64.

For example, on Linux, build a library with a scalar export and grant just that
export at launch:

```sh
ffi_dir=$(mktemp -d)
cat > "$ffi_dir/demo.c" <<'EOF'
#include <stddef.h>
#include <stdint.h>

int32_t demo_add(int32_t a, int32_t b) { return a + b; }

uint64_t demo_sum(uint64_t seed, const uint8_t *bytes, size_t length) {
    for (size_t i = 0; i < length; ++i) seed += bytes[i];
    return seed;
}
EOF
cc -shared -fPIC -o "$ffi_dir/libdemo.so" "$ffi_dir/demo.c"

SAMALTAK_NATIVE_GRANTS="demo|demo_add|i32(i32,i32)|$ffi_dir/libdemo.so" \
  vm/build/samaltak build/samaltak.image --headless --eval "
    | library export types binding |
    library := 'demo'.
    export := 'demo_add'.
    types := {#i32. #i32}.
    binding := FFI bind: {#call. library. export. types. #i32}.
    binding invoke: #(20 22)"
# 42
```

Borrow grants use a five-field row. Put the literal `syncBorrow` before the
path:

```text
demo|demo_sum|u64(u64,bytesWithLength)|syncBorrow|/absolute/path/libdemo.so
```

With that grant, call the `demo_sum` export from the library above:

```smalltalk
| sum |
sum := FFI bind: #(call 'demo' 'demo_sum' (u64 bytesWithLength) u64).
sum invoke: {10. {#[1 2 3]. 2. 2}}
"15"
```

Each `bytesWithLength` supplies one Smalltalk argument but two native
arguments: a read-only pointer and its validated length, in that order. The
entire call must fit in sixteen native argument slots. By granting `syncBorrow`,
the launcher promises the function reads only within each slice and does not
mutate, retain or hand off any borrowed bytes. The borrow ends when the call
returns.

A grant is not a sandbox: trust the library, its dependencies and constructors.
The launcher must supply the actual C prototype; the VM cannot infer it.

## Targets and lifetime

Downcalls run on hosted Linux (x86-64 and arm64) and macOS (Apple Silicon),
when executable adapter memory is available. `--jit none` does not disable
FFI. Built-in math and comparison exports and launcher downcalls also work
in a `NO_PLATFORM=1` build. The `platform` exports and notifications need an
SDL-enabled VM; SDL logs and Linux refresh notifications do not need a
window. UEFI and the Smalltalk VM simulator do not run these adapters.

The image cannot pass or receive raw pointers. Native code must not retain a
borrow or reenter Smalltalk. A synchronous call occupies the VM thread, so
a blocking export also blocks other Smalltalk processes. Use fixed signatures:
no variadic calls, structs by value or arbitrary callback registration.

### Generated call wrappers

Binding checks the names and full signature against the VM's registry. The VM
generates a wrapper for the target and signature on a cache miss. Each wrapper
calls a fixed native address for that VM session. A warm invocation checks the
binding's session-local handle without resolving the export again. The wrapper
validates the Smalltalk arguments, places the converted values in the native
ABI's argument registers and, past them, its outgoing stack arguments, calls
the target, and converts the result back to a Smalltalk object. The positional
path builds neither a Smalltalk argument Array nor an array of converted native
scalars.

The wrapper follows the C calling convention lane by lane, in argument order:
a slice or text argument is two lanes, its pointer and then its length, as two
C parameters. Integer and pointer lanes take the integer registers, `f64` and
`f32` lanes the floating-point registers; once a class's registers are taken,
its later lanes go to the stack, while the other class may still use
registers.

- arm64 (AAPCS64): x0–x7 and v0–v7. Each stack lane takes an 8-byte slot (a
  32-bit value in its low half); on Apple's arm64 ABI (macOS) stack lanes take
  their natural size and alignment instead (4 bytes for `i32`, `u32`,
  `f32`). Converted register lanes live in callee-saved x20–x27 and d8–d15
  across the conversion helpers; a stack lane is written straight into the
  outgoing area at sp.
- x86-64 (System V): rdi, rsi, rdx, rcx, r8, r9 and xmm0–xmm7; each stack
  lane takes an 8-byte slot, the first at rsp at the call. Register lanes stay
  in their final registers and are spilled only around the conversion helpers;
  stack lanes go straight to their slots.

The outgoing area is part of the wrapper's frame and keeps sp 16-byte aligned
at every call. A signature of up to six integer and eight floating-point lanes
(any of up to six arguments) compiles to the same code as before stack
arguments existed. A float result is widened to a double and boxed as one.

Saving a snapshot does not invalidate bindings in the running VM. A restored
binding keeps its descriptor, not native authority: on first use it must
prepare again against the new VM's registry. Launcher grants are fixed at
startup; revoke a grant by restarting without it. A restored binding whose
grant is missing or no longer matches is rejected before native entry.

Libraries and generated wrappers stay mapped until VM exit. The VM can
publish up to 1024 downcall wrappers per process. Dropping a binding or
flushing the ordinary JIT cache does not reclaim them.

### Optimizing JIT call sites

In `--jit opt`, an eligible positional send of up to sixteen arguments can
learn one prepared binding and call its generated wrapper directly. The binding can be computed at
run time; the send need not load a literal. A hit skips the normal Smalltalk
send and bound-invocation primitive, not the wrapper's argument checks or
result conversion. If the guard misses, the normal send runs instead. A
wrapper rejection still answers `false`; a native result is never a reason
to retry the send.

This does not specialize the public Array form. Interpreter and baseline
code still use the same wrappers through the ordinary invoke path.
`--jit opt --jit-flags -ffi-site` disables only this call-site optimization,
not generated wrappers or FFI. See [the JIT notes](jit.md#bound-ffi-sites)
for the guard and GC mechanics.

## Headless verification

With a hosted VM and full image, run:

```sh
tests/vm/runtime_native_grants_test.sh build/samaltak.image vm/build/samaltak
tests/vm/wrapped_ffi_specialization_test.sh build/samaltak.image vm/build/samaltak
tests/vm/bound_ffi_site_test.sh build/samaltak.image vm/build/samaltak
tests/vm/ffi_arity_test.sh build/samaltak.image vm/build/samaltak
```

The grant test covers bind-time validation and reauthorization after restore.
The wrapper test covers Array and positional invocation, native entry counts
and restore with reordered or missing grants. The site test (also run by
`make test-jit-opt`) checks the emitted direct call and executed site counters
with `ffi-site` on and off. It also checks fallback, boxing with GC, and
deoptimization without replay. The witness loads its fixture before tracing
and resumes the same snapshot for both flag settings. Set
`SITEFFI_TEST_LOG_DIR` to keep the witness route and counters. To skip the PTY
portion, pass `--no-pty` after the VM path to the wrapper and site tests. Both
scripts use `--load`, which needs file support.

The arity test (part of `make test-core`) calls launcher grants of
`tests/vm/ffi_arity_fixture.c` with 7, 8, 9, 14 (cublasSgemm's shape) and 16
arguments of mixed integer, float, double and slice types, which use stack
lanes on both CPUs and split a slice between a register and the stack. Each
native hashes its arguments in order and the proof checks the hash, in the
interpreter, baseline and optimized code; a witness run counts the bound-site
hits, and wrong values in stack lanes must be rejected before entry. Given a
third argument, a VM built with `-DSAMALTAK_FFI_TEST_EXPORTS`, it calls the
approved `ffi_test_arity*` exports of the same signatures too (`make
test-ffi-arity`). `RUN` and `CC` run another CPU's VM, e.g. an x86-64 build
under `qemu-x86_64 -L SYSROOT` with the cross compiler of
`tools/x86-toolchain.sh`.

On x64 and arm64 builds compiled with `-DSAMALTAK_FFI_TEST_EXPORTS`,
`tests/vm/writable_ffi_test.sh IMAGE VM` checks guarded native writes,
pre-entry rejection, both invoke forms, optimized site hits, and full GC
during result boxing. On a release build, pass `--expect-no-fixture` to
verify that the test export cannot be bound.

See [bound FFI sites](benchmarks.md#bound-ffi-call-sites) for warm dispatch
measurements. They do not measure the numbered-primitive cutover.

## Notifications

Notifications are fixed native sources, not native calls into Smalltalk. The
host records a latch or copies bytes into a bounded queue; the image polls.
There is no Smalltalk callback.

- `#(notification vsync coalesce 2 step)` samples the native refresh source
  every `step` ticks (`1 2 4 8 16 32 64 128`). The `2` is the fixed native
  context argument position, not an address. `poll` answers and clears a Boolean
  latch; multiple matching ticks between polls count as one. Up to 16
  subscriptions can be active. Plain `FFI bind:` does not signal. Use
  `FFINotification bind: descriptor whenPendingSignal: sem` to have the VM
  thread signal a Semaphore when the latch becomes pending. `poll` re-arms it.
- `#(notification sdlLog queued dropNewestAndCount capacity (category priority messageBytes) byteLimit)`
  takes a capacity of 1–64 and a byte limit of 1–240. There is one SDL log
  subscription per VM. `poll` takes the oldest event as `{category. priority.
  aByteArray}`, or answers `nil` when empty. The copied bytes omit the NUL
  terminator and may end mid-character. When the queue fills, new events are
  discarded and `droppedCount` reports the cumulative loss (saturating at
  2147483647). SDL logging continues as usual.

Close subscriptions explicitly, for example with `ensure:`. Dropping the
object is not enough. Closing releases the registration and discards pending
events; closing again is harmless.
Registrations are process-local: bind again after restoring a snapshot.
Polling a closed or stale subscription signals `FFIError`.

### External notifications

One launcher-granted external subscription can be active per VM. This
example uses the [test library](../tests/vm/ffi_external_notification_fixture.c):

```text
fixture|fixture_subscribe|notifyI32(u32,context,u64)|fixture_unsubscribe|/absolute/fixture.so
```

```smalltalk
FFI bind: #(notification external 'fixture' 'fixture_subscribe' (u32 context u64) i32)
```

The granted callback has one to six arguments, exactly one of which is
`context` (a private native context). Other arguments are `i32`, `u32`,
`i64` or `u64`. The adapter ignores the scalars, sets a pending bit, and
returns zero for `i32` or no result for `void` (grant token `notifyVoid`).
`poll` answers and clears the bit. There is no semaphore delivery.

The trusted registrar has C type
`int32_t subscribe(void (*entry)(void), void *context)` and returns zero on
success. It casts the entry to the granted callback type and passes the
context unchanged in the declared slot. On `close`, the VM calls
`void unsubscribe(void *context)` synchronously. The provider must stop
delivery and wait for in-flight callbacks before returning; a failed
registration must also leave no callbacks live. A notification grant does
not expose either registrar as a downcall.
