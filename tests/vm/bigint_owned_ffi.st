!BigIntegerFFIProof class methodsFor: 'owned result tests'!
arithmeticCases
	^#(
		(20 'core_bigint_add' #+)
		(21 'core_bigint_sub' #-)
		(22 'core_bigint_mul' #*)
		(23 'core_bigint_quo' #quo:)
		(24 'core_bigint_rem' #rem:)
		(25 'core_bigint_floordiv' #//)
		(26 'core_bigint_mod' #\\)
		(28 'core_bigint_bitand' #bitAnd:)
		(29 'core_bigint_bitor' #bitOr:)
		(30 'core_bigint_bitxor' #bitXor:)
		(31 'core_bigint_bitshift' #bitShift:))
!
arithmeticBinding: spec
	^FFI bind: {#call. 'vm:core'. spec second. #(integerMagnitude integerMagnitude). #ownedIntegerMagnitude}
!
ownedResults: productionOnly
	| values |
	values := self values.
	self arithmeticCases do: [:spec |
		| binding shifts |
		binding := productionOnly ifFalse: [self arithmeticBinding: spec].
		shifts := {0. 1. -1. 7. -8. 63. -64. 65. -65. 8192. -8192. (1 bitShift: 100) negated}.
		values do: [:a | (spec first = 31 ifTrue: [shifts] ifFalse: [values]) do: [:b |
			self checkOperation: spec binding: binding left: a right: b]].
		binding ifNotNil: [
			self assert: (binding tryInvoke2: 1 with: 0.5) == false.
			self assert: (binding tryInvoke2: #[1] with: 1) == false.
			self assert: (binding tryInvoke: {1. $a}) == false]].
	productionOnly ifFalse: [self checkOwnedErrors].
	^true
!
checkOperation: spec binding: binding left: a right: b
	| expected actual |
	expected := [self portable: spec first left: a right: b] on: ZeroDivide do: [:e | true].
	binding ifNotNil: [
		actual := binding tryInvoke2: a with: b.
		self checkOwned: actual equals: expected.
		actual := binding tryInvoke: {a. b}.
		self checkOwned: actual equals: expected].
	actual := [a perform: spec third with: b] on: ZeroDivide do: [:e |
		self assert: e dividend == a. true].
	self checkOwned: actual equals: expected
!
portable: op left: a right: b
	op = 20 ifTrue: [^a portableAdd: b subtract: false].
	op = 21 ifTrue: [^a portableAdd: b subtract: true].
	op = 22 ifTrue: [^a portableMultiply: b].
	op <= 26 ifTrue: [^a portableDivide: b mode: op - 23].
	op = 28 ifTrue: [^a portableBitOp: #bitAnd: with: b].
	op = 29 ifTrue: [^a portableBitOp: #bitOr: with: b].
	op = 30 ifTrue: [^a portableBitOp: #bitXor: with: b].
	^a portableBitShift: b
!
checkOwned: actual equals: expected
	self assert: actual class == expected class.
	self assert: (expected isInteger
		ifTrue: [(actual portableCompareInteger: expected) = 0]
		ifFalse: [actual == expected]).
	expected isInteger ifTrue: [self assert: actual digitLength == expected digitLength]
!
checkOwnedErrors
	| huge shift |
	huge := 1 bitShift: 100.
	shift := self arithmeticBinding: self arithmeticCases last.
	self assert: (shift tryInvoke2: 1 with: huge) == nil.
	self assert: ([1 bitShift: huge. false] on: OutOfMemory do: [:e | true]).
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
	expected := a portableAdd: b subtract: false.
	before := Smalltalk vm statistics fullGCs.
	binding := self arithmeticBinding: self arithmeticCases first.
	40 timesRepeat: [self assert: (self positional: binding left: nil right: b) == false].
	self checkOwned: (binding tryInvoke: {a. b}) equals: expected.
	1 to: 36 do: [:i |
		self checkOwned: (self positional: binding left: a right: b) equals: expected.
		self checkOwned: a + b equals: expected].
	self assert: (a + (0 portableAdd: a subtract: true)) == 0.
	self assert: (a bitShift: (0 portableAdd: (1 portableBitShift: 90) subtract: true)) == 0.
	self assert: Smalltalk vm statistics fullGCs - before >= 73.
	^true
!
positional: binding left: a right: b
	^binding tryInvoke2: a with: b
! !

!BigIntegerFFIProof class methodsFor: 'canonical arithmetic'!
production
	self assert: (16r10000000000000000 compareInteger: 16r10000000000000001) = -1.
	^self ownedResults: true
!
forcePortable
	"Reject the downcall before native entry without disabling other FFI."
	| original |
	original := FFIBinding compiledMethodAt: #tryInvoke2:with:.
	FFIBinding addSelector: #witnessInvoke2:with: withMethod: original.
	[
		Compiler compile: 'tryInvoke2: a with: b
			(descriptor first = ''vm:core'' and: [descriptor second beginsWith: ''core_bigint_''])
				ifTrue: [^false].
			^self witnessInvoke2: a with: b' in: FFIBinding.
		Smalltalk vm stderrWrite: 'begin portable bigint', (String with: Character lf).
		self fixedPortableResults.
		self production.
		Smalltalk vm stderrWrite: 'end portable bigint', (String with: Character lf).
		^true
	] ensure: [
		FFIBinding addSelector: #tryInvoke2:with: withMethod: original.
		FFIBinding removeSelector: #witnessInvoke2:with:]
!
fixedPortableResults
	| a b huge min max |
	a := 16r10000000000000000.
	b := a + 5.
	huge := a * a.
	min := SmallInteger minVal.
	max := SmallInteger maxVal.
	self checkOwned: max + 1 equals: 16r4000000000000000.
	self checkOwned: (max + 1) negated equals: min.
	self checkOwned: min negated equals: 16r4000000000000000.
	self assert: (a - a) == 0.
	self checkOwned: huge + 1 equals: 16r100000000000000000000000000000001.
	self assert: ((a * b + 7) quo: b) = a.
	self assert: ((a * b + 7) negated rem: b) == -7.
	self assert: ((a * b + 7) negated // b) = (a + 1) negated.
	self assert: ((a * b + 7) negated \\ b) = (b - 7).
	self assert: (-5 // b) == -1.
	self assert: ((1 portableBitShift: 200) negated bitOr: 17) = ((1 portableBitShift: 200) negated + 17).
	self assert: (b bitAnd: -1) = b.
	self assert: (b bitXor: b) == 0.
	self assert: ((b negated bitShift: -64) = -2).
	self assert: ((b negated bitShift: huge negated) = -1).
	self assert: (0 bitShift: huge) == 0.
	self assert: ([1 bitShift: huge. false] on: OutOfMemory do: [:e | true]).
	self assert: ([b quo: 0. false] on: ZeroDivide do: [:e | e dividend == b])
! !
