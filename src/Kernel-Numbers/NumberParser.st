Object subclass: #NumberParser
	instanceVariableNames: 'stream'
	classVariableNames: ''
	package: 'Kernel-Numbers'!

NumberParser comment: 'I read numbers in Smalltalk syntax from a String or ReadStream: integers (-42, 16rFF, 2r1010), decimals and exponents (3.25, 1.5e10, 2e-3; answered as correctly rounded Floats) and fractions (3/4). I stop at the first character that does not belong to the number.'!

!NumberParser methodsFor: 'accessing'!
on: aStringOrStream
	stream := aStringOrStream isString
		ifTrue: [ReadStream on: aStringOrStream]
		ifFalse: [aStringOrStream]
! !

!NumberParser methodsFor: 'parsing'!
parseNumber
	"Answer the number at the stream position; signal an Error if there is none."
	| negative base mantissa scale exponent isFloat value denominator |
	[stream atEnd not and: [stream peek isSeparator]] whileTrue: [stream next].
	negative := self skipMinus.
	mantissa := self parseDigitsBase: 10.
	mantissa isNil ifTrue: [^self error: 'Number expected'].
	base := 10.
	(stream peek = $r) ifTrue: [
		stream next.
		base := mantissa.
		(base between: 2 and: 36) ifFalse: [^self error: 'Bad radix'].
		self skipMinus ifTrue: [negative := negative not].
		mantissa := self parseDigitsBase: base.
		mantissa isNil ifTrue: [^self error: 'Digits expected after radix']].
	isFloat := false.
	scale := 0.
	(stream peek = $. and: [self isDigit: self peekSecond base: base]) ifTrue: [
		stream next.
		isFloat := true.
		[stream atEnd not and: [self isDigit: stream peek base: base]] whileTrue: [
			mantissa := mantissa * base + stream next digitValue.
			scale := scale + 1]].
	exponent := 0.
	(stream peek = $e and: [(self isDigit: self peekSecond base: 10) or: [self peekSecond = $-]]) ifTrue: [
		| expNegative |
		stream next.
		isFloat := true.
		expNegative := self skipMinus.
		exponent := self parseDigitsBase: 10.
		exponent isNil ifTrue: [^self error: 'Exponent expected'].
		expNegative ifTrue: [exponent := exponent negated]].
	isFloat
		ifTrue: [
			value := mantissa * (base raisedTo: exponent - scale).
			value := value asFloat]
		ifFalse: [
			value := mantissa.
			(stream peek = $/ and: [self isDigit: self peekSecond base: 10]) ifTrue: [
				stream next.
				denominator := self parseDigitsBase: 10.
				value := value / denominator]].
	^negative ifTrue: [value negated] ifFalse: [value]
!
parseDigitsBase: base
	"Answer the non-negative integer made of the digits at the stream position, or nil if there are none."
	| value any |
	value := 0.
	any := false.
	[stream atEnd not and: [self isDigit: stream peek base: base]] whileTrue: [
		value := value * base + stream next digitValue.
		any := true].
	^any ifTrue: [value] ifFalse: [nil]
! !

!NumberParser methodsFor: 'private'!
skipMinus
	(stream atEnd not and: [stream peek = $-]) ifTrue: [stream next. ^true].
	^false
!
isDigit: aCharacter base: base
	| v |
	aCharacter isNil ifTrue: [^false].
	v := aCharacter digitValue.
	^v >= 0 and: [v < base and: [aCharacter isLowercase not or: [base <= 10]]]
!
peekSecond
	"Answer the character after the next one, or nil."
	| pos c |
	pos := stream position.
	stream atEnd ifTrue: [^nil].
	stream next.
	c := stream atEnd ifTrue: [nil] ifFalse: [stream peek].
	stream position: pos.
	^c
! !

!NumberParser class methodsFor: 'parsing'!
parse: aStringOrStream
	^self new on: aStringOrStream; parseNumber
!
parse: aString base: base
	| parser value |
	parser := self new on: aString.
	value := parser parseDigitsBase: base.
	value isNil ifTrue: [^self error: 'Digits expected'].
	^value
! !
