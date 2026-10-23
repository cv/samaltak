Object subclass: #Magnitude
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Magnitude immediateSubclass: #Character
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Magnitude subclass: #Number
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Number subclass: #Integer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Integer immediateSubclass: #SmallInteger
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Integer variableByteSubclass: #LargePositiveInteger
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

LargePositiveInteger variableByteSubclass: #LargeNegativeInteger
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Number subclass: #Float
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Float immediateSubclass: #SmallFloat64
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Float variableDoubleWordSubclass: #BoxedFloat64
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

!Magnitude methodsFor: 'comparing'!
max: x
	^self > x ifTrue: [self] ifFalse: [x]
!
min: x
	^self < x ifTrue: [self] ifFalse: [x]
!
between: a and: b
	^self >= a and: [self <= b]
! !

!Character methodsFor: 'accessing'!
value
	<primitive: 'charValue'>
!
= c
	^self == c
!
hash
	^self value
!
isVowel
	^'aeiouAEIOU' includes: self
!
asString
	| s |
	s := (self value < 256 ifTrue: [ByteString] ifFalse: [WideString]) new: 1.
	s at: 1 put: self.
	^s
!
printString
	^'$' , self asString
!
isDigit
	^self value between: 48 and: 57
! !

!Character class methodsFor: 'instances'!
value: n
	<primitive: 'charFromValue'>
	^self error: 'bad code point'
!
lf
	^self value: 10
! !

!Number methodsFor: 'arithmetic'!
isNumber
	^true
!
@ y
	^Point new setX: self setY: y
!
abs
	^self < 0 ifTrue: [self negated] ifFalse: [self]
!
negated
	^0 - self
!
squared
	^self * self
!
even
	^(self \\ 2) = 0
! !

!Integer methodsFor: 'enumerating'!
timesRepeat: aBlock
	"Evaluate aBlock the receiver number of times (a real message, not inlined)."
	| count |
	count := 1.
	[count <= self] whileTrue: [
		aBlock value.
		count := count + 1]
! !

!Integer methodsFor: 'arithmetic'!
isInteger
	^true
!
isNegative
	^self < 0
!
magnitudeBytes
	^self
!
+ n
	| a b |
	n isFloat ifTrue: [^self asFloat + n].
	a := self magnitudeBytes.
	b := n magnitudeBytes.
	self isNegative = n isNegative ifTrue: [^Integer fromMag: (Integer add: a to: b) negative: self isNegative].
	(Integer compare: a with: b) >= 0
		ifTrue: [^Integer fromMag: (Integer sub: b from: a) negative: self isNegative].
	^Integer fromMag: (Integer sub: a from: b) negative: n isNegative
!
- n
	n isFloat ifTrue: [^self asFloat - n].
	^self + n negated
!
* n
	n isFloat ifTrue: [^self asFloat * n].
	^Integer fromMag: (Integer mul: self magnitudeBytes by: n magnitudeBytes) negative: self isNegative ~~ n isNegative
!
negated
	^Integer fromMag: self magnitudeBytes negative: self isNegative not
!
// n
	n = 0 ifTrue: [^self error: 'division by zero'].
	^(Integer div: self magnitudeBytes by: n) at: 1
!
\\ n
	n = 0 ifTrue: [^self error: 'division by zero'].
	^(Integer div: self magnitudeBytes by: n) at: 2
!
= n
	n isInteger ifFalse: [^false].
	^self isNegative = n isNegative and: [(Integer compare: self magnitudeBytes with: n magnitudeBytes) = 0]
!
< n
	self isNegative = n isNegative ifFalse: [^self isNegative].
	^self isNegative
		ifTrue: [(Integer compare: self magnitudeBytes with: n magnitudeBytes) > 0]
		ifFalse: [(Integer compare: self magnitudeBytes with: n magnitudeBytes) < 0]
!
> n
	^n < self
!
<= n
	^(n < self) not
!
>= n
	^(self < n) not
!
factorial
	| r |
	r := 1.
	2 to: self do: [:i | r := r * i].
	^r
!
printString
	| n s neg |
	self = 0 ifTrue: [^'0'].
	neg := self isNegative.
	n := self abs.
	s := ''.
	[n = 0] whileFalse: [
		s := (Character value: 48 + (n \\ 10)) asString , s.
		n := n // 10].
	neg ifTrue: [s := '-' , s].
	^s
! !

!Integer class methodsFor: 'magnitudes'!
digit: x at: i
	^i > x basicSize ifTrue: [0] ifFalse: [x basicAt: i]
!
lengthOf: x
	| n |
	n := x basicSize.
	[n > 0 and: [(x basicAt: n) = 0]] whileTrue: [n := n - 1].
	^n
!
add: a to: b
	| n r carry s |
	n := (a basicSize max: b basicSize) + 1.
	r := ByteArray new: n.
	carry := 0.
	1 to: n do: [:i |
		s := (self digit: a at: i) + (self digit: b at: i) + carry.
		r at: i put: (s bitAnd: 255).
		carry := s bitShift: -8].
	^r
!
sub: b from: a
	| n r borrow s |
	n := a basicSize.
	r := ByteArray new: n.
	borrow := 0.
	1 to: n do: [:i |
		s := (self digit: a at: i) - (self digit: b at: i) - borrow.
		s < 0 ifTrue: [s := s + 256. borrow := 1] ifFalse: [borrow := 0].
		r at: i put: s].
	^r
!
compare: a with: b
	| la lb x y |
	la := self lengthOf: a.
	lb := self lengthOf: b.
	la = lb ifFalse: [^la < lb ifTrue: [-1] ifFalse: [1]].
	la to: 1 by: -1 do: [:i |
		x := a basicAt: i.
		y := b basicAt: i.
		x = y ifFalse: [^x < y ifTrue: [-1] ifFalse: [1]]].
	^0
!
mul: a by: b
	| la lb r carry k s |
	la := a basicSize.
	lb := b basicSize.
	r := ByteArray new: la + lb.
	1 to: la do: [:i |
		carry := 0.
		1 to: lb do: [:j |
			k := i + j - 1.
			s := (r at: k) + ((a basicAt: i) * (b basicAt: j)) + carry.
			r at: k put: (s bitAnd: 255).
			carry := s bitShift: -8].
		k := i + lb.
		[carry > 0] whileTrue: [
			s := (r at: k) + carry.
			r at: k put: (s bitAnd: 255).
			carry := s bitShift: -8.
			k := k + 1]].
	^r
!
div: a by: d
	"Non-negative magnitude a divided by a small positive integer d: {quotient. remainder}"
	| n q rem s |
	n := a basicSize.
	q := ByteArray new: n.
	rem := 0.
	n to: 1 by: -1 do: [:i |
		s := rem * 256 + (a basicAt: i).
		q at: i put: s // d.
		rem := s \\ d].
	^Array with: (self fromMag: q negative: false) with: rem
!
fromMag: bytes negative: neg
	| n v r |
	n := self lengthOf: bytes.
	(n = 8 and: [neg and: [(bytes basicAt: 8) = 64]]) ifTrue: [
		v := 0.
		1 to: 7 do: [:i | v := v + (bytes basicAt: i)].
		v = 0 ifTrue: [^-4611686018427387903 - 1]].
	(n < 8 or: [n = 8 and: [(bytes basicAt: 8) < 64]]) ifTrue: [
		v := 0.
		n to: 1 by: -1 do: [:i | v := v * 256 + (bytes basicAt: i)].
		^neg ifTrue: [0 - v] ifFalse: [v]].
	r := (neg ifTrue: [LargeNegativeInteger] ifFalse: [LargePositiveInteger]) basicNew: n.
	1 to: n do: [:i | r basicAt: i put: (bytes basicAt: i)].
	^r
! !

!SmallInteger methodsFor: 'arithmetic'!
+ n
	<primitive: 'intAdd'>
	^super + n
!
- n
	<primitive: 'intSub'>
	^super - n
!
* n
	<primitive: 'intMul'>
	^super * n
!
/ n
	<primitive: 'intDiv'>
	^self asFloat / n asFloat
!
// n
	<primitive: 'intFloorDiv'>
	^super // n
!
\\ n
	<primitive: 'intMod'>
	^super \\ n
!
quo: n
	<primitive: 'intQuo'>
	^self error: 'quo: failed'
!
rem: n
	<primitive: 'intRem'>
	^self error: 'rem: failed'
!
< n
	<primitive: 'intLess'>
	^n isFloat ifTrue: [self asFloat < n] ifFalse: [super < n]
!
> n
	<primitive: 'intGreater'>
	^n isFloat ifTrue: [self asFloat > n] ifFalse: [super > n]
!
<= n
	<primitive: 'intLessEq'>
	^super <= n
!
>= n
	<primitive: 'intGreaterEq'>
	^super >= n
!
= n
	<primitive: 'intEq'>
	^super = n
!
~= n
	<primitive: 'intNotEq'>
	^(self = n) not
!
bitAnd: n
	<primitive: 'intBitAnd'>
!
bitOr: n
	<primitive: 'intBitOr'>
!
bitXor: n
	<primitive: 'intBitXor'>
!
bitShift: n
	<primitive: 'intBitShift'>
	n > 0 ifTrue: [^self * (2 raisedTo: n)].
	^self error: 'bitShift: failed'
!
raisedTo: n
	| r |
	r := 1.
	n timesRepeat: [r := r * self].
	^r
!
asFloat
	<primitive: 'intAsFloat'>
!
isNegative
	^self < 0
!
negated
	self = -4611686018427387904 ifTrue: [^Integer fromMag: self magnitudeBytes negative: false].
	^0 - self
!
magnitudeBytes
	| b n i |
	b := ByteArray new: 8.
	n := self.
	i := 1.
	[n = 0] whileFalse: [
		b at: i put: (n rem: 256) abs.
		n := n quo: 256.
		i := i + 1].
	^b
!
hash
	^self
!
identityHash
	^self
! !

!SmallInteger class methodsFor: 'constants'!
maxVal
	^4611686018427387903
!
minVal
	^-4611686018427387904
! !

!LargePositiveInteger methodsFor: 'arithmetic'!
isNegative
	^false
! !

!LargeNegativeInteger methodsFor: 'arithmetic'!
isNegative
	^true
! !

!Float methodsFor: 'arithmetic'!
isFloat
	^true
!
+ n
	<primitive: 'floatAdd'>
	^self + n asFloat
!
- n
	<primitive: 'floatSub'>
	^self - n asFloat
!
* n
	<primitive: 'floatMul'>
	^self * n asFloat
!
/ n
	<primitive: 'floatDiv'>
	^self error: 'float division failed'
!
< n
	<primitive: 'floatLess'>
!
> n
	<primitive: 'floatGreater'>
!
<= n
	<primitive: 'floatLessEq'>
!
>= n
	<primitive: 'floatGreaterEq'>
!
= n
	<primitive: 'floatEq'>
	^false
!
truncated
	<primitive: 'floatTruncated'>
	^self error: 'truncated failed'
!
fractionPart
	<primitive: 'floatFractionPart'>
!
exponent
	<primitive: 'floatExponent'>
!
timesTwoPower: n
	<primitive: 'floatTimesTwoPower'>
!
sqrt
	<primitive: 'floatSqrt'>
!
sin
	<primitive: 'floatSin'>
!
cos
	<primitive: 'floatCos'>
!
arcTan
	<primitive: 'floatArcTan'>
!
ln
	<primitive: 'floatLn'>
!
exp
	<primitive: 'floatExp'>
!
asIEEEBits
	<primitive: 'floatAsIEEEBits'>
!
asFloat
	^self
!
printString
	<primitive: 'floatPrintString'>
! !

!Float class methodsFor: 'instances'!
fromIEEEBits: n
	<primitive: 'floatFromIEEEBits'>
! !
