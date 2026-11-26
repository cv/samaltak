Object subclass: #JSONReader
	instanceVariableNames: 'source position limit'
	classVariableNames: ''
	package: 'System-Remote'!

JSONReader comment: 'I parse JSON text (see JSON). position is the 1-based index of the next character of source.'!

!JSONReader methodsFor: 'initialization'!
setSource: aString
	source := aString.
	limit := source size.
	position := 1
! !

!JSONReader methodsFor: 'parsing'!
parseDocument
	| value |
	value := self parseValue.
	^self documentEndingWith: value
!
documentEndingWith: value
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
	^self parseObjectWithAuth: nil
!
parseObjectWithAuth: authBlock
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
	 (authBlock notNil and: [key = 'auth'])
		ifTrue: [authBlock value]
		ifFalse: [result at: key put: self parseValue].
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
	| stream |
	stream := WriteStream on: (String new: 16).
	self parseStringDo: [:ch | stream nextPut: ch].
	^stream contents
!
parseStringDo: aBlock
	| c |
	self expect: $".
	[self atEnd ifTrue: [^self error: 'unterminated string'].
	 (c := self next) = $"] whileFalse: [
		c = $\
			ifTrue: [aBlock value: self parseEscape]
			ifFalse: [
				c value < 32 ifTrue: [^self error: 'control character in string'].
				aBlock value: c]]
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
		digit := self next.
		digit := digit isAscii ifTrue: [digit digitValue] ifFalse: [-1].
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

!JSONReader methodsFor: 'control requests'!
parseControlBytes: bytes length: byteCount authenticating: verify
	"Decode and erase the source here, and never put auth in the parsed object."
	| authenticated seen json |
	seen := authenticated := false.
	"Allocate once; do not leave an old buffer behind on Unicode promotion."
	source := WideString new: byteCount.
	position := 1.
	^[self decodeControlBytes: bytes length: byteCount.
	  self skipWhitespace.
	  self peek = ${ ifFalse: [^self error: 'object expected'].
	  json := self parseObjectWithAuth: [
		| valid |
		valid := self parseAuthWith: verify.
		authenticated := seen not and: [valid].
		seen := true].
	  self documentEndingWith: json.
	  {json. authenticated}] ensure: [source atAllPut: (Character value: 0)]
!
decodeControlBytes: bytes length: byteCount
	| i n |
	i := 1.
	limit := 0.
	[i <= byteCount] whileTrue: [
		n := bytes utf8LengthAt: i to: byteCount.
		limit := limit + 1.
		source at: limit put: (bytes utf8CharacterAt: i length: n).
		i := i + n abs]
!
parseAuthWith: verify
	"Only a string can be a credential. Decode it into bounded, scratch storage."
	| bytes size |
	self skipWhitespace.
	self peek = $" ifFalse: [self parseValue. ^false].
	bytes := ByteArray new: 35.
	size := 0.
	^[self parseStringDo: [:ch |
		size := size + 1.
		(ch value < 128 and: [size <= bytes size]) ifTrue: [bytes at: size put: ch value]].
	  verify value: (ControlToken verifierOfLength: size byteAt: [:i | bytes at: i])]
		ensure: [bytes atAllPut: 0]
! !

!JSONReader methodsFor: 'scanning'!
atEnd
	^position > limit
!
peek
	"Answer the next character, or nil at the end."
	position > limit ifTrue: [^nil].
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
	position + aString size - 1 > limit ifTrue: [^false].
	1 to: aString size do: [:i | (source at: position + i - 1) = (aString at: i) ifFalse: [^false]].
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
