!Integer methodsFor: 'candidate owned integer results'!
ffiCandidateAdd: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_add' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self + operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #+; signal].
	^result
!
ffiCandidateSubtract: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_sub' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self - operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #-; signal].
	^result
!
ffiCandidateMultiply: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_mul' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self * operand].
	result == nil ifTrue: [^OutOfMemory signalForClass: LargePositiveInteger size: self digitLength + operand digitLength].
	^result
!
ffiCandidateQuo: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_quo' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self quo: operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #quo:; signal].
	result == true ifTrue: [^ZeroDivide new dividend: self; signal].
	^result
!
ffiCandidateRem: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_rem' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self rem: operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #rem:; signal].
	result == true ifTrue: [^ZeroDivide new dividend: self; signal].
	^result
!
ffiCandidateFloorDivide: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_floordiv' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self // operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #//; signal].
	result == true ifTrue: [^ZeroDivide new dividend: self; signal].
	^result
!
ffiCandidateModulo: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_mod' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self \\ operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #\\; signal].
	result == true ifTrue: [^ZeroDivide new dividend: self; signal].
	^result
!
ffiCandidateBitAnd: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_bitand' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self bitAnd: operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #bitAnd:; signal].
	^result
!
ffiCandidateBitOr: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_bitor' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self bitOr: operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #bitOr:; signal].
	^result
!
ffiCandidateBitXor: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_bitxor' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self bitXor: operand].
	result == nil ifTrue: [^PrimitiveFailed new selector: #bitXor:; signal].
	^result
!
ffiCandidateBitShift: operand
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_bigint_bitshift' (integerMagnitude integerMagnitude) ownedIntegerMagnitude))
		tryInvoke2: self with: operand.
	result == false ifTrue: [^self bitShift: operand].
	result == nil ifTrue: [^OutOfMemory signalForClass: LargePositiveInteger size: self digitLength + (operand // 8)].
	^result
! !
