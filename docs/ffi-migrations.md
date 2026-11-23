# Prepared FFI migrations (PR 8)

Scope: the 64 **Adapter** and 34 **Extend** IDs in the
[primitive audit](ffi-primitive-audit.md). Existing **Live**, **Now**,
**Keep** and **Infra** IDs are not migration credit. Keep the numbered
primitive slots, original public API and legacy behavior. A candidate
provides a second implementation on its admitted inputs, not an alias for
the primitive or a claim of parity for every legacy input. No production
send has switched.

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
   shared bounded owner reserves a process-local ticket before the call;
   the producer can publish once, then the image copies at most the
   reserved capacity and releases in `ensure:`. Use a reviewed
   [family-specific result protocol](ffi-owned-output.md) when a fixed
   byte budget is unsuitable: 461 adopts one native result and copies it
   in pages; tag 11 boxes owned limbs within the collecting wrapper.
   Reject stale tickets and distinguish present-empty from absent. Capture side-effecting or
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
   Fallback is allowed only when unavailable or declined **before** native
   entry to the operation. A separate non-mutating eligibility query
   (450) can decline before the draw; it does not execute the draw.
   After entry to the operation, nil, zero, error, pending and partial
   progress are results, never reasons to retry the primitive. A JIT guard miss may use
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
| Files (500–514) | Retest buffered and bounded I/O with paired workloads; extend measurements beyond the pilot. Preserve one stat observation (510) and paged copies of one native result (511/513). |
| Core (20–31, 52, 61, 152–153, 169–170, 172) | Extend corrected tag-11 checks to the release matrix; pair mixed and large inputs separately. Current scalar, text and compare pilots do not clear the release gate. |
| Window/input (400, 402–403, 405, 410–413, 415, 417–418, 420–421) | 410/412 retain owned-size gaps; validate restore, lifetime and live-workload parity before switching senders. |
| GPU (430–456, 458–461) | Extend the remote-CI 450 draw/readback and 461 paged compile checks to other supported GPU backends. Pair a full render workload before switching senders. |
| Socket/TLS/PTY (540–555, 561–562, 564–565) | Extend the loopback, verified TLS and child PTY evidence to the release matrix; pair live retries and partial I/O, not just TCP sends. |

## API and route boundaries

Candidate selectors are opt-in image methods, not new public APIs. The
registry invokes a typed native function independently of the old numbered
entry. Review sources and report route evidence at the following boundaries:

| Family | Image boundary | Successful-route witness |
| --- | --- | --- |
| Files | `File class>>ffiCandidatePrim*` in [File](../src/System-Files/File.st); not a FileStream cutover. | [FileFFITest](../src/Tests-Kernel/FileFFITest.st) uses real temporary paths/descriptors, not an invalid ID loop. 510 is one stat; 511/513 copy from one native observation using a paged, process-local owner. Its 16 live-owner limit and existing backend bounds still apply. |
| Core | Candidate siblings on `Float`, `Time class`, `VirtualMachine` and `Integer`; `vm:core` is not an alias for a launcher grant. | [Core fixture](../tests/vm/core_ffi_test.py) checks real numerics, clocks, output bytes and environment values; [compare](../tests/vm/bigint_ffi_test.sh) and [owned arithmetic](../tests/vm/bigint_owned_ffi_test.sh) fixtures distinguish native entry from Integer fallback. |
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
| New core routes | `migration98-integ5-155237-2` Linux x86-64 SDL-hosted `-O0` VM with canonical seed: `python3 tests/vm/core_ffi_test.py IMAGE VM --trace`. 52/61/152/153/169/170/172 passed in none/baseline/opt, with exact native entry counts (11/24/1/1/2/2/4) per mode and no legacy fallback. Matched stage2 image also passed all seven; proof-only workload ran 30 case/mode combinations with 64 candidate entries and zero direct entries. The new seed on the `cbe6326` hosted VM passed the missing-export controls in all three modes. This diagnostic run is distinct from the freeze2 checks below. |
| ID 27 (bigint compare) | Same hosted diagnostic VM/seed, `tests/vm/bigint_ffi_test.sh IMAGE VM --trace`: 1,589 native entries per run, including prepared Array, positional, candidate facade and post-GC; missing-export fallback separately passed. The original wrapper passed tier flags after the image; the paired pilot below is separate. This is the scalar tag-10 input path, not evidence for the eleven tag-11 result producers. |
| Files 500–514 | Same diagnostic VM/seed, `--headless --test FileFFITest FileTest`: 18/18 per mode, all 15 typed export IDs traced. On full stage2 image, six paired workload shapes verified exact 300 candidate entries and zero direct entries in each mode (18 combinations, proof-only). New VM + old image: 12/12 legacy `FileTest`, no new entries. |
| Socket/TLS/PTY | Same diagnostic VM/seed, `tests/vm/socket_ffi_test.py VM IMAGE --jit MODE --trace`: All 20 routes were traced with live loopback, verified TLS, mixed retry and child PTY I/O; old-VM missing-export fallback also passed. The original socket fixture put VM options after the image, so these runs do not establish coverage by tier. See the separate paired TCP-send pilot below. |
| Window/input | Same diagnostic VM/seed, `tests/vm/window_ffi_test.sh IMAGE VM`: headless none/baseline/opt passed with 412/413/415/417/418 entry counts 11/4,106/1/1/3 in each mode. No display-dependent operation entered. The 410/412 size gaps are separate from this fixture's ordinary inputs. |
| [Display CI](https://github.com/schani/samaltak/actions/runs/45215914479/job/137836879418) | `f70c88c` stage2, `make test-ffi-candidates-display` on X11/Xvfb with lavapipe: window fixture and GPU 8/8 passed in each of none/baseline/opt with legacy calls poisoned on the exercised paths. Window: 400, 402–403, 405, 410–411, 415, 417, 420–421. GPU: 430–449, 451–456, 458–461 (both 443 lanes). This is the earlier GPU state: 450 was absent and 461 used the shared bounded owner, not the paged ABI. |
| Display paired subset | Exact trace counts only for 402/403/405/421 and the joint 444+445 case: 1,024 entries per target in each mode, zero direct entries. All 15 case/mode timing samples were inconclusive (one session); no rollout credit. |
| Restored image | `tests/vm/ffi_trial_test.sh` passed on the same hosted diagnostic build: FileStream reaches 504 during explicit trial, then uninstalls; restored normal snapshot uses legacy. Shared ticket restore/unwind passed with an owned fixture, not with every family's live result. |
| Owned-copy authority | Integ5 x64 hosted diagnostic and test-export relink, [owned fixture](../tests/vm/owned_ffi_test.sh): 135 producer entries per mode (none/baseline/opt); separate gate verifies reserve/copy, unwind/termination and denies old ticket after restore. No operation ID credit. |
| Freeze2 hosted release | `migration98-freeze2-160012-1`, default LTO: byte-for-byte stage2 C regeneration, seven strict core routes with GC verification, and grants, notification, wrapper, bound-site, manifest, registry and owned-output gates passed. |
| Freeze2 Linux `NO_PLATFORM=1` | x86-64: 41/41 focused tests per mode, grants/manifest/registry/owned gates and release denial of the writable fixture passed. Wrapper and bound-site harnesses passed via the `fileInString` launcher adapter (`--load` unavailable). Full matching image passed exact traced routes 52/61/152/153/169/170/172 with GC verification in all three modes. AArch64 cross-build and QEMU architecture smoke passed; neither that smoke nor the isolated writable fixture establishes AArch64 per-ID parity. SDL routes are unavailable on these builds. |
| Rebased hosted checks | `07aa290` default LTO: clean seed, stage2 and `tests/vm/gen_test.sh` passed; checked-in C matched the freeze2 release. Focused suites passed 119/119 in each mode. These are suite/build results, not a per-ID native witness. |
| Simulator and firmware | Freeze2 `VMSimulationTest` passed 5/5 in the canonical layout. No per-ID simulator or UEFI firmware boot proof. |

### Supplemental checks for tag 11, 450 and paged 461

| Artifact | Result and scope |
| --- | --- |
| Clean supplemental snapshot | `migration98-supplement-f70c88c-162550` (`f70c88c` plus the exact landed tag-11 and GPU source patches, before the upstream rebase): fresh x86-64/AArch64 translation, SDL-hosted test-enabled x86-64 and `NO_PLATFORM` AArch64 C builds passed. Fresh hosted stage2 and `tests/vm/gen_test.sh` passed. The seven supplemental generated files landed byte-for-byte in `aab306b`; scheduler C comes from `9d78aa1`. |
| Corrected tag-11 x86-64 SDL | On the clean supplemental stage2, [owned arithmetic](../tests/vm/bigint_owned_ffi_test.sh) passed in actual none/baseline/opt: 16,701 native completions and, in the separate forced post-native full-GC fixture, 74 adds and one shift per tier. The CI-agent local run recorded 93 actual optimized bound-site hits; the supplemental retest recorded 94. A separate 67,108,865-byte magnitude add/compare passed. VM tuning options must precede the image: the old command put them after it, so its tier labels and zero-hit result do not establish a failure in opt. |
| Corrected tag-11 AArch64 `NO_PLATFORM` | CI-agent local cross-build/QEMU rerun of the clean supplement passed with pre-image VM options: 16,701 native completions and forced-GC witnesses of 74 adds and one shift per tier, plus 75 actual optimized bound-site hits. This is correctness evidence, not native-host timing. |
| Corrected SDL headless, 450/461 | On the same test-enabled snapshot, the [paged fixture](../tests/vm/gpu_shader_paged_test.st) adopted, copied and released a synthetic 67,108,868-byte result, checking bounds and stale tickets in actual none/baseline/opt. Per tier, the invalid-pass probe reached 450 eligibility twice and draw once, rejected before SDL, with no legacy replay. Successful draws and live compiles are separate display checks. |
| Pushed `aab306b` display CI | [Remote display job](https://github.com/schani/samaltak/actions/runs/45217681989/job/137843146462), X11/Xvfb with lavapipe: window and GPU 9/9 passed in each mode, including 450 with a legacy pipeline bind, poisoned draw fallback and green pixel readback, and 461 live paged compilation with a legacy byte oracle and error check. The paired subset passed 15 exact route proofs; timing remains inconclusive and does not include 450 or 461. |

## Release pilot: generated scalar and text wrappers

`de2f6cf` emits per-address x86-64 and AArch64 wrappers. For file size and
position, `nonNegativeI64` boxes nonnegative results and returns `nil` on a
completed negative result; older signed descriptors still resolve. Counted
stdout/stderr text uses a synchronous byte span (borrowing ASCII or byte arrays
when possible); `getenv` prepares a NUL-terminated name, copies the value into
native-owned storage, and boxes it with no live heap borrow. Only pre-entry
rejection may fall back; a completed `nil` must not retry.

Quiet Linux x86-64 hosted LTO release matching `de2f6cf`'s runtime source, same
VM and stage2 image for both arms, pinned CPU 1: 17 fresh sessions per stratum,
four balanced AB/BA pairs per session, 4,096 warmup and timed calls per arm.
Separate tracing verified exact native entries in all 24 workload/tier strata
and zero for the dedicated controls. Untraced warm facade timings are paired
candidate/dedicated wall-time ratios. See the [paired harness](../vm/tests/bench/ffi-paired.md).
Brackets give simultaneous 95% intervals over paired session medians.

| Workload | Interpreter | Baseline JIT | Optimizing JIT |
| --- | ---: | ---: | ---: |
| 505 File position, 4 KiB | 1.0695 [1.0433, 1.0832] | 1.0251 [1.0125, 1.0717] | 0.9693 [0.9379, 0.9895] |
| 504 File size, 4 KiB | 1.0314 [1.0186, 1.0448] | 1.0153 [0.9943, 1.0321] | 0.9599 [0.9463, 0.9741] |
| 52 Float fraction part | 1.3646 [1.3136, 1.4506] | 1.4006 [1.3177, 1.5419] | 0.8959 [0.8172, 0.9682] |
| 169 stdout, 8 B | 1.0102 [0.9783, 1.0284] | 1.0138 [1.0064, 1.0206] | 0.9694 [0.9593, 0.9874] |
| 170 stderr, 8 B | 1.0248 [1.0133, 1.0349] | 1.0201 [1.0118, 1.0298] | 0.9716 [0.9469, 0.9924] |
| 169 stdout, 256 B | 0.9871 [0.9555, 0.9945] | 0.9879 [0.9782, 0.9958] | 0.9579 [0.9381, 0.9886] |
| 170 stderr, 256 B | 0.9911 [0.9786, 0.9965] | 0.9905 [0.9835, 1.0061] | 0.9591 [0.9337, 0.9895] |
| 172 getenv, fixed ASCII key/value | 0.7498 [0.7104, 0.7776] | 0.6841 [0.6509, 0.7078] | 0.5539 [0.5184, 0.5853] |

13 of 24 strata clear the gate (simultaneous 95% upper bound ≤ 1.0); eight are
slower and three inconclusive. All eight optimizing strata pass, but
interpreter/baseline regressions remain in metadata, Float fraction and short
stream writes. The 256 B stdout case and the fixed ASCII getenv case pass all
three tiers; neither represents the full operation. These are same-build
comparisons, not before/after ratios.

### Public `getenv:` limits

A separate disposable Linux x86-64/glibc 2.36 image trial compared the
installed public selector against primitive 172 in the same VM/image.
With 15 fresh sessions, four balanced pairs and 24 simultaneous
intervals, 12 strata passed, 11 were slower and one was inconclusive.
Short present, short missing and empty values were slower in interpreter
and baseline but passed in opt; embedded-NUL fallback was slower in
all tiers. Unicode results were slower in interpreter/baseline and
inconclusive in opt. ASCII heap cases passed in all tiers: 4 KiB key
(0.177–0.201× legacy), 513 B value (0.060–0.083×), and 1 KiB key plus
4 KiB value (0.043–0.046×). The fast path uses ASCII scans and bulk
copies, not cached lookups.

The typed name buffer uses 512 B of scratch when the encoded capacity
fits, otherwise native allocation. Owned results use scratch or native
heap and are capped at 64 MiB. After real `setenv` of a 64 MiB + 1 byte
ASCII value, the typed call completed with `nil` while primitive 172
returned the full string. Allocation failure behavior also differs.
Neither path establishes safety with concurrent environment writers.
This blocks public promotion even where timing passes: `nil` is also a
legitimate completed result, so falling back on it would replay the call.

## Release pilot: bounded I/O, bigint, and other core calls

Freeze2 Linux x86-64 SDL default-LTO VM/full image, pinned CPU 1:
13 fresh sessions per stratum, four balanced pairs, 2,048 warmup and
2,048 timed calls per arm. Separate traces verified exact candidate entries
and zero dedicated-arm entries. Same ratio/interval definition as above.

| Workload | Interpreter | Baseline | Opt |
| --- | ---: | ---: | ---: |
| 502 `file-read-64` | 1.169 [1.101, 1.197] | 1.061 [0.989, 1.087] | 0.975 [0.929, 1.245] |
| 502 `file-read-4096` | 1.118 [1.093, 1.207] | 1.049 [1.007, 1.194] | 0.963 [0.768, 1.027] |
| 503 `file-write-64` | 1.099 [1.081, 1.158] | 1.046 [1.003, 1.098] | 0.981 [0.957, 1.049] |
| 503 `file-write-4096` | 1.089 [1.063, 1.149] | 1.042 [1.020, 1.063] | 0.984 [0.956, 1.265] |
| 27 `bigint-27-mixed` | 1.647 [1.483, 1.841] | 2.383 [2.147, 2.702] | 1.042 [0.720, 1.726] |
| 27 `bigint-27-8192b` | 0.918 [0.821, 1.154] | 0.984 [0.734, 1.303] | 0.762 [0.606, 0.921] |
| 544 `socket-send-64` | 1.036 [0.983, 1.072] | 1.002 [0.947, 1.028] | 1.007 [0.973, 1.104] |
| 544 `socket-send-4096` | 1.026 [1.003, 1.046] | 1.027 [0.993, 1.052] | 1.016 [0.950, 1.050] |
| 152 `core-utc-us` | 1.575 [1.468, 1.935] | 1.266 [0.980, 1.456] | 0.802 [0.528, 0.990] |
| 153 `core-thread-cpu-us` | 1.066 [1.050, 1.079] | 1.039 [1.024, 1.082] | 0.969 [0.948, 1.019] |
| 61 `core-float-print-string` | 1.143 [1.091, 1.166] | 1.035 [0.996, 1.185] | 1.005 [0.932, 1.424] |

No workload shown here passes across all three tiers. File I/O supports real
bounded slices but adds about 40 allocated bytes/call and interpreter cost.
Compare mixed and large Integer routes separately. Only TCP sends were
timed, not TLS; pair a live retry workload before claiming TLS parity.

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

**Status at `aab306b` (rebased on `9d78aa1`): 98 integrated alternatives
on admitted inputs; 0 production switches.** The final 12 IDs (20–26,
28–31, 450) have opt-in facades and translator-generated C. ID 461 now
uses paged output. Corrected x86-64 and AArch64/QEMU checks witnessed
all 11 tag-11 producers in each tier and actual collecting opt hits; display CI
confirmed 450 draw/readback and the new 461 ABI. No ID clears the full
tested/measured/default gates. Keep legacy defaults and fallback for
unsupported inputs and backends.

### Core (19)

“Tag 11” rows share the corrected x86-64 and AArch64 arithmetic evidence above.
ID 20 and ID 31 also have forced-GC witnesses; the optimized bound-site
hit counts are for ID 20. This is not release timing or full matrix parity.

| ID | Registered primitive | Audit | State | Evidence or remaining gate |
| ---: | --- | --- | --- | --- |
| 20 | `largeAdd` | Extend | implemented/staged | Tag 11; signed add and normalized carry; forced GC with actual opt hits. Paired route proof only (12/12 strata, 1,024 candidate entries each, zero direct); release timing pending. |
| 21 | `largeSub` | Extend | implemented/staged | Tag 11; signed subtract and normalized zero. |
| 22 | `largeMul` | Extend | implemented/staged | Tag 11; multi-limb product with heap bounds; allocation failure completes without replay. |
| 23 | `largeQuo` | Extend | implemented/staged | Tag 11; truncating quotient and completed zero-divide status. |
| 24 | `largeRem` | Extend | implemented/staged | Tag 11; truncating remainder with dividend sign and completed zero-divide status. |
| 25 | `largeFloorDiv` | Extend | implemented/staged | Tag 11; floor quotient across signs and completed zero-divide status. |
| 26 | `largeMod` | Extend | implemented/staged | Tag 11; floor remainder with divisor sign and completed zero-divide status. |
| 27 | `largeCompare` | Extend | implemented/staged | Matched 1,589 native compare entries per hosted proof run; backend matrix pending. |
| 28 | `largeBitAnd` | Extend | implemented/staged | Tag 11; two’s-complement AND with sign extension. |
| 29 | `largeBitOr` | Extend | implemented/staged | Tag 11; two’s-complement OR with sign extension. |
| 30 | `largeBitXor` | Extend | implemented/staged | Tag 11; two’s-complement XOR with sign extension. |
| 31 | `largeBitShift` | Extend | implemented/staged | Tag 11; signed shift, floor-rounded right shift and completed oversized-left failure; forced-GC witness. |
| 52 | `floatFractionPart` | Adapter | implemented/staged | Hosted and x86-64 `NO_PLATFORM` IEEE fixture; LTO pilot: interpreter/baseline slower, opt inconclusive; keep legacy. |
| 61 | `floatPrintString` | Extend | implemented/staged | Owned shortest-round-trip String, including special values — Hosted and x86-64 `NO_PLATFORM` fixtures passed; target matrix outstanding. |
| 152 | `utcMicroseconds` | Adapter | implemented/staged | Wall-clock microseconds and failure/availability — Hosted and x86-64 `NO_PLATFORM` fixtures passed; target matrix outstanding. |
| 153 | `threadCpuTime` | Adapter | implemented/staged | VM-thread CPU microseconds and clock availability — Hosted and x86-64 `NO_PLATFORM` fixtures passed; target matrix outstanding. |
| 169 | `stdoutWrite` | Adapter | implemented/staged | Counted stdout bytes, flush and receiver — Hosted and x86-64 `NO_PLATFORM` fixtures passed; target matrix outstanding; generated-text prototype rejected. |
| 170 | `stderrWrite` | Adapter | implemented/staged | Counted stderr bytes, flush and receiver — Hosted and x86-64 `NO_PLATFORM` fixtures passed; target matrix outstanding; generated-text prototype rejected. |
| 172 | `getenv` | Extend | implemented/staged | Owned environment text: absent, empty and nonempty — Hosted and x86-64 `NO_PLATFORM` fixtures passed; 64 MiB capture limit remains. Generated-text prototype rejected. |

### Window/input (13)

| ID | Registered primitive | Audit | State | Evidence or remaining gate |
| ---: | --- | --- | --- | --- |
| 400 | `windowOpen` | Adapter | implemented/staged | Live window creation and handle accounting. |
| 402 | `windowSize` | Adapter | implemented/staged | Live point extents before/after resize; legacy comparison. |
| 403 | `windowPixelSize` | Adapter | implemented/staged | Positive live pixel extents; legacy comparison. |
| 405 | `windowSetTitle` | Adapter | implemented/staged | Counted title update and embedded-NUL rejection. |
| 410 | `clipboardGet` | Extend | implemented/staged | Unicode and empty text roundtrips. Legacy-readable text above the 64 MiB owned cap fails after native entry; no replay. |
| 411 | `clipboardSet` | Adapter | implemented/staged | Unicode and empty text roundtrips. |
| 412 | `nextEvent` | Extend | implemented/staged | Witnessed single FIFO dequeue. The 64 MiB ticket includes an 80-byte header; oversized text fails without dequeue or native replay, where legacy can succeed. |
| 413 | `injectEvent` | Extend | implemented/staged | FIFO, event data and real queue overflow. |
| 415 | `platformLastError` | Extend | implemented/staged | Headless copyout and live invalid-window diagnostic. |
| 417 | `platformHandleCounts` | Extend | implemented/staged | Exact headless handle counts and live window accounting. |
| 418 | `droppedEvents` | Adapter | implemented/staged | Real queue overflow and exact dropped-count increment. |
| 420 | `clipboardData` | Extend | implemented/staged | UTF-8 and unadvertised MIME bytes match legacy on X11; cleared selection returns nil. Legacy 20 MiB bound retained. |
| 421 | `windowSetSize` | Adapter | implemented/staged | Live resize with extent check and invalid-size rejection. |

### GPU (31)

| ID | Registered primitive | Audit | State | Evidence or remaining gate |
| ---: | --- | --- | --- | --- |
| 430 | `gpuCreateDevice` | Adapter | implemented/staged | Create and release a real GPU device |
| 431 | `gpuClaimWindow` | Adapter | implemented/staged | Claim a live window on correct device/thread |
| 432 | `gpuSwapchainFormat` | Adapter | implemented/staged | Query actual claimed swapchain format |
| 433 | `gpuCreateShader` | Extend | implemented/staged | Bounded typed shader creation with live device. |
| 434 | `gpuCreatePipeline` | Extend | implemented/staged | Live bounded pipeline creation and wrong-stage rejection. |
| 435 | `gpuCreateTexture` | Adapter | implemented/staged | Create a real texture; preserve formats and widths |
| 436 | `gpuCreateSampler` | Adapter | implemented/staged | Create a real sampler with supported modes |
| 437 | `gpuCreateBuffer` | Adapter | implemented/staged | Create a real buffer and verify resource size |
| 438 | `gpuRelease` | Adapter | implemented/staged | Release each handle kind exactly once |
| 439 | `gpuUploadBuffer` | Adapter | implemented/staged | Borrow read-only bytes and check uploaded contents |
| 440 | `gpuUploadTexture` | Extend | implemented/staged | Bound texture region/stride; verify uploaded pixels |
| 441 | `gpuAcquireCommandBuffer` | Adapter | implemented/staged | Acquire real command buffer with correct ownership |
| 442 | `gpuAcquireSwapchain` | Extend | implemented/staged | Capture atomic texture/width/height result or no texture |
| 443 | `gpuBeginPass` | Adapter | implemented/staged | Live load and clear passes; clear admits both Float representations. |
| 444 | `gpuSetViewport` | Adapter | implemented/staged | Live pass viewport with both Float representations; exact paired trace. |
| 445 | `gpuSetScissor` | Adapter | implemented/staged | Live scissor; exact paired trace. |
| 446 | `gpuBindPipeline` | Adapter | implemented/staged | Bind real pipeline in valid pass |
| 447 | `gpuBindVertexBuffer` | Adapter | implemented/staged | Bind real vertex buffer and offsets |
| 448 | `gpuBindTexture` | Adapter | implemented/staged | Bind real texture/sampler in valid pass |
| 449 | `gpuPushUniforms` | Adapter | implemented/staged | Borrow bounded uniforms and verify shader output |
| 450 | `gpuDraw` | Adapter | implemented/staged | Checked procedural offscreen draw; compatible active pass, live resource-free pipeline with no vertex attributes, and checked count/first. General resource-bound and swapchain draws stay legacy. `aab306b` display CI passed pixel readback in all modes. |
| 451 | `gpuEndPass` | Adapter | implemented/staged | End valid pass and consume handle exactly once |
| 452 | `gpuBlit` | Extend | implemented/staged | Live bounded blit with destination readback. |
| 453 | `gpuSubmit` | Adapter | implemented/staged | Submit once: failure, success/no fence, success/fence |
| 454 | `gpuWaitFence` | Adapter | implemented/staged | Wait on a live fence and preserve blocking |
| 455 | `gpuFenceDone` | Adapter | implemented/staged | Distinguish pending, signaled and bad fence |
| 456 | `gpuDownload` | Extend | implemented/staged | Bound writable destination; verify bytes and canaries |
| 458 | `gpuWaitIdle` | Adapter | implemented/staged | Wait idle on a valid device |
| 459 | `gpuFenceElapsed` | Adapter | implemented/staged | Distinguish pending, elapsed and bad fence |
| 460 | `gpuShaderLanguage` | Adapter | implemented/staged | Map actual shader format to checked enum |
| 461 | `gpuCompileShader` | Extend | implemented/staged | One compile, process-local receipt, bounded pages and eventual release. The shared 64 MiB cap no longer applies; `aab306b` display CI covered the paged compile and diagnostics; the oversized result was synthetic. |

### Files (15)

| ID | Registered primitive | Audit | State | Evidence or remaining gate |
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

Original fixture witnesses show native entry, not tier coverage; see
the socket check above.

| ID | Registered primitive | Audit | State | Evidence or remaining gate |
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
