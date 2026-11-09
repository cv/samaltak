VMPrimitiveModule subclass: #LargeIntegerPrimitives
	instanceVariableNames: 'scratch scratchLimbs'
	classVariableNames: ''
	package: 'VM-Core'!

LargeIntegerPrimitives comment: 'Integer arithmetic beyond SmallIntegers, after Squeak''s LargeIntegersPlugin: add, subtract, compare, multiply (schoolbook), divide (Knuth''s algorithm D), shifts and two''s complement bit operations. Operands are SmallIntegers and LargePositive/NegativeIntegers, read as 32-bit limbs (a LargeInteger''s magnitude bytes are little-endian) with 64-bit intermediates. A result is computed into a scratch buffer kept between calls, then answered as a SmallInteger if it fits, else as a new LargeInteger without leading zero bytes. The primitives fail on other operands, on a zero divisor, and with PRIM_ERR_NO_MEMORY for results that can never fit the heap.'!

!LargeIntegerPrimitives class methodsFor: 'declaring'!
declarations
	^#((scratch 'uint32_t *') (scratchLimbs int64_t))
! !

!LargeIntegerPrimitives methodsFor: 'operands'!
operand: o into: x
	"x := the Integer o: its magnitude as limbs, least significant first (o's bytes, or x's own two for a SmallInteger), their number without leading zero limbs, and its sign (never negative for zero). False if o is no Integer."
	<function>
	| v m c p n |
	(self isInt: o) ifTrue: [
		v := self intVal: o.
		m := v < 0 ifTrue: [(0 - v) asUInt64] ifFalse: [v asUInt64].
		x small at: 0 put: m asUInt32.
		x small at: 1 put: (m >> 32) asUInt32.
		x limbs: x small.
		x count: (m = 0 ifTrue: [0] ifFalse: [(m >> 32) = 0 ifTrue: [1] ifFalse: [2]]).
		x neg: v < 0.
		^true].
	((self isPtr: o) and: [(self formatOf: o) >= F_BYTES]) ifFalse: [^false].
	c := self rawClass: o.
	(c = (memory special: SO_LARGEPOS) or: [c = (memory special: SO_LARGENEG)]) ifFalse: [^false].
	p := self words32Of: o.
	n := ((memory byteSize: o) + 3 quo: 4) asInt64.
	[n > 0 and: [(p at: n - 1) = 0]] whileTrue: [n := n - 1].
	x limbs: p.
	x count: n.
	x neg: (n > 0 and: [c = (memory special: SO_LARGENEG)]).
	^true
!
operands: a and: b
	"Fill a and b with the receiver and the argument; false if either is no Integer."
	^(self operand: self receiver into: a) and: [self operand: self arg0 into: b]
!
scratch: n
	"At least n limbs of scratch memory, kept for the next primitive; NULL if they cannot be had."
	<function>
	| cap |
	n > scratchLimbs ifTrue: [
		cap := n > (scratchLimbs * 2) ifTrue: [n] ifFalse: [scratchLimbs * 2].
		libc free: scratch.
		scratch := self cCoerce: (libc malloc: cap asUInt64 * 4) to: 'uint32_t *'.
		scratchLimbs := scratch isNull ifTrue: [0] ifFalse: [cap]].
	^scratch
!
fits: n
	"Whether a result of n limbs could fit the heap."
	^n * 4 <= gc maxHeapBytes asInt64
!
answer: r count: n negative: neg
	"Answer the Integer with the magnitude r (n limbs) and sign neg: a SmallInteger if it fits, else a new LargeInteger without leading zero bytes."
	<function>
	| k m top bytes o |
	k := n.
	[k > 0 and: [(r at: k - 1) = 0]] whileTrue: [k := k - 1].
	k <= 2 ifTrue: [
		m := k = 0 ifTrue: [0 asUInt64] ifFalse: [k = 1 ifTrue: [(r at: 0) asUInt64] ifFalse: [((r at: 1) asUInt64 << 32) bitOr: (r at: 0)]].
		m <= (neg ifTrue: [VM_INT_MAX asUInt64 + 1] ifFalse: [VM_INT_MAX asUInt64]) ifTrue: [
			^self answer: (self intOop: (neg ifTrue: [(0 - m) asInt64] ifFalse: [m asInt64]))]].
	top := r at: k - 1.
	bytes := (k - 1) * 4 + (top > 16rFFFFFF ifTrue: [4] ifFalse: [top > 16rFFFF ifTrue: [3] ifFalse: [top > 16rFF ifTrue: [2] ifFalse: [1]]]).
	o := memory
		allocObjTry: (memory special: (neg ifTrue: [SO_LARGENEG] ifFalse: [SO_LARGEPOS]))
		format: F_BYTES + ((8 - (bytes rem: 8)) rem: 8) asInt32
		slots: (bytes + 7 quo: 8) asUInt64.
	o = 0 ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	libc memcpy: (self bytesOf: o) from: r size: bytes asUInt64.
	self answer: o
! !

!LargeIntegerPrimitives methodsFor: 'magnitudes'!
compare: a count: na with: b count: nb
	"-1, 0 or 1: the magnitude a against b (no leading zero limbs)."
	<function>
	| i |
	na ~= nb ifTrue: [^na < nb ifTrue: [-1] ifFalse: [1]].
	i := na - 1.
	[i >= 0 and: [(a at: i) = (b at: i)]] whileTrue: [i := i - 1].
	i < 0 ifTrue: [^0].
	^(a at: i) < (b at: i) ifTrue: [-1] ifFalse: [1]
!
sum: a count: na plus: b count: nb into: r
	"r := a + b (na >= nb); answer its limbs (na + 1 at most)."
	<function>
	| carry t |
	carry := 0 asUInt64.
	0 to: nb - 1 do: [:i |
		t := (a at: i) asUInt64 + (b at: i) + carry.
		r at: i put: t asUInt32.
		carry := t >> 32].
	nb to: na - 1 do: [:i |
		t := (a at: i) asUInt64 + carry.
		r at: i put: t asUInt32.
		carry := t >> 32].
	r at: na put: carry asUInt32.
	^na + 1
!
difference: a count: na minus: b count: nb into: r
	"r := a - b (a >= b, na >= nb); answer its limbs (na at most)."
	<function>
	| borrow t |
	borrow := 0.
	0 to: nb - 1 do: [:i |
		t := (a at: i) asInt64 - (b at: i) asInt64 - borrow.
		r at: i put: t asUInt32.
		borrow := t < 0 ifTrue: [1] ifFalse: [0]].
	nb to: na - 1 do: [:i |
		t := (a at: i) asInt64 - borrow.
		r at: i put: t asUInt32.
		borrow := t < 0 ifTrue: [1] ifFalse: [0]].
	^na
!
product: a count: na times: b count: nb into: r
	"r (na + nb limbs) := a * b, schoolbook: a row per limb of a, so a short a makes few passes over b; the first row writes r, the others add to it."
	<function>
	| ai carry t |
	0 to: na - 1 do: [:i |
		ai := (a at: i) asUInt64.
		carry := 0 asUInt64.
		0 to: nb - 1 do: [:j |
			t := ai * (b at: j) + carry.
			i > 0 ifTrue: [t := t + (r at: i + j)].
			r at: i + j put: t asUInt32.
			carry := t >> 32].
		r at: i + nb put: carry asUInt32]
!
divide: a count: na by: b count: nb quotient: q remainder: r work: w
	"q (na - nb + 1 limbs) := a quo: b and r (nb limbs) := a rem: b, for a >= b > 0 without leading zero limbs: short division by one limb, else Knuth's algorithm D (TAOCP 4.3.1) on copies shifted so that the divisor's top bit is set (w: na + nb + 2 limbs)."
	<function>
	| d rem t s un vn vTop vNext num qhat rhat carry borrow p diff |
	nb = 1 ifTrue: [
		d := (b at: 0) asUInt64.
		rem := 0 asUInt64.
		na - 1 to: 0 by: -1 do: [:i |
			t := (rem << 32) bitOr: (a at: i).
			q at: i put: (t quo: d) asUInt32.
			rem := t rem: d].
		r at: 0 put: rem asUInt32.
		^self].
	s := self leadingZeros: (b at: nb - 1).
	un := w.
	vn := w + (na + 1).
	self shift: a count: na left: s into: un.
	self shift: b count: nb left: s into: vn.
	vTop := (vn at: nb - 1) asUInt64.
	vNext := (vn at: nb - 2) asUInt64.
	na - nb to: 0 by: -1 do: [:j |
		"estimate the quotient limb from the top two limbs, at most 2 too large; correct it with the next limb"
		num := ((un at: j + nb) asUInt64 << 32) bitOr: (un at: j + nb - 1).
		qhat := num quo: vTop.
		rhat := num rem: vTop.
		[rhat <= 16rFFFFFFFF and: [qhat > 16rFFFFFFFF or: [qhat * vNext > ((rhat << 32) bitOr: (un at: j + nb - 2))]]] whileTrue: [
			qhat := qhat - 1.
			rhat := rhat + vTop].
		"un[j .. j + nb] -= qhat * vn"
		carry := 0 asUInt64.
		borrow := 0.
		0 to: nb - 1 do: [:i |
			p := qhat * (vn at: i) + carry.
			carry := p >> 32.
			diff := (un at: i + j) asInt64 - (p bitAnd: 16rFFFFFFFF) asInt64 - borrow.
			un at: i + j put: diff asUInt32.
			borrow := diff < 0 ifTrue: [1] ifFalse: [0]].
		diff := (un at: j + nb) asInt64 - carry asInt64 - borrow.
		un at: j + nb put: diff asUInt32.
		diff < 0 ifTrue: [
			"rarely, qhat was still one too large: add vn back"
			qhat := qhat - 1.
			carry := 0 asUInt64.
			0 to: nb - 1 do: [:i |
				p := (un at: i + j) asUInt64 + (vn at: i) + carry.
				un at: i + j put: p asUInt32.
				carry := p >> 32].
			un at: j + nb put: ((un at: j + nb) asUInt64 + carry) asUInt32].
		q at: j put: qhat asUInt32].
	0 to: nb - 1 do: [:i |
		r at: i put: (((un at: i) asUInt64 >> s) bitOr: (un at: i + 1) asUInt64 << (32 - s)) asUInt32]
!
leadingZeros: x
	"The number of leading zero bits of the nonzero 32-bit x."
	| v n |
	v := x asUInt64.
	n := 0.
	[(v bitAnd: 16r80000000) = 0] whileTrue: [
		v := v << 1.
		n := n + 1].
	^n
!
shift: x count: n left: k into: r
	"r (n + (k quo: 32) + 1 limbs) := x << k."
	<function>
	| limbs bits carry t |
	limbs := k quo: 32.
	bits := k rem: 32.
	0 to: limbs - 1 do: [:i | r at: i put: 0].
	carry := 0 asUInt64.
	0 to: n - 1 do: [:i |
		t := ((x at: i) asUInt64 << bits) bitOr: carry.
		r at: limbs + i put: t asUInt32.
		carry := t >> 32].
	r at: limbs + n put: carry asUInt32
!
shift: x count: n right: k into: r
	"r (n - (k quo: 32) limbs, k < 32 n) := x >> k; answer whether 1 bits were shifted out."
	<function>
	| limbs bits lost next |
	limbs := k quo: 32.
	bits := k rem: 32.
	lost := ((x at: limbs) asUInt64 << (32 - bits)) asUInt32 ~= 0.
	0 to: limbs - 1 do: [:i | (x at: i) ~= 0 ifTrue: [lost := true]].
	limbs to: n - 1 do: [:i |
		next := i + 1 < n ifTrue: [(x at: i + 1) asUInt64] ifFalse: [0 asUInt64].
		r at: i - limbs put: (((x at: i) asUInt64 >> bits) bitOr: next << (32 - bits)) asUInt32].
	^lost
!
increment: x count: n
	"x := x + 1 (room for n + 1 limbs); answer its limbs."
	<function>
	| i |
	i := 0.
	[i < n and: [(x at: i) = 16rFFFFFFFF]] whileTrue: [
		x at: i put: 0.
		i := i + 1].
	i = n ifTrue: [
		x at: n put: 1.
		^n + 1].
	x at: i put: (x at: i) + 1.
	^n
!
lowest: x count: n
	"The index of x's lowest nonzero limb; n if there is none."
	<function>
	| i |
	i := 0.
	[i < n and: [(x at: i) = 0]] whileTrue: [i := i + 1].
	^i
!
limb: i of: x lowest: z
	"Limb i of x in two's complement (z: the index of x's lowest nonzero limb): for a negative x, ~(|x| - 1)."
	<function>
	| v |
	v := i < x count ifTrue: [x limbs at: i] ifFalse: [0 asUInt32].
	x neg ifFalse: [^v].
	i < z ifTrue: [^0 asUInt32].
	i = z ifTrue: [^(0 - v asUInt64) asUInt32].
	^v bitInvert32
! !

!LargeIntegerPrimitives methodsFor: 'operations'!
add: subtract
	"The receiver plus the argument (minus it if subtract): magnitudes added if the signs agree, else the smaller subtracted from the larger."
	<function>
	| a b bneg r n |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	bneg := b neg ~= subtract.
	r := self scratch: (a count > b count ifTrue: [a count] ifFalse: [b count]) + 1.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	a neg = bneg ifTrue: [
		n := a count >= b count
			ifTrue: [self sum: a limbs count: a count plus: b limbs count: b count into: r]
			ifFalse: [self sum: b limbs count: b count plus: a limbs count: a count into: r].
		^self answer: r count: n negative: a neg].
	(self compare: a limbs count: a count with: b limbs count: b count) >= 0
		ifTrue: [self answer: r count: (self difference: a limbs count: a count minus: b limbs count: b count into: r) negative: a neg]
		ifFalse: [self answer: r count: (self difference: b limbs count: b count minus: a limbs count: a count into: r) negative: bneg]
!
divide: mode
	"The receiver divided by the argument: mode 0 quo:, 1 rem: (truncated), 2 //, 3 \\ (floored). Fails on a zero divisor."
	<function>
	| a b na nb w q rem qn rn neg floored |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	na := a count.
	nb := b count.
	nb = 0 ifTrue: [^self fail].
	w := self scratch: 2 * (na + nb) + 4.
	w isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	"q: na + 2 limbs, rem: nb, then the work area of na + nb + 2"
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
	mode = 0 ifTrue: [^self answer: q count: qn negative: neg].
	mode = 1 ifTrue: [^self answer: rem count: rn negative: a neg].
	"floored: with differing signs and a remainder, the quotient is one less and the remainder the divisor's complement"
	floored := neg and: [(self lowest: rem count: rn) < rn].
	mode = 2 ifTrue: [^self answer: q count: (floored ifTrue: [self increment: q count: qn] ifFalse: [qn]) negative: neg].
	floored ifTrue: [^self answer: rem + nb count: (self difference: b limbs count: nb minus: rem count: rn into: rem + nb) negative: b neg].
	self answer: rem count: rn negative: a neg
!
bitOp: op
	"The receiver op the argument in two's complement (op 1 bitAnd:, 2 bitOr:, 3 bitXor:), on one more limb than the longer magnitude, so that the top limb holds the sign."
	<function>
	| a b n r za zb x y |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	n := (a count > b count ifTrue: [a count] ifFalse: [b count]) + 1.
	r := self scratch: n.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	za := self lowest: a limbs count: a count.
	zb := self lowest: b limbs count: b count.
	0 to: n - 1 do: [:i |
		x := self limb: i of: a lowest: za.
		y := self limb: i of: b lowest: zb.
		r at: i put: (op = 1 ifTrue: [x bitAnd: y] ifFalse: [op = 2 ifTrue: [x bitOr: y] ifFalse: [x bitXor: y]])].
	((r at: n - 1) >> 31) = 0 ifTrue: [^self answer: r count: n negative: false].
	"negative: the magnitude is the two's complement of r"
	za := self lowest: r count: n.
	r at: za put: (0 - (r at: za) asUInt64) asUInt32.
	za + 1 to: n - 1 do: [:i | r at: i put: (r at: i) bitInvert32].
	self answer: r count: n negative: true
! !

!LargeIntegerPrimitives methodsFor: 'primitives'!
primLargeAdd
	<vmPrimitive: 20 name: 'largeAdd'>
	self add: false
!
primLargeSub
	<vmPrimitive: 21 name: 'largeSub'>
	self add: true
!
primLargeMul
	<vmPrimitive: 22 name: 'largeMul'>
	| a b n r |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	(a count = 0 or: [b count = 0]) ifTrue: [^self answer: (self intOop: 0)].
	n := a count + b count.
	(self fits: n) ifFalse: [^self failCode: PRIM_ERR_NO_MEMORY].
	r := self scratch: n.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	a count <= b count
		ifTrue: [self product: a limbs count: a count times: b limbs count: b count into: r]
		ifFalse: [self product: b limbs count: b count times: a limbs count: a count into: r].
	self answer: r count: n negative: a neg ~= b neg
!
primLargeQuo
	<vmPrimitive: 23 name: 'largeQuo'>
	self divide: 0
!
primLargeRem
	<vmPrimitive: 24 name: 'largeRem'>
	self divide: 1
!
primLargeFloorDiv
	<vmPrimitive: 25 name: 'largeFloorDiv'>
	self divide: 2
!
primLargeMod
	<vmPrimitive: 26 name: 'largeMod'>
	self divide: 3
!
primLargeCompare
	"-1, 0 or 1: the receiver compared with the argument."
	<vmPrimitive: 27 name: 'largeCompare'>
	<leaf>
	| a b c |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	a neg ~= b neg ifTrue: [^self answer: (self intOop: (a neg ifTrue: [-1] ifFalse: [1]))].
	c := self compare: a limbs count: a count with: b limbs count: b count.
	self answer: (self intOop: (a neg ifTrue: [0 - c] ifFalse: [c]))
!
primLargeBitAnd
	<vmPrimitive: 28 name: 'largeBitAnd'>
	self bitOp: 1
!
primLargeBitOr
	<vmPrimitive: 29 name: 'largeBitOr'>
	self bitOp: 2
!
primLargeBitXor
	<vmPrimitive: 30 name: 'largeBitXor'>
	self bitOp: 3
!
primLargeBitShift
	"Left for a positive argument; right for a negative one, rounding toward negative infinity: a negative magnitude that loses 1 bits gains one. Shifts beyond 2^40 bits never fit the heap (left) or leave nothing (right)."
	<vmPrimitive: 31 name: 'largeBitShift'>
	| a s m k n r |
	a := self local: 'LargeOperand'.
	s := self local: 'LargeOperand'.
	(self operands: a and: s) ifFalse: [^self fail].
	m := s count = 0 ifTrue: [0 asUInt64] ifFalse: [s count = 1 ifTrue: [(s limbs at: 0) asUInt64] ifFalse: [((s limbs at: 1) asUInt64 << 32) bitOr: (s limbs at: 0)]].
	(s count > 2 or: [m > 16r10000000000]) ifTrue: [m := 16r10000000000 asUInt64].
	k := m asInt64.
	a count = 0 ifTrue: [^self answer: (self intOop: 0)].
	s neg ifFalse: [
		n := a count + (k quo: 32) + 1.
		(self fits: n) ifFalse: [^self failCode: PRIM_ERR_NO_MEMORY].
		r := self scratch: n.
		r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
		self shift: a limbs count: a count left: k into: r.
		^self answer: r count: n negative: a neg].
	(k quo: 32) >= a count ifTrue: [^self answer: (self intOop: (a neg ifTrue: [-1] ifFalse: [0]))].
	n := a count - (k quo: 32).
	r := self scratch: n + 1.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	((self shift: a limbs count: a count right: k into: r) and: [a neg]) ifTrue: [n := self increment: r count: n].
	self answer: r count: n negative: a neg
! !

VMStruct subclass: #LargeOperand
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

LargeOperand comment: 'An Integer operand of LargeIntegerPrimitives: its magnitude as count 32-bit limbs at limbs (least significant first; small holds them for a SmallInteger) and its sign.'!

!LargeOperand class methodsFor: 'declaring'!
fields
	^#((limbs 'uint32_t *') (count int64_t) (neg bool) (small 'uint32_t[2]'))
! !
