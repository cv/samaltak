Number subclass: #Integer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Integer comment: 'I am the abstract class of integers. SmallIntegers are immediate; LargePositiveInteger and LargeNegativeInteger hold the magnitude as little-endian bytes (no leading zero bytes) and are only used outside the SmallInteger range.

All integer arithmetic here is written in terms of digitAt: (bytes of the magnitude), digitLength and negative, which SmallInteger implements too, so SmallInteger primitives can fall back to me on overflow. Multiplication and division of two large magnitudes convert them to base-2^24 limbs (Arrays of SmallIntegers) to cut the number of steps; division uses Knuth''s algorithm D.'!

!Integer methodsFor: 'arithmetic'!
+ aNumber
	aNumber isInteger ifFalse: [^self retry: #+ coercing: aNumber].
	^self negative == aNumber negative
		ifTrue: [(self digitAdd: aNumber) normalize]
		ifFalse: [self digitSubtract: aNumber]
!
- aNumber
	aNumber isInteger ifFalse: [^self retry: #- coercing: aNumber].
	^self negative == aNumber negative
		ifTrue: [self digitSubtract: aNumber]
		ifFalse: [(self digitAdd: aNumber) normalize]
!
* aNumber
	aNumber isInteger ifFalse: [^self retry: #* coercing: aNumber].
	^self digitMultiply: aNumber neg: self negative ~~ aNumber negative
!
/ aNumber
	"Answer an Integer if the division is exact, else a Fraction."
	aNumber isInteger ifFalse: [^self retry: #/ coercing: aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^(Fraction numerator: self denominator: aNumber) reduced
!
quo: aNumber
	"Answer the quotient truncated toward zero."
	aNumber isInteger ifFalse: [^super quo: aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^(self digitDiv: aNumber neg: self negative ~~ aNumber negative) first
!
rem: aNumber
	"Answer the remainder of truncated division; it has the receiver's sign."
	aNumber isInteger ifFalse: [^super rem: aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^(self digitDiv: aNumber neg: self negative ~~ aNumber negative) last
!
// aNumber
	"Answer the quotient truncated toward negative infinity."
	| qr |
	aNumber isInteger ifFalse: [^super // aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	qr := self digitDiv: aNumber neg: self negative ~~ aNumber negative.
	((qr at: 2) ~= 0 and: [(qr at: 2) negative ~~ aNumber negative]) ifTrue: [^(qr at: 1) - 1].
	^qr at: 1
!
\\ aNumber
	"Answer the modulo; it has the sign of aNumber."
	| r |
	aNumber isInteger ifFalse: [^super \\ aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	r := (self digitDiv: aNumber neg: self negative ~~ aNumber negative) last.
	(r ~= 0 and: [r negative ~~ aNumber negative]) ifTrue: [^r + aNumber].
	^r
!
negated
	^0 - self
!
abs
	^self negative ifTrue: [self negated] ifFalse: [self]
! !

!Integer methodsFor: 'comparing'!
< aNumber
	aNumber isInteger ifFalse: [^self retry: #< coercing: aNumber].
	^(self compareInteger: aNumber) < 0
!
> aNumber
	aNumber isInteger ifFalse: [^self retry: #> coercing: aNumber].
	^(self compareInteger: aNumber) > 0
!
<= aNumber
	aNumber isInteger ifFalse: [^self retry: #<= coercing: aNumber].
	^(self compareInteger: aNumber) <= 0
!
>= aNumber
	aNumber isInteger ifFalse: [^self retry: #>= coercing: aNumber].
	^(self compareInteger: aNumber) >= 0
!
= aNumber
	aNumber isNumber ifFalse: [^false].
	aNumber isInteger ifFalse: [^aNumber = self].
	^(self compareInteger: aNumber) = 0
!
~= aNumber
	^(self = aNumber) not
!
hash
	"Fold the magnitude bytes; SmallInteger overrides with itself."
	| h |
	h := self negative ifTrue: [7] ifFalse: [0].
	1 to: self digitLength do: [:i | h := (h * 31 + (self digitAt: i)) bitAnd: 16r3FFFFFFF].
	^h
!
compareInteger: anInteger
	"Answer -1, 0 or 1 comparing the receiver with anInteger."
	| mag |
	self negative == anInteger negative ifFalse: [^self negative ifTrue: [-1] ifFalse: [1]].
	mag := self digitCompare: anInteger.
	^self negative ifTrue: [mag negated] ifFalse: [mag]
! !

!Integer methodsFor: 'testing'!
isInteger
	^true
!
isLarge
	^false
!
even
	^((self digitAt: 1) bitAnd: 1) = 0
!
odd
	^((self digitAt: 1) bitAnd: 1) = 1
!
isZero
	^self = 0
!
isPrime
	"Answer whether the receiver is a prime number (trial division)."
	| i |
	self <= 1 ifTrue: [^false].
	self <= 3 ifTrue: [^true].
	self even ifTrue: [^false].
	i := 3.
	[i * i <= self] whileTrue: [
		(self \\ i) = 0 ifTrue: [^false].
		i := i + 2].
	^true
!
isPowerOfTwo
	^self > 0 and: [(self bitAnd: self - 1) = 0]
!
sign
	self negative ifTrue: [^-1].
	self = 0 ifTrue: [^0].
	^1
! !

!Integer methodsFor: 'mathematical functions'!
factorial
	"Answer the factorial of the receiver."

	self < 0 ifTrue: [^self error: 'Not valid for negative integers'].
	^(1 to: self) inject: 1 into: [:product :each | product * each]
!
gcd: anInteger
	| a b |
	a := self abs.
	b := anInteger abs.
	[b = 0] whileFalse: [| r | r := a \\ b. a := b. b := r].
	^a
!
lcm: anInteger
	"Answer the least common multiple."
	(self = 0 or: [anInteger = 0]) ifTrue: [^0].
	^(self // (self gcd: anInteger) * anInteger) abs
!
sqrtFloor
	"Answer the largest integer whose square is <= the receiver (Newton's method)."
	| x y |
	self < 0 ifTrue: [^ArithmeticError new signal: 'sqrtFloor of a negative number'].
	self < 2 ifTrue: [^self].
	x := 1 bitShift: self highBit + 1 // 2.
	[y := x + (self // x) // 2. y < x] whileTrue: [x := y].
	^x
!
sqrt
	| root |
	self negative ifTrue: [^self asFloat sqrt].
	root := self sqrtFloor.
	root * root = self ifTrue: [^root].
	^self asFloat sqrt
!
isSquare
	| root |
	self < 0 ifTrue: [^false].
	root := self sqrtFloor.
	^root * root = self
!
raisedTo: aNumber modulo: m
	| result base n |
	result := 1.
	base := self \\ m.
	n := aNumber.
	[n > 0] whileTrue: [
		(n bitAnd: 1) = 1 ifTrue: [result := result * base \\ m].
		n := n bitShift: -1.
		base := base * base \\ m].
	^result
!
numberOfDigitsInBase: base
	^(self abs printString: base) size
! !

!Integer methodsFor: 'enumerating'!
timesRepeat: aBlock
	"Evaluate aBlock the receiver number of times."
	| count |
	count := 1.
	[count <= self] whileTrue: [
		aBlock value.
		count := count + 1]
! !

!Integer methodsFor: 'bit manipulation'!
bitAnd: anInteger
	^self bitLogic: anInteger op: 1
!
bitOr: anInteger
	^self bitLogic: anInteger op: 2
!
bitXor: anInteger
	^self bitLogic: anInteger op: 3
!
bitInvert
	^-1 - self
!
bitClear: mask
	^(self bitOr: mask) bitXor: mask
!
bitAt: index
	"Answer the bit (0 or 1) at index, 1 being the least significant (two's complement)."
	^(self bitShift: 1 - index) bitAnd: 1
!
bitAt: index put: bit
	| mask |
	mask := 1 bitShift: index - 1.
	^bit = 0 ifTrue: [self bitClear: mask] ifFalse: [self bitOr: mask]
!
allMask: mask
	^(self bitAnd: mask) = mask
!
anyMask: mask
	^(self bitAnd: mask) ~= 0
!
noMask: mask
	^(self bitAnd: mask) = 0
!
bitShift: shift
	"Shift left (positive shift) or right (negative shift, rounding toward negative infinity)."
	shift >= 0 ifTrue: [
		self negative ifTrue: [^(self negated bitShift: shift) negated].
		^self digitLshift: shift].
	self negative ifTrue: [^((self negated - 1) bitShift: shift) negated - 1].
	^self digitRshift: shift negated
!
<< shift
	^self bitShift: shift
!
>> shift
	^self bitShift: shift negated
!
highBit
	"Answer the index of the most significant 1 bit of the (non-negative) receiver; 0 for 0."
	self negative ifTrue: [^self error: 'highBit is not defined for negative integers'].
	^self highBitOfMagnitude
!
highBitOfMagnitude
	| len |
	len := self digitLength.
	[len > 0 and: [(self digitAt: len) = 0]] whileTrue: [len := len - 1].
	len = 0 ifTrue: [^0].
	^(len - 1) * 8 + (self digitAt: len) highBit
!
lowBit
	"Answer the index of the least significant 1 bit; 0 for 0."
	| i d |
	self = 0 ifTrue: [^0].
	i := 1.
	[(d := self digitAt: i) = 0] whileTrue: [i := i + 1].
	^(i - 1) * 8 + d lowBit
! !

!Integer methodsFor: 'truncation and rounding'!
truncated
	^self
!
rounded
	^self
!
floor
	^self
!
ceiling
	^self
!
numerator
	^self
!
denominator
	^1
! !

!Integer methodsFor: 'converting'!
asInteger
	^self
!
asCharacter
	^Character value: self
!
asFraction
	^self
!
asExactFraction
	^self
!
asFloat
	"Convert, rounding to nearest even (SmallInteger uses a primitive)."
	| h excess q low half |
	self negative ifTrue: [^self negated asFloat negated].
	h := self highBit.
	h <= 53 ifTrue: [^self asFloatExact].
	excess := h - 53.
	q := self bitShift: excess negated.
	low := self - (q bitShift: excess).
	half := 1 bitShift: excess - 1.
	(low > half or: [low = half and: [q odd]]) ifTrue: [q := q + 1].
	^q asFloatExact timesTwoPower: excess
!
asFloatExact
	"The receiver has at most 53 significant bits: convert digit by digit."
	| f |
	f := 0.0.
	self digitLength to: 1 by: -1 do: [:i | f := f * 256.0 + (self digitAt: i) asFloat].
	^f
! !

!Integer methodsFor: 'printing'!
printOn: aStream base: base
	aStream nextPutAll: (self printString: base)
!
printString
	^self printString: 10
!
printString: base
	"Answer the digits of the receiver in base (2..36), with a leading minus if negative."
	^self subclassResponsibility
!
radix: base
	"Answer the digits in base without a radix prefix (255 radix: 16 = 'FF')."
	^self printString: base
!
printStringRadix: base
	"Answer the receiver with a radix prefix: 16rFF."
	| s |
	s := self abs printString: base.
	^String new: s size + 4 streamContents: [:stream |
		self negative ifTrue: [stream nextPut: $-].
		stream print: base; nextPut: $r; nextPutAll: s]
!
storeString: base
	^self printStringRadix: base
!
storeOn: aStream base: base
	aStream nextPutAll: (self printStringRadix: base)
!
printOn: aStream base: base nDigits: n
	aStream nextPutAll: ((self printString: base) padLeftTo: n with: $0)
!
printPaddedWith: aCharacter to: width
	"Answer the decimal digits padded on the left to width with aCharacter."
	| s |
	s := self abs printString.
	s := s padLeftTo: (self negative ifTrue: [width - 1] ifFalse: [width]) with: aCharacter.
	^self negative ifTrue: ['-', s] ifFalse: [s]
!
printStringHex
	^self printString: 16
!
hex
	^self printStringRadix: 16
!
printStringBase: base
	^self printString: base
!
asStringWithCommas
	| s result count |
	s := self abs printString.
	result := WriteStream on: (String new: s size * 4 // 3 + 2).
	self negative ifTrue: [result nextPut: $-].
	count := s size.
	s do: [:c |
		result nextPut: c.
		count := count - 1.
		(count > 0 and: [count \\ 3 = 0]) ifTrue: [result nextPut: $,]].
	^result contents
!
isLiteral
	^true
! !

!Integer methodsFor: 'private'!
generality
	^self subclassResponsibility
!
coerce: aNumber
	^aNumber
!
negative
	^self subclassResponsibility
!
digitAt: index
	"Answer byte index (1 = least significant) of the magnitude."
	^self subclassResponsibility
!
digitLength
	^self subclassResponsibility
!
digitAdd: arg
	"Answer the sum of the magnitudes, with the receiver's sign (unnormalized)."
	| len arglen sum accum |
	len := self digitLength.
	arglen := arg digitLength.
	arglen > len ifTrue: [len := arglen].
	sum := Integer new: len + 1 neg: self negative.
	accum := 0.
	1 to: len do: [:i |
		accum := (accum bitShift: -8) + (self digitAt: i) + (arg digitAt: i).
		sum digitAt: i put: (accum bitAnd: 255)].
	sum digitAt: len + 1 put: (accum bitShift: -8).
	^sum
!
digitSubtract: arg
	"Answer the receiver minus arg, both taken with the receiver's sign; normalized."
	| sl al larger smaller ng diff z |
	sl := self digitLength.
	al := arg digitLength.
	(self digitCompare: arg) < 0
		ifTrue: [larger := arg. smaller := self. ng := self negative not. sl := al]
		ifFalse: [larger := self. smaller := arg. ng := self negative. sl := sl max: al].
	diff := Integer new: sl neg: ng.
	z := 0.
	1 to: sl do: [:i |
		z := z + (larger digitAt: i) - (smaller digitAt: i).
		z < 0
			ifTrue: [diff digitAt: i put: z + 256. z := -1]
			ifFalse: [diff digitAt: i put: z. z := 0]].
	^diff normalize
!
digitCompare: arg
	"Compare the magnitudes: -1, 0 or 1."
	| len arglen a b |
	len := self digitLength.
	[len > 1 and: [(self digitAt: len) = 0]] whileTrue: [len := len - 1].
	arglen := arg digitLength.
	[arglen > 1 and: [(arg digitAt: arglen) = 0]] whileTrue: [arglen := arglen - 1].
	len ~= arglen ifTrue: [^len > arglen ifTrue: [1] ifFalse: [-1]].
	len to: 1 by: -1 do: [:i |
		a := self digitAt: i.
		b := arg digitAt: i.
		a ~= b ifTrue: [^a > b ifTrue: [1] ifFalse: [-1]]].
	^0
!
digitMultiply: arg neg: ng
	"Answer the product of the magnitudes with sign ng."
	| a b m prod carry ab k len |
	(self = 0 or: [arg = 0]) ifTrue: [^0].
	a := self.
	b := arg.
	a digitLength < b digitLength ifTrue: [a := arg. b := self].
	b digitLength <= 5 ifTrue: [
		"short multiplication by a SmallInteger below 2^40"
		m := b abs.
		len := a digitLength.
		prod := Integer new: len + 5 neg: ng.
		carry := 0.
		k := 1.
		(a isLarge and: [m < 16r1000000]) ifTrue: [
			"32-bit limbs: a limb times m plus the carry stays below 2^57, a SmallInteger"
			[k + 3 <= len] whileTrue: [
				ab := (a uint32At: k) * m + carry.
				prod uint32At: k put: (ab bitAnd: 16rFFFFFFFF).
				carry := ab bitShift: -32.
				k := k + 4]].
		k to: len do: [:i |
			ab := (a digitAt: i) * m + carry.
			prod digitAt: i put: (ab bitAnd: 255).
			carry := ab bitShift: -8].
		k := len.
		[carry > 0] whileTrue: [
			k := k + 1.
			prod digitAt: k put: (carry bitAnd: 255).
			carry := carry bitShift: -8].
		^prod normalize].
	^Integer
		fromLimbs: (Integer multiplyLimbs: a magnitudeLimbs by: b magnitudeLimbs)
		neg: ng
!
digitDiv: arg neg: ng
	"Answer {quotient. remainder} of truncated division: the quotient has sign ng, the remainder the receiver's sign."
	| cmp qr q r |
	cmp := self digitCompare: arg.
	cmp < 0 ifTrue: [^Array with: 0 with: self].
	cmp = 0 ifTrue: [^Array with: (ng ifTrue: [-1] ifFalse: [1]) with: 0].
	arg digitLength <= 6
		ifTrue: [
			qr := self digitShortDivide: arg abs neg: ng.
			q := qr first.
			r := qr last]
		ifFalse: [
			qr := Integer divideLimbs: self magnitudeLimbs by: arg magnitudeLimbs.
			q := Integer fromLimbs: qr first neg: ng.
			r := Integer fromLimbs: qr last neg: false].
	self negative ifTrue: [r := r negated].
	^Array with: q with: r
!
digitShortDivide: divisor neg: ng
	"divisor is a positive SmallInteger below 2^48. Answer {quotient with sign ng. non-negative remainder}."
	| len quo r acc |
	len := self digitLength.
	quo := Integer new: len neg: ng.
	r := 0.
	len to: 1 by: -1 do: [:i |
		acc := (r bitShift: 8) + (self digitAt: i).
		quo digitAt: i put: acc // divisor.
		r := acc \\ divisor].
	^Array with: quo normalize with: r
!
digitLshift: shift
	"Shift the (non-negative) receiver left by shift bits."
	| len byteShift bitShift result carry v |
	len := self digitLength.
	byteShift := shift // 8.
	bitShift := shift \\ 8.
	result := Integer new: len + byteShift + 1 neg: false.
	carry := 0.
	1 to: len do: [:i |
		v := ((self digitAt: i) bitShift: bitShift) + carry.
		result digitAt: i + byteShift put: (v bitAnd: 255).
		carry := v bitShift: -8].
	result digitAt: len + byteShift + 1 put: carry.
	^result normalize
!
digitRshift: shift
	"Shift the (non-negative) receiver right by shift bits."
	| len byteShift bitShift newLen result v |
	len := self digitLength.
	byteShift := shift // 8.
	bitShift := shift \\ 8.
	byteShift >= len ifTrue: [^0].
	newLen := len - byteShift.
	result := Integer new: newLen neg: false.
	1 to: newLen do: [:i |
		v := ((self digitAt: i + byteShift) bitShift: bitShift negated)
			+ (((self digitAt: i + byteShift + 1) bitShift: 8 - bitShift) bitAnd: 255).
		result digitAt: i put: v].
	^result normalize
!
bitLogic: arg op: op
	"op: 1 and, 2 or, 3 xor, on the two's complement representations."
	| len a b r x y |
	arg isInteger ifFalse: [^self error: 'bit operations need Integers'].
	len := (self digitLength max: arg digitLength) + 1.
	a := self twosComplementBytes: len.
	b := arg twosComplementBytes: len.
	r := ByteArray new: len.
	1 to: len do: [:i |
		x := a at: i.
		y := b at: i.
		r at: i put: (op = 1
			ifTrue: [x bitAnd: y]
			ifFalse: [op = 2 ifTrue: [x bitOr: y] ifFalse: [x bitXor: y]])].
	^Integer fromTwosComplementBytes: r
!
twosComplementBytes: len
	| bytes borrow d |
	bytes := ByteArray new: len.
	self negative ifFalse: [
		1 to: len do: [:i | bytes at: i put: (self digitAt: i)].
		^bytes].
	borrow := 1.
	1 to: len do: [:i |
		d := (self digitAt: i) - borrow.
		d < 0
			ifTrue: [d := d + 256. borrow := 1]
			ifFalse: [borrow := 0].
		bytes at: i put: 255 - d].
	^bytes
!
magnitudeLimbs
	"Answer the magnitude as an Array of base-2^24 limbs, least significant first, without leading zero limbs."
	| n limbs b count |
	n := self digitLength.
	count := n + 2 // 3.
	limbs := Array new: count.
	1 to: count do: [:i |
		b := i - 1 * 3.
		limbs at: i put: (self digitAt: b + 1)
			+ ((self digitAt: b + 2) bitShift: 8)
			+ ((self digitAt: b + 3) bitShift: 16)].
	[count > 1 and: [(limbs at: count) = 0]] whileTrue: [count := count - 1].
	count < limbs size ifTrue: [^limbs copyFrom: 1 to: count].
	^limbs
! !

!Integer class methodsFor: 'instance creation'!
new: length neg: aBoolean
	"Answer a zeroed large integer with length magnitude bytes."
	^(aBoolean ifTrue: [LargeNegativeInteger] ifFalse: [LargePositiveInteger]) basicNew: length
!
readFrom: aStringOrStream
	^(NumberParser parse: aStringOrStream) asInteger
!
readFrom: aString base: base
	^NumberParser parse: aString base: base
!
fromLimbs: limbs neg: ng
	"Answer the integer whose magnitude has the base-2^24 limbs."
	| result l b |
	result := Integer new: limbs size * 3 neg: ng.
	1 to: limbs size do: [:i |
		l := limbs at: i.
		b := i - 1 * 3.
		result digitAt: b + 1 put: (l bitAnd: 255).
		result digitAt: b + 2 put: ((l bitShift: -8) bitAnd: 255).
		result digitAt: b + 3 put: (l bitShift: -16)].
	^result normalize
!
fromTwosComplementBytes: r
	| neg result carry d |
	neg := (r at: r size) >= 128.
	result := Integer new: r size neg: neg.
	neg ifFalse: [
		1 to: r size do: [:i | result digitAt: i put: (r at: i)].
		^result normalize].
	carry := 1.
	1 to: r size do: [:i |
		d := 255 - (r at: i) + carry.
		result digitAt: i put: (d bitAnd: 255).
		carry := d bitShift: -8].
	^result normalize
! !

!Integer class methodsFor: 'limb arithmetic'!
productFrom: low to: high
	"Answer low * (low + 1) * ... * high by binary splitting, so that big products multiply numbers of similar size."
	| result mid |
	high - low < 16 ifTrue: [
		result := 1.
		low to: high do: [:i | result := result * i].
		^result].
	mid := low + high // 2.
	^(self productFrom: low to: mid) * (self productFrom: mid + 1 to: high)
!
multiplyLimbs: a by: b
	"Schoolbook multiplication of base-2^24 limb Arrays."
	| prod ai carry t k |
	prod := Array new: a size + b size withAll: 0.
	1 to: a size do: [:i |
		ai := a at: i.
		ai = 0 ifFalse: [
			carry := 0.
			k := i.
			1 to: b size do: [:j |
				t := (prod at: k) + (ai * (b at: j)) + carry.
				prod at: k put: (t bitAnd: 16rFFFFFF).
				carry := t bitShift: -24.
				k := k + 1].
			prod at: k put: carry]].
	^prod
!
divideLimbs: u by: v
	"Knuth's algorithm D on base-2^24 limbs. v has at least two limbs and no leading zero limb; u >= v. Answer {quotient limbs. remainder limbs}."
	| n m s vn un q qhat rhat num borrow p t carry vTop vNext base mask |
	base := 16r1000000.
	mask := 16rFFFFFF.
	n := v size.
	m := u size - n.
	s := 24 - (v at: n) highBit.
	vn := self shiftLimbs: v left: s size: n.
	un := self shiftLimbs: u left: s size: u size + 1.
	vTop := vn at: n.
	vNext := vn at: n - 1.
	q := Array new: m + 1 withAll: 0.
	m to: 0 by: -1 do: [:j |
		num := ((un at: j + n + 1) bitShift: 24) + (un at: j + n).
		qhat := num // vTop.
		rhat := num \\ vTop.
		[rhat < base and: [qhat >= base or: [qhat * vNext > ((rhat bitShift: 24) + (un at: j + n - 1))]]]
			whileTrue: [
				qhat := qhat - 1.
				rhat := rhat + vTop].
		borrow := 0.
		1 to: n do: [:i |
			p := qhat * (vn at: i).
			t := (un at: i + j) - borrow - (p bitAnd: mask).
			un at: i + j put: (t bitAnd: mask).
			borrow := (p bitShift: -24) - (t bitShift: -24)].
		t := (un at: j + n + 1) - borrow.
		un at: j + n + 1 put: (t bitAnd: mask).
		t < 0 ifTrue: [
			qhat := qhat - 1.
			carry := 0.
			1 to: n do: [:i |
				t := (un at: i + j) + (vn at: i) + carry.
				un at: i + j put: (t bitAnd: mask).
				carry := t bitShift: -24].
			un at: j + n + 1 put: ((un at: j + n + 1) + carry bitAnd: mask)].
		q at: j + 1 put: qhat].
	^Array
		with: q
		with: (self shiftLimbs: (un copyFrom: 1 to: n) right: s)
!
shiftLimbs: limbs left: s size: size
	"Answer limbs shifted left by s (< 24) bits in an Array of size limbs."
	| result carry v |
	result := Array new: size withAll: 0.
	carry := 0.
	1 to: limbs size do: [:i |
		v := ((limbs at: i) bitShift: s) + carry.
		result at: i put: (v bitAnd: 16rFFFFFF).
		carry := v bitShift: -24].
	limbs size < size ifTrue: [result at: limbs size + 1 put: carry].
	^result
!
shiftLimbs: limbs right: s
	| result v next |
	result := Array new: limbs size.
	1 to: limbs size do: [:i |
		next := i < limbs size ifTrue: [limbs at: i + 1] ifFalse: [0].
		v := ((limbs at: i) bitShift: s negated) + ((next bitShift: 24 - s) bitAnd: 16rFFFFFF).
		result at: i put: v].
	^result
! !
