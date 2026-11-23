Object subclass: #BigIntegerFFIProof
	instanceVariableNames: ''
	classVariableNames: 'PoisonLeft PoisonRight'
	package: 'BigIntegerFFIProof'!

!BigIntegerFFIProof class methodsFor: 'testing'!
padded: integer extra: extra
	| negative result |
	negative := integer negative.
	result := (negative ifTrue: [LargeNegativeInteger] ifFalse: [LargePositiveInteger])
		basicNew: integer digitLength + extra.
	1 to: integer digitLength do: [:i | result basicAt: i put: (integer digitAt: i)].
	^result
!
values
	| wide huge |
	wide := (1 bitShift: 73) + 253.
	huge := (1 bitShift: 8191) + 333.
	^{0. -1. 1. SmallInteger minVal. SmallInteger maxVal.
		SmallInteger minVal - 1. SmallInteger maxVal + 1.
		16rFFFFFFFFFFFFFFFF. 16r10000000000000000.
		wide. wide negated. wide + 1. huge. huge negated. huge - 1.
		LargePositiveInteger basicNew: 0. LargeNegativeInteger basicNew: 19.
		self padded: 1 extra: 17. self padded: -1 extra: 2.
		self padded: SmallInteger minVal extra: 8.
		self padded: SmallInteger maxVal extra: 1.
		self padded: wide extra: 23. self padded: wide negated extra: 7}
!
assert: aBoolean
	aBoolean ifFalse: [self error: 'arbitrary-precision FFI witness failed']
!
proof
	| values binding |
	values := self values.
	binding := FFI tryBindCall: #(call 'vm:core' 'core_bigint_compare' (integerMagnitude integerMagnitude) i32).
	self assert: binding notNil.
	values do: [:a | values do: [:b |
		| expected |
		expected := a compareInteger: b.
		self assert: (binding tryInvoke2: a with: b) == expected.
		self assert: (binding tryInvoke: {a. b}) == expected.
		self assert: (a ffiCandidateCompareInteger: b) == expected]].
	{nil. 1.0. $a. #[1 2 3]. #(1 2 3)} do: [:bad |
		self assert: (binding tryInvoke2: bad with: 1) == false.
		self assert: (binding tryInvoke2: 1 with: bad) == false.
		self assert: (binding tryInvoke: {bad. 1}) == false].
	self assert: (FFI tryBindCall: #(call 'vm:core' 'core_bigint_compare' (i64 i64) i32)) isNil.
	Smalltalk vm garbageCollect.
	self assert: (binding tryInvoke2: values last with: 0) == -1.
	self strictFacade.
	^true
!
strictFacade
	| source saved |
	PoisonLeft := (1 bitShift: 97) + 34.
	PoisonRight := PoisonLeft + 1.
	saved := Integer compiledMethodAt: #compareInteger:.
	Integer addSelector: #bigIntegerCompareWitnessLegacy: withMethod: saved.
	source := 'compareInteger: b
		(BigIntegerFFIProof poisonLeft == self and: [BigIntegerFFIProof poisonRight == b])
			ifTrue: [self error: ''bigint facade took legacy fallback''].
		^self bigIntegerCompareWitnessLegacy: b'.
	[
		Compiler compile: source in: Integer.
		self assert: (PoisonLeft ffiCandidateCompareInteger: PoisonRight) == -1
	] ensure: [
		Integer addSelector: #compareInteger: withMethod: saved.
		Integer removeSelector: #bigIntegerCompareWitnessLegacy:.
		PoisonLeft := PoisonRight := nil]
!
poisonLeft
	^PoisonLeft
!
poisonRight
	^PoisonRight
! !
