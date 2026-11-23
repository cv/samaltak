# FFI primitive audit

The PR adds typed native calls without removing or renumbering primitives.
The [generated registry](../vm/gen/primitive_entries.c) maps ID to name and
C symbol. The tables cover all IDs once; gaps (including 517) are unassigned.
See the [decision](#decision) and [headless sin probe](#headless-sin-probe).

## Registry

| Family | IDs | main `fce26a3` | PR |
| --- | --- | ---: | ---: |
| Core (including work clock) | 1–199, 567–570, 572–578 (registered IDs only) | 156 | 156 |
| Legacy display | 200–206 | 7 | 7 |
| Platform | 400–421, 430–461, 470–478, 480–483, 500–516, 518, 540–555, 560–566, 571, 580–584 | 114 | 114 |
| FFI infrastructure | 250–265 | 0 | 16 |
| **Total, hosted platform build** | | **277** | **293** |
| **Total, hosted `NO_PLATFORM=1`** | | **163** | **168** |

Counted table initializers by ID and guard: neither revision has duplicate
IDs or OS-specific alternatives in this file. `SAMALTAK_NO_PLATFORM` drops
all 114 platform rows plus 252–262 on the PR; `--headless` on a platform
binary does not. The normal simulator loads the core rows (including the
guest display bridge) and omits VM-Platform; a platform-adapter simulation
can load those same IDs, not additional entries.
[UEFI](uefi.md) has a separate freestanding translation: native FFI wrappers
and notifications are unavailable; keep its machine, NIC and raster paths
(and existing fallbacks). A registered primitive need not be implemented on
every target.

`PlatformPrimitives` has 67 generated adapters and 47 handwritten methods
on the PR, not 67 descriptor bindings. Ten facade methods use nine distinct
platform exports; all ten retain legacy slots.

## How to read the dispositions

- **Live:** already FFI-first in the hosted production facade.
- **Now:** existing binding fits; production still uses the primitive.
- **Adapter:** a narrow typed wrapper or exact-prototype allowlist entry fits
  today’s scalar ABI (including packing/scalarizing fixed results or a bounded
  read-only borrow where noted). A generated primitive adapter is not an
  approved FFI export.
- **Extend:** needs bounded data, result or ownership semantics beyond a
  narrow adapter, even if existing bytes could serve as transport.
- **Keep:** VM-specific, freestanding, or no case for replacing it.
- **Infra:** provides FFI itself, not a migration candidate.

Of the 277 pre-existing IDs: 10 Live, 9 Now, 64 Adapter, 34 Extend,
160 Keep. The 16 Infra IDs are separate.

The [FFI contract](ffi.md) permits exact approved signatures, six native
argument slots, and no raw pointers, general callbacks, native writes into
heap buffers, or pointer/aggregate results. A `syncBorrow` uses exact ByteArray
slices with SmallInteger offset/count and checked 1-based bounds. The pointer
and derived length use two native slots; no writes, retention, handoff or VM
reentry. A built-in borrow needs explicit approval. Wrappers consume arguments
before native entry; result boxing can move objects. Preserve VM
roots, barriers and safepoints; never keep interior heap pointers across GC.
A numeric handle does not grant pointer authority. Preserve kind/lifetime,
SmallInteger-only checks and narrowing where the primitive requires them;
a descriptor’s `i64` accepts fitting LargeIntegers too. Existing window/PTY
exports narrow to C `int32_t` like their legacy calls; do not assume `i64`
means a 64-bit handle or a range check.

Fallback is for pre-entry rejection only (`false` in the private invoke
protocol). Native zero, negative status and `nil` for `void` are completed
calls: translate each operation’s status without retrying. Keep old slots
and errors for saved images and targets without FFI. Rebind after restore
against the new registry; that does not revive resource handles. Logical
exports are image-wide rights, not C linker symbols or private methods.

## Dispositions

### Core and infrastructure

| IDs | Disposition | Boundary |
| --- | --- | --- |
| 1–19 | Keep | `prim_int_add` and peers implement tagged arithmetic, overflow/fallback, exact division and JIT fast paths; not C arithmetic. |
| 20–31 | Extend | `prim_large_add` and peers consume arbitrary-precision Integers; fixed-width FFI scalars cannot carry their limbs/results. Keep the VM implementation. |
| 41–51, 62–63, 65 | Keep | Float arithmetic/comparison and IEEE bitcasts; `prim_float_div` rejects zero and `prim_float_hash` defers integral values to Integer hash. `trunc` returns Float; 51 returns an Integer and rejects results outside `[−2⁶², 2⁶²)`. |
| 52 | Adapter | `modf` needs a local output variable; export only the fractional `f64`, preserving signed zero and nonfinite behavior. |
| 53–54 | Now | Two guarded matches: call `ilogb` only for finite nonzero Floats, otherwise return 0; check a SmallInteger exponent and clamp to ±100000 before `ldexp`. |
| 55–60, 64 | Now | Seven direct hosted math matches: `sqrt`, `sin`, `cos`, `atan`, `log`, `exp`, `fabs`. Preserve Float-only inputs, native nonfinite results, and existing JIT/freestanding paths. |
| 61, 172 | Extend | `prim_float_print_string` needs an owned shortest-round-trip String; `prim_getenv` needs copied text with absent distinct from empty. |
| 70–93 | Keep | Allocation, object layout/identity, mutation/barriers, dispatch, reflection, Characters and case conversion: e.g. `prim_basic_new`, `prim_become_forward`, `prim_string_as_uppercase`. |
| 100–118 | Keep | String formats, indexing, mutability, copy/barriers, endian access and search. `memcmp` compares read-only ByteArray slices, not `prim_string_compare`'s full String/Symbol semantics. |
| 120–121, 130–146 | Keep | Closure activation, scheduling/Semaphores, stack and allocation sampling (`prim_closure_value`, `prim_semaphore_wait`, `prim_process_stack_into`). |
| 150–151, 567–570, 572–578 | Keep | `prim_microsecond_clock` and work-clock controls use scheduler time, including virtual time/pacing. |
| 152–153 | Adapter | Scalar wrappers around `gettimeofday` and the real VM-thread CPU clock, preserving µs and failure/availability policy; no raw time structs. |
| 160–168, 171, 173–174, 180–182, 195–199 | Keep | Lifecycle, GC, VM introspection and unwinding: `prim_snapshot`, `prim_vm_stats`, `prim_jit_send_sites`, `prim_terminate_to`. |
| 169–170 | Adapter | Counted input to the existing VM streams (`fwrite` + `fflush`), not arbitrary fds or stream pointers. Preserve embedded NUL, surrogateescape and receiver. |
| 200–206 | Keep | Simulator guest-display bridge (`prim_display_open` through `prim_display_flush`); native builds have no guest-display surface. Not host SDL. |
| 250–251, 263–265 | Infra | `ffiBind/ffiInvoke` legacy word path; `ffiPrepare/ffiBoundInvoke/ffiBoundInvokeArray` prepared downcalls. |
| 252–262 | Infra | Vsync 252–254, SDL logs 255–258 and test probe 259, external grants 260–262. Native latch/queue, not a Smalltalk callback. |

### Windows, input and GPU

| IDs | Disposition | Boundary |
| --- | --- | --- |
| 401, 404, 406–409, 419 | Live | Already routed by `GPUPrimitives`: `platform_windows_close`, scale/rate, visibility, cursor shape and IME area (seven IDs, six exports). Zero fails status calls; negative fails scale/rate, zero rate is valid. |
| 402–403, 418, 421 | Adapter | Pack one checked width/height pair from `platform_windows_size`/`pixel_size` (points/pixels); `PlatformEvents>>dropped` and validated `set_size` are scalar. |
| 400, 405, 411 | Adapter | `platform_windows_open`, `set_title`, `clipboard_set`: counted text with surrogateescape, embedded-NUL rejection and a native terminated copy; no exposed C strings. |
| 410, 415, 417, 420 | Extend | `clipboard_get`, last error, handle-count array and owned `clipboard_data` MIME bytes (20 MiB cap) need bounded results and copy/ownership. |
| 412–413 | Extend | `prim_next_event`/`prim_inject_event` marshal an event record (text, coordinates, window, etc.); preserve queue and no-event semantics. |
| 414, 416 | Keep | Input/vsync register with the scheduler and affect rearming. FFI latches don't replace legacy delivery. |
| 430–432, 435–438, 441, 444–448, 450–451 | Adapter | `claim_window`, `set_viewport` and the other scalar GPU calls need exact widths, bool/f32 conversion, typed handles and SDL thread/ownership checks. `release_handle` dispatches by kind; `end_pass` consumes a handle. |
| 439, 449 | Adapter | `upload_buffer`/`push_uniforms` can borrow an exact read-only ByteArray prefix with bounds checked before narrowing. Data is copied to native storage before return; legacy byte objects/Bitmaps need a path. |
| 443 | Adapter | Split `begin_pass` into load and clear; four doubles plus two handles fit six slots, with a local float array. |
| 453–455, 458–460 | Adapter | `submit`: consume once, separate failure/no fence/fence; `fence_done` and `fence_elapsed`: distinguish bad handle from pending. Wait/idle block the VM thread; `shader_language` can return a checked enum. |
| 433–434, 440, 442, 452, 456, 461 | Extend | Shader/pipeline and blit shapes exceed flat arity; `upload_texture` needs a bounded region/stride with read-only input; `acquire_swapchain` needs an atomic tagged triple (or no texture); `download` writes a bounded destination; `platform_gpu_compile_shader` returns owned bytes. |
| 457 | Keep | `texture_size` returns a triple; no production consumer found to justify a result adapter. |

### Machine, raster and I/O

| IDs | Disposition | Boundary |
| --- | --- | --- |
| 470–478 | Keep | Firmware addresses/calls, native allocation/memory and watched events (`prim_machine_call`, `prim_machine_watch`); scalar-looking is not safe authority. |
| 480–483 | Keep | `prim_raster_draw/fill/blit/copy` decode surfaces, bounds, formats, strides and writable buffers or firmware addresses. |
| 500–501, 503–509, 512, 514 | Adapter | `platform_files_size`, `position`, `seek` and close/flush fit scalars; writes borrow bounded read-only bytes; paths need the same counted-text rules as titles. |
| 502, 510–511, 513 | Extend | `platform_files_read` writes into the caller’s slice; stat is one compound observation, directory/cwd results are owned text. |
| 515–516, 518, 560 | Keep | `platform_files_spawn`/`platform_ptys_spawn` marshal argv/env as applicable; general `process_wait` selects/reaps by PID; exec replaces the VM process. |
| 542, 545–547, 549, 553–555, 564–565 | Adapter | `platform_sockets_accept` can flatten local would-block into pending vs handle vs failure. Socket/TLS/PTY setters take numeric readiness indices; scheduler still signals OOPs. `platform_ptys_wait` can encode status/pending/error for a PTY handle; blocking still blocks the VM. |
| 540–541, 548, 550 | Adapter | Counted text for listen/connect, lookup and TLS start. `platform_sockets_lookup` copies before worker handoff; `platform_tls_start` preserves verified-host setup and transfers the handle on success. |
| 543, 551, 561 | Extend | `platform_sockets_recv`, `platform_tls_recv`, `pty_read` need writable caller slices. Preserve zero at EOF, would-block/nil and distinct facade failure. |
| 544, 552, 562 | Adapter | `platform_sockets_send`, `platform_tls_send`, `pty_write`: bounded read-only bytes, partial writes and rearming; non-ByteArray inputs need a legacy path. If TLS retains a retry pointer, use native-owned storage. |
| 563, 566, 571 | Live | `pty_resize`, `pty_close`, `pty_foreground` used by `PseudoTerminal`; status zero (resize/close) or negative (foreground) maps to nil without retry; resize bounds 1–65535. |
| 580–584 | Keep | Raw NIC capability, frame ownership/writable receives, readiness semaphore and status records. Do not expose firmware addresses or handles as generic grants. |

## Performance evidence

[Bound-site measurements](benchmarks.md#bound-ffi-call-sites) on hosted
Linux x86-64 compare the same binary with the optimization on/off: warm
matched scalar 27.5 → 9.5 ns/call; live PTY facade foreground 844.3 → 781.1 ns,
resize 1095.8 → 1008.7 ns. Dedicated primitive controls are separate; this
is not a main-vs-PR comparison. The older [descriptor trial](../vm/tests/bench/descriptor-ffi.md)
used invalid window handles (error paths, not live windows).
### Headless sin probe

On Linux x86-64 at `20d7ce0`, stock Float and both FFI forms agreed on 11
inputs for each of the seven direct matches. For warm `sin`, dedicated vs
pre-bound positional medians were **86.8 vs 106.0 ns/call** in the interpreter
and **49.0 vs 44.5** with opt (site hits verified). The opt paired ratio
ranged 0.76–1.17×; disabling `ffi-site` gave **49.8 vs 67.0**.
This is one input loop on one host, not a facade or cold-binding benchmark.
No window calls were run.

## Decision

No migration or ABI expansion here. If a follow-up can remove duplicate
authored glue, pilot **505 `filePosition`** first, then **504 `fileSize`**.
Use the existing handle table and signed result; preserve buffered position
and error mapping. Compare a warmed positional facade against the dedicated
primitive and a forwarding control on the same live file; check zero and
nonzero offsets, read-ahead, invalid/closed handles, and old-image,
simulator and UEFI behavior. Measure first-bind cost separately.

Retire duplicated authored wrappers only if one audited declaration can
emit both the approved FFI registration and the compatibility entry.
Keep the numbered slots. If that doesn't remove authored glue without
expanding authority or regressing behavior, keep the current adapters.
