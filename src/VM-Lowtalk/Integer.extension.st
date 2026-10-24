!Integer methodsFor: '*VM-Lowtalk'!
asInt8
	"Lowtalk: the C cast (int8_t)."
	^self wrapBits: 8 signed: true
!
asUInt8
	^self wrapBits: 8 signed: false
!
asInt16
	^self wrapBits: 16 signed: true
!
asUInt16
	^self wrapBits: 16 signed: false
!
asInt32
	^self wrapBits: 32 signed: true
!
asUInt32
	^self wrapBits: 32 signed: false
!
asInt64
	^self wrapBits: 64 signed: true
!
asUInt64
	^self wrapBits: 64 signed: false
!
wrapBits: n signed: aBoolean
	| v |
	(self class == SmallInteger and: [self >= 0 and: [n >= 63 or: [self < (1 bitShift: (aBoolean ifTrue: [n - 1] ifFalse: [n]))]]]) ifTrue: [^self].
	v := self bitAnd: (1 bitShift: n) - 1.
	(aBoolean and: [v >= (1 bitShift: n - 1)]) ifTrue: [v := v - (1 bitShift: n)].
	^v
!
bitInvert64
	"Lowtalk: ~x on a uint64_t."
	^self bitXor: 16rFFFFFFFFFFFFFFFF
!
bitInvert32
	^self bitXor: 16rFFFFFFFF
!
ifNoOverflowAdd: anInteger do: aBlock
	"Lowtalk: if self + anInteger fits int64_t, evaluate aBlock with it (__builtin_add_overflow)."
	^self ifInt64: self + anInteger do: aBlock
!
ifNoOverflowSub: anInteger do: aBlock
	^self ifInt64: self - anInteger do: aBlock
!
ifNoOverflowMul: anInteger do: aBlock
	^self ifInt64: self * anInteger do: aBlock
!
ifInt64: anInteger do: aBlock
	(anInteger >= -16r8000000000000000 and: [anInteger <= 16r7FFFFFFFFFFFFFFF]) ifTrue: [aBlock value: anInteger].
	^nil
!
isNull
	"Lowtalk: a pointer held as an address."
	^self = 0
!
notNull
	^self ~= 0
!
simulatedAddressIn: aMemory
	^self
! !
