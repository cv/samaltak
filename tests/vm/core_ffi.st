Object subclass: #CoreFFISmoke
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'CoreFFISmoke'!

!CoreFFISmoke class methodsFor: 'checking'!
assert: condition
	condition ifFalse: [self error: 'Core FFI semantic check failed']
!
withoutLegacy: specs do: block
	| methods |
	methods := specs collect: [:spec | spec first compiledMethodAt: spec second].
	[
		specs do: [:spec |
			Compiler compile: spec third, ' self error: ''unexpected core legacy fallback''' in: spec first].
		block value
	] ensure: [
		specs withIndexDo: [:spec :i | spec first addSelector: spec second withMethod: (methods at: i)]]
!
run
	| vm floats fractions strings wall cpu env rawKey longKey |
	vm := Smalltalk vm.
	floats := #(0 16r8000000000000000 1 16r8000000000000001
		16r3FF0000000000001 16rC006000000000000 16r4340000000000000
		16r7FEFFFFFFFFFFFFF 16r7FF0000000000000 16rFFF0000000000000
		16r7FF8000000000042) collect: [:bits | Float fromIEEEBits: bits].
	fractions := floats collect: [:x | x fractionPart asIEEEBits].
	strings := floats collect: [:x | x primPrintString].
	rawKey := 'SAMALTAK_CORE_RAW_KEY_', (String with: (Character value: 16rDCFF)).
	longKey := String new: 513 withAll: $Q.
	env := {'SAMALTAK_CORE_PRESENT'. #SAMALTAK_CORE_EMPTY. 'SAMALTAK_CORE_ABSENT'. rawKey.
		'SAMALTAK_CORE_LATIN1'. 'SAMALTAK_CORE_LONG'. longKey. ''}
		collect: [:key | {key. vm getenv: key}].
	self assert: env first second = 'text'.
	self assert: env second second = ''.
	self assert: env third second isNil.
	self assert: (env fourth second asArray collect: [:ch | ch value]) = #(65 16rDCED 16rDCA0 16rDC80 233).
	self assert: (vm ffiCandidateGetenv: ('SAMALTAK_CORE_PRESENT', (String with: (Character value: 0)))) isNil.
	self assert: (vm ffiCandidateGetenv: #[]) isNil.
	self assert: env fifth second class == ByteString.
	self assert: env fifth second size = 1.
	self assert: (env at: 6) second size = 1024.
	self assert: (env at: 7) second = 'long key'.
	self assert: (env at: 8) second isNil.
	wall := Time utcMicroseconds.
	cpu := vm threadCpuMicroseconds.
	self withoutLegacy: {
		{Float. #fractionPart. 'fractionPart'}.
		{Float. #primPrintString. 'primPrintString'}.
		{Time class. #utcMicroseconds. 'utcMicroseconds'}.
		{VirtualMachine. #threadCpuMicroseconds. 'threadCpuMicroseconds'}.
		{VirtualMachine. #getenv:. 'getenv: key'}} do: [
		floats doWithIndex: [:x :i |
			self assert: x ffiCandidateFractionPart asIEEEBits = (fractions at: i).
			self assert: x ffiCandidatePrimPrintString = (strings at: i).
			self assert: x ffiCandidatePrimPrintString class == ByteString].
		wall := {wall. Time ffiCandidateUtcMicroseconds}.
		cpu := {cpu. vm ffiCandidateThreadCpuMicroseconds}.
		env do: [:each |
			| result |
			result := vm ffiCandidateGetenv: each first.
			self assert: result = each second.
			self assert: result class == each second class]].
	self assert: (wall second between: wall first and: Time utcMicroseconds).
	self assert: (cpu second between: cpu first and: vm threadCpuMicroseconds).
	self testOutput: vm.
	self testRawBindings.
	self testTextRejections.
	^true
!
testOutput: vm
	| text |
	text := String withAll: ({79. 0. 233. 16rDCFF. 16r20AC. 16rD800}
		collect: [:cp | Character value: cp]).
	self withoutLegacy: {
		{VirtualMachine. #stdoutWrite:. 'stdoutWrite: text'}.
		{VirtualMachine. #stderrWrite:. 'stderrWrite: text'}} do: [
		self assert: (vm ffiCandidateStdoutWrite: text) == vm.
		self assert: (vm ffiCandidateStderrWrite: #[69 0 255]) == vm.
		self assert: (vm ffiCandidateStderrWrite: text) == vm.
		self assert: (vm ffiCandidateStdoutWrite: #[]) == vm.
		self assert: (vm ffiCandidateStdoutWrite: #asciiText) == vm.
		self assert: (vm ffiCandidateStderrWrite: ('a', (String with: Character null), 'bcdefghi')) == vm]
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
