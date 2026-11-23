# Prepared FFI migrations (PR 8)

Scope: the 64 **Adapter** and 34 **Extend** IDs in the
[primitive audit](ffi-primitive-audit.md). Existing **Live**, **Now**,
**Keep** and **Infra** IDs are not migration credit. Keep the numbered
primitive slots, original public API and legacy behavior. A candidate
provides a second implementation, not an alias for the primitive.

## Implementation plan and contract

1. **Prove the scalar lane first.** Declare exact prototypes on typed
   Lowtalk `FFIPrimitives` (core) or `SDLPlatform` (platform) methods.
   Generate registry entries from those declarations; keep `src` authoritative.
   Keep the legacy adapter, sharing only typed backend operations. Pilot 505
   then 504 on live files (including buffered read-ahead). Make the image
   facade callable as a production-shaped alternative without switching the
   public send. Bind once and reuse the prepared positional wrapper; use the
   existing guarded positional JIT where eligible. Count native slots after
   lowering, not just Smalltalk arguments (maximum six). The new logical
   `vm:core` and `platform` entries are built-ins, prepared-only, and
   never resolved via launcher authority. Test exact signature mismatches,
   reserved aliases (including existing `core` grant compatibility) and
   250/251 rejection.
2. **Specify bounded data before adopting it.** Read-only counted input
   carries a pointer and exact length; copy before native retention or
   worker handoff. Text follows each legacy operation's encoding
   (including surrogateescape); use a native terminated copy and reject
   embedded NUL only for operations that require C strings. Keep older
   admitted types on the legacy path when the narrowed FFI view does not
   admit them. A writable slice is an explicitly approved prepared built-in,
   never a launcher grant or a 250/251 word call. Accept only exact mutable
   ByteArrays with checked 1-based offset and count; check all arguments
   before entry, including on JIT hits, and bound every write. Use
   `bytesWithLength` for read-only input and `writableBytesWithLength` for
   mutable output; each occupies two C slots. The borrow is synchronous:
   no retention, handoff, VM reentry or GC during the borrow. Never expose
   addresses, raw OOPs or hidden shared return storage.
3. **Choose a result format per operation before writing its adapter.**
   Scalarize fixed values only with unambiguous status and lossless
   ranges. For compound results, define byte order, fields, size caps and
   success/no-result/error tags; use one bounded copyout or an owned
   immutable native result with typed copy and explicit release. The
   proposed owned path reserves a process-local ticket before the call;
   the producer can publish once, then the image copies at most the
   reserved capacity and releases in `ensure:`. Keep the table on the VM
   thread, bound both per-result and total storage, reject stale tickets,
   and distinguish present-empty from absent. Capture side-effecting or
   changing results once (stat, events, swapchain, etc.): no size probe
   that reruns the operation. Decode only complete, validated records;
   allocate or box only after borrowed addresses are dead. For large
   records and excess arity, use a bounded versioned record or a narrowly
   split operation that preserves atomicity. If an admitted result can
   exceed a cap and cannot be excluded before entry, that route is not at
   parity. Do not install generic pointer, aggregate, callback or OOP ABIs.
4. **Stage the facade and prove both routes.** Preserve receiver, input
   admission and narrowing, object shape, native status, errors, handle
   kind/lifetime/thread rules, scheduler rearming and partial I/O.
   Fallback is allowed only when unavailable or rejected **before** native
   entry. After entry, nil, zero, error, pending and partial progress are
   results, never reasons to retry the primitive. A JIT guard miss may use
   the normal prepared send; distinguish that from a primitive fallback.
   Old images retain their slots. Restored descriptors reauthorize against
   the current registry; native resources, wrappers and result tokens do
   not survive restore. No implicit rebinding of stale resource handles.
5. **Promote by route, not by family.** Land coherent, callable alternatives
   first. Run the correctness and timing gates below before routing
   production sends. Do not use default callers as a trial for an
   unmeasured or known-slower path. Keep unsupported backends on their
   existing paths; do not change an unsafe backend to make the count look
   complete.

## Evidence gates

| State | What earns it for an ID |
| --- | --- |
| `planned` | Audited only, or partial: a design, native method, descriptor, facade stub or tests without a complete built/loaded route. Name the missing piece. |
| `implemented/staged` | Typed native target and exact approved registration connected to a full callable facade with the original path preserved. Built/loaded together; not a default. List any excluded input or backend. |
| `tested` | On the staged build, real eligible inputs reach the alternative and match legacy results and effects. Entry/fallback is independently distinguished; rejection/negative cases and relevant compatibility modes have explicit results. Report narrower passing checks separately, without promoting a partly tested row. |
| `measured` | The tested route has current, paired measurements on the promotion matrix below, including its actual facade cost. A measurement may fail the promotion gate. |
| `default` | The public send demonstrably selects the alternative on the documented eligible routes after passing correctness and timing gates; legacy still works elsewhere. |

Correctness requires zero contract mismatches and zero unexpected fallback on
eligible success cases. For selected operations, assert one entry and matching
effects on success and on native failure, and zero entries on pre-entry
rejection. Exercise public calls and candidate calls independently; wrapper
unit tests alone do not prove facade selection. Cover nontrivial lengths and
bounds, invalid/stale handles, writable guard bytes, lifetime and cleanup,
snapshot restore, moving GC/deopt on eligible routes, and asynchronous
handoff/readiness cases where applicable. Compare exact results and shapes
when deterministic; for clocks, concurrent events and asynchronous completion
use documented invariants rather than equating unrelated observations.

Test and report separately:

| Surface | Required evidence |
| --- | --- |
| Hosted, display-free | Full image plus selected facade tests with valid files, sockets, TLS, PTYs or numeric inputs as applicable. Check interpreter (`--jit none`), baseline, and opt; opt with `-ffi-site` is a separate control, not proof of an optimized hit. |
| Hosted, display/graphics | CI only: a real window, real clipboard/event data and valid GPU resources, with a successful acquire/draw/submit/readback or operation-specific equivalent. Invalid handles and SDL's headless startup do not qualify. Run display-dependent suites through the CI jobs, not local display or Xvfb. |
| Snapshot/image | Record image build/revision and fresh vs restored route. Check old numbered slots, rebind/missing registry and stale resources; an image build alone is not parity. |
| Hosted `NO_PLATFORM=1` | Separate build; check eligible core calls and availability/fallback without SDL exports. An SDL binary with `--headless` is not this build. |
| Simulator; UEFI | Check legacy behavior independently on each, using the relevant primitive or fallback. No native adapter/performance credit for either. A UEFI build is not a firmware run. |

For each promotion target (OS/architecture/backend), pair legacy and candidate
on the same build and valid fixtures in `none`, `baseline` and `opt`. Use
`--jit opt --jit-flags -ffi-site` as a separate control; if that mode is part
of the proposed rollout, gate it too. Use balanced AB/BA pairs and
equivalent fresh resources for consuming operations. Report wall/CPU time
per operation, allocation/GC and first bind/use separately from warm calls.
Use a 95% simultaneous interval over independently restarted process medians,
not over correlated pairs within a VM. At-par requires an upper bound
**≤ 1.0** for candidate/legacy in every required case and mode. A lower
bound > 1.0 is a slowdown; insufficient or overlapping evidence is not a
pass. Pair representative workloads against `origin/main` as an integration
control (repository gate: reproducible regressions over 5% block).

Count routed operations, match successful outcomes/sample sizes and verify
opt hits when claiming site speed. Include facade marshalling, copies and
decode; raw wrapper timing and invalid-handle loops are only diagnostics.
A CI timing sample is not a quiet-host promotion result. Historical numbers
in the audit or benchmarks do not count.

## Follow-up slices

| Slice | Next gate |
| --- | --- |
| Files (500–514) | Start with 505/504 on valid buffered files, then 503/502 with offset/canary and EOF checks. Stage path and handle operations; 510 needs one compound stat, 511/513 need owned surrogateescape text. For 511, preserve large directories with a separately bounded streaming copy of one native result or keep legacy; no truncation or re-enumeration. |
| Core (20–31, 52, 61, 152–153, 169–170, 172) | Prove scalar fraction part, real clocks and VM stream writes (including binary text). Use bounded text copyout for 61 and owned text for 172, preserving absent versus empty. Pilot 27 with a vetted signed-magnitude input and scalar result; cover 20–26/28–31 only after a bounded result and exact oversized behavior are specified. Do not replace VM arithmetic by fixed-width scalars. |
| Window/input (400, 402–403, 405, 410–413, 415, 417–418, 420–421) | Prove the window and text scalars in graphics CI; prove a single queue dequeue and full record roundtrip for 412/413. Cover owned text/error/counts and MIME bytes with cap and lifetime checks for 410/415/417/420. |
| GPU (430–456, 458–461) | Pair a real render workload with typed handle lifecycle and fence outcomes. Specify bounded shader/pipeline and blit records (433/434/452), upload region/stride (440), atomic acquire (442), bounded download (456) and owned shader bytes (461) before switching senders. |
| Socket/TLS/PTY (540–555, 561–562, 564–565) | Loopback and verified TLS plus a real child PTY; prove would-block vs EOF vs error, partial sends, wakeups and close/ownership. Verify TLS retry storage never retains a borrowed pointer and PTY wait reports status/consumes as before. |

## API and route boundaries

Candidate selectors are opt-in image methods, not new public APIs. The
registry invokes a typed native function independently of the old numbered
entry. Review sources and report route evidence at the following boundaries:

| Family | Image boundary | Successful-route witness |
| --- | --- | --- |
| Files | `File class>>ffiCandidatePrim*` in [File](../src/System-Files/File.st); not a FileStream cutover. | [FileFFITest](../src/Tests-Kernel/FileFFITest.st) uses real temporary paths/descriptors, not an invalid ID loop. 510 is one stat; 511/513 copy from one native observation using a paged, process-local owner. Its 16 live-owner limit and existing backend bounds still apply. |
| Core | Candidate siblings on `Float`, `Time class`, `VirtualMachine` and `Integer`; `vm:core` is not an alias for a launcher grant. | [Core fixture](../tests/vm/core_ffi_test.py) checks real numerics, clocks, output bytes and environment values; [bigint fixture](../tests/vm/bigint_ffi_test.sh) distinguishes signed-magnitude native entry from Integer fallback. |
| Window/input | Candidate siblings on `GPUPrimitives class` and `VirtualMachine`; not a scheduler registration change. | [Window fixture](../tests/vm/window_ffi_test.sh): headless queue/overflow and handle diagnostics, separately from display-CI window/clipboard success. Empty headless state cannot prove a successful graphics route. |
| GPU | Candidate siblings on `GPUPrimitives class`; native handles keep kind, thread and consumption rules. | Graphics CI must use a real device, resources and pass; compiler or static registry success is not an actual render test. |
| Socket/TLS/PTY | `RemoteSocket class>>ffiCandidatePlatform*` is hosted only and does not replace dispatch to `NetworkStack`. `TLSSocket class` and `PseudoTerminal class` have separate `ffiCandidatePrim*` siblings. | [Socket fixture](../tests/vm/socket_ffi_test.py) checks loopback, verified localhost TLS, and a child PTY. Test WANT retry storage, native close and switching between candidate/legacy while progress is pending. |

## Recorded checks

Do not read a passing control as a migrated route. The proof harness runs
with native-entry tracing or traps on the legacy send; timing runs use the
same real fixture with tracing off. See the
[paired harness](../vm/tests/bench/ffi-paired.md) for commands.
Explicit publication in a disposable trial is not a production default.

| Check | Result and scope |
| --- | --- |
| Direct controls | Fresh Linux x86-64 hosted LTO build of `cbe6326`: 29 direct fixtures each in none/baseline/opt (87 runs), with zero approved entries. Legacy loopback/TLS/PTY fixtures passed all three modes. These are controls, not timing or alternative-entry evidence. |
| Shared counted text | Hosted x86-64 `cbe6326` VM with staged image source: `PlatformFFITextTest NativeCountedTextTest FileTest`, 17/17 each in none/baseline/opt. Includes Lowtalk helper simulation, not a simulator migration run. Native helper guard-page test passed; helper compiled for UEFI x86-64, not a firmware boot. |
| Registry and seeded bindings | Live source file-in on hosted release controls: exact registry prototype and duplicate-key rejection; literal binding validation and actual existing `libm` downcall. Warmed literal rebind after restore passed none/baseline/opt on `cbe6326` with source file-in. This does not prove restore for any new export. |
| Launcher/legacy gates | [Manifest](../tests/vm/ffi_migration_manifest_test.sh) and legacy controls passed on hosted controls. Isolated Linux x86-64 `NO_PLATFORM=1` [writable](../tests/vm/writable_ffi_test.sh) fixture: 80 native entries per mode (none/baseline/opt/opt without site), including completed error and boxing/GC; release denied the test export. AArch64 Linux `NO_PLATFORM=1` cross-build/QEMU also produced 80 entries per mode; QEMU is not native-host performance evidence. Focused resolver check rejects mismatched result/slice modes, unavailable platform IDs and wrong names. These are infrastructure checks, not 98-ID credit. |
| New core routes | `migration98-integ5-155237-2` Linux x86-64 SDL-hosted `-O0` VM with canonical seed: `python3 tests/vm/core_ffi_test.py IMAGE VM --trace`. 52/61/152/153/169/170/172 passed in none/baseline/opt, with exact native entry counts (11/24/1/1/2/2/4) per mode and no legacy fallback. Matched stage2 image also passed all seven; proof-only workload ran 30 case/mode combinations with 64 candidate entries and zero direct entries. The new seed on the `cbe6326` hosted VM passed the missing-export controls in all three modes. This is not LTO timing, `NO_PLATFORM` candidate or firmware evidence. |
| ID 27 (bigint compare) | Same hosted diagnostic VM/seed, `tests/vm/bigint_ffi_test.sh IMAGE VM --trace`: 1,589 native entries per mode, including prepared Array, positional, candidate facade and post-GC; missing-export fallback separately passed on hosted control. This does not implement the eleven result-producing bigint primitives. |
| Files 500–514 | Same diagnostic VM/seed, `--headless --test FileFFITest FileTest`: 18/18 per mode, all 15 typed export IDs traced. On full stage2 image, six paired workload shapes verified exact 300 candidate entries and zero direct entries in each mode (18 combinations, proof-only). New VM + old image: 12/12 legacy `FileTest`, no new entries. |
| Socket/TLS/PTY | Same diagnostic VM/seed, `tests/vm/socket_ffi_test.py VM IMAGE --jit MODE --trace`: all 20 routes traced in none/baseline/opt including trusted TLS, mixed retry, real I/O and readiness. New seed + old VM fallback passed all modes. Five workload shapes passed the route-only controls (15 combinations); no timing inferred. |
| Window/input | Same diagnostic VM/seed, `tests/vm/window_ffi_test.sh IMAGE VM`: headless none/baseline/opt passed with 412/413/415/417/418 entry counts 11/4,106/1/1/3 in each mode. No display-dependent operation entered. Clipboard text and event text still have the owned-output cap gap. |
| Graphics | Freeze2 generated and linked all 30 staged GPU alternatives with image facades, including 433/434/452/461. 450 remains without a shared-tree alternative. No local display or graphics measurements. Require the valid-input display CI witness before advancing any of these rows. |
| Restored image | `tests/vm/ffi_trial_test.sh` passed on the same hosted diagnostic build: FileStream reaches 504 during explicit trial, then uninstalls; restored normal snapshot uses legacy. Shared ticket restore/unwind passed with an owned fixture, not with every family's live result. |
| Owned-copy authority | Integ5 x64 hosted diagnostic and test-export relink, [owned fixture](../tests/vm/owned_ffi_test.sh): 135 producer entries per mode (none/baseline/opt); separate gate verifies reserve/copy, unwind/termination and denies old ticket after restore. No operation ID credit. |

## Release pilot: 504, 505, 52

Same Linux x86-64 SDL VM and stage2 image, default LTO,
`migration98-integ5-155237-2`; stage2 C regenerated byte-for-byte. Pinned
CPU 1; 15 fresh sessions per stratum, four balanced AB/BA pairs per
session, 8,000 warmup and 12,000 timed calls per arm. Separate proofs
witnessed 128 entries per candidate and zero direct entries in each of
21 strata. Values are candidate/legacy wall ratios with simultaneous 95%
intervals. See the [paired harness](../vm/tests/bench/ffi-paired.md).

| Real workload | Interpreter | Baseline | Opt |
| --- | ---: | ---: | ---: |
| 505 buffered file position, 4 KiB | 1.055 [1.030, 1.070] | 1.063 [1.050, 1.075] | 0.943 [0.923, 0.956] |
| 504 file size, 4 KiB | 1.044 [1.027, 1.057] | 1.036 [1.025, 1.039] | 0.959 [0.947, 0.977] |
| 52 Float fraction part | 1.357 [1.322, 1.540] | 1.680 [1.553, 1.788] | 0.993 [0.902, 1.098] |

1 B and 1 MiB files agree in direction. File opt passes this local gate but
all interpreter/baseline cases are slower. Float opt is inconclusive and
order-sensitive. The at-par check exited 1. Keep all three defaults on the
legacy primitive. Next, isolate cached versus seeded facade costs on the
same real calls, then rerun the full pilot and fresh-bind/resource tests;
an opt-only win is not approval. No cross-backend or historical timing
counts toward this result.

## Status ledger

The ledger is keyed to audit revision `cbe6326`. Expand each Adapter and
Extend range and join its ID to [the numbered registry](../vm/gen/primitive_entries.c).
There are 98 distinct IDs: 64 Adapter and 34 Extend. The registry names below
identify legacy slots, not new native symbols or Smalltalk API selectors.
States show the highest gate met; a single passing check never marks a partial
migration complete. Record exact exports and selector/class side separately from
legacy primitive names. For every build/test claim include the artifact and
revision, command, target, mode, result and route witness. Label build-only,
fixture-only, skipped, failed and not run distinctly.

**Evidence snapshot:** 12 planned, 86 implemented/staged, 0 tested,
0 measured, 0 default. Integ5 witnessed hosted native success on 48 IDs;
38 more are built in freeze2 but have no display-native proof. The release
pilot timed three IDs on one host; none qualifies as a default. No ID has
cleared the full target-matrix gate.

### Core (19)

| ID | Registered primitive | Audit | State | Proof still needed |
| ---: | --- | --- | --- | --- |
| 20 | `largeAdd` | Extend | planned | Signed-magnitude add, carry and normalized result |
| 21 | `largeSub` | Extend | planned | Subtract across signs and normalize zero |
| 22 | `largeMul` | Extend | planned | Multi-limb product, bounded output and overflow fallback |
| 23 | `largeQuo` | Extend | planned | Truncating quotient, negative signs and zero divisor |
| 24 | `largeRem` | Extend | planned | Truncating remainder sign and zero divisor |
| 25 | `largeFloorDiv` | Extend | planned | Floor quotient on mixed-sign operands |
| 26 | `largeMod` | Extend | planned | Floor modulo on mixed-sign operands |
| 27 | `largeCompare` | Extend | implemented/staged | Matched 1,589 native compare entries/mode on hosted proof build; core backend matrix pending. |
| 28 | `largeBitAnd` | Extend | planned | Bitwise AND with negative/sign-extension cases |
| 29 | `largeBitOr` | Extend | planned | Bitwise OR with negative/sign-extension cases |
| 30 | `largeBitXor` | Extend | planned | Bitwise XOR with negative/sign-extension cases |
| 31 | `largeBitShift` | Extend | planned | Left/right shift, negative and oversized shifts |
| 52 | `floatFractionPart` | Adapter | implemented/staged | Hosted exact IEEE fixture and LTO pilot; interpreter/baseline slower, opt inconclusive; keep legacy. |
| 61 | `floatPrintString` | Extend | implemented/staged | Owned shortest-round-trip String, including special values — SDL-hosted fixture passed; target matrix outstanding. |
| 152 | `utcMicroseconds` | Adapter | implemented/staged | Wall-clock microseconds and failure/availability — SDL-hosted fixture passed; target matrix outstanding. |
| 153 | `threadCpuTime` | Adapter | implemented/staged | VM-thread CPU microseconds and clock availability — SDL-hosted fixture passed; target matrix outstanding. |
| 169 | `stdoutWrite` | Adapter | implemented/staged | Counted stdout bytes, flush and receiver — SDL-hosted fixture passed; target matrix outstanding. |
| 170 | `stderrWrite` | Adapter | implemented/staged | Counted stderr bytes, flush and receiver — SDL-hosted fixture passed; target matrix outstanding. |
| 172 | `getenv` | Extend | implemented/staged | Owned environment text: absent, empty and nonempty — SDL-hosted fixture passed; 64 MiB capture limit and NO_PLATFORM outstanding. |

### Window/input (13)

| ID | Registered primitive | Audit | State | Proof still needed |
| ---: | --- | --- | --- | --- |
| 400 | `windowOpen` | Adapter | implemented/staged | Counted title, live open and handle ownership |
| 402 | `windowSize` | Adapter | implemented/staged | Losslessly pack point dimensions from one live query |
| 403 | `windowPixelSize` | Adapter | implemented/staged | Losslessly pack pixel dimensions from one live query |
| 405 | `windowSetTitle` | Adapter | implemented/staged | Live title update with exact counted-text admission |
| 410 | `clipboardGet` | Extend | implemented/staged | Display CI pending; 64 MiB owner can reject legacy-readable text. |
| 411 | `clipboardSet` | Adapter | implemented/staged | Set valid counted text; verify clipboard roundtrip |
| 412 | `nextEvent` | Extend | implemented/staged | Witnessed single FIFO dequeue on hosted proof build; text beyond ticket cap can remain queued where legacy succeeds. |
| 413 | `injectEvent` | Extend | implemented/staged | Inject validated event record; preserve order and event data |
| 415 | `platformLastError` | Extend | implemented/staged | Owned error text, preserving empty/error and encoding |
| 417 | `platformHandleCounts` | Extend | implemented/staged | One handle-count array with correct shape and lifetime |
| 418 | `droppedEvents` | Adapter | implemented/staged | Real queue overflow and dropped-count semantics |
| 420 | `clipboardData` | Extend | implemented/staged | Owned MIME bytes, including cap and absence |
| 421 | `windowSetSize` | Adapter | implemented/staged | Set valid size and check live window dimensions |

### GPU (31)

| ID | Registered primitive | Audit | State | Proof still needed |
| ---: | --- | --- | --- | --- |
| 430 | `gpuCreateDevice` | Adapter | implemented/staged | Create and release a real GPU device |
| 431 | `gpuClaimWindow` | Adapter | implemented/staged | Claim a live window on correct device/thread |
| 432 | `gpuSwapchainFormat` | Adapter | implemented/staged | Query actual claimed swapchain format |
| 433 | `gpuCreateShader` | Extend | implemented/staged | Bounded typed shader linked in freeze2; shader creation in CI pending. |
| 434 | `gpuCreatePipeline` | Extend | implemented/staged | Bounded typed pipeline linked in freeze2; live pipeline in CI pending. |
| 435 | `gpuCreateTexture` | Adapter | implemented/staged | Create a real texture; preserve formats and widths |
| 436 | `gpuCreateSampler` | Adapter | implemented/staged | Create a real sampler with supported modes |
| 437 | `gpuCreateBuffer` | Adapter | implemented/staged | Create a real buffer and verify resource size |
| 438 | `gpuRelease` | Adapter | implemented/staged | Release each handle kind exactly once |
| 439 | `gpuUploadBuffer` | Adapter | implemented/staged | Borrow read-only bytes and check uploaded contents |
| 440 | `gpuUploadTexture` | Extend | implemented/staged | Bound texture region/stride; verify uploaded pixels |
| 441 | `gpuAcquireCommandBuffer` | Adapter | implemented/staged | Acquire real command buffer with correct ownership |
| 442 | `gpuAcquireSwapchain` | Extend | implemented/staged | Capture atomic texture/width/height result or no texture |
| 443 | `gpuBeginPass` | Adapter | implemented/staged | Separate load/clear lanes; verify contents and handle consumption |
| 444 | `gpuSetViewport` | Adapter | implemented/staged | Check viewport/f32 conversion in valid pass |
| 445 | `gpuSetScissor` | Adapter | implemented/staged | Check scissor in valid pass |
| 446 | `gpuBindPipeline` | Adapter | implemented/staged | Bind real pipeline in valid pass |
| 447 | `gpuBindVertexBuffer` | Adapter | implemented/staged | Bind real vertex buffer and offsets |
| 448 | `gpuBindTexture` | Adapter | implemented/staged | Bind real texture/sampler in valid pass |
| 449 | `gpuPushUniforms` | Adapter | implemented/staged | Borrow bounded uniforms and verify shader output |
| 450 | `gpuDraw` | Adapter | planned | No safe mixed-route render-state validation yet; keep primitive. Prove pipeline/vertex/instance state and actual draw output before adding a route. |
| 451 | `gpuEndPass` | Adapter | implemented/staged | End valid pass and consume handle exactly once |
| 452 | `gpuBlit` | Extend | implemented/staged | Bounded blit linked in freeze2; destination readback in CI pending. |
| 453 | `gpuSubmit` | Adapter | implemented/staged | Submit once: failure, success/no fence, success/fence |
| 454 | `gpuWaitFence` | Adapter | implemented/staged | Wait on a live fence and preserve blocking |
| 455 | `gpuFenceDone` | Adapter | implemented/staged | Distinguish pending, signaled and bad fence |
| 456 | `gpuDownload` | Extend | implemented/staged | Bound writable destination; verify bytes and canaries |
| 458 | `gpuWaitIdle` | Adapter | implemented/staged | Wait idle on a valid device |
| 459 | `gpuFenceElapsed` | Adapter | implemented/staged | Distinguish pending, elapsed and bad fence |
| 460 | `gpuShaderLanguage` | Adapter | implemented/staged | Map actual shader format to checked enum |
| 461 | `gpuCompileShader` | Extend | implemented/staged | Owned compiler-output linked in freeze2; backend success pending. 64 MiB cap can reject legacy-readable output. |

### Files (15)

| ID | Registered primitive | Audit | State | Proof still needed |
| ---: | --- | --- | --- | --- |
| 500 | `fileOpen` | Adapter | implemented/staged | Open real file with modes and counted path |
| 501 | `fileClose` | Adapter | implemented/staged | Close live file once; preserve errors |
| 502 | `fileRead` | Extend | implemented/staged | Bound writable file slice, partial read and EOF |
| 503 | `fileWrite` | Adapter | implemented/staged | Bound read-only source slice and verify written bytes |
| 504 | `fileSize` | Adapter | implemented/staged | Hosted status/size fixture and LTO pilot; opt at-par on tested host, interpreter/baseline slower. |
| 505 | `filePosition` | Adapter | implemented/staged | Buffered/read-ahead fixture and LTO pilot; opt at-par on tested host, interpreter/baseline slower. |
| 506 | `fileSeek` | Adapter | implemented/staged | Check seek modes and resulting position |
| 507 | `fileFlush` | Adapter | implemented/staged | Verify flush on live buffered writes |
| 508 | `fileDelete` | Adapter | implemented/staged | Verify deletion and path admission/failures |
| 509 | `fileRename` | Adapter | implemented/staged | Verify rename with two independently validated paths |
| 510 | `fileStat` | Extend | implemented/staged | Take one stat observation; decode size and kind |
| 511 | `dirEntries` | Extend | implemented/staged | Own directory result, preserving entry names and shape |
| 512 | `dirCreate` | Adapter | implemented/staged | Create real directory; preserve path failures |
| 513 | `cwd` | Extend | implemented/staged | Own cwd text, preserving surrogateescape |
| 514 | `mkfifo` | Adapter | implemented/staged | Create actual FIFO; verify mode and path failures |

### Socket/TLS/PTY (20)

| ID | Registered primitive | Audit | State | Proof still needed |
| ---: | --- | --- | --- | --- |
| 540 | `socketListen` | Adapter | implemented/staged | Listen on loopback with counted host text |
| 541 | `socketConnect` | Adapter | implemented/staged | Connect to local listener; preserve async status |
| 542 | `socketAccept` | Adapter | implemented/staged | Accept real connection: pending versus new handle |
| 543 | `socketRecv` | Extend | implemented/staged | Bound writable receive; pending versus EOF versus error |
| 544 | `socketSend` | Adapter | implemented/staged | Bound read-only send; partial progress/rearming |
| 545 | `socketClose` | Adapter | implemented/staged | Close live socket exactly once |
| 546 | `socketSemaphore` | Adapter | implemented/staged | Verify readiness indices and delivery/rearm |
| 547 | `socketLocalPort` | Adapter | implemented/staged | Report actual bound local port |
| 548 | `socketResolve` | Adapter | implemented/staged | Copy counted host before lookup worker handoff |
| 549 | `socketConnected` | Adapter | implemented/staged | Distinguish pending, connected and error |
| 550 | `tlsStart` | Adapter | implemented/staged | Verify TLS hostname and handle transfer on success |
| 551 | `tlsRecv` | Extend | implemented/staged | Bound writable TLS receive; EOF/would-block/error |
| 552 | `tlsSend` | Adapter | implemented/staged | Verify partial and retry sends with native-owned storage |
| 553 | `tlsClose` | Adapter | implemented/staged | Close verified live TLS session with correct ownership |
| 554 | `tlsSemaphore` | Adapter | implemented/staged | Verify TLS readiness indices/delivery |
| 555 | `tlsHandshake` | Adapter | implemented/staged | Verify handshake progress, success and certificate failure |
| 561 | `ptyRead` | Extend | implemented/staged | Read real child output into bounded slice; EOF/pending/error |
| 562 | `ptyWrite` | Adapter | implemented/staged | Write actual child input, including partial progress |
| 564 | `ptySemaphore` | Adapter | implemented/staged | Verify PTY readiness indices and delivery |
| 565 | `ptyWait` | Adapter | implemented/staged | Check pending/exit status and exactly-once reap |
