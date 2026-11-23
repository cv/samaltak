!Integer methodsFor: 'portable magnitude arithmetic'!
magnitudeSize
	| n |
	n := self digitLength.
	[n > 0 and: [(self digitAt: n) = 0]] whileTrue: [n := n - 1].
	^n
!
compareMagnitude: operand size: n withSize: m
	| i x y |
	n ~= m ifTrue: [^n < m ifTrue: [-1] ifFalse: [1]].
	i := n.
	[i > 0] whileTrue: [
		x := self digitAt: i.
		y := operand digitAt: i.
		x ~= y ifTrue: [^x < y ifTrue: [-1] ifFalse: [1]].
		i := i - 1].
	^0
!
portableCompareInteger: operand
	| n m neg otherNeg order |
	n := self magnitudeSize.
	m := operand magnitudeSize.
	neg := n > 0 and: [self negative].
	otherNeg := m > 0 and: [operand negative].
	neg ~= otherNeg ifTrue: [^neg ifTrue: [-1] ifFalse: [1]].
	order := self compareMagnitude: operand size: n withSize: m.
	^neg ifTrue: [0 - order] ifFalse: [order]
!
portableAdd: operand subtract: subtract
	| n m neg otherNeg |
	n := self magnitudeSize.
	m := operand magnitudeSize.
	neg := self negative.
	otherNeg := operand negative ~= subtract.
	neg = otherNeg ifTrue: [
		^self combineMagnitude: operand count: (n max: m) factor: 1 negative: neg].
	(self compareMagnitude: operand size: n withSize: m) < 0
		ifTrue: [^operand combineMagnitude: self count: m factor: -1 negative: otherNeg].
	^self combineMagnitude: operand count: n factor: -1 negative: neg
!
combineMagnitude: operand count: n factor: factor negative: neg
	"Add or subtract magnitudes, the larger first for subtraction."
	| digits digit carry |
	digits := ByteArray new: n + (factor = 1 ifTrue: [1] ifFalse: [0]).
	carry := 0.
	1 to: n do: [:i |
		digit := (operand digitAt: i) * factor + (self digitAt: i) + carry.
		digits basicAt: i put: (digit bitAnd: 255).
		carry := digit bitShift: -8].
	factor = 1 ifTrue: [digits basicAt: n + 1 put: carry].
	^Integer fromMagnitudeBytes: digits negative: neg
!
portableMultiply: operand
	"Base 2^24 keeps products and carries in SmallIntegers."
	| n m a b product x carry digit |
	n := self magnitudeSize.
	m := operand magnitudeSize.
	(n = 0 or: [m = 0]) ifTrue: [^0].
	a := self magnitudeLimbs: n left: 0.
	b := operand magnitudeLimbs: m left: 0.
	n := a basicSize - 1.
	m := b basicSize - 1.
	product := Array new: n + m withAll: 0.
	1 to: n do: [:i |
		x := a basicAt: i.
		carry := 0.
		1 to: m do: [:j | | k |
			k := i + j - 1.
			digit := x * (b basicAt: j) + (product basicAt: k) + carry.
			product basicAt: k put: (digit bitAnd: 16rFFFFFF).
			carry := digit bitShift: -24].
		product basicAt: i + m put: carry].
	^Integer fromMagnitudeBytes: (Integer magnitudeBytesFromLimbs: product count: n + m right: 0)
		negative: self negative ~= operand negative
!
magnitudeLimbs: n left: bits
	"Pack into 24-bit limbs, with one extra limb for a normalization shift."
	| limbs count k carry word |
	count := n + 2 // 3.
	limbs := Array new: count + 1.
	carry := 0.
	k := 1.
	1 to: count do: [:i |
		word := (self digitAt: k) + ((self digitAt: k + 1) bitShift: 8) + ((self digitAt: k + 2) bitShift: 16).
		word := (word bitShift: bits) + carry.
		limbs basicAt: i put: (word bitAnd: 16rFFFFFF).
		carry := word bitShift: -24.
		k := k + 3].
	limbs basicAt: count + 1 put: carry.
	^limbs
!
portableDivide: divisor mode: mode
	"Modes 0/1 truncate, 2/3 floor; even modes answer the quotient."
	| n m quotient remainder neg floored result |
	n := self magnitudeSize.
	m := divisor magnitudeSize.
	m = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	n = 0 ifTrue: [^0].
	neg := self negative ~= divisor negative.
	(self compareMagnitude: divisor size: n withSize: m) < 0 ifTrue: [
		mode = 0 ifTrue: [^0].
		mode = 2 ifTrue: [^neg ifTrue: [-1] ifFalse: [0]].
		mode = 3 ifTrue: [
			neg ifTrue: [^divisor combineMagnitude: self count: m factor: -1 negative: divisor negative]].
		^self normalizedMagnitude: n negative: self negative].
	quotient := ByteArray new: n - m + 2.
	remainder := m <= 6
		ifTrue: [self divideMagnitude: n bySmall: divisor size: m quotient: quotient]
		ifFalse: [self divideMagnitude: n by: divisor size: m quotient: quotient].
	floored := mode >= 2 and: [neg and: [remainder isZero not]].
	mode odd ifTrue: [
		floored ifTrue: [^divisor combineMagnitude: remainder count: m factor: -1 negative: divisor negative].
		^self negative
			ifTrue: [0 portableAdd: remainder subtract: true]
			ifFalse: [remainder]].
	result := Integer fromMagnitudeBytes: quotient negative: neg.
	^floored ifTrue: [result portableAdd: 1 subtract: true] ifFalse: [result]
!
divideMagnitude: n bySmall: divisor size: m quotient: quotient
	"Bring down a byte at a time; every partial dividend fits a SmallInteger."
	| d r digit |
	d := 0.
	m to: 1 by: -1 do: [:i | d := d * 256 + (divisor digitAt: i)].
	r := 0.
	n to: 1 by: -1 do: [:i |
		digit := r * 256 + (self digitAt: i).
		i <= quotient basicSize ifTrue: [quotient basicAt: i put: (digit quo: d)].
		r := digit rem: d].
	^r
!
divideMagnitude: n by: divisor size: m quotient: quotient
	"Knuth division in base 2^24, with the high bit of the divisor set for the estimate."
	| u v base bits prefix rest q aCount bCount vTop vNext index |
	base := 16r1000000.
	bits := 3 - ((m - 1) rem: 3) * 8 - (divisor digitAt: m) highBit.
	u := self magnitudeLimbs: n left: bits.
	v := divisor magnitudeLimbs: m left: bits.
	aCount := u basicSize - 1.
	bCount := v basicSize - 1.
	vTop := v basicAt: bCount.
	vNext := v basicAt: bCount - 1.
	aCount - bCount to: 0 by: -1 do: [:offset |
		index := offset + bCount.
		prefix := ((u basicAt: index + 1) bitShift: 24) + (u basicAt: index).
		q := (prefix quo: vTop) min: base - 1.
		rest := prefix - (q * vTop).
		[q * vNext > ((rest bitShift: 24) + (u basicAt: index - 1))] whileTrue: [
			q := q - 1.
			rest := rest + vTop].
		q ~= 0 ifTrue: [
			(self subtractLimbs: v count: bCount times: q from: u offset: offset) ifFalse: [
				self restoreLimbs: v count: bCount into: u offset: offset.
				q := q - 1].
			index := offset * 3 + 1.
			0 to: 2 do: [:i |
				index + i <= quotient basicSize ifTrue: [
					quotient basicAt: index + i put: ((q bitShift: i * -8) bitAnd: 255)]]]].
	^Integer fromMagnitudeBytes: (Integer magnitudeBytesFromLimbs: u count: bCount right: bits) negative: false
!
subtractLimbs: divisor count: m times: q from: work offset: offset
	"Subtract one quotient limb times the divisor. Return false on borrow."
	| product digit index carry |
	carry := 0.
	1 to: m do: [:i |
		index := offset + i.
		product := (divisor basicAt: i) * q + carry.
		digit := (work basicAt: index) - (product bitAnd: 16rFFFFFF).
		work basicAt: index put: (digit bitAnd: 16rFFFFFF).
		carry := (product bitShift: -24) - (digit bitShift: -24)].
	index := offset + m + 1.
	digit := (work basicAt: index) - carry.
	work basicAt: index put: (digit bitAnd: 16rFFFFFF).
	^digit >= 0
!
restoreLimbs: divisor count: m into: work offset: offset
	"An estimate still one too high borrows: add the divisor back."
	| digit index carry |
	carry := 0.
	1 to: m do: [:i |
		index := offset + i.
		digit := (work basicAt: index) + (divisor basicAt: i) + carry.
		work basicAt: index put: (digit bitAnd: 16rFFFFFF).
		carry := digit bitShift: -24].
	work basicAt: offset + m + 1 put: (((work basicAt: offset + m + 1) + carry) bitAnd: 16rFFFFFF)
!
normalizedMagnitude: n negative: neg
	| bytes |
	bytes := ByteArray new: n.
	1 to: n do: [:i | bytes basicAt: i put: (self digitAt: i)].
	^Integer fromMagnitudeBytes: bytes negative: neg
! !

!Integer methodsFor: 'portable bit arithmetic'!
twosComplementDigitAt: i correctionAt: low
	| digit |
	digit := self digitAt: i.
	low = 0 ifTrue: [^digit].
	i < low ifTrue: [^0].
	i = low ifTrue: [^256 - digit].
	^255 - digit
!
twosComplementCorrection
	"First nonzero magnitude byte of a negative operand, or 0."
	| i n |
	self negative ifFalse: [^0].
	n := self digitLength.
	i := 1.
	[i <= n and: [(self digitAt: i) = 0]] whileTrue: [i := i + 1].
	^i <= n ifTrue: [i] ifFalse: [0]
!
portableBitOp: selector with: operand
	| n digits a b neg carry digit |
	n := (self magnitudeSize max: operand magnitudeSize) + 1.
	digits := ByteArray new: n.
	a := self twosComplementCorrection.
	b := operand twosComplementCorrection.
	1 to: n do: [:i |
		digits basicAt: i put: ((self twosComplementDigitAt: i correctionAt: a)
			perform: selector with: (operand twosComplementDigitAt: i correctionAt: b))].
	neg := (digits basicAt: n) = 255.
	neg ifTrue: [
		carry := 1.
		1 to: n do: [:i |
			digit := 255 - (digits basicAt: i) + carry.
			digits basicAt: i put: (digit bitAnd: 255).
			carry := digit bitShift: -8]].
	^Integer fromMagnitudeBytes: digits negative: neg
!
portableBitShift: shift
	| n m k byteShift bits digits digit carry lost neg |
	n := self magnitudeSize.
	n = 0 ifTrue: [^0].
	neg := self negative.
	m := shift magnitudeSize.
	m = 0 ifTrue: [^self normalizedMagnitude: n negative: neg].
	"With 32-bit slot counts, a shift using more than seven magnitude bytes
	cannot leave bits on a right shift or fit in any left-shift result."
	m > 7 ifTrue: [
		shift negative ifTrue: [^neg ifTrue: [-1] ifFalse: [0]].
		^OutOfMemory signalForClass: LargePositiveInteger size: (shift portableDivide: 8 mode: 0)].
	k := 0.
	m to: 1 by: -1 do: [:i | k := k * 256 + (shift digitAt: i)].
	byteShift := k bitShift: -3.
	bits := k bitAnd: 7.
	shift negative ifFalse: [
		digits := ByteArray new: n + byteShift + (bits = 0 ifTrue: [0] ifFalse: [1]).
		carry := 0.
		1 to: n do: [:i |
			digit := ((self digitAt: i) bitShift: bits) + carry.
			digits basicAt: i + byteShift put: (digit bitAnd: 255).
			carry := digit bitShift: -8].
		bits > 0 ifTrue: [digits basicAt: digits basicSize put: carry].
		^Integer fromMagnitudeBytes: digits negative: neg].
	byteShift >= n ifTrue: [^neg ifTrue: [-1] ifFalse: [0]].
	digits := ByteArray new: n - byteShift.
	carry := 0.
	n to: byteShift + 1 by: -1 do: [:i |
		digit := self digitAt: i.
		digits basicAt: i - byteShift put: ((digit bitShift: 0 - bits) bitOr: carry).
		carry := (digit bitShift: 8 - bits) bitAnd: 255].
	lost := carry ~= 0.
	1 to: byteShift do: [:i | (self digitAt: i) ~= 0 ifTrue: [lost := true]].
	digit := Integer fromMagnitudeBytes: digits negative: neg.
	^(neg and: [lost]) ifTrue: [digit portableAdd: 1 subtract: true] ifFalse: [digit]
! !

!Integer class methodsFor: 'portable magnitude arithmetic'!
magnitudeBytesFromLimbs: limbs count: n right: bits
	"Unpack the low n limbs, discarding a normalization shift."
	| bytes next carry limb |
	bytes := ByteArray new: n * 3.
	carry := 0.
	n to: 1 by: -1 do: [:i |
		next := limbs basicAt: i.
		limb := (next bitShift: 0 - bits) bitOr: carry.
		bytes basicAt: i * 3 put: (limb bitShift: -16).
		bytes basicAt: i * 3 - 1 put: ((limb bitShift: -8) bitAnd: 255).
		bytes basicAt: i * 3 - 2 put: (limb bitAnd: 255).
		carry := (next bitShift: 24 - bits) bitAnd: 16rFFFFFF].
	^bytes
!
fromMagnitudeBytes: bytes negative: negative
	"Drop high zero bytes and fold into a SmallInteger without overflowing."
	| n top result |
	n := bytes basicSize.
	[n > 0 and: [(bytes basicAt: n) = 0]] whileTrue: [n := n - 1].
	n = 0 ifTrue: [^0].
	top := bytes basicAt: n.
	(n < 8 or: [n = 8 and: [top < 64]]) ifTrue: [
		result := 0.
		n to: 1 by: -1 do: [:i | result := result * 256 + (bytes basicAt: i)].
		^negative ifTrue: [0 - result] ifFalse: [result]].
	(n = 8 and: [top = 64 and: [negative]]) ifTrue: [
		result := 0.
		1 to: 7 do: [:i | result := result bitOr: (bytes basicAt: i)].
		result = 0 ifTrue: [^SmallInteger minVal]].
	result := (negative ifTrue: [LargeNegativeInteger] ifFalse: [LargePositiveInteger]) basicNew: n.
	1 to: n do: [:i | result basicAt: i put: (bytes basicAt: i)].
	^result
! !
