# Lowtalk: the VM in Smalltalk

The VM (object memory, GC, interpreter, scheduler, primitives, image I/O) and the platform layer are written in *Lowtalk*, a subset of Smalltalk that is also plain Smalltalk:

- **Running it directly is the simulator.** Lowtalk classes are ordinary classes in the image. A `VMSimulation` instantiates the modules over a `SimulatedMemory` and runs them, so the VM can be stepped in the debugger, profiled and tested without a C compiler.
- **`VMTranslator` turns it into C** (`vm/gen/`, checked in). The C build compiles only generated code.

Packages (all layer 0): `VM-Lowtalk` (the language's runtime: `VMModule`, `VMStruct`, `CLibrary`, `CPointer`, `SimulatedMemory`, `VMSimulation`), `VM-Translator`, `VM-Core` and `VM-Platform` (the VM), `VM-Jit` (machine code, see docs/jit.md), `Tests-VM`.

## Rules

Everything below means the same in Smalltalk and in C; anything else is rejected by the translator.

**Modules.** A `VMModule` subclass is a C module (one `.c` file). Its instance variables are C globals, its methods C functions. `declarations` (class side) answers `#((name type [initialValue]) ...)`; variables typed with a module or library class (`(memory ObjectMemory)`) connect modules and produce no C. Abstract module classes (`isAbstractModule`) may only declare connections; their methods are shared helpers. A module's class-side `cPreamble` goes at the top of its C file (before the header). Calls go to `self` or to a connection: `memory allocObj: cls format: F_FIXED slots: 3`. An *interface* (`isInterface`, e.g. `PlatformInterface`) only declares prototypes; a subclass implements them under the same C names, and the build links one implementation.

**Constants** are class variables in UPPER_SNAKE case (`F_BYTES`, `CTX_SENDER`), shared through `VMConstants` (the image's single definition of the object model) or private to a module; set in the class-side `initialize`. They become `#define`s.

**Functions.** A method with `<c: 'oop alloc_obj(oop cls, int fmt, uint32_t n)'>` is a C function (prototype parameters map to the method's arguments in order). A method without `<c:>` is inline: expanded at each call, untyped and generic, blocks passed to it inlined too. `<export>` keeps a function non-static even if no Lowtalk module calls it; `<noreturn>` marks one that never returns. `const` in prototypes and types is kept in the C but not checked by the translator (the C compiler checks it). Local variable types are inferred from the first assignment (an integer literal gives `int64_t`); `<var: #name type: 'T'>` declares one. A local assigned exactly once, with a constant, is that constant (no variable), so case analysis on it folds away.

**Integers** are mathematical in Smalltalk and fixed-width in C, so:
- a value must fit its type; wrapping is explicit: `asUInt64`, `asInt64`, `asUInt32`, `asInt32`, `asUInt16`, `asInt16`, `asUInt8`, `asInt8` (C casts);
- implicit conversions may not lose values (assign a `size_t` to an `int32_t` local: write `asInt32`); stores into memory (fields, `at:put:`) may narrow, the simulator checks each stored value;
- comparisons, `quo:`, `rem:` and `>>` may not mix signedness where C would convert a possibly negative operand to unsigned; `+ - *` and bit operations may (the result is the same modulo 2^64);
- `<<` only on 64-bit values (`asInt64`/`asUInt64` first): narrower shifts overflow in C, not in the simulator;
- an unsigned `to:` limit may not be computed by a subtraction (it wraps in C when it would go negative);
- `quo:`/`rem:` (truncating) only; `/` only on doubles; no `//`, `\\`;
- `<<`, `>>`, `bitAnd:`, `bitOr:`, `bitXor:`, `bitClear:`; `bitInvert` only on signed values (`bitInvert64`/`bitInvert32` for unsigned);
- overflow checks: `x ifNoOverflowAdd: y do: [:r | ...]` (also `Sub`, `Mul`) runs the block with the 64-bit signed result if there was none (`__builtin_*_overflow`);
- `$a value` is a character code; `=`/`~=` compare values; `==`, `~~` and `nil` are not Lowtalk.

**Control flow:** `ifTrue:ifFalse:` (conditions must be `bool`), `and:`/`or:`, `whileTrue:`/`whileFalse:`, `to:do:`/`to:by:do:`, `timesRepeat:`, `repeat`, `caseOf:otherwise:` (a C `switch` for constant keys), `^`. Blocks only as arguments of these or of inline methods.

**Pointers** (`T *`): `p at: i`, `p at: i put: v`, `p value`, `p value: v`, `p + n`, `p - n`, `p - q`, comparisons, `p isNull`, `p notNull`, `self null`. A struct pointer answers its fields (`fr method`, `fr method: m`), `p fieldAddress: #method` (`&p->method`), `p copyStructFrom: q` (`*p = *q`); `p at: i` of a struct pointer is `p + i`. Casts: `self cCoerce: e to: 'T'`. Raw memory: `self uint64At: a`, `self uint64At: a put: v` (also `uint32`, `uint16`, `uint8`, `int*`, `float64`, `float32`). `self sizeof: 'T'`. Function pointers: `self functionPointer: #ticker:`, called with `fp call`, `fp call: x`, ... An address cast to a function pointer type (`(self cCoerce: entry to: 'int64_t (*)(int64_t)') call: 42`) calls machine code; simulated, the memory's `machineCodeRunner` runs it (VM-Jit's `Arm64Emulator`).

**Locals in memory.** `p := self local: 'T'` answers a pointer to fresh zeroed storage for a `T` (a struct, a scalar out-parameter, an array `'char[256]'`), living until the function returns.

**Strings.** A string literal is a `char *` for C library calls and for storing into memory. To read one as bytes, write `self cString: 'literal'`.

**Structs.** A `VMStruct` subclass is a C struct; `fields` (class side) answers `#((name type) ...)` (`(name 'T[n]')` arrays, `(union (a T) (b U))`); field names must not be methods of `VMStruct`. The header checks with `_Static_assert` that C lays a struct out as the simulator does. An `ExternStruct` names a C library struct (`cName`) and the fields the VM uses, by their C names.

**C libraries.** A `CLibrary` subclass declares the C functions, variables and macros the VM calls: `<c: 'void *memcpy(void *dst, const void *src, size_t n)'>` (variadic ones once per arity), `<cVariable: 'FILE *stderr'>`, `<cMacro: 'int PROT_READ'>`, `<noreturn>`; class-side `headers` are included, `typedefs` answers `#((FILE opaque) (pthread_t uintptr_t))`. The method bodies are the simulation.

**The interpreter loop.** `<bytecode: n>`, `<bytecodes: #(first last)>` (a range; single bytecodes and lists take precedence) and `<bytecodeList: #(...)>` mark handler methods; `<bytecodes: #()>` handles unknown bytecodes. `registers` (class side) names variables that are C locals of the interpreter function. Ending a handler (`^self`) dispatches the next bytecode; `^self someLabel` in a handler is a `goto` to a `<label>` method (its arguments become shared locals) or to another handler; `^self dispatch: byte` re-dispatches; `^self inlineHelper` expands the helper so that each of its returns dispatches. `<specialize>` handlers get one copy per bytecode with `self currentBytecode` constant.

**Primitives:** `<vmPrimitive: 1 name: 'intAdd'>` on a `void` method (`<leaf>`: never allocates or switches; `<notTryable>`: not for the debugger's tryPrimitive). The translator emits the table (`primitive_entries.c`); the image compiler and builder read the names and numbers from the same methods.
