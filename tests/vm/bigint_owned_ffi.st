!BigIntegerFFIProof class methodsFor: 'owned result tests'!
arithmeticCases
	^#(
		(20 'core_bigint_add' #+ #ffiCandidateAdd:)
		(21 'core_bigint_sub' #- #ffiCandidateSubtract:)
		(22 'core_bigint_mul' #* #ffiCandidateMultiply:)
		(23 'core_bigint_quo' #quo: #ffiCandidateQuo:)
		(24 'core_bigint_rem' #rem: #ffiCandidateRem:)
		(25 'core_bigint_floordiv' #// #ffiCandidateFloorDivide:)
		(26 'core_bigint_mod' #\\ #ffiCandidateModulo:)
		(28 'core_bigint_bitand' #bitAnd: #ffiCandidateBitAnd:)
		(29 'core_bigint_bitor' #bitOr: #ffiCandidateBitOr:)
		(30 'core_bigint_bitxor' #bitXor: #ffiCandidateBitXor:)
		(31 'core_bigint_bitshift' #bitShift: #ffiCandidateBitShift:))
!
arithmeticBinding: spec
	^FFI bind: {#call. 'vm:core'. spec second. #(integerMagnitude integerMagnitude). #ownedIntegerMagnitude}
!
ownedResults
	| values |
	values := self values.
	self arithmeticCases do: [:spec |
		| binding shifts |
		binding := self arithmeticBinding: spec.
		shifts := {0. 1. -1. 7. -8. 63. -64. 65. -65. 8192. -8192. (1 bitShift: 100) negated}.
		values do: [:a | (spec first = 31 ifTrue: [shifts] ifFalse: [values]) do: [:b |
			self checkOperation: spec binding: binding left: a right: b]].
		self assert: (binding tryInvoke2: 1 with: 0.5) == false.
		self assert: (binding tryInvoke2: #[1] with: 1) == false.
		self assert: (binding tryInvoke: {1. $a}) == false].
	self checkOwnedErrors.
	^true
!
checkOperation: spec binding: binding left: a right: b
	| expected actual |
	expected := [a perform: spec third with: b] on: ZeroDivide do: [:e | true].
	actual := binding tryInvoke2: a with: b.
	self checkOwned: actual equals: expected.
	actual := binding tryInvoke: {a. b}.
	self checkOwned: actual equals: expected.
	actual := [a perform: spec fourth with: b] on: ZeroDivide do: [:e |
		self assert: e dividend == a. true].
	self checkOwned: actual equals: expected
!
checkOwned: actual equals: expected
	self assert: actual class == expected class.
	self assert: actual = expected.
	expected isInteger ifTrue: [self assert: actual digitLength == expected digitLength]
!
checkOwnedErrors
	| huge shift |
	huge := 1 bitShift: 100.
	shift := self arithmeticBinding: self arithmeticCases last.
	self assert: (shift tryInvoke2: 1 with: huge) == nil.
	self assert: ([1 ffiCandidateBitShift: huge. false] on: OutOfMemory do: [:e | true]).
	self assert: (shift tryInvoke2: 0 with: huge) == 0.
	self assert: ([FFI bind: #(call 'libm' 'sqrt' (integerMagnitude integerMagnitude) ownedIntegerMagnitude). false]
		on: FFIError do: [:e | true]).
	self assert: (FFI tryBindCall: #(call 'vm:core' 'core_bigint_add' (integerMagnitude integerMagnitude) u64)) isNil.
	self verifyOwnedAdmission
!
verifyOwnedAdmission
	| descriptor binding |
	Compiler compile: 'bigintLegacyBind: library symbol: name tags: tags result: result
		<primitive: ''ffiBind''>
		^#rejected' in: FFI class.
	Compiler compile: 'bigintLegacyInvoke: id library: library symbol: name tags: tags result: result args: args
		<primitive: ''ffiInvoke''>
		^#rejected' in: FFI class.
	self assert: (FFI bigintLegacyBind: 'vm:core' symbol: 'core_bigint_add' tags: #[10 10] result: 11) == #rejected.
	self assert: (FFI bigintLegacyInvoke: 1044 library: 'vm:core' symbol: 'core_bigint_add' tags: #[10 10]
		result: 11 args: #(1 2)) == #rejected.
	#(('vm:core' 'core_bigint_compare' #[10 10] 11)
	  ('vm:core' 'core_bigint_add' #[10 10] 7)
	  ('vm:core' 'core_bigint_add' #[3 3] 11)
	  ('libm' 'sqrt' #[6] 11)) do: [:parts |
		descriptor := parts copy.
		descriptor beReadOnlyObject.
		binding := FFIBinding new initializeDescriptor: descriptor.
		self assert: binding prepare not]
!
forceGC
	| a b binding expected before |
	a := (1 bitShift: 1024) + 65535.
	b := (1 bitShift: 998) + 1.
	expected := a + b.
	before := Smalltalk vm statistics fullGCs.
	binding := self arithmeticBinding: self arithmeticCases first.
	40 timesRepeat: [self assert: (self positional: binding left: nil right: b) == false].
	self assert: (binding tryInvoke: {a. b}) = expected.
	1 to: 36 do: [:i |
		self assert: (self positional: binding left: a right: b) = expected.
		self assert: (a ffiCandidateAdd: b) = expected].
	self assert: (a ffiCandidateAdd: a negated) == 0.
	self assert: (a ffiCandidateBitShift: (1 bitShift: 90) negated) == 0.
	self assert: Smalltalk vm statistics fullGCs - before >= 75.
	^true
!
positional: binding left: a right: b
	^binding tryInvoke2: a with: b
! !
