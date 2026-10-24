# Lowtalk: the VM in Smalltalk

The VM (object memory, GC, interpreter, scheduler, primitives, image I/O) and the platform layer are written in *Lowtalk*, a subset of Smalltalk that is also plain Smalltalk:

- **Running it directly is the simulator.** Lowtalk classes are ordinary classes in the image. A `VMSimulation` instantiates the modules over a `SimulatedMemory` and runs them, so the VM can be stepped in the debugger, profiled and tested without a C compiler.
- **`VMTranslator` turns it into C** (`vm/gen/`, checked in). The C build compiles only generated code.

Packages (all layer 0): `VM-Lowtalk` (the language's runtime: `VMModule`, `VMStruct`, `CLibrary`, `CPointer`, `SimulatedMemory`, Integer conversions), `VM-Core` and `VM-Platform` (the VM), `VM-Translator`, `VM-Simulator`, `Tests-VM`.

## Rules

Everything below means the same in Smalltalk and in C; anything else is rejected by the translator.

**Modules.** A `VMModule` subclass is a C module (one `.c` file). Its instance variables are C globals, its methods C functions. `declarations` (class side) answers `#((name type [initialValue]) ...)`; module-typed variables (`(memory ObjectMemory)`) hold the other modules and produce no C. Calls go to `self` or to a module variable: `memory allocSlots: 3 class: cls`. A function's C name is the first keyword in snake case (`allocSlots:class:` → `alloc_slots`) unless `<c: ...>` names it; duplicate names are errors.

**Constants** are class variables in UPPER_SNAKE case (`F_BYTES`, `CTX_SENDER`), shared through `VMConstants` (the image's single definition of the object model) or private to a module. They become `#define`s.

**Signatures.** A function that is not `<inline>` declares its prototype: `<c: 'oop alloc_slots(oop cls, uint32_t n)'>`. Types are C types, plus `oop` (a tagged word) and struct class names. Local variable types are inferred from their first assignment; `<var: #name type: 'T'>` declares one.

**`<inline>`** methods are expanded at each call (blocks passed to them are inlined too); they need no types and may be generic. Trivial accessors (`^var`, `var := x`) are always inlined.

**Integers** are mathematical in Smalltalk and fixed-width in C, so:
- a value must fit its type; wrapping is explicit: `asUInt64`, `asInt64`, `asUInt32`, `asInt32`, `asUInt16`, `asInt16`, `asUInt8`, `asInt8` (bit reinterpretations, C casts);
- comparisons and arithmetic may not mix signedness where C would convert the signed operand to unsigned;
- `quo:`/`rem:` (truncating) only; `/` only on doubles; no `//`, `\\`;
- `<<`, `>>`, `bitAnd:`, `bitOr:`, `bitXor:`, `bitClear:`; `bitInvert` only on signed values (`bitInvert64`/`bitInvert32` for unsigned);
- overflow checks: `x ifNoOverflowAdd: y do: [:r | ...]` (also `Sub`, `Mul`) runs the block with the 64-bit signed result if there was none (`__builtin_*_overflow`);
- `=`/`~=` compare values; `==`, `~~` and `nil` are not Lowtalk.

**Control flow:** `ifTrue:ifFalse:` (conditions must be `bool`), `and:`/`or:`, `whileTrue:`/`whileFalse:`, `to:do:`/`to:by:do:`, `timesRepeat:`, `repeat`, `caseOf:otherwise:` (a C `switch` for constant keys), `^`. Blocks only as arguments of these or of `<inline>` methods.

**Pointers** (`T *`): `p at: i`, `p at: i put: v`, `p value`, `p value: v`, `p + n`, `p - n`, `p - q`, comparisons, `p isNull`, `p notNull`, `self null`. A struct pointer answers its fields: `fr method`, `fr method: m`. Casts: `self cCoerce: e to: 'T'`. Raw memory: `self uint64At: a`, `self uint64At: a put: v` (also `uint32`, `uint16`, `uint8`, `int*`, `float64`, `float32`). `self sizeof: 'T'`.

**Locals in memory.** `p := self local: 'T'` answers a pointer to fresh zeroed storage for a `T` (a struct, a scalar out-parameter, an array `'char[256]'`), living until the function returns.

**Structs.** A `VMStruct` subclass is a C struct; `fields` (class side) answers `#((name type) ...)` (`(name 'T[n]')` arrays, `(union (a T) (b U))`). An `ExternStruct` names a C library struct (`cName`) and the fields the VM uses; its field selectors are the C names.

**C libraries.** A `CLibrary` subclass declares the C functions, variables and macros the VM calls: `<c: 'void *memcpy(void *dst, const void *src, size_t n)'>` (variadic ones once per arity), `<cVariable: 'FILE *stderr'>`, `<cMacro: 'int PROT_READ'>`; its `headers` are included. The method bodies are the simulation. Function pointers: `self functionPointer: #ticker:`, called with `fp call`, `fp call: x`.

**The interpreter loop.** `<bytecode: n>` / `<bytecodes: #(first last)>` mark handler methods; `<registers>` variables (`ip`, `sp`, `fp`, …) are C locals of the interpreter function. Ending a handler (`^self`) dispatches the next bytecode; `^self someLabel` in a handler is a `goto` to a `<label>` method (its arguments become shared locals); `^self dispatch: byte` re-dispatches. `<specialize>` handlers get one copy per bytecode with `self currentBytecode` constant, so case analysis on it folds away.

**Primitives:** `<primitive: 1 name: 'intAdd'>` (`<leaf>`: never allocates or switches; `<notTryable>`). The translator emits the table; the image compiler and builder read the names and numbers from the same methods.
