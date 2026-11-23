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
	| vm floats fractions strings wall cpu env rawKey |
	vm := Smalltalk vm.
	floats := #(0 16r8000000000000000 1 16r8000000000000001
		16r3FF0000000000001 16rC006000000000000 16r4340000000000000
		16r7FEFFFFFFFFFFFFF 16r7FF0000000000000 16rFFF0000000000000
		16r7FF8000000000042) collect: [:bits | Float fromIEEEBits: bits].
	fractions := floats collect: [:x | x fractionPart asIEEEBits].
	strings := floats collect: [:x | x primPrintString].
	rawKey := 'SAMALTAK_CORE_RAW_KEY_', (String with: (Character value: 16rDCFF)).
	env := {'SAMALTAK_CORE_PRESENT'. #SAMALTAK_CORE_EMPTY. 'SAMALTAK_CORE_ABSENT'. rawKey}
		collect: [:key | {key. vm getenv: key}].
	self assert: env first second = 'text'.
	self assert: env second second = ''.
	self assert: env third second isNil.
	self assert: (env fourth second asArray collect: [:ch | ch value]) = #(65 16rDCED 16rDCA0 16rDC80 233).
	self assert: (vm ffiCandidateGetenv: ('SAMALTAK_CORE_PRESENT', (String with: (Character value: 0)))) isNil.
	self assert: (vm ffiCandidateGetenv: #[]) isNil.
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
		env do: [:each | self assert: (vm ffiCandidateGetenv: each first) = each second]].
	self assert: (wall second between: wall first and: Time utcMicroseconds).
	self assert: (cpu second between: cpu first and: vm threadCpuMicroseconds).
	self testOutput: vm.
	self testRawBindings.
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
		self assert: (vm ffiCandidateStdoutWrite: #[]) == vm]
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
! !
