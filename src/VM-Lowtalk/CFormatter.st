Object subclass: #CFormatter
	instanceVariableNames: 'memory format arguments argIndex out'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CFormatter comment: 'I am printf for the simulator: I format a C format string with arguments as the C library does (flags, width, precision, length modifiers; d i u x X o c s p e f g %). Floating-point conversions are exact (correctly rounded, ties to even), as in Apple''s and glibc''s printf.'!

!CFormatter class methodsFor: 'formatting'!
format: aFormatString arguments: anArray memory: aMemory
	^self new setMemory: aMemory format: aFormatString arguments: anArray; run
! !

!CFormatter methodsFor: 'initialization'!
setMemory: aMemory format: aString arguments: anArray
	memory := aMemory.
	format := aString.
	arguments := anArray.
	argIndex := 0
! !

!CFormatter methodsFor: 'formatting'!
nextArgument
	argIndex := argIndex + 1.
	^arguments at: argIndex
!
run
	| s c |
	out := WriteStream on: String new.
	s := ReadStream on: format.
	[s atEnd] whileFalse: [
		c := s next.
		c = $%
			ifTrue: [self directive: s]
			ifFalse: [out nextPut: c]].
	^out contents
!
directive: s
	| flags width precision conv text |
	flags := Set new.
	[s atEnd not and: ['-+ 0#' includes: s peek]] whileTrue: [flags add: s next].
	width := self numberFrom: s.
	precision := nil.
	(s atEnd not and: [s peek = $.]) ifTrue: [
		s next.
		precision := (self numberFrom: s) ifNil: [0]].
	[s atEnd not and: ['hlLqjzt' includes: s peek]] whileTrue: [s next].
	conv := s next.
	conv = $% ifTrue: [^out nextPut: $%].
	text := self convert: conv flags: flags precision: precision.
	self pad: text width: width flags: flags conversion: conv
!
numberFrom: s
	| n |
	(s atEnd not and: [s peek = $*]) ifTrue: [s next. ^self nextArgument].
	(s atEnd not and: [s peek isDigit]) ifFalse: [^nil].
	n := 0.
	[s atEnd not and: [s peek isDigit]] whileTrue: [n := n * 10 + s next digitValue].
	^n
!
convert: conv flags: flags precision: precision
	| v |
	('di' includes: conv) ifTrue: [^self signed: self nextArgument flags: flags precision: precision].
	conv = $u ifTrue: [^self digits: (self unsigned: self nextArgument) base: 10 precision: precision].
	conv = $x ifTrue: [^self alternate: '0x' flags: flags digits: (self digits: (self unsigned: self nextArgument) base: 16 precision: precision) asLowercase].
	conv = $X ifTrue: [^self alternate: '0X' flags: flags digits: (self digits: (self unsigned: self nextArgument) base: 16 precision: precision)].
	conv = $o ifTrue: [^self digits: (self unsigned: self nextArgument) base: 8 precision: precision].
	conv = $c ifTrue: [^String with: (Character value: self nextArgument)].
	conv = $s ifTrue: [
		v := memory stringAt: self nextArgument.
		^precision isNil ifTrue: [v] ifFalse: [v first: (precision min: v size)]].
	conv = $p ifTrue: [^'0x' , ((memory addressOf: self nextArgument) printStringBase: 16) asLowercase].
	('eE' includes: conv) ifTrue: [^self exponent: self nextArgument asFloat precision: (precision ifNil: [6]) flags: flags upper: conv = $E].
	('fF' includes: conv) ifTrue: [^self fixed: self nextArgument asFloat precision: (precision ifNil: [6]) flags: flags].
	('gG' includes: conv) ifTrue: [^self general: self nextArgument asFloat precision: (precision ifNil: [6]) flags: flags upper: conv = $G].
	^memory simulationError: 'printf conversion %' , (String with: conv) , ' is not simulated'
!
unsigned: anInteger
	"Arguments of %u/%x are unsigned: negative ones are their two's complement."
	anInteger isInteger ifFalse: [^memory addressOf: anInteger].
	^anInteger < 0 ifTrue: [anInteger + (1 bitShift: 64)] ifFalse: [anInteger]
!
signed: anInteger flags: flags precision: precision
	| d |
	d := self digits: anInteger abs base: 10 precision: precision.
	anInteger < 0 ifTrue: [^'-' , d].
	(flags includes: $+) ifTrue: [^'+' , d].
	(flags includes: $ ) ifTrue: [^' ' , d].
	^d
!
digits: anInteger base: base precision: precision
	| d |
	(precision = 0 and: [anInteger = 0]) ifTrue: [^''].
	d := anInteger printStringBase: base.
	(precision notNil and: [d size < precision]) ifTrue: [d := (String new: precision - d size withAll: $0) , d].
	^d
!
alternate: prefix flags: flags digits: aString
	^((flags includes: $#) and: [aString notEmpty and: [aString ~= '0']]) ifTrue: [prefix , aString] ifFalse: [aString]
!
pad: aString width: width flags: flags conversion: conv
	| fill text |
	text := aString.
	(width isNil or: [text size >= width]) ifTrue: [^out nextPutAll: text].
	(flags includes: $-) ifTrue: [^out nextPutAll: text; nextPutAll: (String new: width - text size withAll: $ )].
	((flags includes: $0) and: ['diuxXoeEfFgG' includes: conv]) ifTrue: [
		fill := String new: width - text size withAll: $0.
		(text notEmpty and: ['+- ' includes: text first]) ifTrue: [^out nextPut: text first; nextPutAll: fill; nextPutAll: text allButFirst].
		((text beginsWith: '0x') or: [text beginsWith: '0X']) ifTrue: [^out nextPutAll: (text first: 2); nextPutAll: fill; nextPutAll: (text allButFirst: 2)].
		^out nextPutAll: fill; nextPutAll: text].
	out nextPutAll: (String new: width - text size withAll: $ ); nextPutAll: text
! !

!CFormatter methodsFor: 'floating point'!
special: aFloat flags: flags upper: aBoolean
	| s |
	aFloat isNaN ifTrue: [s := 'nan'].
	aFloat isInfinite ifTrue: [s := aFloat > 0 ifTrue: ['inf'] ifFalse: ['-inf']].
	s isNil ifTrue: [^nil].
	(aFloat isInfinite and: [aFloat > 0 and: [flags includes: $+]]) ifTrue: [s := '+' , s].
	^aBoolean ifTrue: [s asUppercase] ifFalse: [s]
!
sign: aFloat flags: flags
	(aFloat < 0 or: [aFloat = 0.0 and: [aFloat sign < 0 or: [(aFloat asIEEEBits bitShift: -63) = 1]]]) ifTrue: [^'-'].
	(flags includes: $+) ifTrue: [^'+'].
	(flags includes: $ ) ifTrue: [^' '].
	^''
!
exact: aFloat
	"The exact value of |aFloat| as a Fraction or Integer."
	| bits e m |
	bits := aFloat asIEEEBits.
	e := (bits bitShift: -52) bitAnd: 16r7FF.
	m := bits bitAnd: 16rFFFFFFFFFFFFF.
	e = 0 ifTrue: [e := 1] ifFalse: [m := m + 16r10000000000000].
	^m * (2 raisedTo: e - 1075)
!
roundHalfEven: aNumber
	| f r |
	f := aNumber floor.
	r := aNumber - f.
	r > (1/2) ifTrue: [^f + 1].
	r < (1/2) ifTrue: [^f].
	^f even ifTrue: [f] ifFalse: [f + 1]
!
decimalDigits: aFloat count: n
	"Answer {digits. exponent}: n significant digits of |aFloat| (correctly rounded) and the decimal exponent of the first."
	| x e scaled digits |
	x := self exact: aFloat.
	x = 0 ifTrue: [^Array with: (String new: n withAll: $0) with: 0].
	e := 0.
	[(10 raisedTo: e + 1) <= x] whileTrue: [e := e + 1].
	[(10 raisedTo: e) > x] whileTrue: [e := e - 1].
	scaled := self roundHalfEven: x * (10 raisedTo: n - 1 - e).
	scaled >= (10 raisedTo: n) ifTrue: [
		e := e + 1.
		scaled := self roundHalfEven: x * (10 raisedTo: n - 1 - e)].
	digits := scaled printString.
	^Array with: digits with: e
!
exponent: aFloat precision: p flags: flags upper: aBoolean
	| special r digits e s |
	special := self special: aFloat flags: flags upper: aBoolean.
	special notNil ifTrue: [^special].
	r := self decimalDigits: aFloat count: p + 1.
	digits := r at: 1.
	e := r at: 2.
	s := WriteStream on: String new.
	s nextPutAll: (self sign: aFloat flags: flags).
	s nextPut: digits first.
	(p > 0 or: [flags includes: $#]) ifTrue: [s nextPut: $.].
	s nextPutAll: digits allButFirst.
	s nextPut: (aBoolean ifTrue: [$E] ifFalse: [$e]).
	s nextPut: (e < 0 ifTrue: [$-] ifFalse: [$+]).
	e abs < 10 ifTrue: [s nextPut: $0].
	s print: e abs.
	^s contents
!
fixed: aFloat precision: p flags: flags
	| special x scaled digits s |
	special := self special: aFloat flags: flags upper: false.
	special notNil ifTrue: [^special].
	x := self exact: aFloat.
	scaled := self roundHalfEven: x * (10 raisedTo: p).
	digits := scaled printString.
	digits size <= p ifTrue: [digits := (String new: p + 1 - digits size withAll: $0) , digits].
	s := WriteStream on: String new.
	s nextPutAll: (self sign: aFloat flags: flags).
	s nextPutAll: (digits first: digits size - p).
	(p > 0 or: [flags includes: $#]) ifTrue: [s nextPut: $.].
	s nextPutAll: (digits last: p).
	^s contents
!
general: aFloat precision: precision flags: flags upper: aBoolean
	| special p r e text |
	special := self special: aFloat flags: flags upper: aBoolean.
	special notNil ifTrue: [^special].
	p := precision = 0 ifTrue: [1] ifFalse: [precision].
	r := self decimalDigits: aFloat count: p.
	e := (self exact: aFloat) = 0 ifTrue: [0] ifFalse: [r at: 2].
	text := (e < -4 or: [e >= p])
		ifTrue: [self exponent: aFloat precision: p - 1 flags: flags upper: aBoolean]
		ifFalse: [self fixed: aFloat precision: p - 1 - e flags: flags].
	(flags includes: $#) ifTrue: [^text].
	^self stripZeros: text
!
stripZeros: aString
	"Remove trailing zeros of the fraction (and a trailing point), keeping any exponent."
	| mantissa exp i |
	i := aString indexOf: $e.
	i = 0 ifTrue: [i := aString indexOf: $E].
	i = 0
		ifTrue: [mantissa := aString. exp := '']
		ifFalse: [mantissa := aString first: i - 1. exp := aString allButFirst: i - 1].
	(mantissa includes: $.) ifFalse: [^aString].
	[mantissa last = $0] whileTrue: [mantissa := mantissa allButLast].
	mantissa last = $. ifTrue: [mantissa := mantissa allButLast].
	^mantissa , exp
! !
