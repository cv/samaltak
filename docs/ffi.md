# Foreign function interface

`FFI bind:` accepts literal or computed descriptors. A call descriptor names a
registered native export and its exact C signature. `FFI bind:` resolves and
checks the export and prepares a generated call wrapper. An `FFIBinding` can
then invoke it synchronously many times.

```smalltalk
(FFI bind: #(call 'libm' 'sqrt' (f64) f64)) invoke: #(9.0)
"3.0"
```

## Call descriptors

The shape is `#(call library symbol argumentTypes resultType)`. The library and
symbol are case-sensitive names (Strings or Symbols, 1–127 ASCII bytes with no
NUL). The library is a logical name, not a path. `argumentTypes` is an Array of
zero to six type Symbols; `resultType` is a type Symbol. A binding keeps its
immutable copy of the names and signature.

| Type | Value |
| --- | --- |
| `i32`, `i64` | Signed Integer of the given width |
| `u32`, `u64` | Unsigned Integer of the given width |
| `f64` | Float (C `double`) |
| `void` | Result only; answers `nil` |
| `byteSlice` | Argument only for `memcmp`; a read-only byte slice |
| `bytesWithLength` | Argument only for a `syncBorrow` grant; a read-only byte slice with its length |

An invalid descriptor, unavailable export or signature mismatch signals
`FFIError` at bind time. Integers must fit the declared width; `f64` requires
a Float.

A byte slice is `{aByteArray. oneBasedOffset. length}` with a `ByteArray` and
`SmallInteger` offset and length. It must fit inside the ByteArray; a zero-length
slice may start one past the end. The explicit `memcmp` count must fit in
both slices. Only the sign of its result is significant.

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
`tryInvoke1:`, `tryInvoke2:with:`, and so on up to six arguments. Like the
private Array form `tryInvoke:`, these sends answer `false` only for
pre-entry rejection. A facade may take an alternate path on `false`, but
must not retry a completed call, even if it returned zero, an error status
or `nil`.

## Built-in exports

| Library | Export | Signature |
| --- | --- | --- |
| `libm` | `sin`, `cos`, `log`, `exp`, `atan`, `sqrt`, `fabs`, `trunc` | `(f64) f64` |
| `libm` | `ldexp` | `(f64 i32) f64` |
| `libm` | `ilogb` | `(f64) i32` |
| `libc` | `memcmp` | `(byteSlice byteSlice u64) i32` |

The SDL build also registers these `platform` exports. Prefer the Smalltalk
window and PTY APIs for their argument and error handling.

| Export | Signature |
| --- | --- |
| `platform_windows_close`, `platform_windows_set_cursor`, `pty_close`, `pty_foreground` | `(i64) i32` |
| `platform_windows_display_scale`, `platform_windows_refresh_rate` | `(i64) f64` |
| `platform_windows_show` | `(i64 i32) i32` |
| `platform_windows_set_text_input_area` | `(i64 i64 i64 i64 i64 i64) i32` |
| `pty_resize` | `(i64 i64 i64) i32` |

## Launcher grants

For another library, start the VM with `SAMALTAK_NATIVE_GRANTS` in its
environment. The manifest has one `alias|symbol|result(arg1,arg2,...)|/absolute/path`
row per export, with no spaces in the signature. Use `()` for no arguments.
The manifest is limited to 32 rows and 4096 bytes. Aliases use ASCII letters,
digits, `_`, `.` and `-`; symbols are C identifiers. The aliases `libm`,
`libc` and `platform` are reserved; an alias/symbol pair may occur only once.
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
entire call must fit in six native argument slots. By granting `syncBorrow`,
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
ABI's argument registers, calls the target, and converts the result back to a
Smalltalk object. The positional path builds neither a Smalltalk argument
Array nor an array of converted native scalars.

Saving a snapshot does not invalidate bindings in the running VM. A restored
binding keeps its descriptor, not native authority: on first use it must
prepare again against the new VM's registry. Launcher grants are fixed at
startup; revoke a grant by restarting without it. A restored binding whose
grant is missing or no longer matches is rejected before native entry.

Libraries and generated wrappers stay mapped until VM exit. The VM can
publish up to 1024 downcall wrappers per process. Dropping a binding or
flushing the ordinary JIT cache does not reclaim them.

## Headless verification

With a hosted VM and full image, run:

```sh
tests/vm/runtime_native_grants_test.sh build/samaltak.image vm/build/samaltak
tests/vm/wrapped_ffi_specialization_test.sh build/samaltak.image vm/build/samaltak
```

Both checks passed on Linux x86-64. The grant test covers bind-time
validation and reauthorization after restore. The wrapper test covers Array
and positional invocation in interpreter and optimizing JIT modes, native
entry counts on completion and rejection, and restore with reordered or
missing grants. For a hosted `NO_PLATFORM=1` build, pass `--no-pty` to the
wrapper test after the VM path.

The [wrapper benchmark](../vm/tests/bench/wrapped-ffi.py) binds before
timing: it measures warm invocation and allocation, not binding or code
generation. On Linux x86-64 (EPYC 7B13, 10 rounds of 50,000 calls per
case after warmup), the scalar case using `invoke:` with a fresh Array
allocated about 24 more bytes per call than the positional case. In that run,
the median paired time ratio (Array / positional) was 1.94× with `--jit none`
and 1.21× with `--jit opt`.

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
