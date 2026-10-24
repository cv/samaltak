# JIT

Status: plan. Every JIT variant is written in Smalltalk: Lowtalk for code in the VM (translated to C like the rest of it), ordinary Smalltalk for code in the image. No LLVM at run time. Target: Apple Silicon (M2 Max, arm64, macOS).

The goal is a comparison of JIT designs and optimizations on the same VM, the same image and the same benchmarks: speed of the generated code (warm-up and steady state) and speed of the JIT itself.

## Variants

| name | `--jit` | what |
|---|---|---|
| I | `none` | the interpreter (computed goto, PGO) |
| M | (all) | married Contexts: closure creation no longer flushes frames (interpreter change, benefits every variant) |
| T | `threaded` | call threading: one `bl` per bytecode into the handler; removes dispatch only |
| S | `stencil` | copy-and-patch: handler stencils compiled by the C compiler at build time, read by Smalltalk from the object file, copied and patched at run time |
| B | `baseline` | Cog-style: own arm64 assembler, simulated operand stack in registers, machine-code inline caches (monomorphic, polymorphic, megamorphic), inline SmallInteger/Float arithmetic and common primitives |
| Y | `sista` | B plus a speculative optimizer in the image (Smalltalk, as Sista/Scorch): type feedback from B's inline caches, inlining with guards, unsafe bytecodes, deoptimization in Smalltalk |
| O | `opt` | B plus an optimizing tier in the VM (Lowtalk): SSA IR, inlining from type feedback, escape analysis, unboxed floats, bounds-check elimination, linear-scan register allocation, deoptimization to frames |

Each variant has ablation flags (`--jit-flags -ic,-arith,...`) so that the effect of each optimization is measured separately.

## Shared runtime

The interpreter's frames are the canonical state. Machine code runs on the same frame records and C-stack slots; at every safepoint (a call out of machine code that may allocate, collect, flush frames, switch processes or run Smalltalk) the values it holds in registers are in their slots and the frame's `ip`/`sp` are valid. Hence:

- the interpreter can resume any frame of compiled code at its bytecode pc, and compiled code can be entered at the pc of a frame the interpreter was running (on-stack replacement at backward jumps, return into a compiled caller);
- GC roots, `materialize_all` (frames into Contexts), the debugger, stack printing and process switches stay as they are;
- deoptimizing baseline code is free; flushing the code cache only needs no machine code on the native stack.

**Native stack.** Machine code calls compiled callees with `bl` and returns with `ret`, so the native stack mirrors the frames entered since the last `jit_enter`, 16 bytes (x29, x30) per activation. Leaving to the interpreter (a callee without code, a fallback, flushed frames) resets the native stack to `jit_enter`'s and returns to the interpreter, which reloads the top frame. Returning from the first activation entered by `jit_enter` lands in the trampoline, which returns to the interpreter.

**Registers** (callee-saved, pinned): x19 the frame record, x20 its slots (`fp`, receiver at `fp[-1]`), x21 the receiver, x22 the JIT state (nil/true/false, young-space bounds, eden top/limit, interrupt flag, runtime entry points). x23–x28 are free for register allocation; x0–x17 scratch.

**Code.** One `MAP_JIT` region (`pthread_jit_write_protect_np`, `sys_icache_invalidate`), bump allocated, flushed completely when full. A compiled method starts with a header: the method (a GC root), entry points, the bytecode-pc to machine-pc map for resumption points, the sites of embedded object references (updated by GC and become). Only old objects are embedded; literals are loaded through the frame's `lits`. Methods are found by identity hash (stable across moves). Method-dictionary changes, snapshots and become reset inline caches or the cache.

**Triggering.** Counters on activation and on backward jumps; thresholds are flags (`--jit-threshold`), so warm-up can be compared.

**Statistics** (vmStats): methods and bytecodes compiled, microseconds compiling, code bytes, cache flushes, per tier.

## Machine code

Package `VM-Jit` (layer 0), shared by all variants:

- **`Arm64Assembler`** (Lowtalk module, translated with the JIT). `asm beginAt: start limit: end`, one message per instruction with operands in assembly order, `asm finish` (an `ASM_*` error code; the first error sticks). Registers, conditions, shifts, extends and barriers are class variables of `Arm64Module` (subclass it to use them): `X0`–`X30`, `XZR`, `SP`, `W0`–`W30`, `WZR`, `WSP`, `D0`–`D31`, `COND_EQ`…, `SHIFT_LSL`…, `EXT_SXTW`…, `BARRIER_ISH`…; the width (W/X) comes from the destination register, FP forms from D registers (`ldr: D0 base: X1 offset: 8`). Selectors: `add:with:imm:` (also `adds sub subs`, `cmp:imm:`, `cmn:imm:`; lsl #12 and negative immediates chosen automatically), `add:with:with:` `…shift:amount:` `…extend:amount:`, `neg:with:`; `and orr eor ands bic` `:with:imm:` (bitmask immediates) and `:with:with:[shift:amount:]` (also `orn eon bics tst mvn`); `mov:with:`, `mov:imm:` (shortest movz/movn/movk or orr), `mov:imm64:` (fixed four instructions, patchable), `movz/movk/movn:imm:shift:`; `lsl lsr asr ror` `:with:imm:` and `:with:with:`; `mul madd:…add: msub:…sub: smulh umulh sdiv udiv clz`; `csel csinc csinv csneg` `:with:with:cond:`, `cset:cond: csetm:cond: cinc cinv cneg:with:cond:`; `ubfx sbfx ubfiz sbfiz bfi bfxil` `:with:lsb:width:`, `ubfm sbfm bfm`, `sxtb sxth sxtw uxtb uxth`; `ldr str ldrb strb ldrh strh ldrsb ldrsh ldrsw` `:base:offset:` (scaled, else unscaled) `:base:preIndex:` `:base:postIndex:` `:base:index:[extend:shift:]`, `ldur stur …`, `ldp stp` `:with:base:offset:/preIndex:/postIndex:`, `ldr:label:`; `adr:label: adrp:label:`; `b: bl: b:if: cbz:to: cbnz:to: tbz:bit:to: tbnz:bit:to: br: blr: ret ret:`; `nop brk: dmb: dsb: isb`; `fmov:with: fmov:imm: fadd fsub fmul fdiv` `:with:with:`, `fsqrt fneg fabs frintm frintp frintz frintn scvtf ucvtf fcvtzs` `:with:`, `fcmp:with: fcmpZero: fcsel:with:with:cond:`. Labels: `newLabel`, `bind:`, `labelAt: anAddress`; forward branches are patched at `bind:`. Encoders: `logicalImmediate:width:`, `fmovImmediate:` (-1 if not encodable). Patching: `patchBranchAt:to:`, `branchTargetAt:`, `patchMov64At:value:`, `mov64At:`. Notes for annotated disassembly, recorded only after `recordNotes: true`: `comment:`, `comment:with:`, `bytecode:`. With constant operands an instruction is one store of a constant word and a limit check; emission runs at about 3·10^8 instructions/s (`Tests-VM/JitSample` with the argument `bench`, cc -O2, M2 Max).
- **`CodeCache`** (Lowtalk module): `openWithSize:` (one `MAP_JIT` mapping), `allocate:`, `flush`, `beginWriting`, `endWritingFrom:size:` (`pthread_jit_write_protect_np`, `sys_icache_invalidate`, bound in the library `DarwinJit`). Code is called by casting its address: `(self cCoerce: entry to: 'int64_t (*)(int64_t)') call: 42`.
- **`Arm64Disassembler`** (image): `textFor:at:` prints as LLVM's objdump does; `listingOfWords:at:annotations:` prints a listing with `Arm64CodeAnnotations` (bytecode headers, comments, labels for branch targets, symbol names for calls).
- **`Arm64Emulator`** (image, for the simulator): runs the code in a `SimulatedMemory` (x0–x30, sp, NZCV, d0–d31). Simulated, a call through a function pointer to machine code runs in it (`SimulatedMemory>>machineCodeRunner`, installed by `DarwinJit`); `blr` to a Lowtalk function pointer calls the Smalltalk method with the arguments of its prototype, so JIT code runs in the simulator.

Tests (`Tests-VM`): encodings against the system assembler's (`Arm64Reference`, generated by `tools/arm64-reference.py`), simulated and compiled with cc; disassembly against objdump; emulator semantics checked against the CPU; `JitTest` runs `JitSample` natively and in the emulator.

## Benchmarks

- **Are We Fast Yet** (Marr et al., DLS 2016): Bounce, CD, DeltaBlue, Havlak, Json, List, Mandelbrot, NBody, Permute, Queens, Richards, Sieve, Storage, Towers. The same sources also run on Pharo 12 (Cog), the reference ceiling.
- The micro suite (`vm/tests/bench`), and real workloads: recompiling the image's sources, text rendering.
- Per benchmark: every iteration's time (warm-up curve), steady state (median of the last half), JIT time and code size.
