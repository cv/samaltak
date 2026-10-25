# JIT

Status: the shared runtime, the template, threaded, stencil and baseline compilers and the optimizing tier run; `sista` is planned. Every JIT variant is written in Smalltalk: Lowtalk for code in the VM (translated to C like the rest of it), ordinary Smalltalk for code in the image. No LLVM at run time. Target: Apple Silicon (M2 Max, arm64, macOS).

The goal is a comparison of JIT designs and optimizations on the same VM, the same image and the same benchmarks: speed of the generated code (warm-up and steady state) and speed of the JIT itself. The best variant must beat Pharo 12's Cog JIT on every Are We Fast Yet benchmark (docs/benchmarks.md).

## Variants

| name | `--jit` | what |
|---|---|---|
| I | `none` | the interpreter (computed goto, PGO) |
| M | (all) | married Contexts: closure creation no longer flushes frames (interpreter change, benefits every variant) |
| P | `template` | a fixed machine-code template per bytecode on the frame's slots, the interpreter's inline paths, sends through the runtime: dispatch removed, nothing else |
| T | `threaded` | call threading: one `bl` per bytecode into the handler; removes dispatch only |
| S | `stencil` | copy-and-patch: handler stencils compiled by the C compiler at build time, read by Smalltalk from the object file, copied and patched at run time |
| B | `baseline` | Cog-style: own arm64 assembler, simulated operand stack in registers, machine-code inline caches (monomorphic, polymorphic, megamorphic), inline SmallInteger/Float arithmetic and common primitives |
| Y | `sista` | B plus a speculative optimizer in the image (Smalltalk, as Sista/Scorch): type feedback from B's inline caches, inlining with guards, unsafe bytecodes, deoptimization in Smalltalk |
| O | `opt` | B plus an optimizing tier in the VM (Lowtalk): SSA IR, inlining from type feedback, closures not made, unboxed Floats, linear-scan register allocation, deoptimization to frames |

Each variant has ablation flags (`--jit-flags -ic,-arith,...`) so that the effect of each optimization is measured separately.

## Shared runtime

The interpreter's frames are the canonical state. Machine code runs on the same frame records and C-stack slots; at every safepoint (a call out of machine code that may allocate, collect, flush frames, switch processes or run Smalltalk) the values it holds in registers are in their slots and the frame's `pc`/`sp` are valid. Hence:

- the interpreter can resume any frame of compiled code at its bytecode pc, and compiled code can be entered at the pc of a frame the interpreter was running (on-stack replacement at backward jumps, return into a compiled caller);
- GC roots, `materialize_all` (frames into Contexts), the debugger, stack printing and process switches stay as they are;
- deoptimizing baseline code is free; flushing the code cache only needs no machine code on the native stack.

**Frames.** A `Frame` has a `code` field: its method's `JitMethod` (machine code), 0 (none), or 1 to 0xFFFF while the JIT counts it (activations, then backward jumps). Every frame push sets it: from the method cache entry (`K_JIT` entries hold the code or 1; `fillCache` asks `JitRuntime`), for blocks from the home method's code. Machine code keeps `pc` and `sp` (one 64-bit store) current at safepoints instead of `ip`; the runtime turns them into `ip`, `nframes` and `cstackUsed` (`Interpreter>>syncFrame:`). Operands live in their slots at offsets known at compile time (`BytecodeAnalysis`: the depth before every instruction).

**Native stack.** Machine code calls compiled callees with `blr` and returns with `ret`, so the native stack mirrors the frames entered since the last `jit_enter`, 16 bytes (x29, x30) per activation. `jit_enter(frame, address)` (`JitStubs`, generated at startup) saves the callee-saved registers, sets x19–x22, remembers the native stack pointer, pushes x29/x30 as a prologue would and branches to `address`. Leaving to the interpreter resets the native stack to `jit_enter`'s and returns: `exitSync` (the code stored the frame's pc and sp: the interpreter continues there), `exitPlain` (the runtime made the frames canonical). Returning from the first activation lands in the trampoline, which answers the caller's frame; the runtime continues its machine code if it has some (`JitRuntime>>run:at:`), else the interpreter.

**Registers** (callee-saved, pinned): x19 the frame record, x20 its slots (`fp`, receiver at `fp[-1]`), x21 the receiver, x22 the `JitState` (nil/true/false and the classes inline paths check, refreshed after every GC; the interrupt flag; the frames array; jit_enter's stack pointer; the young space's bounds). x23–x28 are free for register allocation (baseline: x23–x25 nil, true, false; x26–x28 loop temps); x0–x17 scratch. A method or block starts with the prologue (`JIT_PROLOGUE_BYTES`: x19 := the next Frame, push x29/x30, load x20, x21), then an interrupt check; its start is after the prologue.

**Calls into the runtime.** Machine code stores pc and sp, calls a stub (`ldr x16, =function; br x16`, in the code cache so that `bl` reaches it) with the frame in x0; after a safepoint it reloads x21. The runtime answers 0 (continue), 1 (leave: `exitPlain`) or, for a send, the callee's entry (frame pushed; the caller `blr`s it). If frames were flushed (process switch, `thisContext`, stack full), or code was invalidated, it answers 1. Sends (`send:info:site:`) use the interpreter's inline caches, keyed by the site's code address: frameless sends (^ivar, constants, setters) touch the frame only when an interrupt is pending (they are safepoints, as in the interpreter); leaf primitives and primitives run as in the interpreter; a method with code gets its frame pushed from the cache entry; a method without code is counted (compiled at the threshold) or its frame is pushed and the interpreter runs it; a send the runtime cannot complete cleanly (doesNotUnderstand:, a married receiver, a full stack, `perform:`) leaves to the interpreter to execute it again, which it can because nothing happened yet. Special selectors (`special:info:site:`) first try the interpreter's fast paths, `value`/`value:` on blocks enter the block's code. Closures, Arrays (`0x94`) and outer temps (when frames are not 64 bytes) are runtime calls.

**Interpreter hooks.** Activating a method whose cache entry is `K_JIT` (count, compile, enter at start: `JitRuntime>>activated:`), returning or non-locally returning into a frame with code and activating a block whose home has code (continue at `ip`: `resume:`), a backward jump in a frame whose `code` is not 0 (count, compile, on-stack replacement: `backJump:`). Process switches flush all frames, often (the sampler), so returning into or jumping back in a Context whose method has code marries the Context to a new bottom frame, its sender the base, and continues it in machine code (`resumeContext:`, `Interpreter>>thawFor:`); otherwise long-running loops would stay interpreted and every return into them would leave machine code. With `--jit none` they cost a load and a branch on paths that already do work. The bytecode-pc to machine-pc map holds the resumption points: method and block starts, continuations after sends, loop heads, conditional jumps (a `mustBeBoolean` send returns to them).

**Exits.** A compiler may leave to the interpreter at any instruction (`exitSync`): the template does for `thisContext`, non-local returns, `mustBeBoolean`, stores into immutable objects and returns from the bottom frame. The interpreter continues the frame and comes back at the next send, return or backward jump.

**Code.** One `MAP_JIT` region (`pthread_jit_write_protect_np`, `sys_icache_invalidate`), bump allocated after the stubs. A compiled method's header (`JitMethod`) follows its code: the method (a GC root), the compiler, start, the bytecode map, the sites of embedded object references (`mov:imm64:` of old objects; full GCs and become patch them), the notes. Methods are found by identity hash (stable across moves) in a 64K open-addressed table; activations are counted per hash. Scavenges update the methods of headers compiled while the method was young (a list); full GCs and become all of them. Literals are loaded through the frame's `lits`, or embedded with `--jit-flags embed`. When the cache (or the table) is full the method stays interpreted and the whole cache is flushed at the next interpreter hook, when no machine code is on the native stack: frames go back to counting, the method caches are flushed. Become of a compiled method kills its code (its frames are interpreted from then on). Method dictionary changes flush the interpreter's caches, which the runtime's sends use. Snapshots flush the frames; machine code is not saved.

**Triggering.** `--jit-threshold N`: activations before a method is compiled (0: the first); `--jit-osr N`: backward jumps in an interpreted frame before its method is compiled and the frame continues in machine code. `--jit-cache MB` (1–128).

**Disassembly.** The machine code of any method can be shown from the image, for any variant (compiling it if needed, `CompiledMethod>>machineCode`, `machineCodeFor: #template`, the System Browser's method menu): every instruction, grouped under the bytecode it implements (with the source line), and commented with what it does (tag check, overflow branch, spill, call into the runtime by name...). Compilers record the comments as they emit (always for a disassembly, for all code with `--jit-flags notes`); `jitCode` answers code, address, bytecode map, notes and stub names; `Arm64Disassembler` prints them.

**Statistics** (`vmStats`, `VMStatistics`): methods and bytecodes compiled, microseconds compiling, code bytes, cache flushes, entries into machine code, exits, resumptions, on-stack replacements, methods that could not be compiled.

**Constants.** The code generators (`JitStubs`, the compilers) are `Arm64Module`s, so they name registers and conditions; the runtime and the analysis are `VMCoreModule`s, with the VM's helpers and constants. Neither needs the other's class variables: the generators ask the runtime through inline accessors (`runtime arith`, `runtime prologueBytes`), struct offsets come from the structs (`(self cCoerce: 0 to: 'Frame *') fieldAddress: #fp`).

## Compilers

`JitRuntime>>compile:mode:notes:` analyzes the method (`BytecodeAnalysis>>analyze:`), then has the mode's compiler emit at the assembler's pc; it appends the header, installs it and counts. A new variant:

- a module subclassing `JitCompiler` (its conventions: prologue, `emitSync:depth:`, stubs, frame and state offsets) with `compile: aMethod` answering whether it emitted every reachable instruction; it records resumption points (`runtime noteResume:at:`) and embedded references (`runtime noteReference:`);
- its mode in `JitRuntime>>modeNamed:` / `modeName:` and a case in `compile:mode:notes:`; its flags in `flagNamed:length:` (queried as inline accessors);
- if it keeps values in registers, spills before every runtime call and at every resumption point.

**Template** (`JitTemplateCompiler`, `--jit template`). Every bytecode is a fixed template on the frame's slots; no values stay in registers between bytecodes. Inline: pushes, stores (the store barrier's fast path), jumps (an interrupt check on backward ones), outer temps (married frames' slots or the Context's), SmallInteger `+ - * // \\ bitAnd: bitOr:` and comparisons with tag checks and overflow branches, Floats (SmallFloat64 or SmallInteger operands, without boxing) out of line, `== ~~`, `at: at:put: size` on Arrays, `x y` on Points, `class`; as in the interpreter an arithmetic result followed by a pop into a temp goes straight there and a comparison followed by a conditional jump branches directly (the consumed instruction's code is emitted out of line for slow paths and resumption). Sends and everything else call the runtime. Flags: `arith` (inline arithmetic and primitives), `fuse` (the fusions), `barrier` (the barrier's fast path), `notes`, `embed`.

**Stencils** (`JitStencils`, shared by `threaded` and `stencil`). One Lowtalk method per bytecode handler (`<stencil>`; `<stencil: 16>` for variants by an operand, `self case`), with the template's inline paths, superinstructions and fusions. The JIT state is the stencil's arguments, pinned registers: `fp` x20, `rcv` x21, `st` x22 (the `JitState`), `sp` x23 (the operand stack's top), `fr` x24 (the frame). `self hole: #A` is a value patched in at compile time (`PC`, `A`, `B`, `C`, `INFO`, `VALUE`; `SITE` is the stencil's address); `^self continue` goes to the next bytecode, `^self jump` to the target, `^self slow` to an out-of-line stencil, `^self exitSync`/`exitPlain` leave to the interpreter, `^self return` returns the frame; the runtime is called as from any VM code (`jit send: fr info: ... site: ...`, after `self sync` at safepoints), a compiled callee with `self call: entry` (x19 := the frame, x23/x24 kept on the native stack). `make translate` writes:

- `vm/gen/jit_stencils.c`: each stencil as a `preserve_none` C function taking the state; holes are `extern` symbols (`&_JIT_A`), continuations `musttail` calls of extern functions; not part of the VM;
- `vm/gen/jit_stencils_table.c`: the translator compiles that file with cc (`-O2`, no unwind tables, no stack protector, no jump tables, no outliner), `MachObjectFile` (Smalltalk) reads the object's sections, symbols, relocations (`BRANCH26`, `PAGE21`/`PAGEOFF12`, `GOT_LOAD_PAGE21`/`PAGEOFF12`, `UNSIGNED`, `ADDEND`) and linker optimization hints (which `adrp`/`ldr` pairs belong together), `StencilTable` writes code bytes, per stencil offset, size, relocations and the length without trailing trampolines, the symbols, read-only data. Reproducible: `tests/vm/gen_test.sh` checks it;
- `vm/gen/jit_stencils_threaded.c`: the same stencils as ordinary C functions in the VM (holes as arguments, continuations as return codes), compiled with `-ffixed-x20`…`x24`.

**Stencil** (`JitStencilCompiler`, `--jit stencil`). Copies each bytecode's stencil and patches it: a hole's GOT load becomes `movz`/`movn` (16 bits), `movz`+`movk` (32), `adr`, `adrp`+`add` or a literal after the method; branches to the runtime go to veneers, `ldr`s of its symbols to a GOT, both in the code cache in `adrp` range (`JitStencilCompiler>>open`). Continuations: a branch to the next stencil is left out when trailing, branches to a trampoline go where the trampoline goes (then the trampolines are not copied), jumps to labels, slow paths out of line after the method. Interrupt checks of method starts and backward jumps branch to an out-of-line poll. Methods start with the shared prologue, then `mov x24, x19; add x23, x20, #8·(depth−1)`; resumption points get that glue out of line. The code cache replaces a reserved region of the VM's bss so that `bl` from the code reaches the VM's functions.

**Threaded** (`JitStencilCompiler compile:threaded:`, `--jit threaded`). One `bl` per bytecode into its stencil compiled into the VM, holes in x0–x5 (`movz`), the answered continuation tested after it (`cbnz x0`, `cmp`; `b.eq`), exits through the shared glue; same prologue, resumption points and runtime calls as `stencil`.

**Baseline** (`JitBaselineCompiler`, `JitBaselineRuntime`, `--jit baseline`). After Cog's StackToRegisterMappingCogit: one pass over the bytecodes with a simulated operand stack whose entries are in their slot, in a register (x0–x8, x12–x15), a constant, nil/true/false (pinned in x23–x25), self (x21), a temp or a literal not loaded yet, or an unboxed Float (d8–d15). Values go from producer to consumer in registers, constants become immediates, folded where both are known; the stack goes to its slots at sends, runtime calls and merge points (which start with every entry in its slot). Before an instruction that may send, everything below its operands is written back (unboxed Floats stay: its slow path boxes and reloads them around the send), so its slow path stores only the operands. Layout: checked entry, unchecked entry, frame code, the bytecodes in pc order (block bodies with their entries), slow paths, resumption stubs, the literal pool, the `JitMethod` header (`adr` reaches it).

- *Sends*: the receiver in x0, receiver and arguments in their slots, `add x20` to the callee's fp, `ldr x9` the site's class from the pool, `bl` the site's target, `sub x20` after; the result comes back in x0. The target is the miss stub while unlinked; a compiled method's checked entry when monomorphic (its class check against x9: tag test, class word, compare; immediates by tag out of line); a `BaselinePic` of up to 6 classes, each branching to its target's unchecked entry; or, megamorphic, the megamorphic stub (x9 then holds the selector; a 4096-entry table probed in machine code). The miss stub calls `JitBaselineRuntime>>miss:receiver:ret:`, which looks the send up (the interpreter's global cache), compiles the target at the threshold, links or relinks the site (code patched under the W^X toggle) and jumps to the target; it leaves to the interpreter for `doesNotUnderstand:`, married Contexts, `perform:` and uncompiled targets. Young classes are cached too (their words become young roots). Method dictionary changes (`flushMethodCache`, `flushCacheFor:`), become and dead code unlink every (or every such) site. Super sends link once to the unchecked entry. Each site's state is its type feedback: `JitBaselineRuntime>>feedbackSitesOf:` and friends (pc, selector, state, receiver class and target per case) for the optimizing tiers, `CompiledMethod>>jitSendSites` in the image.
- *Frames*: the callee compares its fp against the JitState's stack limit (0 while an interrupt is pending: the one compare is also the interrupt check), pushes the native record (x29, x30) and its Frame with two `stp`s and a `str` (code, closure and ctx nil, fp, pc and sp 0), x21 := the receiver, nil into its temps; a return pops both after one check (a married frame, or frame 0, which `run:at:` marries, takes the slow path). A Frame's method, pc, sp, ip and lits are lazy: the runtime makes a suspended frame canonical from the return address in its callee's native record (`canonicalizeBelow:`, the method's return map: return offset, pc, depth, argc, length, pushes; frame f's record is at `baseRecord − 16·(f − baseFrame)`), top down, stopping at the first frame that already is (a zero pc marks a frame pushed since). Every runtime entry that may collect, flush or leave does that first (`JitRuntime>>sync:`, the exit stub).
- *Quick methods* (^ivar, ^self, ^constant, ^literal, setters) run without a frame; with an interrupt pending they take the frame's path (sends are safepoints). *Primitives* run before the frame: in machine code for `basicNew`, `basicNew:` (eden bump allocation with the identity hash generator inline), `==`, `class`, closure `value`, SmallInteger and Float arithmetic and comparisons, SmallInteger `quo: rem: // \\`, `sqrt`, `truncated`, `charValue`, `Character value:`, `identityHash`, `at: at:put: basicSize` (pointers without fixed fields, 32-bit words, bytes), `uint32At:` and `uint32At:put:` of bytes; the others through their C function (`prim:fp:fn:info:`; leaf ones without canonicalizing). Failure continues into the frame and the body.
- *Inline at send sites*: SmallInteger `+ - * // \\ bitAnd: bitOr: bitShift:` and comparisons (tag checks only for operands not known, immediates, overflow branches), compare and branch fused with the conditional jump, jumps threaded into a conditional jump on the value just pushed (`and:`, `or:`). Floats: an operation with an operand that surely is a Float (an unboxed value, a Float constant, a temp whose unboxed value is known in the basic block) decodes the other (SmallFloat64, BoxedFloat64, SmallInteger) and leaves its result unboxed in a d register for the next one; other operations try SmallIntegers first, Floats out of line; boxing (a SmallFloat64, else a BoxedFloat64 allocated inline, else by the runtime) happens when a value goes to memory or a send. `== ~~ class` never send, nor do `isNil notNil` while only UndefinedObject and ProtoObject define them (a heap scan; another definition drops all code); `at: at:put:` inline for Arrays, out of line for Strings, Symbols and ByteArrays (`size` is sent: classes define their own, and Arrays answer it from the primitive in machine code); `value value: value:value:` check the closure's class and argument count and call the block stub, which finds the block's entry in a (home method, startpc) cache. Closures (with the marriage's Context), Arrays (`0x94`) and Floats are allocated inline; outer temps inline; the store barrier's fast path inline (the remember stub saves the registers).
- *Loops*: innermost loops that send nothing (inline operations' slow paths aside) keep their three most used temps in x26–x28, stored through to their slots; slow paths that call reload them, a stub loads them at the loop head for on-stack replacement.
- *Non-local returns* to a home frame in this machine-code session, above frame 0, without an unwind marker in between, widow the frames and return from the home through its native record (`nlr:`); others leave to the interpreter.
- Resumption points: method and block starts (an interrupt check out of line), loop heads, send continuations (a stub loads the result from its slot) unless unboxed values are live there. Exits as the template's, through the runtime so that the frames below become canonical.
- Flags (each switches one optimization off, for the ablations): `ic` (inline caches: every send looks up in the runtime), `pic`, `mega`, `regs` (every push to its slot), `arith`, `fuse` (compare and branch, jump threading), `float`, `access`, `prims`, `alloc`, `blocks`, `nlr`, `quick`, `temps` (loop temps in registers), `barrier`, and `notes`.

## Optimizing tier

`--jit opt` (`OptBuilder`, `OptPasses`, `OptRegalloc`, `OptCodegen`, `OptRuntime`, `JitFeedback`; Lowtalk in `VM-Jit`). Baseline code is the lower tier; hot methods, blocks and loops are compiled again from their bytecodes with type feedback, inlining and speculation, and deoptimize to frames when a speculation fails.

**Tiering.** In this mode baseline code counts, per method (identity hash), method and block entries and backward jumps (`emitTierUp:depth:loop:`, a decrement of a word in the VM's data). At zero it stores pc and sp and calls the tier-up stub (x0 the frame, x1 whether at a backward jump); `OptRuntime>>tierUp:loop:` answers where the frame continues: the method's optimized code at its start, a block's unit, or a loop's unit (on-stack replacement at the loop head). Units are compiled once per method, per block (method, startpc) and per loop (method, block, loop head); a failed compilation is remembered. A method's optimized code is installed in the method caches, in its cell (direct calls from optimized code read entry and header there) and over its baseline code's unchecked entry: a `b` to an entry that builds the frame as baseline callers expect it (`JitBaselineRuntime>>redirect:to:`, undone on invalidation; not for quick methods and primitives). `--jit-opt N` sets the count (default 1000), `--jit-flags eager` makes it 1. Frames resumed after a process switch (Contexts married to new frames) enter loop units too; if their code makes closures, the temps the closures reach stay in the frame (a closure may change them through the Context).

**Calls between the tiers.** Optimized code calls baseline code with the frame pushed, through the template's prologue that baseline code has in this mode before each method and block start, and takes the result from x0 (baseline callees answer only there). It answers in x0 and the receiver's slot, so either tier may call it, and keeps x23–x25 (baseline code's nil, true, false; reloaded after runtime calls). Baseline frames below an optimized one are lazy: `canonicalizeBelow:` skips optimized frames (their pc and sp are stored at every call) and marks the ones it passed (lits odd until the frame is pushed again or a GC), so the next walk stops there; leaf primitives sent from optimized code run without the walk.

**Type feedback** (`JitFeedback`): per (method, bytecode pc) up to 4 receiver classes with counts, `FB_MEGA` beyond, and profile bits: Float operand, non-number operand, overflow, and why optimized code deoptimized there (class guard, arithmetic guard, bounds check, other). It does not depend on the compiler that collects it: baseline code reports every receiver class its inline caches miss on (`noteSend:pc:class:`) and, without a call, sets a byte per site when an inline Float path runs (`floatBitAddressFor:pc:`); deoptimization reports what failed (an arithmetic guard looks at the operands). What baseline code takes inline without a send gives no feedback; the optimizer reads that as the inline case: `at: at:put: size` as Arrays, `value value: value:value:` as BlockClosures (both guarded), arithmetic as SmallIntegers; `isNil notNil` are comparisons with nil while no class but UndefinedObject and ProtoObject defines them.

**IR** (`OptIR`): nodes in fixed arrays (operation, representation oop or double, type: SmallInteger with a range, Float, Boolean, nil, Character, a class), blocks with predecessor edges, frame states (per activation: method, closure, receiver, pc, slot values, chained to the caller's) for every guard and safepoint, inlined activations. `OptBuilder` builds SSA directly from the bytecodes (Braun et al., Simple and Efficient Construction of Static Single Assignment Form, CC 2013), one variable per frame slot of every activation; arguments are never phis, temps a loop does not store are not either.

**Inlining.** A send is inlined for the class the receiver is known to have, or speculated from feedback: one class behind a guard, up to four behind a type switch (anything else deoptimizes); a mega site, one that deoptimized for a class, and sends without feedback go through the runtime (`OptRuntime>>send:index:site:`, the interpreter's inline caches) or, for a method with machine code, as a direct call: the frame pushed inline, the entry from the method's cell (it follows tier changes). Methods up to 200 bytecodes, 3000 in all, 8 deep, a recursive one once. Blocks evaluated by an inlined `value…` send are inlined into the activation that made them; their closures are never made: frame states describe them (sunk), deoptimization makes them, marrying the frames they refer to. A closure that escapes (stored, passed, answered) makes the compilation start over without inlining the method that made it. `^` in an inlined block is a jump to the home activation's return; in a block's unit it deoptimizes.

**Primitives and speculation.** SmallInteger `+ - * < > <= >= = ~= // \\ quo: rem: bitAnd: bitOr: bitXor: bitShift:` with tag guards and overflow checks (Boolean results branch directly, no frame state); Float `+ - * / < > <= >= = ~= sqrt` on doubles (SmallFloat64 or SmallInteger operands decoded, the result encoded; out of SmallFloat64's range, a zero divisor: deoptimize; a box used again in its block is not decoded; a site whose feedback shows Floats and never two SmallIntegers has no SmallInteger path, two SmallIntegers deoptimize); `at: at:put: size basicSize` with bounds checks for pointer, byte and string objects; `basicNew basicNew:` of pointer objects in eden (header, class, nil fields inline; the send when eden or the allocation sample's limit is reached); `== ~~ class`, `Character value`, `Character value:`; `value value: value:value:` of a closure the IR does not know: the frame pushed inline for the code the site called last (a 4-word cache per site, cleared at every GC and kill). Interrupt checks at method entries and backward jumps; the write barrier inline, left out for stores of immediates, nil, true and false; immutability checked once per object and block.

**Passes** (`OptPasses`): unreachable blocks, trivial phis, global value numbering over the dominator tree (guards, arithmetic, comparisons, Float conversions, constants; field loads within a block with no store or safepoint between), unused pure nodes, critical edges split, reverse postorder.

**Registers** (`OptRegalloc`): linear scan (Poletto and Sarkar) over one interval per value: x0–x13, x26–x28, doubles d16–d31 (never spilled, never live across a safepoint); a value live across a safepoint also has a home slot in the frame, stored at its definition and reloaded after the safepoint; constants are rematerialized. Phi moves are sequentialized (cycles through a scratch register).

**Code and frames** (`OptCodegen`). An optimized frame is a frame: x19–x22 as in the lower tier, the root activation's arguments in their slots, then home slots and the outgoing receiver and arguments; its `pc` is the bytecode size plus a safepoint number. Out-of-line paths after the code: guard failures, interrupt checks, store barriers, deoptimization after a call, the stack check, the bottom frame's return. The header holds the safepoint table, the deoptimization records (kind, the send, per activation method, closure, receiver, pc and the location of every slot: register, slot, constant, sunk closure) and the dependencies; an oop pool after the code (pc-relative loads, GC roots). The listing (`machineCodeFor: #opt`) shows the root method's bytecodes and the inlined activations' pcs.

**Deoptimization** (`OptRuntime`). A failed guard jumps to a stub that saves the registers; the record rebuilds the activations as frames (the closures never made are made), the interpreter continues the innermost one, and the site's feedback learns what failed. A failure the feedback had not reported invalidates the code at once (it compiles differently next time), so does the ninth deoptimization; a site that fails again in code compiled with what it reports now is marked: no speculation there next time; a unit is compiled at most 32 times. `materializeAll` (process switches, `thisContext`, the debugger) turns an optimized frame into a Context per activation; the interpreter returning into an optimized frame resumes it at its safepoint. Invalidation (lazy): a method added or removed for a selector the code inlined or speculated on (`flushCacheForSelector:`), become of a method: the code is marked dead, frames running it deoptimize when control comes back to them (a check after every call), calls into it go to the lower tier. Switching the mode away from `opt` makes every optimized frame Contexts first.

**Stress.** `--jit-flags eager` optimizes at the first count; `deopt` makes optimized code take every 37th slow path it passes (guards, interrupt checks, returns from calls) and deoptimize there, without feedback. `make test-jit` runs the image's tests under `--jit opt` with eager and with eager,deopt; `vm/tests/run.sh` the mini kernel's under both (with the GC stress) and the default thresholds; `JitOptRuntimeTest` covers deoptimization of a failed speculation, invalidation of inlined code while it runs, the stress, the listing.

**Flags** (`--jit-flags`, all on by default): `inline` (methods), `blocks` (closures), `prims`, `unbox` (Floats on doubles), `calls` (direct and block calls), `alloc`, `gvn`; `eager` and `deopt` are off.

Not done: loop-invariant code motion, range analysis and bounds-check elimination, escape analysis beyond closures, unboxed Floats across safepoints, inlining of closures the code did not make (a loop unit entered with a closure in a temp calls it).

## Machine code

Package `VM-Jit` (layer 0), shared by all variants:

- **`Arm64Assembler`** (Lowtalk module, translated with the JIT). `asm beginAt: start limit: end`, one message per instruction with operands in assembly order, `asm finish` (an `ASM_*` error code; the first error sticks). Registers, conditions, shifts, extends and barriers are class variables of `Arm64Module` (subclass it to use them): `X0`–`X30`, `XZR`, `SP`, `W0`–`W30`, `WZR`, `WSP`, `D0`–`D31`, `COND_EQ`…, `SHIFT_LSL`…, `EXT_SXTW`…, `BARRIER_ISH`…; the width (W/X) comes from the destination register, FP forms from D registers (`ldr: D0 base: X1 offset: 8`). Selectors: `add:with:imm:` (also `adds sub subs`, `cmp:imm:`, `cmn:imm:`; lsl #12 and negative immediates chosen automatically), `add:with:with:` `…shift:amount:` `…extend:amount:`, `neg:with:`; `and orr eor ands bic` `:with:imm:` (bitmask immediates) and `:with:with:[shift:amount:]` (also `orn eon bics tst mvn`); `mov:with:`, `mov:imm:` (shortest movz/movn/movk or orr), `mov:imm64:` (fixed four instructions, patchable), `movz/movk/movn:imm:shift:`; `lsl lsr asr ror` `:with:imm:` and `:with:with:`; `mul madd:…add: msub:…sub: smulh umulh sdiv udiv clz`; `csel csinc csinv csneg` `:with:with:cond:`, `cset:cond: csetm:cond: cinc cinv cneg:with:cond:`; `ubfx sbfx ubfiz sbfiz bfi bfxil` `:with:lsb:width:`, `ubfm sbfm bfm`, `sxtb sxth sxtw uxtb uxth`; `ldr str ldrb strb ldrh strh ldrsb ldrsh ldrsw` `:base:offset:` (scaled, else unscaled) `:base:preIndex:` `:base:postIndex:` `:base:index:[extend:shift:]`, `ldur stur …`, `ldp stp` `:with:base:offset:/preIndex:/postIndex:`, `ldr:label:`; `adr:label: adrp:label:`; `b: bl: b:if: cbz:to: cbnz:to: tbz:bit:to: tbnz:bit:to: br: blr: ret ret:`; `nop brk: dmb: dsb: isb`; `fmov:with: fmov:imm: fadd fsub fmul fdiv` `:with:with:`, `fsqrt fneg fabs frintm frintp frintz frintn scvtf ucvtf fcvtzs` `:with:`, `fcmp:with: fcmpZero: fcsel:with:with:cond:`. Labels: `newLabel`, `bind:`, `labelAt: anAddress`; forward branches are patched at `bind:`. Encoders: `logicalImmediate:width:`, `fmovImmediate:` (-1 if not encodable). Patching: `patchBranchAt:to:`, `branchTargetAt:`, `patchMov64At:value:`, `mov64At:`. Notes for annotated disassembly, recorded only after `recordNotes: true`: `comment:`, `comment:with:`, `bytecode:`. With constant operands an instruction is one store of a constant word and a limit check; emission runs at about 3·10^8 instructions/s (`Tests-VM/JitSample` with the argument `bench`, cc -O2, M2 Max).
- **`CodeCache`** (Lowtalk module): `openWithSize:` (one `MAP_JIT` mapping), `allocate:`, `keep` (what is allocated survives flushes), `flush`, `beginWriting`, `endWritingFrom:size:` (`pthread_jit_write_protect_np`, `sys_icache_invalidate`, bound in the library `DarwinJit`), `endWriting`, `invalidate:size:`. Code is called by casting its address: `(self cCoerce: entry to: 'int64_t (*)(int64_t)') call: 42`.
- **`Arm64Disassembler`** (image): `textFor:at:` prints as LLVM's objdump does; `listingOfWords:at:annotations:` prints a listing with `Arm64CodeAnnotations` (bytecode headers, comments, labels for branch targets, symbol names for calls).
- **`JitRuntime`**, **`BytecodeAnalysis`**, **`JitStencils`** (VMCoreModules), **`JitCompiler`**, **`JitStubs`**, **`JitTemplateCompiler`**, **`JitStencilCompiler`** (Arm64Modules), **`JitStencilTable`** (the generated table), **`JitPrimitives`** (`jitParameters`: `Smalltalk vm jitParameters`, `jitMode:`; `jitCode`): the shared runtime and the template compiler, part of the VM.
- **`Arm64Emulator`** (image, for the simulator): runs the code in a `SimulatedMemory` (x0–x30, sp, NZCV, d0–d31). Simulated, a call through a function pointer to machine code runs in it (`SimulatedMemory>>machineCodeRunner`, installed by `DarwinJit`); `blr` to a Lowtalk function pointer calls the Smalltalk method with the arguments of its prototype, so JIT code runs in the simulator.

Tests (`Tests-VM`): encodings against the system assembler's (`Arm64Reference`, generated by `tools/arm64-reference.py`), simulated and compiled with cc; disassembly against objdump; emulator semantics checked against the CPU; `JitTest` runs `JitSample` natively and in the emulator, and the mini kernel under the template and the baseline JIT in the simulated VM; `JitRuntimeTest` covers on-stack replacement, redefinition and become while machine code runs, embedded literals, process switches, deep recursion, code cache flushes and the listing, `JitStencilRuntimeTest` and `JitThreadedRuntimeTest` the same for the other modes, `JitBaselineTest` the baseline's inline caches through their states, relinking, unboxed Floats and loop temps when Smalltalk runs in a slow path, non-local returns, allocation and every ablation flag; `StencilTableTest` reads an object file cc compiled. `vm/tests/run.sh` runs the mini kernel's tests also under `--jit template`, `threaded`, `stencil` and `baseline` with `--jit-threshold 0` (with the GC stress) and the default thresholds; `make test-jit` the image's tests under each with `--jit-threshold 0`, Tests-Kernel also with a 1 MB cache that keeps notes for `template`, `baseline` and `stencil` (it is flushed again and again).

## Benchmarks

- **Are We Fast Yet** (Marr et al., DLS 2016): Bounce, CD, DeltaBlue, Havlak, Json, List, Mandelbrot, NBody, Permute, Queens, Richards, Sieve, Storage, Towers. The same sources also run on Pharo 12 (Cog), the reference ceiling.
- The micro suite (`vm/tests/bench`), and real workloads: recompiling the image's sources, text rendering.
- Per benchmark: every iteration's time (warm-up curve), steady state (median of the last half), JIT time and code size.

## Results

Template JIT against the interpreter, M2 Max shared with other jobs: the base commit's VM, this VM with `--jit none` and with `--jit template` (default thresholds 2 and 50), interleaved, 10 iterations, best of 3 invocations of the steady state (median of the last half) and of the first iteration, ms (`vm/tests/bench/results/samaltak-{base,jit-none,jit-template}-2026-10-24-*.csv`, `samaltak-micro-*`). Pharo 12 (Cog) from docs/benchmarks.md for scale.

| benchmark | base | `none` | `template` | first | template / none | Cog |
|---|---|---|---|---|---|---|
| Bounce | 101.7 | 104.3 | 76.2 | 76.8 | 0.73 | 33 |
| CD | 364.4 | 363.1 | 325.6 | 329.1 | 0.90 | 214 |
| DeltaBlue | 106.5 | 107.3 | 100.2 | 102.8 | 0.93 | 45 |
| Havlak | 695.1 | 710.3 | 625.9 | 632.1 | 0.88 | 367 |
| Json | 90.9 | 91.1 | 82.2 | 83.5 | 0.90 | 56 |
| List | 125.4 | 124.9 | 101.3 | 101.7 | 0.81 | 24 |
| Mandelbrot | 516.0 | 501.8 | 522.3 | 553.5 | 1.04 | 377 |
| NBody | 745.4 | 746.3 | 676.6 | 665.0 | 0.91 | 374 |
| Permute | 107.8 | 111.6 | 62.9 | 63.7 | 0.56 | 34 |
| Queens | 104.4 | 107.6 | 57.0 | 57.0 | 0.53 | 44 |
| Richards | 98.3 | 101.4 | 74.7 | 78.3 | 0.74 | 23 |
| Sieve | 95.8 | 96.2 | 37.8 | 38.8 | 0.39 | 60 |
| Storage | 107.9 | 112.5 | 104.6 | 106.0 | 0.93 | 62 |
| Towers | 92.9 | 95.4 | 58.1 | 59.3 | 0.61 | 17 |

Micro suite (same runs): Fib 24.5 → 20.1, Loop 110.7 → 66.3, Floats 29.4 → 30.6, Sends 100.7 → 78.9, Blocks 118.3 → 105.5, Dict 98.5 → 79.8, Strings 149.4 → 141.5, Alloc 67.9 → 74.2, Factorial 24.9 → 15.7 (`none` → `template`).

- The template removes dispatch: loops, inline arithmetic and comparisons, Array access gain most (Sieve 2.5×, Queens, Permute, Towers). Sends still go through C (`send:info:site:`) and every value lives in memory; Float operations take an out-of-line path that decodes and encodes SmallFloat64s (Mandelbrot, MicroFloats), allocation goes through C (MicroAlloc). First iterations are within a few percent of steady state: compiling costs 5 µs per method, 0.19 µs per bytecode, 37 bytes of code per bytecode (2190 methods, 63084 bytecodes over the AWFY runs).
- `--jit none` against the base VM: 0–4 % on AWFY, MicroBlocks 4–7 %; removing the block path's JIT checks made MicroBlocks slower still, so the difference is code layout under the retrained profile rather than the checks.
- Process switches (the sampler) flush all frames ~1500 times per second; before Contexts could continue in machine code, returns into flushed loops left machine code 5.7 million times per Havlak iteration.

Threaded and stencil (`vm/tests/bench/results/samaltak-cp-{none,template,threaded,stencil}-2026-10-24-*.csv`): the four modes, default thresholds, interleaved, 10 iterations, best of 3 invocations of the steady state and of the first iteration, ms.

| benchmark | `none` | `template` | `threaded` | `stencil` | first threaded | first stencil | threaded / none | stencil / template |
|---|---|---|---|---|---|---|---|---|
| Bounce | 108.8 | 77.5 | 130.6 | 87.1 | 131.1 | 85.6 | 1.20 | 1.12 |
| CD | 380.6 | 333.2 | 501.2 | 406.6 | 494.4 | 410.9 | 1.32 | 1.22 |
| DeltaBlue | 114.5 | 103.3 | 148.3 | 116.0 | 150.6 | 118.6 | 1.30 | 1.12 |
| Havlak | 743.3 | 637.1 | 888.5 | 728.6 | 898.9 | 730.8 | 1.20 | 1.14 |
| Json | 95.5 | 84.5 | 113.0 | 92.3 | 115.0 | 94.4 | 1.18 | 1.09 |
| List | 131.4 | 103.6 | 177.5 | 117.9 | 173.6 | 116.6 | 1.35 | 1.14 |
| Mandelbrot | 542.0 | 583.1 | 507.3 | 537.6 | 513.4 | 540.4 | 0.94 | 0.92 |
| NBody | 784.9 | 700.0 | 954.1 | 773.5 | 954.1 | 780.1 | 1.22 | 1.10 |
| Permute | 116.3 | 64.9 | 141.6 | 76.1 | 138.2 | 76.9 | 1.22 | 1.17 |
| Queens | 113.0 | 58.2 | 135.9 | 80.5 | 135.2 | 79.6 | 1.20 | 1.38 |
| Richards | 105.6 | 76.6 | 124.4 | 94.8 | 125.8 | 96.9 | 1.18 | 1.24 |
| Sieve | 97.9 | 39.0 | 111.1 | 46.3 | 110.9 | 47.8 | 1.13 | 1.19 |
| Storage | 114.5 | 109.5 | 171.4 | 124.3 | 176.7 | 125.6 | 1.50 | 1.14 |
| Towers | 96.2 | 60.7 | 107.0 | 69.7 | 102.8 | 70.8 | 1.11 | 1.15 |
| MicroFib | 25.2 | 20.8 | 34.5 | 23.5 | 35.1 | 23.3 | 1.37 | 1.13 |
| MicroLoop | 112.8 | 68.3 | 114.1 | 70.7 | 114.3 | 70.9 | 1.01 | 1.04 |
| MicroFloats | 29.9 | 31.9 | 39.9 | 30.0 | 38.9 | 30.4 | 1.33 | 0.94 |
| MicroSends | 101.9 | 81.3 | 146.9 | 91.9 | 142.2 | 91.7 | 1.44 | 1.13 |
| MicroBlocks | 118.7 | 110.3 | 171.9 | 120.1 | 174.7 | 118.9 | 1.45 | 1.09 |
| MicroDict | 103.6 | 83.4 | 131.1 | 91.0 | 134.4 | 96.4 | 1.27 | 1.09 |
| MicroStrings | 151.9 | 148.2 | 193.2 | 168.5 | 190.0 | 168.9 | 1.27 | 1.14 |
| MicroAlloc | 68.5 | 76.6 | 105.5 | 83.2 | 108.9 | 84.2 | 1.54 | 1.09 |
| MicroFactorial | 25.5 | 16.3 | 31.7 | 20.0 | 32.5 | 21.0 | 1.24 | 1.23 |
| Recompile | 105.0 | 65.6 | 93.1 | 73.0 | 94.9 | 75.2 | 0.89 | 1.11 |
| TextRendering | 110.5 | 99.3 | 131.7 | 108.9 | 132.8 | 111.6 | 1.19 | 1.10 |

- Compiling (AWFY, 2205 methods, 63159 bytecodes): `template` 4.8 µs per method, 0.17 µs per bytecode, 37 bytes per bytecode; `threaded` 3.5 µs, 0.12 µs, 15 bytes; `stencil` 4.2 µs, 0.15 µs, 69 bytes. First iterations are within a few percent of steady state for all three.
- `stencil` is 0.92–1.38× `template` (geometric mean 1.15 on AWFY), 0.86× `none`. The stencils keep the operand stack's top in a register (`add x23` per push and pop) where the template knows every slot's offset; sends and returns are larger (124 bytes for a send: the state saved around calls, GOT values materialized; a hole relaxed to one instruction leaves a `nop`); clang lays slow paths out after the fast path, so a stencil that falls through to the next one through a cold block still takes a branch. On Float code (Mandelbrot, MicroFloats) it is as fast as the interpreter, the template slower.
- `threaded` is 0.89–1.54× `none` (geometric mean 1.21): a `bl`, a `ret` and a test of the answered continuation per bytecode cost more than the interpreter's dispatch (computed goto, PGO); it gains only on Recompile and Mandelbrot.


Baseline against Pharo 12 (`vm/tests/bench/results/samaltak-jit-{none,template,baseline}-2026-10-25-*.csv`, `pharo12-cog-2026-10-25-*.csv`): the three modes and Pharo 12 (Cog, the same sources) interleaved, default thresholds, 10 iterations, best of 3 invocations of the steady state and of the first iteration, ms.

| benchmark | `none` | `template` | `baseline` | first | Pharo 12 | first | baseline / Pharo |
|---|---|---|---|---|---|---|---|
| Bounce | 104.8 | 77.1 | 22.6 | 22.8 | 32.5 | 32.6 | 0.69 |
| CD | 369.1 | 345.8 | 87.9 | 91.6 | 205.2 | 203.7 | 0.43 |
| DeltaBlue | 108.2 | 105.1 | 27.7 | 29.4 | 42.3 | 83.4 | 0.65 |
| Havlak | 720.0 | 635.3 | 200.2 | 204.0 | 348.6 | 402.3 | 0.57 |
| Json | 91.3 | 88.0 | 32.1 | 33.4 | 55.3 | 59.0 | 0.58 |
| List | 127.2 | 102.2 | 17.5 | 17.4 | 23.6 | 23.7 | 0.74 |
| Mandelbrot | 525.6 | 569.4 | 202.8 | 205.6 | 372.7 | 370.5 | 0.54 |
| NBody | 772.2 | 716.5 | 344.6 | 344.8 | 379.6 | 364.2 | 0.91 |
| Permute | 113.4 | 66.9 | 21.6 | 21.5 | 33.5 | 33.6 | 0.64 |
| Queens | 109.7 | 68.6 | 21.4 | 21.7 | 43.2 | 43.4 | 0.50 |
| Richards | 101.2 | 81.7 | 17.4 | 18.3 | 22.4 | 23.2 | 0.77 |
| Sieve | 93.7 | 38.0 | 32.5 | 34.1 | 58.2 | 59.8 | 0.56 |
| Storage | 111.4 | 113.8 | 35.6 | 37.6 | 55.3 | 57.5 | 0.64 |
| Towers | 94.8 | 62.3 | 13.8 | 14.0 | 16.5 | 16.8 | 0.83 |
| MicroFib | 24.3 | 21.9 | 5.0 | 5.1 | 10.0 | 10.2 | 0.50 |
| MicroLoop | 110.2 | 67.3 | 31.8 | 31.9 | 63.6 | 63.3 | 0.50 |
| MicroFloats | 28.8 | 31.4 | 20.4 | 20.5 | 38.9 | 39.1 | 0.52 |
| MicroSends | 102.3 | 82.6 | 22.0 | 22.1 | 22.3 | 22.5 | 0.99 |
| MicroBlocks | 117.7 | 119.0 | 29.1 | 29.0 | 30.1 | 30.5 | 0.97 |
| MicroDict | 101.5 | 89.3 | 31.3 | 36.3 | 126.0 | 219.2 | 0.25 |
| MicroStrings | 145.7 | 149.7 | 34.1 | 35.8 | 61.3 | 72.9 | 0.56 |
| MicroAlloc | 66.5 | 82.7 | 19.8 | 21.7 | 33.1 | 39.7 | 0.60 |
| MicroFactorial | 24.9 | 15.9 | 6.5 | 7.4 | 7.9 | 9.2 | 0.82 |
| Recompile | 102.0 | 69.1 | 18.6 | 20.6 | - | - | - |
| TextRendering | 104.6 | 99.7 | 58.1 | 60.3 | - | - | - |

- `baseline` beats Pharo 12 on every AWFY benchmark, in the steady state and in the first iteration: geometric mean 0.64 of Pharo's time (first iterations 0.61), 0.31× `template`, 0.25× `none`. Closest: NBody 0.91, Towers 0.83; of the micro benchmarks MicroSends 0.99 and MicroBlocks 0.97.
- Compiling (AWFY, 2988 methods, 69210 bytecodes): 4.7 µs per method, 0.20 µs per bytecode, 43 bytes of code and literal pool per bytecode (`template` 4.6 µs, 0.16 µs, 37 bytes). It compiles quick methods and primitives too. First iterations are within 8 % of the steady state, MicroDict's within 16 %.
- Ablations (`samaltak-jit-baseline-no-FLAG-2026-10-25-*.csv`, one flag off, otherwise the same; geometric mean of the steady state relative to all on):

| flag off | AWFY | micro | most affected |
|---|---|---|---|
| `ic` | 5.56 | 3.59 | Richards 13.95, List 12.45 (min Sieve 1.00) |
| `pic` | 1.06 | 1.05 | CD 1.14, MicroAlloc 1.14 (min Permute 1.00) |
| `mega` | 1.25 | 1.01 | CD 3.09, Havlak 2.77 (min MicroBlocks 0.98) |
| `regs` | 1.34 | 1.23 | Mandelbrot 2.20, MicroSends 1.71 (min MicroAlloc 1.03) |
| `arith` | 1.44 | 2.82 | MicroFloats 22.15, MicroLoop 4.37 (min List 0.99) |
| `fuse` | 1.05 | 1.03 | Bounce 1.29, CD 1.17 (min Queens 0.96) |
| `float` | 1.08 | 1.35 | MicroFloats 17.34, Mandelbrot 2.29 (min DeltaBlue 0.95) |
| `access` | 1.07 | 1.07 | MicroStrings 1.43, Sieve 1.29 (min CD 0.98) |
| `prims` | 1.22 | 1.41 | MicroStrings 2.94, MicroAlloc 2.79 (min MicroBlocks 0.99) |
| `alloc` | 1.02 | 1.02 | Json 1.15, Havlak 1.13 (min Queens 0.98) |
| `blocks` | 1.13 | 1.16 | MicroBlocks 3.65, Bounce 1.98 (min MicroStrings 0.97) |
| `nlr` | 0.99 | 1.05 | MicroLoop 1.13, MicroStrings 1.11 (min NBody 0.97) |
| `quick` | 1.07 | 1.01 | CD 1.26, Richards 1.22 (min MicroFactorial 0.97) |
| `temps` | 0.99 | 1.10 | MicroLoop 2.15, Sieve 1.09 (min DeltaBlue 0.95) |
| `barrier` | 1.26 | 1.07 | Towers 1.80, Permute 1.74 (min List 0.99) |

- Inline caches matter most (every send through the runtime: 5.6×), then inline arithmetic, register mapping, the store barrier's fast path (Towers and Permute store into Arrays), the megamorphic cache (CD, Havlak), machine-code primitives and blocks. Polymorphic caches, fusion, inline allocation, loop temps in registers and the non-local return fast path gain little on AWFY (loop temps: 2× on MicroLoop); most of what they do the other paths also cover. Values under 1.00 are within the noise (±5 %).
- Where the remaining time goes (native pc samples mapped onto the listings, `--jit-flags notes`): NBody spends 72 % in `advance:` and 20 % in Body's accessors; most of `advance:` is out-of-line Float code: an operation on two send results tries SmallIntegers first, then decodes both operands and boxes the result for the join (an operand known to be a Float keeps the result unboxed, but every accessor send boxes and decodes again). Towers is send-bound: its four small methods take 70 %, the accessors most of the rest; MicroSends and MicroBlocks are a frame, a check and a return per send or block; List is pointer chasing. For the next tiers: inlining guided by the inline caches (accessors, small methods, blocks), Floats unboxed across what was inlined, frames only for real calls. Smaller: a C primitive is a runtime call (frames made canonical unless it is a leaf; the frequent ones run in machine code), LargeInteger arithmetic is Smalltalk over 32-bit limbs (MicroFactorial), the always-on profiler's samples flush the frames about 1000 times a second (about 1 %).

Optimizing tier against the other modes and Pharo 12 (`vm/tests/bench/results/samaltak-{none,template,baseline,opt}-2026-10-25d-*.csv`, `pharo12-cog-2026-10-25d-*.csv`): the four modes and Pharo 12 interleaved, default thresholds (`--jit-opt 1000`), 30 iterations, best of 3 invocations of the steady state (median of the last half) and of the first iteration, ms.

| benchmark | `none` | `template` | `baseline` | `opt` | first `opt` | Pharo 12 | first Pharo | opt / Pharo | opt / baseline |
|---|---|---|---|---|---|---|---|---|---|
| Bounce | 101.7 | 85.6 | 22.4 | 11.6 | 12.9 | 31.9 | 32.0 | 0.36 | 0.52 |
| CD | 352.9 | 400.6 | 87.9 | 66.6 | 67.1 | 196.9 | 200.9 | 0.34 | 0.76 |
| DeltaBlue | 105.0 | 125.2 | 26.7 | 14.8 | 66.1 | 39.7 | 78.2 | 0.37 | 0.55 |
| Havlak | 708.1 | 765.3 | 196.5 | 95.6 | 121.8 | 334.5 | 388.9 | 0.29 | 0.49 |
| Json | 92.4 | 106.1 | 31.2 | 17.7 | 44.7 | 54.1 | 56.6 | 0.33 | 0.57 |
| List | 128.6 | 115.6 | 17.2 | 12.6 | 13.2 | 23.2 | 23.5 | 0.54 | 0.73 |
| Mandelbrot | 513.0 | 545.7 | 195.9 | 120.2 | 124.4 | 359.9 | 353.8 | 0.33 | 0.61 |
| NBody | 756.2 | 724.2 | 337.3 | 143.9 | 148.1 | 328.0 | 349.6 | 0.44 | 0.43 |
| Permute | 109.4 | 77.5 | 21.3 | 17.0 | 17.2 | 32.5 | 32.0 | 0.52 | 0.80 |
| Queens | 106.7 | 78.4 | 20.8 | 12.8 | 13.7 | 42.5 | 41.2 | 0.30 | 0.61 |
| Richards | 102.8 | 89.6 | 17.4 | 14.2 | 16.3 | 21.9 | 22.9 | 0.65 | 0.81 |
| Sieve | 95.1 | 38.0 | 32.3 | 22.2 | 28.4 | 51.8 | 57.1 | 0.43 | 0.69 |
| Storage | 111.4 | 134.0 | 35.6 | 23.0 | 28.2 | 52.8 | 52.4 | 0.44 | 0.65 |
| Towers | 92.4 | 73.1 | 13.5 | 9.1 | 9.7 | 16.4 | 16.3 | 0.55 | 0.67 |

Micro suite (`samaltak-{baseline,opt}-micro-2026-10-25d.csv`, `pharo12-cog-micro-2026-10-25d.csv`, one invocation each, 20 iterations):

| benchmark | `baseline` | `opt` | first `opt` | Pharo 12 | opt / Pharo | opt / baseline |
|---|---|---|---|---|---|---|
| MicroFib | 5.1 | 6.4 | 6.4 | 10.2 | 0.63 | 1.24 |
| MicroLoop | 32.4 | 29.7 | 30.9 | 64.2 | 0.46 | 0.92 |
| MicroFloats | 20.6 | 20.0 | 22.0 | 38.6 | 0.52 | 0.97 |
| MicroSends | 22.4 | 12.1 | 13.6 | 22.5 | 0.54 | 0.54 |
| MicroBlocks | 29.5 | 45.3 | 47.9 | 30.7 | 1.47 | 1.53 |
| MicroDict | 31.0 | 17.4 | 16.6 | 138.2 | 0.13 | 0.56 |
| MicroStrings | 34.6 | 31.4 | 37.6 | 82.8 | 0.38 | 0.91 |
| MicroAlloc | 20.8 | 12.8 | 15.9 | 34.8 | 0.37 | 0.62 |
| MicroFactorial | 6.7 | 8.0 | 27.9 | 8.4 | 0.95 | 1.20 |

- `opt` beats Pharo 12 on every AWFY benchmark: geometric mean 0.41 of Pharo's time (first iterations 0.49), 0.62× `baseline` (first iterations 0.79), 0.17× `template`, 0.15× `none`. Closest to Pharo: Richards 0.65, Towers 0.55, List 0.54; closest to `baseline`: Richards 0.81, Permute 0.80. First iterations beat Pharo's too, DeltaBlue closest (0.85): its 120 units take 55 ms to compile.
- Gains over `baseline`: NBody 0.43 (Body's accessors inlined, the arithmetic on doubles), Havlak 0.49, Bounce 0.52, DeltaBlue 0.55, MicroSends 0.54 (the callee inlined: no frame, class check or return). MicroBlocks and MicroFib are slower than `baseline`: a loop unit entered with a closure already made calls it (a block call pushes a whole frame), and recursion beyond the one inlined level is a direct call with a heavier frame than baseline code's; MicroFactorial is LargeInteger arithmetic through the runtime.
- Compiling (3 runs of the AWFY suite, 566 units, 48540 bytecodes each, inlined ones included): 307 µs per unit, 3.6 µs per bytecode, 75 bytes of code per bytecode; liveness and intervals over the inlined IR dominate. With template code as the lower tier (`samaltak-{opt,baseline}-2026-10-25c-*.csv`, `pharo12-cog-2026-10-25c-*.csv`) the steady state was 0.44× Pharo; baseline code as the lower tier gained most where the code optimized code does not cover runs (Havlak 0.82 → 0.49 of `baseline`) and in first iterations.
- Ablations (`samaltak-opt-no-FLAG-2026-10-25d.csv`, one invocation, 10 iterations, one flag off; geometric mean of the steady state relative to all on):

| flag off | AWFY | most affected |
|---|---|---|
| `inline` | 6.48 | Queens 10.96, Towers 10.85 (min Mandelbrot 1.04) |
| `blocks` | 1.27 | NBody 2.26, Bounce 2.06 (min List 1.00) |
| `prims` | 2.52 | Sieve 11.44, Queens 6.18 (min Mandelbrot 1.02) |
| `unbox` | 1.41 | Mandelbrot 5.35, NBody 4.77 (min Bounce 0.97) |
| `calls` | 1.37 | DeltaBlue 2.59, Permute 2.04 (min Mandelbrot 1.01) |
| `alloc` | 1.23 | Storage 2.23, Havlak 1.92 (min Mandelbrot 1.01) |
| `gvn` | 1.08 | Sieve 1.20, Permute 1.16 (min Storage 0.99) |

- Without inlining every send goes through the runtime or a direct call (6.5×; Queens and Towers are small methods); without primitives `at:`, `at:put:` and arithmetic are sends (Sieve 11×); Floats on doubles matter for Mandelbrot and NBody, direct and block calls for DeltaBlue and Permute, eden allocation for Storage and Havlak. Value numbering gains up to 20 %.
