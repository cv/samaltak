# FFI primitive audit

The original remove-98 set comprises 64 **Adapter** and 34 **Extend**
IDs: 19 core and 79 platform. The hosted process cutover reserves four
additional IDs (515, 516, 518, 560), separate from those 98. The
[retained-primitives report](vm-primitives-retained.html) catalogs the 156
**Keep** IDs. See the [cutover contract](ffi-migrations.md).

## Registry

The [generated registry](../vm/gen/primitive_entries.c) maps numbered
primitive IDs to names and C entry points. The counts below describe scope,
not completed runtime verification.

| Family | Pre-cutover `ff327a9` | Original remove-98 target | Rebased remove-98 | With process cutover |
| --- | ---: | ---: | ---: | ---: |
| Core (including work clock) | 156 | 137 | 137 | 137 |
| Simulator guest display | 7 | 7 | 7 | 7 |
| Platform | 114 | 35 | 36 | 32 |
| FFI infrastructure | 16 | 16 | 16 | 16 |
| **Hosted SDL** | **293** | **195** | **196** | **192** |
| **Hosted `NO_PLATFORM=1`** | **168** | **149** | **149** | **149** |

The rebased SDL registry includes 422 (`windowSetPosition`), which is
outside the original audit and the Keep catalog. `NO_PLATFORM=1` omits
platform rows and FFI notification slots 252–262; `--headless` on an SDL
binary does not. Approved FFI export IDs are separate from these totals.

## Dispositions

- **Adapter:** a narrow typed export or exact-prototype registration fits
  the operation, with checked conversion or bounded input where necessary.
- **Extend:** the operation needs an explicit data, result or ownership
  protocol (see [output protocols](ffi-owned-output.md)).
- **Live:** a facade already uses FFI; its numbered slot is outside this scope.
- **Now:** an existing binding fits, but the numbered slot is outside this scope.
- **Keep:** a numbered slot outside both cutovers, including VM-specific or
  freestanding operations.
- **Process cutover:** a hosted process operation migrated separately.
- **Infra:** implements FFI itself.

The original 98 and the four process IDs are reserved, not aliases.
Reservation does not provide compatibility for an older image. Unassigned
gaps such as 517 are not part of either retirement set.

### Core and infrastructure

| IDs | Disposition | Boundary |
| --- | --- | --- |
| 1–19 | Keep | `prim_int_add` and peers implement tagged arithmetic, overflow/fallback, exact division and JIT fast paths; not C arithmetic. |
| 20–31 | Extend | Arbitrary-precision Integer arithmetic and comparison use checked magnitude inputs; arithmetic boxes owned limbs. |
| 41–51, 62–63, 65 | Keep | Float arithmetic/comparison and IEEE bitcasts; `prim_float_div` rejects zero and `prim_float_hash` defers integral values to Integer hash. `trunc` returns Float; 51 returns an Integer and rejects results outside `[−2⁶², 2⁶²)`. |
| 52 | Adapter | `modf` needs a local output variable; export only the fractional `f64`, preserving signed zero and nonfinite behavior. |
| 53–54 | Now | Two guarded matches: call `ilogb` only for finite nonzero Floats, otherwise return 0; check a SmallInteger exponent and clamp to ±100000 before `ldexp`. |
| 55–60, 64 | Now | Seven direct hosted math matches: `sqrt`, `sin`, `cos`, `atan`, `log`, `exp`, `fabs`. Preserve Float-only inputs, native nonfinite results, and existing JIT/freestanding paths. |
| 61, 172 | Extend | Float printing uses bounded copyout of the shortest round-trip decimal; environment lookup uses owned text, with absent distinct from empty. |
| 70–93 | Keep | Allocation, object layout/identity, mutation/barriers, dispatch, reflection, Characters and case conversion: e.g. `prim_basic_new`, `prim_become_forward`, `prim_string_as_uppercase`. |
| 100–118 | Keep | String formats, indexing, mutability, copy/barriers, endian access and search. `memcmp` compares read-only ByteArray slices, not `prim_string_compare`'s full String/Symbol semantics. |
| 120–121, 130–146 | Keep | Closure activation, scheduling/Semaphores, stack and allocation sampling (`prim_closure_value`, `prim_semaphore_wait`, `prim_process_stack_into`). |
| 150–151, 567–570, 572–578 | Keep | `prim_microsecond_clock` and work-clock controls use scheduler time, including virtual time/pacing. |
| 152–153 | Adapter | Scalar wrappers around `gettimeofday` and the real VM-thread CPU clock, preserving µs and failure/availability policy; no raw time structs. |
| 160–168, 171, 173–174, 180–182, 195–199 | Keep | Lifecycle, GC, VM introspection and unwinding: `prim_snapshot`, `prim_vm_stats`, `prim_jit_send_sites`, `prim_terminate_to`. |
| 169–170 | Adapter | Counted input to the existing VM streams (`fwrite` + `fflush`), not arbitrary fds or stream pointers. Preserve embedded NUL, surrogateescape and receiver. |
| 200–206 | Keep | Simulator guest-display bridge (`prim_display_open` through `prim_display_flush`); the [Smalltalk-80 Workspace example](vm-primitives-retained.html#guest-display) shows the guest/host boundary. |
| 250–251, 263–265 | Infra | `ffiBind/ffiInvoke` legacy word path; `ffiPrepare/ffiBoundInvoke/ffiBoundInvokeArray` prepared downcalls. |
| 252–262 | Infra | Vsync 252–254, SDL logs 255–258 and test probe 259, external grants 260–262. Native latch/queue, not a Smalltalk callback. |

### Windows, input and GPU

| IDs | Disposition | Boundary |
| --- | --- | --- |
| 401, 404, 406–409, 419 | Live | Already routed by `GPUPrimitives`: `platform_windows_close`, scale/rate, visibility, cursor shape and IME area (seven IDs, six exports). Zero fails status calls; negative fails scale/rate, zero rate is valid. |
| 402–403, 418, 421 | Adapter | Pack one checked width/height pair from `platform_windows_size`/`pixel_size` (points/pixels); `PlatformEvents>>dropped` and validated `set_size` are scalar. |
| 400, 405, 411 | Adapter | `platform_windows_open`, `set_title`, `clipboard_set`: counted text with surrogateescape, embedded-NUL rejection and a native terminated copy; no exposed C strings. |
| 410, 415, 417, 420 | Extend | Clipboard text uses a paged lease; last error and handle counts use fixed copyout. Clipboard MIME bytes use a 20 MiB bound. |
| 412–413 | Extend | Marshal an event record with fixed metadata and variable text. Preserve one dequeue, empty-queue status and readiness rearming. |
| 414, 416 | Keep | Input/vsync register with the scheduler and affect rearming. FFI latches don't replace legacy delivery. |
| 430–432, 435–438, 441, 444–448, 450–451 | Adapter | Scalar GPU calls need exact widths, bool/f32 conversion, typed handles and SDL thread/ownership checks. Draw uses the general backend; release dispatches by handle kind and end-pass consumes the handle. |
| 439, 449 | Adapter | `upload_buffer`/`push_uniforms` can borrow an exact read-only ByteArray prefix with bounds checked before narrowing. Normalize admitted byte objects to the required view; consume or copy data before returning. |
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
| 515–516, 518, 560 | Process cutover | Spawn returns a PID; wait selects and reaps by PID (not a PTY handle); exec replaces the VM process on success; PTY spawn returns a handle and PID together. |
| 542, 545–547, 549, 553–555, 564–565 | Adapter | `platform_sockets_accept` can flatten local would-block into pending vs handle vs failure. Socket/TLS/PTY setters take numeric readiness indices; scheduler still signals OOPs. `platform_ptys_wait` can encode status/pending/error for a PTY handle; blocking still blocks the VM. |
| 540–541, 548, 550 | Adapter | Counted text for listen/connect, lookup and TLS start. `platform_sockets_lookup` copies before worker handoff; `platform_tls_start` preserves verified-host setup and transfers the handle on success. |
| 543, 551, 561 | Extend | `platform_sockets_recv`, `platform_tls_recv`, `pty_read` need writable caller slices. Preserve zero at EOF, would-block/nil and distinct facade failure. |
| 544, 552, 562 | Adapter | `platform_sockets_send`, `platform_tls_send`, `pty_write`: bounded read-only bytes, partial writes and rearming; normalize admitted non-ByteArray inputs. If TLS retains a retry pointer, use native-owned storage. |
| 563, 566, 571 | Live | `pty_resize`, `pty_close`, `pty_foreground` used by `PseudoTerminal`; status zero (resize/close) or negative (foreground) maps to nil without retry; resize bounds 1–65535. |
| 580–584 | Keep | Raw NIC capability, frame ownership/writable receives, readiness semaphore and status records. Do not expose firmware addresses or handles as generic grants. |
