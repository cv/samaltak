# Samaltak implementation spec

The contract between the C core, the Python seed bootstrapper, and the Smalltalk image. `docs/design.md` says *why*; this says *exactly what*. Change this file first, then code.

## Layout

```
vm/                 C core (≈5k lines). Makefile → vm/build/samaltak
  src/              object memory, GC, interpreter, scheduler, image I/O, core primitives
  src/prims.def     X-macro primitive table: PRIM(number, "name", c_function)
  platform/         SDL3 window/input, SDL_GPU, files, sockets, clipboard; prims_platform.def
boot/bootstrap.py   seed compiler: src/**/*.st → build/seed.image (Python 3, no deps)
src/                Smalltalk sources, one directory per package; src/packages.txt = load order + layer
fonts/              TTF files (OFL)
tests/              integration tests (headless Smalltalk runs, samaltak-ctl UI scenarios)
tools/              samaltak-ctl (Node ≥18, no deps), video scripts
build/              generated, git-ignored
```

`make` (top level) builds the VM, the seed image, then the full image:

1. `python3 boot/bootstrap.py src build/seed.image` — the only non-Smalltalk compiler; just good enough to bootstrap.
2. `vm/build/samaltak build/seed.image --headless --stage2 build/samaltak.image` — the image initializes its classes, **recompiles every method with the Smalltalk compiler**, rasterizes font atlases, builds the World, and snapshots.
3. `make test` — everything, from a fresh image: `test-vm` (mini kernel, also under the GC verifier), the bootstrapper's layering check (`tests/boot/layering_test.sh`), the full Smalltalk suite (`tests/st_suite.sh`, incl. the compiler fixpoint: recompiling the stage-2 image yields identical methods), Tests-Kernel and Tests-Compiler again with a 1 MB eden under the heap verifier (`SAMALTAK_VERIFY_GC=1 --eden 1`), the platform tests (`vm/platform`: C and Smalltalk), and the samaltak-ctl scenarios (`tests/remote/cli_test.sh` headless, `tests/tools/desktop_test.sh` in a hidden window). It fails on any failure, on a skipped test, and on a VM built without the platform layer.

Tests (`TestCase`, System-Support) must pass on a loaded machine and with several runs at once: each runs in its own Process with a time limit; they wait for asynchronous effects with `waitFor:timeout:` (polls, answers false at the timeout; asserted) instead of fixed sleeps, start Processes with `fork:` / `fork:named:at:` (or register them with `track:`), which are terminated after `tearDown`, and write files only into `scratchDirectory` (a fresh `/tmp/samaltak-<class>-<UTC µs>-<n>`, made with mkdir so concurrent runs never share it, deleted after the test).

## Object memory

64-bit words, little-endian. An *oop* is a tagged 64-bit value:

| low bits | kind | value |
|---|---|---|
| `…1` | SmallInteger | `(int64)oop >> 1` (63-bit signed) |
| `…010` | Character | code point = `oop >> 3` |
| `…100` | SmallFloat64 | Spur encoding (below) |
| `…000` | object pointer | 8-byte aligned address, never 0 |

**SmallFloat64** (Spur): let `b` be the IEEE bits. If `b` is ±0.0: `oop = (sign << 3) | 4` (sign in bit 3). Else `e = (b >> 52) & 0x7FF`; immediate iff `896 < e < 1151`; then `r = rotl64(b, 1) - (896 << 53)`; `oop = (r << 3) | 4`. Decode: `r = oop >> 3`; if `r <= 1` → ±0.0 (sign = r); else `b = rotr64(r + (896 << 53), 1)`. Other doubles (inf, NaN, huge, tiny) are **BoxedFloat64** objects (format 9, one 64-bit slot of IEEE bits). Float primitives accept both and return immediate when possible.

**Object header** — two words before the body:

word 0:

| bits | field |
|---|---|
| 0–31 | `numSlots`: body size in 8-byte words |
| 32–36 | `format` |
| 37–58 | `identityHash` (22 bits, assigned at allocation, never 0, never derived from the address) |
| 59 | immutable |
| 60–62 | GC private (marks, age, remembered) |
| 63 | forwarded (GC private) |

word 1: class oop.

**Formats**

| format | meaning |
|---|---|
| 0 | no fields |
| 1 | fixed pointer fields |
| 2 | indexable pointers, no fixed fields (Array) |
| 3 | fixed + indexable pointers (Context) |
| 4 | weak: fixed fields strong, indexable slots weak (see Weak references) |
| 7 | immediate class marker (SmallInteger, Character, SmallFloat64: no instances) |
| 9 | 64-bit indexable (BoxedFloat64) |
| 10–11 | 32-bit indexable; `format - 10` unused trailing 32-bit units (WideString, Bitmap) |
| 16–23 | 8-bit indexable; `format - 16` unused trailing bytes (ByteString, ByteSymbol, ByteArray, LargeInts) |

Element count: bytes = `numSlots*8 - (format-16)`; 32-bit units = `numSlots*2 - (format-10)`.

**Class format** (a Behavior's `format` slot, SmallInteger): `(instSpec << 16) | instSize` where `instSpec ∈ {0,1,2,3,4,7,9,10,16}` and `instSize` = fixed field count. `basicNew:` derives the object format (adding unused-unit counts).

**Pointer discipline** (keeps a pauseless, moving GC possible — see design.md): every heap pointer load goes through `load_ref`, every pointer store through `store_ref`; C code never holds a raw oop across an allocation or safepoint unless it is registered as a root; identity hash lives in the header.

**GC**: generational. Eden (bump allocation) + survivor semispaces, scavenged by copying with a remembered set maintained by `store_ref`; tenured objects in old space; full GC when old space exceeds its budget (implementation's choice: copying or mark-compact). Contexts are ordinary objects allocated in eden; most die there. A context's slots above `stackp` are not roots: the collector sets them to nil, so code that builds or grows a context must raise `stackp` before storing into the new slots.

**Weak references**: the indexable slots of a format-4 object do not keep their referents alive (its fixed fields do). After tracing, a scavenge sets to nil every weak slot whose young referent was not reached (old referents survive a scavenge), and a full GC every weak slot whose referent was not reached; weak objects stay in the remembered set while they refer to young objects. If any slot was cleared, the VM signals the finalization Semaphore (special object 35) at the next safepoint. Smalltalk: `WeakArray` (Kernel-Collections); `WeakRegistry` (System-Support) maps objects to executors, run (`finalize`, or `value` for a Block) by the 'finalization' Process at priority 50; an executor must not reference its object. GPU resources and fences, FileStreams and RemoteSockets register themselves and release their platform handle when collected unreleased.

## Image file

```
offset  size  field
0       8     magic "SAMALTK1"
8       8     version = 1
16      8     header size = 64
24      8     heap bytes (N)
32      8     base address the heap was written at (B, nonzero, 8-aligned)
40      8     special objects array oop (an address in [B, B+N))
48      8     identity hash seed (VM continues from here)
56      8     reserved (0)
64      N     objects, contiguous, each: 2 header words + numSlots words
```

The loader places the heap in old space and adds `(newBase - B)` to every pointer oop (class words and pointer-format slots). The Python bootstrapper writes with `B = 0x100000`.

## Special objects array

An Array (format 2). Indices (0-based) the VM relies on:

| # | object | # | object |
|---|---|---|---|
| 0 | nil | 17 | Process class |
| 1 | false | 18 | Semaphore class |
| 2 | true | 19 | Point class |
| 3 | Processor (the ProcessorScheduler) | 20 | LargePositiveInteger class |
| 4 | Smalltalk (SystemDictionary) | 21 | LargeNegativeInteger class |
| 5 | SmallInteger class | 22 | Message class |
| 6 | Character class | 23 | Association class |
| 7 | SmallFloat64 class | 24 | Bitmap class (32-bit) |
| 8 | BoxedFloat64 class | 25 | #doesNotUnderstand: |
| 9 | Array class | 26 | #mustBeBoolean |
| 10 | ByteArray class | 27 | #cannotReturn: |
| 11 | ByteString class | 28 | #aboutToReturn:through: |
| 12 | ByteSymbol class | 29 | #attemptToAssign:withIndex: |
| 13 | WideString class | 30 | specialSelectors (Array, below) |
| 14 | CompiledMethod class | 31 | timer Semaphore (signaled at the requested ms) |
| 15 | Context class | 32 | externalObjects (Array; VM signals Semaphores by index; `Smalltalk vm registerExternalSemaphore:` / `unregisterExternalSemaphore:` manage the slots, growing the Array when full) |
| 16 | BlockClosure class | 33 | WideSymbol class |
| | | 34 | #primitiveFailed (answered by `tryPrimitiveWithArgs`) |
| | | 35 | finalization Semaphore (signaled after a GC cleared weak slots) |

**Constants, defined once.** The special-object indices, object formats, header bits, the class format word's shift and mask, the CompiledMethod primitive mask and error flag, the marker primitive numbers and `CTX_SLACK` live in the `BEGIN/END EXPORTED CONSTANTS` block of `vm/src/vm.h` (plain `#define`s and `enum`s). `boot/bootstrap.py` parses that block for the seed image (and resolves `prims.def` entries that use a constant name), and generates the class-side methods of `VMConstants` (Kernel-Objects) from it: one per constant, the C name in lower camel case (`SO_EXTERNAL_OBJECTS` → `VMConstants soExternalObjects`, `F_W32` → `fW32`); `so…` indices are 1-based for `at:`. Smalltalk code uses those instead of numbers.

`specialSelectors` is an Array of 32 selectors, in bytecode order (`0xA0 + i`):
`+ - < > <= >= = ~= * / \\ @ bitShift: // bitAnd: bitOr: at: at:put: size == ~~ value value: isNil notNil new new: x y class value:value: max:` (the VM knows each one's arg count from the selector). `==` and `~~` never send. Others have VM fast paths (SmallInteger/Float arithmetic and comparisons, `at:`/`at:put:`/`size` on Arrays, ByteArrays and Strings, `value`/`value:` on BlockClosures, `x`/`y` on Points, `class`) and otherwise do a normal send.

## VM-known class layouts (fixed fields, in order)

| class | fields |
|---|---|
| Behavior | superclass methodDict format |
| ClassDescription | (Behavior) instanceVariables organization |
| Class | (ClassDescription) subclasses name classPool sharedPools package comment |
| Metaclass | (ClassDescription) thisClass |
| MethodDictionary | tally keys values — `keys`/`values` Arrays, capacity a power of two, slot = `identityHash(selector) & (cap-1)`, linear probing, nil key = empty |
| CompiledMethod | selector methodClass literals bytecodes numArgs numTemps frameSize primitive source category pragmas sourceMap properties |
| Context (format 3) | sender pc stackp method closureOrNil receiver, then indexable: args, temps, stack |
| BlockClosure | outerContext startpc numArgs numTemps frameSize |
| Process | nextLink suspendedContext priority myList name cpuTime (µs, SmallInteger, VM-maintained) |
| ProcessorScheduler | quiescentProcessLists (Array of 80 LinkedLists, index = priority) activeProcess |
| LinkedList | firstLink lastLink |
| Semaphore | firstLink lastLink excessSignals |
| Association | key value |
| Message | selector arguments |
| Point | x y |

Other kernel classes are Smalltalk's business. `numTemps` excludes args. `frameSize` = numArgs + numTemps + max stack depth.

## Method execution

**Contexts are heap objects**; there is no separate C stack of Smalltalk frames. The interpreter caches the active context's ip/sp in registers and writes them back before any context switch, before pushing `thisContext`, and before any primitive that inspects contexts — so every non-active context is always coherent and Smalltalk code (debugger, exceptions) may read and modify any context.

- `pc` is a 0-based index into `method bytecodes` (a ByteArray), or nil once the context has returned ("dead").
- `stackp` is the count of used indexable slots (args + temps + stack).
- On return the VM sets the returning context's `pc` and `sender` to nil.
- **Method activation**: new Context, size `frameSize`, receiver and args copied, temps nil, pc 0, stackp = numArgs + numTemps.
- **Block activation** (`value…`): context with `method = closure outerContext method`, `receiver = outerContext receiver`, `closureOrNil = closure`, pc = `startpc`, args then `numTemps` nil temps.
- **Primitives**: a method whose `primitive` ≠ 0 runs its primitive first; on success it returns without a context; on failure the method body runs (with an optional error code in the first temp, if the method declares `<primitive: … error: ec>`). The marker primitives `ensureMarker` (`ensure:`/`ifCurtailed:`, `PRIM_ENSURE_MARKER`) and `onDoMarker` (`on:do:`, `PRIM_ONDO_MARKER`) always fail; Smalltalk finds those contexts by `method primitive`.
- **Non-local return** (`^` in a block): home = follow `closureOrNil outerContext` until a context with `closureOrNil == nil`. If home is dead → send `#cannotReturn:` (value) to the active context. Else, if any context between the active one and home (exclusive of home's sender) has a method with the `ensureMarker` primitive → send `#aboutToReturn: value through: firstMarkedContext` to the active context (Smalltalk runs the unwind blocks and completes the return). Else return value to `home sender`, killing every context from the active one up to home.
- **doesNotUnderstand**: the VM builds a `Message` (selector, arguments Array) and sends `#doesNotUnderstand:` to the receiver; if that is not understood either, the VM aborts with a printed stack.
- **Non-boolean in conditional jump**: the VM leaves the context's pc *at the jump bytecode*, pops the value, and sends `#mustBeBoolean` to it; the result is pushed and the jump re-executes with it.
- **Store into an immutable object** (`storeInstVar`): instead of storing, the VM sends `#attemptToAssign: value withIndex: index` (index 1-based) to the receiver, leaving the value on the stack for the following `pop`. (The compiler never uses a popping inst-var store.) `at:put:`-style primitives fail on immutable receivers.
- **Method lookup**: receiver class → `methodDict` → superclass chain; global cache keyed by (class, selector); primitive `flushMethodCache` (and `flushCacheFor: selector`) is called by Smalltalk whenever a method dictionary changes.

### Bytecodes

One opcode byte, then operand bytes (unsigned unless noted, `int16` = little-endian signed, relative to the pc after the instruction).

| opcode | operands | meaning |
|---|---|---|
| 0x00–0x0F | | push temp 0–15 |
| 0x10–0x1F | | push inst var 0–15 |
| 0x20–0x3F | | push literal constant 0–31 |
| 0x40–0x5F | | push literal variable 0–31 (value of the Association) |
| 0x60–0x67 | | pop & store temp 0–7 |
| 0x70 | | push self |
| 0x71 / 0x72 / 0x73 | | push true / false / nil |
| 0x74 / 0x75 | | push SmallInteger 0 / 1 |
| 0x76 | | push thisContext |
| 0x77 | | dup |
| 0x78 | | pop |
| 0x79 | | return top (from method; or from block to its caller when executed in a block context — see 0x7B) |
| 0x7A | | return self |
| 0x7B | | block return top (to the block context's sender) |
| 0x7C | | non-local return top (`^` inside a block) |
| 0x80 i | i | push temp i |
| 0x81 i | i | push inst var i |
| 0x82 i | i | push literal constant i |
| 0x83 i | i | push literal variable i |
| 0x84 i | i | store temp i (no pop) |
| 0x85 i | i | store inst var i (no pop; immutability check) |
| 0x86 i | i | store literal variable i (no pop) |
| 0x87 i | i | pop & store temp i |
| 0x89 i | i | pop & store literal variable i |
| 0x8A d i | depth, index | push outer temp: context = `closureOrNil outerContext` repeated d times (d ≥ 1) |
| 0x8B d i | | store outer temp (no pop) |
| 0x8C d i | | pop & store outer temp |
| 0x8D l n | literal index, argc | send selector `literals[l]` |
| 0x8E l n | literal index, argc | super send: lookup starts at `method methodClass superclass` |
| 0x8F a t f s1 s0 | numArgs, numTemps, frameSize, size (big-endian 16 bit) | push a BlockClosure (outerContext = active context, startpc = pc after this instruction) and skip the `size`-byte block body |
| 0x90 o | int16 | jump |
| 0x91 o | int16 | pop, jump if true |
| 0x92 o | int16 | pop, jump if false |
| 0x93 v | int16 | push SmallInteger v |
| 0x94 n | n | pop n values into a new Array, push it |
| 0xA0–0xBF | | send special selector i |
| 0xC0–0xCF | | send literal 0–15, 0 args |
| 0xD0–0xDF | | send literal 0–15, 1 arg |
| 0xE0–0xEF | | send literal 0–15, 2 args |

Backward jumps and sends are **safepoints**: the VM checks its interrupt flag there.

In the image only `InstructionStream` (System-Debugging) decodes bytecodes: it turns each instruction into a message (`pushTemporaryVariable:`, `send:super:numArgs:`, `jump:if:`, ...) sent to a client — the `Simulator` executes them, the `Disassembler` (`CompiledMethod>>symbolic`) prints them. `BytecodeEncoder` (Compiler) encodes.

## Processes and interrupts

- Run queues: `Processor quiescentProcessLists at: priority` (1–80). `activeProcess` is not in a run queue.
- `resume`: if the process's priority is higher than the active one, the active process is **preempted to the back of its queue** (this gives round-robin among equals whenever a higher-priority process runs; wakeups of the sampler and allocation-sample semaphores put it at the front instead, so profiling does not change the schedule) and recorded as `lastPreemptedProcess`; otherwise the resumed process goes to the back of its queue.
- `suspend`, `yield`, `Semaphore>>signal`/`wait` are primitives with Squeak semantics. `terminate` is Smalltalk.
- At each process switch the VM adds the elapsed microseconds to the outgoing process's `cpuTime`.
- **Interrupts**: an atomic "check" flag, set when something is due: by a ticker thread (a kqueue timer) at the timer's and the CPU sampler's next deadline and, if the platform asked for it (`request_periodic_poll`: windows exist or sockets have semaphores), every 1 ms; by allocation when the allocation-sample threshold is crossed; by GCs that cleared weak slots; by external semaphore signals and injected events. The ticker is disarmed while the VM waits in `platform_wait` (the wait's timeout covers the timer and the sampler; events and sockets end the wait), so an idle VM gets no ticks. At the next safepoint the VM: signals the timer semaphore if its time has come; signals the sampler semaphore at the configured interval; polls platform events and sockets and signals their registered semaphores; signals the allocation-sample semaphore (recording the allocated object's class and size). Signaling may preempt.
- **Idle**: Smalltalk's idle process (priority 1) calls `relinquishProcessorForMicroseconds:`, which blocks in the platform's event wait until an event, socket activity, the next timer or the next sampler tick (the always-on profiler samples idle time too, so an idle image still wakes once per sampler interval).

## Primitive interface (C)

`vm/src/vm.h` is the only header primitives include:

```c
typedef uint64_t oop;
bool is_int(oop); int64_t int_val(oop); oop int_oop(int64_t); bool int_fits(int64_t);
bool is_char(oop); uint32_t char_val(oop); oop char_oop(uint32_t);
bool is_float(oop);            /* SmallFloat64 or BoxedFloat64 */
double float_val(oop); oop float_oop(double);   /* may allocate */
bool is_ptr(oop); oop class_of(oop);
uint32_t num_slots(oop); int format_of(oop);
oop load_ref(oop obj, uint32_t i); void store_ref(oop obj, uint32_t i, oop v);
uint8_t *bytes_of(oop); size_t byte_size(oop);
uint32_t *words32_of(oop); size_t word32_size(oop);
oop alloc_slots(oop cls, uint32_t n); oop alloc_bytes(oop cls, size_t n); oop alloc_words32(oop cls, size_t n);
oop special(int index); extern oop nil_oop, true_oop, false_oop;
oop string_from_utf8(const char *s, size_t n);   /* ByteString or WideString */
char *utf8_of(oop string);                        /* malloc'd, NUL-terminated; NULL if out of memory */
void push_root(oop *p); void pop_root(void);     /* protect C locals across allocation */
/* inside a primitive */
int prim_argc(void); oop prim_receiver(void); oop prim_arg(int i);   /* i = 0..argc-1 */
void prim_return(oop v); void prim_fail(void); void prim_fail_code(int code);
void signal_external_semaphore(int index);       /* VM thread only */
void request_interrupt_check(void);              /* any thread */
void request_periodic_poll(int64_t interval_us); /* VM thread: platform_poll at least every interval_us while Smalltalk runs; 0 = none */
```

Error codes for `prim_fail_code` are in the EXPORTED CONSTANTS block of vm.h (Smalltalk: `VMConstants primErr…`). `PRIM_ERR_NO_MEMORY` (1): the object can never fit in the heap, even after a full GC (size beyond the heap limit or the object size limit, or a LargePositiveInteger size). `basicNew:` and `shallowCopy` fail with it and their Smalltalk fallbacks signal `OutOfMemory` (Kernel-Exceptions; `requestedClass`, `requestedSize`). Other allocations that cannot be satisfied (contexts, small objects when the heap is full) are fatal.

Primitive functions are `void fn(void)`. `prims.def` (core, numbers 1–399) and `platform/prims_platform.def` (400–699) are X-macro lists `PRIM(n, "name", fn)`, the single source of truth: the Python bootstrapper parses them, and `Smalltalk vm primitiveNames` returns them to the Smalltalk compiler. Source refers to primitives by name: `<primitive: 'basicNew'>` (a bare number also works).

## Core primitives (names are fixed; numbers are the VM's choice)

A primitive fails (method body runs) on wrong argument types or ranges. Indices are 1-based and count indexable fields only (after fixed fields).

| area | names |
|---|---|
| object | `class` `identical` (==) `identityHash` `basicNew` `basicNew:` `basicSize` `at` `atPut` (pointers → oops, bytes/words → SmallIntegers, BoxedFloat64 → bits) `instVarAt` `instVarAtPut` `shallowCopy` `perform` (selector + up to 4 args on the stack) `performWithArguments` `isImmutable` `setImmutable:` (answers the old flag) `changeClassTo:` `allInstances` (Behavior receiver) `tryPrimitiveWithArgs` (Context receiver: `tryPrimitive: index receiver: r args: array` answers the result, or the special object `#primitiveFailed` symbol on failure — for the debugger's simulator) |
| SmallInteger | `intAdd` `intSub` `intMul` `intDiv` (exact only) `intQuo` `intRem` `intFloorDiv` (//) `intMod` (\\) `intLess` `intGreater` `intLessEq` `intGreaterEq` `intEq` `intNotEq` `intBitAnd` `intBitOr` `intBitXor` `intBitShift` `intAsFloat` — fail on overflow (Smalltalk falls back to LargeInteger code) |
| Float | `floatAdd` `floatSub` `floatMul` `floatDiv` `floatLess` `floatGreater` `floatLessEq` `floatGreaterEq` `floatEq` `floatNotEq` `floatTruncated` (fails outside SmallInteger range) `floatFractionPart` `floatExponent` `floatTimesTwoPower` `floatSqrt` `floatSin` `floatCos` `floatArcTan` `floatLn` `floatExp` `floatPrintString` (shortest round-trip) `floatAsIEEEBits` `floatFromIEEEBits` (class side) |
| Character | `charValue` `charFromValue` (class side) |
| strings & bytes | `stringAt` `stringAtPut` (Characters; ByteString/WideString/Symbols) `stringHash` `stringCompare` (answers -1/0/1 by code point) `replaceFromToWithStartingAt` (same-format bulk copy) `bytesUint16At` `bytesUint32At` `bytesInt16At` `bytesFloat32At` `bytesFloat32AtPut` `bytesUint32AtPut` `bytesFloat64At` `bytesFloat64AtPut` (byte offset 1-based, little-endian) `bytesUint16BigEndianAt` `bytesInt16BigEndianAt` `bytesUint32BigEndianAt` (for TrueType) |
| blocks | `closureValue` (0–4 args) `closureValueWithArguments` — markers `ensureMarker` (`ensure:`/`ifCurtailed:`), `onDoMarker` (`on:do:`) |
| processes | `processResume` `processSuspend` `processorYield` `semaphoreSignal` `semaphoreWait` `processorLastPreempted` `processorRelinquish` (µs) `signalAtMilliseconds` (timer semaphore) `samplerInterval` (µs, external semaphore index; 0 stops) `allocationSampling` (byte interval, external semaphore index) `allocationSampleInfo` (Array: class, size) `processCpuTime` (cpuTime including the running slice) `processStackInto` (profiler: a non-running process's frames as method, pc pairs into an Array; see prims_control.c) |
| time | `millisecondClock` `microsecondClock` (monotonic) `utcMicroseconds` |
| system | `quit` `snapshot` (path; answers true when resumed from the snapshot, false right after writing) `gc` (full GC) `scavenge` (young generation only; a full GC, if old space then exceeds its budget, happens at the next allocation) `vmStats` (Array of counters, documented in prims.def; `Smalltalk vm statistics` wraps it in a VMStatistics with named accessors) `flushMethodCache` `flushCacheForSelector` `vmArguments` `imagePath` `stdoutWrite` `stderrWrite` `primitiveNames` `getenv` |

## Sources

`src/packages.txt`: one line per package, `Name layer [uses Package…]`, in load order, plus `export Package layer Global…` lines (the layering allow-list, see Layers in the image). Each class lives in `src/<Package>/<Class>.st`; methods a package adds to another package's class go in `src/<Package>/<Class>.extension.st`. Classic chunk format (`!` terminates a chunk, `!!` escapes):

```
Object subclass: #Point
	instanceVariableNames: 'x y'
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Point comment: 'I am a two-dimensional point.'!

Point class instanceVariableNames: 'cache'!

!Point methodsFor: 'accessing'!
x
	^x
!
x: aNumber
	x := aNumber
! !

!Point class methodsFor: 'instance creation'!
x: ax y: ay
	^self basicNew setX: ax setY: ay
! !
```

Definition variants: `subclass:`, `variableSubclass:`, `variableByteSubclass:`, `variableWordSubclass:`, `weakSubclass:`, `immediateSubclass:`, and `nil subclass:` for roots. Files are UTF-8; strings with code points > 255 become WideStrings. Symbols are unique (`Symbol` interns them); `String>>hash` and `Symbol>>hash` are the same function: FNV-1a over code points (`h = 2166136261; for cp: h = ((h ^ cp) * 16777619) mod 2^32`), result `& 16r3FFFFFFF`, primitive `stringHash`.

## Seed startup

The bootstrapper builds the class graph (classes, metaclasses, method dictionaries, globals in `Smalltalk`, class pools, interned symbols), compiles every method, creates `Processor` with 80 empty LinkedLists, and one Process at priority 40 whose context runs `Smalltalk bootstrapStartUp` (with receiver `Smalltalk`). `bootstrapStartUp` (Smalltalk) runs class-side `initialize` in load order, rehashes hashed collections, and continues with stage 2 (when `--stage2` is given) or the normal startup.

## Graphics (platform layer, Smalltalk-facing)

SDL3 windows and events; SDL_GPU (Metal) for rendering. Shaders are MSL source strings owned by Smalltalk (Graphics-Canvas); the C side only wraps SDL_GPU calls with integer handles. Events reach Smalltalk as 8-slot Arrays `[type, timeMs, x, y, buttonOrKey, modifiers, textOrDelta, windowId]`; `injectEvent:` pushes an Array in the same format into the same queue (the virtual input device used by remote control). Frame readback (`gpuDownload…`) feeds screenshots (PNG encoded in Smalltalk) and video recording (raw frames written to a FIFO read by ffmpeg).

## Layers in the image

`Kernel-*`/`System-*`/`Compiler` (layer 0) → `Graphics-GPU` (thin wrapper over GPU primitives) → `Graphics-Canvas` (fonts, glyph atlases, display lists, the 2D renderer) → `UI-Windows` (World, Compositor, Window with its own Process, animation), `Demos` → `UI-Widgets` (incl. the `Desktop` facade) → `Tools`. A package uses its own layer, the one directly below and layer 0, plus the exceptions declared in `src/packages.txt` (`export` lines: Graphics-Canvas' Canvas/Color/Font/Form from layer 3 up; `uses`: test fixtures). The bootstrapper checks every global a method or class definition references and fails listing each violation as file:line (docs/ui.md).
