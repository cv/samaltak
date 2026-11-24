VMPrimitiveModule subclass: #LargeIntegerPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

LargeIntegerPrimitives comment: 'The native Integer magnitude kernel: 64-bit limbs with 128-bit intermediates, schoolbook multiplication and Knuth division. Callers own the result and scratch storage.'!

!LargeIntegerPrimitives methodsFor: 'magnitudes'!
sum: a count: na plus: b count: nb into: r
	"r := a + b (na >= nb); answer its limbs (na + 1 at most)."
	<function>
	<var: #a type: 'const uint64_t *'>
	<var: #b type: 'const uint64_t *'>
	<var: #carry type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	<var: #u type: 'uint64_t'>
	| carry x t u |
	carry := 0.
	0 to: nb - 1 do: [:i |
		x := a at: i.
		t := (x + (b at: i)) asUInt64.
		u := (t + carry) asUInt64.
		carry := (t < x or: [u < t]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64].
		r at: i put: u].
	nb to: na - 1 do: [:i |
		x := a at: i.
		u := (x + carry) asUInt64.
		carry := u < x ifTrue: [1 asUInt64] ifFalse: [0 asUInt64].
		r at: i put: u].
	r at: na put: carry.
	^na + 1
!
difference: a count: na minus: b count: nb into: r
	"r := a - b (a >= b, na >= nb); answer its limbs (na at most)."
	<function>
	<var: #a type: 'const uint64_t *'>
	<var: #b type: 'const uint64_t *'>
	<var: #borrow type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<var: #y type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	| borrow x y t |
	borrow := 0.
	0 to: nb - 1 do: [:i |
		x := a at: i.
		y := b at: i.
		t := (x - y) asUInt64.
		r at: i put: (t - borrow) asUInt64.
		borrow := (x < y or: [t < borrow]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
	nb to: na - 1 do: [:i |
		x := a at: i.
		r at: i put: (x - borrow) asUInt64.
		borrow := x < borrow ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
	^na
!
product: a count: na times: b count: nb into: r
	"r (na + nb limbs) := a * b, schoolbook: a row per limb of a (na >= 1), so a short a makes few passes over b; the first row writes r, the others add to it; each step a 64 x 64 bit product with what it adds (mul64:by:plus:plus:high:)."
	<function>
	<var: #a type: 'const uint64_t *'>
	<var: #b type: 'const uint64_t *'>
	<var: #ai type: 'uint64_t'>
	<var: #carry type: 'uint64_t'>
	| ai carry hi |
	hi := self local: 'uint64_t'.
	ai := a at: 0.
	carry := 0.
	0 to: nb - 1 do: [:j |
		r at: j put: (self mul64: ai by: (b at: j) plus: carry plus: 0 high: hi).
		carry := hi value].
	r at: nb put: carry.
	1 to: na - 1 do: [:i |
		ai := a at: i.
		carry := 0.
		0 to: nb - 1 do: [:j |
			r at: i + j put: (self mul64: ai by: (b at: j) plus: carry plus: (r at: i + j) high: hi).
			carry := hi value].
		r at: i + nb put: carry]
!
estimate: qhat times: v exceeds: rhat low: u
	"Whether qhat * v exceeds rhat * 2^64 + u (algorithm D's test of a quotient limb)."
	<function>
	<var: #qhat type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	<var: #rhat type: 'uint64_t'>
	<var: #u type: 'uint64_t'>
	<var: #lo type: 'uint64_t'>
	| lo hi |
	hi := self local: 'uint64_t'.
	lo := self mul64: qhat by: v plus: 0 plus: 0 high: hi.
	^hi value > rhat or: [hi value = rhat and: [lo > u]]
!
divide: a count: na by: b count: nb quotient: q remainder: r work: w
	"q (na - nb + 1 limbs) := a quo: b and r (nb limbs) := a rem: b, for a >= b > 0 without leading zero limbs: short division by one limb, else Knuth's algorithm D (TAOCP 4.3.1) on a copy of a (w: na + 1 limbs) and b as they are: each quotient limb estimated from the top limbs of both shifted so that b's top bit is set (normalized: limb:of:shiftedBy:), 128 by 64 bits (div128:low:by:remainder:); subtracting its multiple of b from the remainder is the shifted subtraction scaled back, borrow and all, so neither number is shifted, nor the remainder back."
	<function>
	<var: #a type: 'const uint64_t *'>
	<var: #b type: 'const uint64_t *'>
	<var: #d type: 'uint64_t'>
	<var: #vTop type: 'uint64_t'>
	<var: #vNext type: 'uint64_t'>
	<var: #top type: 'uint64_t'>
	<var: #qhat type: 'uint64_t'>
	<var: #rhat type: 'uint64_t'>
	<var: #carry type: 'uint64_t'>
	<var: #borrow type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	<var: #u type: 'uint64_t'>
	<var: #p type: 'uint64_t'>
	| d rem hi s un vTop vNext top qhat rhat big carry borrow x t u p |
	rem := self local: 'uint64_t'.
	hi := self local: 'uint64_t'.
	nb = 1 ifTrue: [
		d := b at: 0.
		rem value: 0.
		na - 1 to: 0 by: -1 do: [:i | q at: i put: (self div128: rem value low: (a at: i) by: d remainder: rem)].
		r at: 0 put: rem value.
		^self].
	s := self leadingZeros: (b at: nb - 1).
	un := w.
	libc memcpy: un from: a size: (na * 8) asUInt64.
	un at: na put: 0.
	vTop := self limb: nb - 1 of: b shiftedBy: s.
	vNext := self limb: nb - 2 of: b shiftedBy: s.
	na - nb to: 0 by: -1 do: [:j |
		"the quotient limb estimated from the top two limbs, at most 2 too large; corrected with the next one"
		top := self limb: j + nb of: un shiftedBy: s.
		top >= vTop
			ifTrue: [
				"(the top limb is vTop then) the largest limb; a remainder estimate past 2^64 tests nothing"
				qhat := 16rFFFFFFFFFFFFFFFF.
				rhat := ((self limb: j + nb - 1 of: un shiftedBy: s) + vTop) asUInt64.
				big := rhat < vTop]
			ifFalse: [
				qhat := self div128: top low: (self limb: j + nb - 1 of: un shiftedBy: s) by: vTop remainder: rem.
				rhat := rem value.
				big := false].
		[big not and: [self estimate: qhat times: vNext exceeds: rhat low: (self limb: j + nb - 2 of: un shiftedBy: s)]] whileTrue: [
			qhat := qhat - 1.
			t := (rhat + vTop) asUInt64.
			big := t < rhat.
			rhat := t].
		"un[j .. j + nb] -= qhat * b"
		carry := 0.
		borrow := 0.
		0 to: nb - 1 do: [:i |
			p := self mul64: qhat by: (b at: i) plus: carry plus: 0 high: hi.
			carry := hi value.
			x := un at: i + j.
			t := (x - p) asUInt64.
			un at: i + j put: (t - borrow) asUInt64.
			borrow := (x < p or: [t < borrow]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
		x := un at: j + nb.
		t := (x - carry) asUInt64.
		un at: j + nb put: (t - borrow) asUInt64.
		(x < carry or: [t < borrow]) ifTrue: [
			"rarely, qhat was still one too large: add b back"
			qhat := qhat - 1.
			carry := 0.
			0 to: nb - 1 do: [:i |
				x := un at: i + j.
				t := (x + (b at: i)) asUInt64.
				u := (t + carry) asUInt64.
				un at: i + j put: u.
				carry := (t < x or: [u < t]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
			un at: j + nb put: ((un at: j + nb) + carry) asUInt64].
		q at: j put: qhat].
	0 to: nb - 1 do: [:i | r at: i put: (un at: i)]
!
limb: i of: x shiftedBy: s
	"Limb i of x << s (s < 64): x's limb i shifted, below it what limb i - 1 shifts out (limb 0 has none below)."
	<function>
	<var: #x type: 'const uint64_t *'>
	<returns: 'uint64_t'>
	(s = 0 or: [i = 0]) ifTrue: [^((x at: i) << s) asUInt64].
	^((x at: i) << s) asUInt64 bitOr: (x at: i - 1) >> (64 - s)
!
leadingZeros: x
	"The number of leading zero bits of the nonzero 64-bit x."
	<var: #x type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	| v n |
	v := x.
	n := 0.
	[(v >> 63) = 0] whileTrue: [
		v := (v << 1) asUInt64.
		n := n + 1].
	^n
!
shift: x count: n left: k into: r
	"r (n + (k quo: 64) + 1 limbs) := x << k."
	<function>
	<var: #x type: 'const uint64_t *'>
	<var: #carry type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	| limbs bits carry v |
	limbs := k quo: 64.
	bits := k rem: 64.
	0 to: limbs - 1 do: [:i | r at: i put: 0].
	bits = 0 ifTrue: [
		0 to: n - 1 do: [:i | r at: limbs + i put: (x at: i)].
		r at: limbs + n put: 0.
		^self].
	carry := 0.
	0 to: n - 1 do: [:i |
		v := x at: i.
		r at: limbs + i put: ((v << bits) asUInt64 bitOr: carry).
		carry := v >> (64 - bits)].
	r at: limbs + n put: carry
!
shift: x count: n right: k into: r
	"r (n - (k quo: 64) limbs, k < 64 n) := x >> k; answer whether 1 bits were shifted out."
	<function>
	<var: #x type: 'const uint64_t *'>
	<var: #next type: 'uint64_t'>
	| limbs bits lost next |
	limbs := k quo: 64.
	bits := k rem: 64.
	lost := bits > 0 and: [((x at: limbs) << (64 - bits)) asUInt64 ~= 0].
	0 to: limbs - 1 do: [:i | (x at: i) ~= 0 ifTrue: [lost := true]].
	limbs to: n - 1 do: [:i |
		bits = 0
			ifTrue: [r at: i - limbs put: (x at: i)]
			ifFalse: [
				next := i + 1 < n ifTrue: [x at: i + 1] ifFalse: [0].
				r at: i - limbs put: (((x at: i) >> bits) bitOr: (next << (64 - bits)) asUInt64)]].
	^lost
!
increment: x count: n
	"x := x + 1 (room for n + 1 limbs); answer its limbs."
	<function>
	| i |
	i := 0.
	[i < n and: [(x at: i) = 16rFFFFFFFFFFFFFFFF]] whileTrue: [
		x at: i put: 0.
		i := i + 1].
	i = n ifTrue: [
		x at: n put: 1.
		^n + 1].
	x at: i put: ((x at: i) + 1) asUInt64.
	^n
!
lowest: x count: n
	"The index of x's lowest nonzero limb; n if there is none."
	<function>
	<var: #x type: 'const uint64_t *'>
	| i |
	i := 0.
	[i < n and: [(x at: i) = 0]] whileTrue: [i := i + 1].
	^i
!
limb: i of: x lowest: z
	"Limb i of x in two's complement (z: the index of x's lowest nonzero limb): for a negative x, ~(|x| - 1)."
	<function>
	<returns: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	| v |
	v := i < x count ifTrue: [x limbs at: i] ifFalse: [0].
	x neg ifFalse: [^v].
	i < z ifTrue: [^0].
	i = z ifTrue: [^(0 - v) asUInt64].
	^v bitInvert64
! !

VMStruct subclass: #LargeOperand
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

LargeOperand comment: 'An Integer operand of LargeIntegerPrimitives: its magnitude as count 64-bit limbs at limbs (least significant first; small holds the one of a SmallInteger) and its sign.'!

!LargeOperand class methodsFor: 'declaring'!
fields
	^#((limbs 'const uint64_t *') (count int64_t) (neg bool) (small 'uint64_t[1]'))
! !
