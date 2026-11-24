Object subclass: #CoreFFISmoke
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'CoreFFISmoke'!

!CoreFFISmoke class methodsFor: 'checking'!
assert: condition
	condition ifFalse: [self error: 'Core FFI semantic check failed']
!
run
	| vm floats fractions strings wall cpu env rawKey longKey |
	vm := Smalltalk vm.
	floats := #(0 16r8000000000000000 1 16r8000000000000001
		16r3FF0000000000001 16rC006000000000000 16r4340000000000000
		16r7FEFFFFFFFFFFFFF 16r7FF0000000000000 16rFFF0000000000000
		16r7FF8000000000042) collect: [:bits | Float fromIEEEBits: bits].
	fractions := #(0 16r8000000000000000 1 16r8000000000000001 16r3CB0000000000000
		16rBFE8000000000000 0 0 0 16r8000000000000000 16r7FF8000000000042).
	strings := #('0.0' '-0.0' '5.0e-324' '-5.0e-324' '1.0000000000000002' '-2.75'
		'9007199254740992.0' '1.7976931348623157e308' 'inf' '-inf' 'nan').
	vm stderrWrite: 'core-ffi-begin', (String with: Character lf).
	rawKey := 'SAMALTAK_CORE_RAW_KEY_', (String with: (Character value: 16rDCFF)).
	longKey := String new: 513 withAll: $Q.
	env := {'SAMALTAK_CORE_PRESENT'. #SAMALTAK_CORE_EMPTY. 'SAMALTAK_CORE_ABSENT'. rawKey.
		'SAMALTAK_CORE_LATIN1'. 'SAMALTAK_CORE_LONG'. longKey. ''}
		collect: [:key | {key. vm getenv: key}].
	self assert: env first second = 'text'.
	self assert: env second second = ''.
	self assert: env third second isNil.
	self assert: (env fourth second asArray collect: [:ch | ch value]) = #(65 16rDCED 16rDCA0 16rDC80 233).
	self assert: (vm getenv: ('SAMALTAK_CORE_PRESENT', (String with: (Character value: 0)))) isNil.
	self assert: (vm getenv: #[]) isNil.
	self assert: env fifth second class == ByteString.
	self assert: env fifth second size = 1.
	self assert: (env at: 6) second size = 1024.
	self assert: (env at: 7) second = 'long key'.
	self assert: (env at: 8) second isNil.
	wall := Time utcMicroseconds.
	cpu := vm threadCpuMicroseconds.
	floats doWithIndex: [:x :i |
		self assert: x fractionPart asIEEEBits = (fractions at: i).
		self assert: x primPrintString = (strings at: i).
		self assert: x primPrintString class == ByteString].
	self assert: Time utcMicroseconds >= wall.
	self assert: vm threadCpuMicroseconds >= cpu.
	self testOutput: vm.
	self testRawBindings.
	self testTextRejections.
	vm stderrWrite: (String with: Character lf), 'core-ffi-end', (String with: Character lf).
	^true
!
testOutput: vm
	| text |
	text := String withAll: ({79. 0. 233. 16rDCFF. 16r20AC. 16rD800}
		collect: [:cp | Character value: cp]).
	self assert: (vm stdoutWrite: text) == vm.
	self assert: (vm stderrWrite: #[69 0 255]) == vm.
	self assert: (vm stderrWrite: text) == vm.
	self assert: (vm stdoutWrite: #[]) == vm.
	self assert: (vm stdoutWrite: #asciiText) == vm.
	self assert: (vm stderrWrite: ('a', (String with: Character null), 'bcdefghi')) == vm
!
testRawBindings
	| binding buffer |
	binding := CoreFFI floatPrintString.
	buffer := #[33 33 33 33 33 33] copy.
	self assert: (binding tryInvoke2: 0.0 with: {buffer. 2. 2}) = -1.
	self assert: buffer = #[33 33 33 33 33 33].
	self assert: (binding tryInvoke: {0.0. {buffer. 2. 3}}) = 3.
	self assert: buffer = #[33 48 46 48 33 33].
	buffer beReadOnlyObject.
	self assert: (binding tryInvoke2: 0.0 with: {buffer. 2. 3}) == false.
	self assert: ((FFI bind: #(call 'vm:core' 'core_float_fraction_part' (f64) f64)) tryInvoke1: 1) == false
!
testTextRejections
	| count key |
	count := FFI bind: #(call 'vm:core' 'core_stdout_text' (countedText) void).
	key := FFI bind: #(call 'vm:core' 'core_getenv_text' (cText) ownedText).
	self assert: (count tryInvoke1: 16rDEADBEEF) == false.
	self assert: (count tryInvoke: {#a. #b}) == false.
	self assert: (count tryInvoke1: {#[1]. 1. 1}) == false.
	self assert: (key tryInvoke1: #[65]) == false.
	self assert: (key tryInvoke1: (String with: Character null)) == false.
	self assert: (key tryInvoke1: (String withAll: {Character value: 16r20AC. Character null})) == false.
	self assert: ((PlatformFFI bind: #(call 'vm:core' 'core_stdout_write' (countedText) void)) isNil).
	self assert: ((PlatformFFI bind: #(call 'vm:core' 'core_getenv_text' (bytesWithLength u64) i32)) isNil)
! !
