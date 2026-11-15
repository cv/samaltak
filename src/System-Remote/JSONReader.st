Object subclass: #JSONReader
	instanceVariableNames: 'source position'
	classVariableNames: ''
	package: 'System-Remote'!

JSONReader comment: 'I parse JSON text (see JSON). position is the 1-based index of the next character of source.'!

!JSONReader methodsFor: 'initialization'!
setSource: aString
	source := aString.
	position := 1
! !

!JSONReader methodsFor: 'parsing'!
parseDocument
	| value |
	value := self parseValue.
	self skipWhitespace.
	self atEnd ifFalse: [self error: 'unexpected text after the value'].
	^value
!
parseValue
	| c |
	self skipWhitespace.
	self atEnd ifTrue: [^self error: 'unexpected end of input'].
	c := self peek.
	c = ${ ifTrue: [^self parseObject].
	c = $[ ifTrue: [^self parseArray].
	c = $" ifTrue: [^self parseString].
	(c = $- or: [c between: $0 and: $9]) ifTrue: [^self parseNumber].
	(self matches: 'true') ifTrue: [^true].
	(self matches: 'false') ifTrue: [^false].
	(self matches: 'null') ifTrue: [^nil].
	^self error: 'unexpected character ', c printString
!
parseObject
	| result key |
	result := Dictionary new.
	self expect: ${.
	self skipWhitespace.
	(self peekFor: $}) ifTrue: [^result].
	[self skipWhitespace.
	 self peek = $" ifFalse: [^self error: 'object key expected'].
	 key := self parseString.
	 self skipWhitespace.
	 self expect: $:.
	 result at: key put: self parseValue.
	 self skipWhitespace.
	 self peekFor: $,] whileTrue.
	self expect: $}.
	^result
!
parseArray
	| result |
	result := OrderedCollection new.
	self expect: $[.
	self skipWhitespace.
	(self peekFor: $]) ifTrue: [^#() copy].
	[result add: self parseValue.
	 self skipWhitespace.
	 self peekFor: $,] whileTrue.
	self expect: $].
	^result asArray
!
parseString
	| stream c |
	self expect: $".
	stream := WriteStream on: (String new: 16).
	[self atEnd ifTrue: [^self error: 'unterminated string'].
	 (c := self next) = $"] whileFalse: [
		c = $\
			ifTrue: [stream nextPut: self parseEscape]
			ifFalse: [
				c value < 32 ifTrue: [^self error: 'control character in string'].
				stream nextPut: c]].
	^stream contents
!
parseEscape
	| c code low |
	self atEnd ifTrue: [^self error: 'unterminated escape'].
	c := self next.
	c = $" ifTrue: [^$"].
	c = $\ ifTrue: [^$\].
	c = $/ ifTrue: [^$/].
	c = $b ifTrue: [^Character value: 8].
	c = $f ifTrue: [^Character value: 12].
	c = $n ifTrue: [^Character value: 10].
	c = $r ifTrue: [^Character value: 13].
	c = $t ifTrue: [^Character value: 9].
	c = $u ifFalse: [^self error: 'bad escape \', c asString].
	code := self parseHex4.
	(code between: 16rD800 and: 16rDBFF) ifTrue: [
		((self peekFor: $\) and: [self peekFor: $u]) ifFalse: [^self error: 'unpaired surrogate'].
		low := self parseHex4.
		(low between: 16rDC00 and: 16rDFFF) ifFalse: [^self error: 'unpaired surrogate'].
		code := 16r10000 + ((code - 16rD800) bitShift: 10) + (low - 16rDC00)].
	(code between: 16rDC00 and: 16rDFFF) ifTrue: [^self error: 'unpaired surrogate'].
	^Character value: code
!
parseHex4
	| value digit |
	value := 0.
	4 timesRepeat: [
		self atEnd ifTrue: [^self error: 'bad \u escape'].
		digit := self next asUppercase digitValue.
		(digit between: 0 and: 15) ifFalse: [^self error: 'bad \u escape'].
		value := value * 16 + digit].
	^value
!
parseNumber
	"Integers stay exact (LargeIntegers included); a fraction part or an exponent makes a Float."
	| negative mantissa fractionDigits exponent exponentNegative isFloat float |
	negative := self peekFor: $-.
	(self atEnd not and: [self peek between: $0 and: $9]) ifFalse: [^self error: 'digit expected'].
	mantissa := 0.
	(self peekFor: $0)
		ifFalse: [[self atEnd not and: [self peek between: $0 and: $9]] whileTrue: [mantissa := mantissa * 10 + self next digitValue]].
	isFloat := false.
	fractionDigits := 0.
	(self peekFor: $.) ifTrue: [
		isFloat := true.
		(self atEnd not and: [self peek between: $0 and: $9]) ifFalse: [^self error: 'digit expected after .'].
		[self atEnd not and: [self peek between: $0 and: $9]] whileTrue: [
			mantissa := mantissa * 10 + self next digitValue.
			fractionDigits := fractionDigits + 1]].
	exponent := 0.
	(self atEnd not and: [self peek = $e or: [self peek = $E]]) ifTrue: [
		isFloat := true.
		self next.
		exponentNegative := self peekFor: $-.
		exponentNegative ifFalse: [self peekFor: $+].
		(self atEnd not and: [self peek between: $0 and: $9]) ifFalse: [^self error: 'digit expected in exponent'].
		[self atEnd not and: [self peek between: $0 and: $9]] whileTrue: [
			exponent := exponent * 10 + self next digitValue min: 100000].
		exponentNegative ifTrue: [exponent := exponent negated]].
	isFloat ifFalse: [^negative ifTrue: [mantissa negated] ifFalse: [mantissa]].
	float := self floatFrom: mantissa exponent: exponent - fractionDigits.
	^negative ifTrue: [float negated] ifFalse: [float]
!
floatFrom: mantissa exponent: exponent
	"Answer the Float nearest to mantissa * 10^exponent (mantissa >= 0)."
	mantissa = 0 ifTrue: [^0.0].
	exponent > 400 ifTrue: [^Float infinity].
	exponent < -400 ifTrue: [^0.0].
	exponent >= 0 ifTrue: [^(mantissa * (10 raisedTo: exponent)) asFloat].
	^(mantissa / (10 raisedTo: exponent negated)) asFloat
! !

!JSONReader methodsFor: 'scanning'!
atEnd
	^position > source size
!
peek
	"Answer the next character, or nil at the end."
	position > source size ifTrue: [^nil].
	^source at: position
!
next
	| c |
	c := source at: position.
	position := position + 1.
	^c
!
peekFor: aCharacter
	(self atEnd not and: [self peek = aCharacter]) ifFalse: [^false].
	position := position + 1.
	^true
!
expect: aCharacter
	(self peekFor: aCharacter) ifFalse: [
		self error: (self atEnd
			ifTrue: [aCharacter printString, ' expected at end of input']
			ifFalse: [aCharacter printString, ' expected but found ', self peek printString])]
!
matches: aString
	(position + aString size - 1 <= source size
		and: [(source copyFrom: position to: position + aString size - 1) = aString]) ifFalse: [^false].
	position := position + aString size.
	^true
!
skipWhitespace
	[self atEnd not and: [#(32 9 10 13) includes: self peek value]] whileTrue: [position := position + 1]
! !

!JSONReader methodsFor: 'errors'!
error: aString
	^JSONError new position: position; signal: 'JSON: ', aString, ' at position ', position printString
! !

!JSONReader class methodsFor: 'instance creation'!
on: aString
	^self new setSource: aString
! !
