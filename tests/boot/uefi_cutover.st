| check frac print clock out err bytes a b |
check := [:condition :label | condition ifFalse: [self error: 'UEFI cutover: ', label]].
check value: Machine hasFirmware value: 'not running under firmware'.
#(20 21 22 23 24 25 26 27 28 29 30 31 52 61 152 153 169 170 172) do: [:slot |
	check value: ((Smalltalk vm primitiveNames at: slot) isNil) value: 'retired slot present'].

frac := FFI bind: #(call 'vm:core' 'core_float_fraction_part' (f64) f64).
check value: (frac tryInvoke0 == false) value: 'wrong arity accepted'.
check value: ((frac tryInvoke1: 5) == false) value: 'wrong type accepted'.
check value: ((frac invoke: #(-1.25)) = -0.25) value: 'array invocation'.
Smalltalk vm garbageCollect.
check value: ((frac tryInvoke1: -1.25) = -0.25) value: 'positional invocation after GC'.
check value: (-1.25 fractionPart = -0.25) value: 'float fraction'.
check value: (9007199254740992.0 printString = '9007199254740992.0') value: 'float print'.

print := FFI bind: #(call 'vm:core' 'core_float_print_string' (f64 writableBytesWithLength) i32).
bytes := #[170 0 0 0 0 170] copy.
check value: ((print tryInvoke2: 1.25 with: {bytes. 2. 3}) = -1) value: 'completed short write'.
check value: (bytes = #[170 0 0 0 0 170]) value: 'short write touched buffer'.
check value: ((print tryInvoke2: 1.25 with: {bytes. 2. 99}) == false) value: 'out-of-bounds slice accepted'.
check value: ((print tryInvoke2: 1.25 with: {#[170 0 0 0 0 170]. 2. 4}) == false) value: 'immutable buffer accepted'.
check value: ((print tryInvoke2: 1.25 with: {bytes. 2. 4}) = 4) value: 'float buffer count'.
check value: (bytes = #[170 49 46 50 53 170]) value: 'float buffer bytes or guards'.

clock := Time utcMicroseconds.
check value: (clock > 1500000000000000) value: 'invalid wall clock'.
clock := Smalltalk vm threadCpuMicroseconds.
(Delay forMilliseconds: 10) wait.
check value: (Smalltalk vm threadCpuMicroseconds >= clock) value: 'clock went backward'.
check value: ((Smalltalk vm getenv: 'PATH') isNil) value: 'unexpected environment'.
check value: (File exists: '/samaltak.args') not value: 'unexpected boot volume File API'.

out := FFI bind: #(call 'vm:core' 'core_stdout_text' (countedText) void).
err := FFI bind: #(call 'vm:core' 'core_stderr_text' (countedText) void).
check value: ((out tryInvoke1: 1) == false) value: 'wrong text type accepted'.
check value: ((err tryInvoke1: '') isNil) value: 'completed void was rejected'.
Smalltalk vm stdoutWrite: 'UEFI-stdout-π', (String with: Character lf).
Smalltalk vm stderrWrite: 'UEFI-stderr-é', (String with: Character lf).
check value: ((FFI tryBindCall: #(call 'vm:core' 'core_utc_microseconds' () u64)) isNil) value: 'wrong signature accepted'.
check value: ((FFI tryBindCall: #(call 'other' 'core_utc_microseconds' () i64)) isNil) value: 'noncore library accepted'.
check value: ((FFI tryBindCall: #(call 'vm:core' 'core_stdout_write' (bytesWithLength) void)) isNil) value: 'unlisted core export accepted'.
check value: ((FFI tryBindCall: #(call 'vm:core' 'core_bigint_add' (integerMagnitude integerMagnitude) ownedIntegerMagnitude)) isNil) value: 'unexpected native bigint'.

a := (1 bitShift: 257) - 1.
b := (1 bitShift: 129) + 7.
check value: ((a * b) quo: a) = b value: 'portable bigint multiply/divide'.
check value: ((a + b) - b = a) value: 'portable bigint add/subtract'.
check value: ((a bitXor: b) bitXor: b) = a value: 'portable bigint xor'.
'UEFI cutover OK'
