# Samaltak design notes

Working decisions. Open questions marked **?**.

## Core

- Freestanding C11 VM: object memory, bytecode interpreter, GC, ~100 primitives, image loader. Target ≈5k lines.
- C is the bootstrap language because it is the simplest target for a Smalltalk-written translator (Slang-style) to emit later; Stage 1 replaces hand-written C with generated C, Stage 2 with Smalltalk-emitted native code.
- Platform layer (window surface, input, GPU via `webgpu.h` / wgpu-native) is a separate C module behind a small primitive interface, not part of the core.

## Language

- Smalltalk-80 semantics and syntax.
- Source of truth: text files in git; image built from source by a bootstrapper.
- Immutable literals; per-object immutability bit.
- **?** Modules/namespaces vs. single global namespace.

## Concurrency

- Green threads: Smalltalk `Process`es on one OS thread, priority-preemptive at safepoints (sends, backward jumps). Squeak semantics.
- Every window runs in its own Process, so one busy window does not block others.
- The compositor is a high-priority Process woken by the vsync Semaphore.
- GC runs on its own OS thread(s), concurrently with the single mutator thread.

## GC: keep the door open for pauseless (C4-style)

Start with a simple collector, but the design must not preclude a concurrent, compacting, never-stop-the-world GC. Rules from day one:

1. **Single choke point for heap reference loads.** Every load of an object pointer from the heap goes through one VM macro/function (`load_ref`). Initially a no-op; later it becomes C4's loaded-value barrier (check, then self-heal on stale/unmarked refs). The future JIT emits the same barrier.
2. **Single choke point for stores** (`store_ref`), for generational/remembered-set and SATB needs.
3. **Spare pointer bits.** Tagged 64-bit words reserve metadata bits (e.g. NMT/color) that the barrier can test; immediates use the low tag bits.
4. **Identity hash in the header**, never derived from the address.
5. **No raw heap pointers held across safepoints** in C code. Primitives and the platform layer use handles or re-load after any allocation/safepoint.
6. **Precise roots.** Contexts are heap objects (or precisely mapped stack frames); no conservative scanning.
7. **Region (page) based heap** with bump allocation, so pages can be evacuated and relocated concurrently.
8. **Mutator checkpoints instead of global stops.** The mutator polls at safepoints; GC phase changes use per-thread handshakes, not a world stop. With one mutator thread this is cheap.
9. **`become:` via forwarding** handled by the same load barrier, not by a heap scan.
10. **Off-heap memory for GPU and I/O buffers**: never moved, referenced by handle objects.
11. Weak references and ephemerons designed for concurrent marking from the start.

## Debugging and profiling

Only features with no significant memory, performance or complexity cost.

1. **Contexts are heap objects**, so every frame is inspectable, restartable and editable. Smalltalk's `thisContext` requires this anyway; a future JIT must map frames to Contexts on demand.
2. **One safepoint mechanism** serves preemption, GC handshakes, profiler sampling and interrupts.
3. **Sampling profiler**: a timer interrupt records the active Process's stack at the next safepoint into a fixed ring buffer (≈1 MB). Always on, attributed per Process (i.e. per window).
4. **Allocation sampling** piggybacks on the bump allocator's limit check: the limit is lowered to the next sample point, so the fast path is unchanged.
5. **Watchpoints use the immutability bit** stores already check: mark the object read-only, catch the failed store, report, retry.
6. **Breakpoints, logpoints, conditional and per-object breakpoints are image-side**: recompiled methods or a per-object anonymous subclass. No VM support.
7. **Frame timeline**: per frame, a small record of which Processes ran, draw/raster times, GPU timestamp queries and GC phases.
8. **The debugger never runs in the debugged Process.** Any window's Process can be stopped while the rest stays live.
9. Profile data are ordinary objects behind a Kernel-level API; tools never call raw primitives.

Rejected as too costly: record/replay and time-travel debugging, always-on send/allocation tracing, read watchpoints, remote debugging, an in-image VM simulator before Stage 1.

## Remote control

The whole UI must be drivable by an agent (Claude) without a human, at no cost when unused.

- **Virtual input device** (Platform layer): synthetic pointer/key events enter the same input path as OS events, so remote input behaves exactly like real input and punches no hole through the layers.
- **Frame readback** (Platform layer): PNG of the screen or one window's layer texture.
- **Control service** (image, Tools layer): a Process blocked on a local socket. Commands:
  - `snapshot`: the widget tree as structured text (window, role, label, bounds, state, stable ref per widget), like an accessibility tree;
  - `click` / `type` / `key` / `drag` on a ref or coordinate, sent through the virtual input device;
  - `eval`: run a Smalltalk expression, return its printString;
  - `screenshot`;
  - `wait`: until a condition holds (widget exists, Process idle, frame presented).
- A small CLI (`samaltak-ctl`) wraps the socket, modeled on `agent-browser`.
- Same channel later serves automated UI tests.

## Graphics and UI layering

Each layer only calls the one directly below.

| Layer | Package | Responsibility |
|---|---|---|
| 5 | Tools | Browser, Workspace, Inspector, Debugger |
| 4 | UI-Widgets | Widgets, layout, events. What normal UI code uses. |
| 3 | UI-Windows | Window (owns a Process), Compositor |
| 2 | Graphics-Canvas | 2D paths, text, images → immutable DisplayLists; GPU compute rasterizer |
| 1 | Graphics-GPU | WebGPU-shaped 3D API: devices, buffers, pipelines, command encoders |
| 0 | Platform (C) | Surface, input, wgpu-native |

Widgets draw on a `Canvas`; they never see `GPUDevice`.

## Deferred

- Bare metal (boot stub, drivers, CPU arch, real GPU drivers).

## UI direction

Classic revival (`prototypes/1-classic/`): overlapping windows, Smalltalk-80 tools. Blue Book theme (black on white, hard frames, halftone desk, ultramarine as the only color) with pi-orb typography: Iosevka Etoile for UI, JetBrains Mono for code.
