VMPrimitiveModule subclass: #NumericPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

NumericPrimitives comment: 'SmallInteger, Float and Character primitives. SmallInteger primitives fail on non-SmallInteger arguments or overflow; Float primitives take SmallFloat64 and BoxedFloat64 receivers and also SmallInteger arguments.'!

!NumericPrimitives methodsFor: 'helpers'!
intArgsDo: aBlock
	| ro ao |
	ro := self receiver.
	ao := self arg0.
	((self isInt: ro) and: [self isInt: ao]) ifFalse: [^self fail].
	aBlock value: (self intVal: ro) value: (self intVal: ao)
!
floatReceiverDo: aBlock
	| ro |
	ro := self receiver.
	(memory isFloat: ro) ifFalse: [^self fail].
	aBlock value: (memory floatVal: ro)
!
floatArgsDo: aBlock
	| ro bo |
	ro := self receiver.
	(memory isFloat: ro) ifFalse: [^self fail].
	self argCount < 1 ifTrue: [^self fail].
	bo := self arg: 0.
	((memory isFloat: bo) or: [self isInt: bo]) ifFalse: [^self fail].
	aBlock value: (memory floatVal: ro) value: ((self isInt: bo) ifTrue: [(self intVal: bo) asFloat] ifFalse: [memory floatVal: bo])
!
isFinite: d
	^d - d = 0.0
! !

!NumericPrimitives methodsFor: 'SmallInteger'!
primIntAdd
	<vmPrimitive: 1 name: 'intAdd'>
	<leaf>
	self intArgsDo: [:a :b | self answerInt: a + b]
!
primIntSub
	<vmPrimitive: 2 name: 'intSub'>
	<leaf>
	self intArgsDo: [:a :b | self answerInt: a - b]
!
primIntLess
	<vmPrimitive: 3 name: 'intLess'>
	<leaf>
	self intArgsDo: [:a :b | self answerBool: a < b]
!
primIntGreater
	<vmPrimitive: 4 name: 'intGreater'>
	<leaf>
	self intArgsDo: [:a :b | self answerBool: a > b]
!
primIntLessEq
	<vmPrimitive: 5 name: 'intLessEq'>
	<leaf>
	self intArgsDo: [:a :b | self answerBool: a <= b]
!
primIntGreaterEq
	<vmPrimitive: 6 name: 'intGreaterEq'>
	<leaf>
	self intArgsDo: [:a :b | self answerBool: a >= b]
!
primIntEq
	<vmPrimitive: 7 name: 'intEq'>
	<leaf>
	self intArgsDo: [:a :b | self answerBool: a = b]
!
primIntNotEq
	<vmPrimitive: 8 name: 'intNotEq'>
	<leaf>
	self intArgsDo: [:a :b | self answerBool: a ~= b]
!
primIntMul
	<vmPrimitive: 9 name: 'intMul'>
	<leaf>
	self intArgsDo: [:a :b |
		a ifNoOverflowMul: b do: [:r | ^self answerInt: r].
		self fail]
!
primIntDiv
	<vmPrimitive: 10 name: 'intDiv'>
	<leaf>
	self intArgsDo: [:a :b |
		(b = 0 or: [(a rem: b) ~= 0]) ifTrue: [^self fail].
		self answerInt: (a quo: b)]
!
primIntMod
	<vmPrimitive: 11 name: 'intMod'>
	<leaf>
	| r |
	self intArgsDo: [:a :b |
		b = 0 ifTrue: [^self fail].
		r := a rem: b.
		(r ~= 0 and: [(r < 0) ~= (b < 0)]) ifTrue: [r := r + b].
		self answerInt: r]
!
primIntFloorDiv
	<vmPrimitive: 12 name: 'intFloorDiv'>
	<leaf>
	| q |
	self intArgsDo: [:a :b |
		b = 0 ifTrue: [^self fail].
		q := a quo: b.
		((a rem: b) ~= 0 and: [(a < 0) ~= (b < 0)]) ifTrue: [q := q - 1].
		self answerInt: q]
!
primIntQuo
	<vmPrimitive: 13 name: 'intQuo'>
	<leaf>
	self intArgsDo: [:a :b |
		b = 0 ifTrue: [^self fail].
		self answerInt: (a quo: b)]
!
primIntBitAnd
	<vmPrimitive: 14 name: 'intBitAnd'>
	<leaf>
	self intArgsDo: [:a :b | self answerInt: (a bitAnd: b)]
!
primIntBitOr
	<vmPrimitive: 15 name: 'intBitOr'>
	<leaf>
	self intArgsDo: [:a :b | self answerInt: (a bitOr: b)]
!
primIntBitXor
	<vmPrimitive: 16 name: 'intBitXor'>
	<leaf>
	self intArgsDo: [:a :b | self answerInt: (a bitXor: b)]
!
primIntBitShift
	<vmPrimitive: 17 name: 'intBitShift'>
	<leaf>
	| r |
	self intArgsDo: [:a :b |
		b >= 0
			ifTrue: [
				a = 0 ifTrue: [^self answerInt: 0].
				b >= 62 ifTrue: [^self fail].
				r := (a asUInt64 << b) asInt64.
				(r >> b) ~= a ifTrue: [^self fail].
				self answerInt: r]
			ifFalse: [self answerInt: (b <= -63 ifTrue: [a < 0 ifTrue: [-1] ifFalse: [0]] ifFalse: [a >> b negated])]]
!
primIntRem
	<vmPrimitive: 18 name: 'intRem'>
	<leaf>
	self intArgsDo: [:a :b |
		b = 0 ifTrue: [^self fail].
		self answerInt: (a rem: b)]
!
primIntAsFloat
	<vmPrimitive: 19 name: 'intAsFloat'>
	| r |
	r := self receiver.
	(self isInt: r) ifFalse: [^self fail].
	self answerFloat: (self intVal: r) asFloat
! !

!NumericPrimitives methodsFor: 'Float'!
primFloatAdd
	<vmPrimitive: 41 name: 'floatAdd'>
	self floatArgsDo: [:a :b | self answerFloat: a + b]
!
primFloatSub
	<vmPrimitive: 42 name: 'floatSub'>
	self floatArgsDo: [:a :b | self answerFloat: a - b]
!
primFloatLess
	<vmPrimitive: 43 name: 'floatLess'>
	self floatArgsDo: [:a :b | self answerBool: a < b]
!
primFloatGreater
	<vmPrimitive: 44 name: 'floatGreater'>
	self floatArgsDo: [:a :b | self answerBool: a > b]
!
primFloatLessEq
	<vmPrimitive: 45 name: 'floatLessEq'>
	self floatArgsDo: [:a :b | self answerBool: a <= b]
!
primFloatGreaterEq
	<vmPrimitive: 46 name: 'floatGreaterEq'>
	self floatArgsDo: [:a :b | self answerBool: a >= b]
!
primFloatEq
	<vmPrimitive: 47 name: 'floatEq'>
	self floatArgsDo: [:a :b | self answerBool: a = b]
!
primFloatNotEq
	<vmPrimitive: 48 name: 'floatNotEq'>
	self floatArgsDo: [:a :b | self answerBool: a ~= b]
!
primFloatMul
	<vmPrimitive: 49 name: 'floatMul'>
	self floatArgsDo: [:a :b | self answerFloat: a * b]
!
primFloatDiv
	<vmPrimitive: 50 name: 'floatDiv'>
	self floatArgsDo: [:a :b |
		b = 0.0 ifTrue: [^self fail].
		self answerFloat: a / b]
!
primFloatTruncated
	<vmPrimitive: 51 name: 'floatTruncated'>
	<leaf>
	| t |
	self floatReceiverDo: [:a |
		t := libm trunc: a.
		(t >= -4611686018427387904.0 and: [t < 4611686018427387904.0]) ifFalse: [^self fail].
		self answer: (self intOop: t truncated)]
!
primFloatFractionPart
	<vmPrimitive: 52 name: 'floatFractionPart'>
	| ip |
	ip := self local: 'double'.
	self floatReceiverDo: [:a | self answerFloat: (libm modf: a integralPart: ip)]
!
primFloatExponent
	<vmPrimitive: 53 name: 'floatExponent'>
	self floatReceiverDo: [:a |
		(a = 0.0 or: [(self isFinite: a) not]) ifTrue: [^self answer: (self intOop: 0)].
		self answer: (self intOop: (libm ilogb: a))]
!
primFloatTimesTwoPower
	<vmPrimitive: 54 name: 'floatTimesTwoPower'>
	| e n |
	self floatReceiverDo: [:a |
		e := self arg0.
		(self isInt: e) ifFalse: [^self fail].
		n := self intVal: e.
		n > 100000 ifTrue: [n := 100000].
		n < -100000 ifTrue: [n := -100000].
		self answerFloat: (libm ldexp: a exponent: n asInt32)]
!
primFloatSqrt
	<vmPrimitive: 55 name: 'floatSqrt'>
	self floatReceiverDo: [:a | self answerFloat: (libm sqrt: a)]
!
primFloatSin
	<vmPrimitive: 56 name: 'floatSin'>
	self floatReceiverDo: [:a | self answerFloat: (libm sin: a)]
!
primFloatCos
	<vmPrimitive: 57 name: 'floatCos'>
	self floatReceiverDo: [:a | self answerFloat: (libm cos: a)]
!
primFloatArcTan
	<vmPrimitive: 58 name: 'floatArcTan'>
	self floatReceiverDo: [:a | self answerFloat: (libm atan: a)]
!
primFloatLn
	<vmPrimitive: 59 name: 'floatLn'>
	self floatReceiverDo: [:a | self answerFloat: (libm log: a)]
!
primFloatExp
	<vmPrimitive: 60 name: 'floatExp'>
	self floatReceiverDo: [:a | self answerFloat: (libm exp: a)]
!
primFloatPrintString
	"Shortest round-trip decimal: 123.0, 0.1, 1.0e-10, -2.5e100, inf, -inf, nan."
	<vmPrimitive: 61 name: 'floatPrintString'>
	self floatReceiverDo: [:a | self answer: (self printStringOf: a)]
!
printStringOf: a
	<function>
	| out |
	out := self local: 'char[64]'.
	a ~= a ifTrue: [^memory stringFromUtf8: 'nan' size: 3].
	(self isFinite: a) ifFalse: [^a < 0.0 ifTrue: [memory stringFromUtf8: '-inf' size: 4] ifFalse: [memory stringFromUtf8: 'inf' size: 3]].
	a = 0.0 ifTrue: [^((self bitsOfDouble: a) >> 63) ~= 0 ifTrue: [memory stringFromUtf8: '-0.0' size: 4] ifFalse: [memory stringFromUtf8: '0.0' size: 3]].
	self finiteFloatDecimal: a in: out.
	^memory stringFromUtf8: out size: (libc strlen: out)
!
primFloatAsIEEEBits
	<vmPrimitive: 62 name: 'floatAsIEEEBits'>
	| b |
	self floatReceiverDo: [:a |
		b := self bitsOfDouble: a.
		self answer: (b <= VM_INT_MAX asUInt64
			ifTrue: [self intOop: b asInt64]
			ifFalse: [memory largeIntFrom: b negative: false])]
!
primFloatFromIEEEBits
	<vmPrimitive: 63 name: 'floatFromIEEEBits'>
	| b |
	b := self local: 'uint64_t'.
	(self argCount < 1 or: [(memory u64Of: (self arg: 0) into: b) not]) ifTrue: [^self fail].
	self answerFloat: (self doubleFromBits: b value)
!
primFloatAbs
	<vmPrimitive: 64 name: 'floatAbs'>
	self floatReceiverDo: [:a | self answerFloat: (libm fabs: a)]
!
primFloatHash
	"Float>>hash: NaN and the infinities answer constants, other non-integral values murmur3's fmix64 of their bits, the low 30 bits; integral values fail."
	<vmPrimitive: 65 name: 'floatHash'>
	<leaf>
	| h |
	self floatReceiverDo: [:a |
		(self isFinite: a) ifFalse: [
			a = a ifFalse: [^self answer: (self intOop: 16r7FF8)].
			^self answer: (self intOop: (a > 0.0 ifTrue: [16r7FF0] ifFalse: [-16r7FF0]))].
		(libm trunc: a) = a ifTrue: [^self fail].
		h := self bitsOfDouble: a.
		h := h bitXor: h >> 33.
		h := (h * 16rFF51AFD7ED558CCD) asUInt64.
		h := h bitXor: h >> 33.
		h := (h * 16rC4CEB9FE1A85EC53) asUInt64.
		h := h bitXor: h >> 33.
		self answer: (self intOop: (h bitAnd: 16r3FFFFFFF) asInt64)]
! !

!NumericPrimitives methodsFor: 'Character'!
primCharValue
	<vmPrimitive: 90 name: 'charValue'>
	<leaf>
	| r |
	r := self receiver.
	(self isChar: r) ifFalse: [^self fail].
	self answer: (self intOop: (self charVal: r))
!
primCharFromValue
	<vmPrimitive: 91 name: 'charFromValue'>
	| v |
	v := self arg0.
	((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= CHAR_VALUE_MAX]]) ifFalse: [^self fail].
	self answer: (self charOop: (self intVal: v) asUInt32)
! !
