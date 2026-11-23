!LargeIntegerPrimitives methodsFor: 'owned magnitude transport'!
decodeMagnitude: p signedCount: signedCount into: x
	<var: #p type: 'const uint64_t *'>
	<var: #signedCount type: 'int64_t'>
	<var: #x type: 'LargeOperand *'>
	| count |
	x neg: signedCount < 0.
	count := x neg ifTrue: [0 - signedCount] ifFalse: [signedCount].
	p isNull
		ifTrue: [
			x small at: 0 put: count asUInt64.
			x limbs: x small.
			x count: (count = 0 ifTrue: [0] ifFalse: [1])]
		ifFalse: [
			x limbs: p.
			x count: count]
!
ownedLimbs: cap into: out
	"Only wrapper-local storage or one malloc. No VM scratch, global result, heap pointers or VM allocation."
	<function>
	<var: #cap type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'uint64_t *'>
	| p |
	(cap < 0 or: [cap asUInt64 > 16r1FFFFFFFFFFFFFFF]) ifTrue: [^self cCoerce: 0 to: 'uint64_t *'].
	cap <= 4 ifTrue: [^out small].
	p := self cCoerce: (libc malloc: cap asUInt64 * 8) to: 'uint64_t *'.
	out allocation: p.
	^p
!
ownedResult: data count: count negative: negative into: out
	<function>
	<var: #data type: 'const uint64_t *'>
	<var: #count type: 'int64_t'>
	<var: #negative type: 'bool'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	| n |
	n := count.
	[n > 0 and: [(data at: n - 1) = 0]] whileTrue: [n := n - 1].
	out data: data.
	out count: (negative ifTrue: [0 - n] ifFalse: [n]).
	out status: 0
!
magnitudeOperation: op left: left signedCount: an right: right signedCount: bn maxHeap: maxHeap into: out
	"Pure sign/magnitude operation, given trusted normalized spans and a heap size
	limit; callers own out, including completion of any allocation. Never dispatch
	a VM primitive, use VM scratch, hold OOPs or safepoint."
	<export>
	<var: #op type: 'int32_t'>
	<var: #left type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #right type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #maxHeap type: 'uint64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	| a b |
	out allocation: (self cCoerce: 0 to: 'uint64_t *').
	out status: PRIM_ERR_NO_MEMORY.
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	self decodeMagnitude: left signedCount: an into: a.
	self decodeMagnitude: right signedCount: bn into: b.
	op <= 21 ifTrue: [^self ownedAdd: a and: b subtract: op = 21 into: out].
	op = 22 ifTrue: [^self ownedMultiply: a and: b maxHeap: maxHeap into: out].
	op <= 26 ifTrue: [^self ownedDivide: a by: b mode: op - 23 into: out].
	op <= 30 ifTrue: [^self ownedBitOp: op - 27 on: a and: b into: out].
	self ownedShift: a by: b maxHeap: maxHeap into: out
! !

!LargeIntegerPrimitives methodsFor: 'owned arithmetic'!
ownedAdd: a and: b subtract: subtract into: out
	<function>
	<returns: 'void'>
	| aCount bCount bNeg r n |
	aCount := a count.
	bCount := b count.
	bNeg := b neg ~= subtract.
	r := self ownedLimbs: (aCount > bCount ifTrue: [aCount] ifFalse: [bCount]) + 1 into: out.
	r isNull ifTrue: [^self].
	a neg = bNeg ifTrue: [
		n := aCount >= bCount
			ifTrue: [self sum: a limbs count: aCount plus: b limbs count: bCount into: r]
			ifFalse: [self sum: b limbs count: bCount plus: a limbs count: aCount into: r].
		^self ownedResult: r count: n negative: a neg into: out].
	(self compare: a limbs count: aCount with: b limbs count: bCount) >= 0
		ifTrue: [self ownedResult: r count: (self difference: a limbs count: aCount minus: b limbs count: bCount into: r) negative: a neg into: out]
		ifFalse: [self ownedResult: r count: (self difference: b limbs count: bCount minus: a limbs count: aCount into: r) negative: bNeg into: out]
!
ownedMultiply: a and: b maxHeap: maxHeap into: out
	<function>
	<returns: 'void'>
	| n r |
	(a count = 0 or: [b count = 0]) ifTrue: [^self ownedResult: out small count: 0 negative: false into: out].
	n := a count + b count.
	(n * 8) asUInt64 > maxHeap ifTrue: [^self].
	r := self ownedLimbs: n into: out.
	r isNull ifTrue: [^self].
	a count <= b count
		ifTrue: [self product: a limbs count: a count times: b limbs count: b count into: r]
		ifFalse: [self product: b limbs count: b count times: a limbs count: a count into: r].
	self ownedResult: r count: n negative: a neg ~= b neg into: out
!
ownedDivide: a by: b mode: mode into: out
	<function>
	<returns: 'void'>
	| na nb w q rem qn rn neg floored |
	na := a count.
	nb := b count.
	nb = 0 ifTrue: [out status: 2. ^self].
	w := self ownedLimbs: 2 * (na + nb) + 4 into: out.
	w isNull ifTrue: [^self].
	q := w.
	rem := w + (na + 2).
	(self compare: a limbs count: na with: b limbs count: nb) < 0
		ifTrue: [
			q at: 0 put: 0.
			qn := 1.
			0 to: na - 1 do: [:i | rem at: i put: (a limbs at: i)].
			rn := na]
		ifFalse: [
			self divide: a limbs count: na by: b limbs count: nb quotient: q remainder: rem work: rem + nb.
			qn := na - nb + 1.
			rn := nb].
	neg := a neg ~= b neg.
	mode = 0 ifTrue: [^self ownedResult: q count: qn negative: neg into: out].
	mode = 1 ifTrue: [^self ownedResult: rem count: rn negative: a neg into: out].
	floored := neg and: [(self lowest: rem count: rn) < rn].
	mode = 2 ifTrue: [^self ownedResult: q count: (floored ifTrue: [self increment: q count: qn] ifFalse: [qn]) negative: neg into: out].
	floored ifTrue: [^self ownedResult: rem + nb count: (self difference: b limbs count: nb minus: rem count: rn into: rem + nb) negative: b neg into: out].
	self ownedResult: rem count: rn negative: a neg into: out
!
ownedBitOp: op on: a and: b into: out
	<function>
	<returns: 'void'>
	| n r za zb x y |
	n := (a count > b count ifTrue: [a count] ifFalse: [b count]) + 1.
	r := self ownedLimbs: n into: out.
	r isNull ifTrue: [^self].
	za := self lowest: a limbs count: a count.
	zb := self lowest: b limbs count: b count.
	0 to: n - 1 do: [:i |
		x := self limb: i of: a lowest: za.
		y := self limb: i of: b lowest: zb.
		r at: i put: (op = 1 ifTrue: [x bitAnd: y] ifFalse: [op = 2 ifTrue: [x bitOr: y] ifFalse: [x bitXor: y]])].
	((r at: n - 1) >> 63) = 0 ifTrue: [^self ownedResult: r count: n negative: false into: out].
	za := self lowest: r count: n.
	r at: za put: (0 - (r at: za)) asUInt64.
	za + 1 to: n - 1 do: [:i | r at: i put: (r at: i) bitInvert64].
	self ownedResult: r count: n negative: true into: out
!
ownedShift: a by: s maxHeap: maxHeap into: out
	<function>
	<returns: 'void'>
	| m k n r |
	m := s count = 0 ifTrue: [0 asUInt64] ifFalse: [s limbs at: 0].
	(s count > 1 or: [m > 16r10000000000]) ifTrue: [m := 16r10000000000 asUInt64].
	k := m asInt64.
	a count = 0 ifTrue: [^self ownedResult: out small count: 0 negative: false into: out].
	s neg ifFalse: [
		n := a count + (k quo: 64) + 1.
		(n * 8) asUInt64 > maxHeap ifTrue: [^self].
		r := self ownedLimbs: n into: out.
		r isNull ifTrue: [^self].
		self shift: a limbs count: a count left: k into: r.
		^self ownedResult: r count: n negative: a neg into: out].
	(k quo: 64) >= a count ifTrue: [
		out small at: 0 put: 1.
		^self ownedResult: out small count: (a neg ifTrue: [1] ifFalse: [0]) negative: a neg into: out].
	n := a count - (k quo: 64).
	r := self ownedLimbs: n + 1 into: out.
	r isNull ifTrue: [^self].
	((self shift: a limbs count: a count right: k into: r) and: [a neg]) ifTrue: [n := self increment: r count: n].
	self ownedResult: r count: n negative: a neg into: out
! !
