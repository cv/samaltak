Object subclass: #Scanner
	instanceVariableNames: 'source size mark tokenType tokenValue tokenStart tokenStop errorKind'
	classVariableNames: 'CharClasses'
	package: 'Compiler'!

Scanner comment: 'I split Smalltalk source into tokens. Each token has a type, a value and a 1-based inclusive interval (tokenStart to tokenStop).

Token types: #identifier #keyword #binary #bar #number #string #symbol #character #literalArrayStart (#() #byteArrayStart (#[) #assignment #return #colon #period #semicolon #leftParen #rightParen #leftBracket #rightBracket #leftBrace #rightBrace #eof #error (tokenValue is the message).

For syntax highlighting use Scanner class>>highlight:do: or highlightTokens:, which never fail.'!

!Scanner class methodsFor: 'instance creation'!
on: aString
	^self new setSource: aString
! !

!Scanner class methodsFor: 'highlighting'!
highlight: aString do: aBlock
	"Evaluate aBlock with type, start and stop for every token and comment of aString. Never fails, even on incomplete input.
	Types: #comment #string #symbol #number #character #keyword #binary #identifier #global #self #super #true #false #nil #thisContext #assignment #return #literalArrayStart #punctuation #error."
	(self on: aString) highlightDo: aBlock
!
highlightTokens: aString
	"Answer an OrderedCollection of {type. start. stop} triples, see highlight:do:."
	| result |
	result := OrderedCollection new.
	self highlight: aString do: [:type :start :stop | result add: (Array with: type with: start with: stop)].
	^result
! !

!Scanner class methodsFor: 'private'!
initCharClasses
	| t |
	t := Array new: 128.
	1 to: 128 do: [:i | t at: i put: #other].
	65 to: 90 do: [:i | t at: i + 1 put: #letter].
	97 to: 122 do: [:i | t at: i + 1 put: #letter].
	t at: 96 put: #letter.
	48 to: 57 do: [:i | t at: i + 1 put: #digit].
	#(9 10 12 13 32) do: [:i | t at: i + 1 put: #separator].
	#(43 45 42 47 92 60 62 61 126 64 37 38 63 44 33) do: [:i | t at: i + 1 put: #binary].
	CharClasses := t
! !

!Scanner methodsFor: 'initialization'!
setSource: aString
	CharClasses isNil ifTrue: [Scanner initCharClasses].
	source := aString.
	size := aString size.
	mark := 1.
	tokenStart := 1.
	tokenStop := 0
! !

!Scanner methodsFor: 'accessing'!
tokenType
	^tokenType
!
tokenValue
	^tokenValue
!
tokenStart
	^tokenStart
!
tokenStop
	^tokenStop
!
errorKind
	^errorKind
!
mark
	^mark
! !

!Scanner methodsFor: 'characters'!
charAt: anInteger
	(anInteger >= 1 and: [anInteger <= size]) ifTrue: [^source at: anInteger].
	^nil
!
classOf: aCharacter
	| v |
	aCharacter isNil ifTrue: [^#eof].
	v := aCharacter value.
	v < 128 ifTrue: [^CharClasses at: v + 1].
	^#other
!
digitValueOf: aCharacter
	"Answer the digit value of aCharacter (0-9, A-Z/a-z = 10-35), or 99."
	| v |
	aCharacter isNil ifTrue: [^99].
	v := aCharacter value.
	(v >= 48 and: [v <= 57]) ifTrue: [^v - 48].
	(v >= 65 and: [v <= 90]) ifTrue: [^v - 55].
	(v >= 97 and: [v <= 122]) ifTrue: [^v - 87].
	^99
! !

!Scanner methodsFor: 'scanning'!
nextToken
	"Scan the next token, skipping separators and comments. Answer its type."
	[self skipSeparators.
	 (self charAt: mark) == $"] whileTrue: [
		self scanComment ifFalse: [^tokenType]].
	^self scanToken
!
skipSeparators
	[mark <= size and: [(self classOf: (source at: mark)) == #separator]]
		whileTrue: [mark := mark + 1]
!
scanComment
	"mark is at a double quote. Skip the comment and answer true; answer false (error token) if it is unterminated."
	| i |
	errorKind := nil.
	tokenStart := mark.
	i := mark + 1.
	[i <= size and: [(source at: i) ~~ $"]] whileTrue: [i := i + 1].
	i > size ifTrue: [
		mark := size + 1.
		self setError: 'Unterminated comment' kind: #unterminatedComment.
		^false].
	mark := i + 1.
	tokenStop := i.
	^true
!
scanToken
	| c cls |
	errorKind := nil.
	tokenStart := mark.
	mark > size ifTrue: [
		tokenStop := size.
		tokenValue := nil.
		^tokenType := #eof].
	c := source at: mark.
	cls := self classOf: c.
	cls == #letter ifTrue: [^self scanIdentifier].
	cls == #digit ifTrue: [^self scanNumber].
	cls == #binary ifTrue: [^self scanBinary].
	c == $' ifTrue: [^self scanString].
	c == $$ ifTrue: [^self scanCharacter].
	c == $# ifTrue: [^self scanHash].
	c == $: ifTrue: [
		(self charAt: mark + 1) == $= ifTrue: [
			mark := mark + 2.
			^self setToken: #assignment value: ':='].
		mark := mark + 1.
		^self setToken: #colon value: ':'].
	mark := mark + 1.
	c == $^ ifTrue: [^self setToken: #return value: '^'].
	c == $( ifTrue: [^self setToken: #leftParen value: '('].
	c == $) ifTrue: [^self setToken: #rightParen value: ')'].
	c == $[ ifTrue: [^self setToken: #leftBracket value: '['].
	c == $] ifTrue: [^self setToken: #rightBracket value: ']'].
	c == ${ ifTrue: [^self setToken: #leftBrace value: '{'].
	c == $} ifTrue: [^self setToken: #rightBrace value: '}'].
	c == $. ifTrue: [^self setToken: #period value: '.'].
	c == $; ifTrue: [^self setToken: #semicolon value: ';'].
	c == $| ifTrue: [^self setToken: #bar value: '|'].
	^self setError: 'Unknown character' kind: #character
!
scanIdentifier
	| cls |
	[mark := mark + 1.
	 cls := self classOf: (self charAt: mark).
	 cls == #letter or: [cls == #digit]] whileTrue.
	((self charAt: mark) == $: and: [(self charAt: mark + 1) ~~ $=]) ifTrue: [
		mark := mark + 1.
		^self setToken: #keyword value: (source copyFrom: tokenStart to: mark - 1)].
	^self setToken: #identifier value: (source copyFrom: tokenStart to: mark - 1)
!
scanBinary
	| c |
	mark := mark + 1.
	[c := self charAt: mark.
	 (self classOf: c) == #binary
		and: [c ~~ $- or: [(self classOf: (self charAt: mark + 1)) ~~ #digit]]]
			whileTrue: [mark := mark + 1].
	^self setToken: #binary value: (source copyFrom: tokenStart to: mark - 1)
!
scanString
	"mark is at the opening quote."
	| i pieceStart value |
	i := mark + 1.
	pieceStart := i.
	value := nil.
	[i <= size] whileTrue: [
		(source at: i) == $'
			ifTrue: [
				value := value isNil
					ifTrue: [source copyFrom: pieceStart to: i - 1]
					ifFalse: [value , (source copyFrom: pieceStart to: i - 1)].
				(self charAt: i + 1) == $' ifFalse: [
					mark := i + 1.
					^self setToken: #string value: value].
				value := value , ''''.
				i := i + 2.
				pieceStart := i]
			ifFalse: [i := i + 1]].
	mark := size + 1.
	^self setError: 'Unterminated string' kind: #unterminatedString
!
scanCharacter
	mark + 1 > size ifTrue: [
		mark := size + 1.
		^self setError: 'Character expected' kind: #character].
	mark := mark + 2.
	^self setToken: #character value: (source at: mark - 1)
!
scanHash
	| c cls start |
	c := self charAt: mark + 1.
	c == $( ifTrue: [
		mark := mark + 2.
		^self setToken: #literalArrayStart value: '#('].
	c == $[ ifTrue: [
		mark := mark + 2.
		^self setToken: #byteArrayStart value: '#['].
	start := mark + 1.
	[(self charAt: start) == $#] whileTrue: [start := start + 1].
	c := self charAt: start.
	c == $' ifTrue: [
		mark := start.
		self scanString.
		tokenType == #string ifTrue: [
			tokenType := #symbol.
			tokenValue := tokenValue asSymbol].
		^tokenType].
	cls := self classOf: c.
	cls == #letter ifTrue: [
		mark := start.
		[cls := self classOf: (self charAt: mark).
		 cls == #letter or: [cls == #digit or: [(self charAt: mark) == $:]]]
			whileTrue: [mark := mark + 1].
		^self setToken: #symbol value: (source copyFrom: start to: mark - 1) asSymbol].
	(cls == #binary or: [c == $|]) ifTrue: [
		mark := start.
		[c := self charAt: mark.
		 (self classOf: c) == #binary or: [c == $|]]
			whileTrue: [mark := mark + 1].
		^self setToken: #symbol value: (source copyFrom: start to: mark - 1) asSymbol].
	mark := tokenStart + 1.
	^self setError: 'Literal expected after #' kind: #hash
!
scanNumber
	| value radix negative mantissa scale exponent fractionStart fraction negativeExponent |
	radix := 10.
	negative := false.
	scale := 0.
	exponent := 0.
	value := self scanDigits: 10.
	(self charAt: mark) == $r ifTrue: [
		radix := value.
		(radix < 2 or: [radix > 36]) ifTrue: [^self setError: 'Invalid radix' kind: #number].
		mark := mark + 1.
		(self charAt: mark) == $- ifTrue: [
			negative := true.
			mark := mark + 1].
		(self digitValueOf: (self charAt: mark)) < radix
			ifFalse: [^self setError: 'Digit expected' kind: #number].
		value := self scanDigits: radix].
	mantissa := value.
	fraction := false.
	((self charAt: mark) == $. and: [(self digitValueOf: (self charAt: mark + 1)) < radix]) ifTrue: [
		mark := mark + 1.
		fractionStart := mark.
		value := self scanDigits: radix.
		scale := mark - fractionStart.
		mantissa := mantissa * (self power: radix to: scale) + value.
		fraction := true].
	((self charAt: mark) == $e
		and: [(self digitValueOf: (self charAt: mark + 1)) < 10
			or: [(self charAt: mark + 1) == $- and: [(self digitValueOf: (self charAt: mark + 2)) < 10]]])
		ifTrue: [
			mark := mark + 1.
			negativeExponent := (self charAt: mark) == $-.
			negativeExponent ifTrue: [mark := mark + 1].
			exponent := self scanDigits: 10.
			negativeExponent ifTrue: [exponent := exponent negated]].
	negative ifTrue: [mantissa := mantissa negated].
	exponent := exponent - scale.
	(fraction not and: [exponent >= 0]) ifTrue: [
		^self setToken: #number value: mantissa * (self power: radix to: exponent)].
	^self setToken: #number value: (self floatFrom: mantissa radix: radix exponent: exponent)
!
scanDigits: radix
	| value digit |
	value := 0.
	[digit := self digitValueOf: (self charAt: mark).
	 digit < radix] whileTrue: [
		value := value * radix + digit.
		mark := mark + 1].
	^value
!
power: base to: exponent
	| result |
	result := 1.
	1 to: exponent do: [:i | result := result * base].
	^result
!
floatFrom: mantissa radix: radix exponent: exponent
	exponent >= 0 ifTrue: [^(mantissa * (self power: radix to: exponent)) asFloat].
	^mantissa asFloat / (self power: radix to: exponent negated) asFloat
!
setToken: aSymbol value: anObject
	tokenType := aSymbol.
	tokenValue := anObject.
	tokenStop := mark - 1.
	^aSymbol
!
setError: aString kind: aSymbol
	tokenType := #error.
	tokenValue := aString.
	errorKind := aSymbol.
	tokenStop := mark - 1.
	^#error
! !

!Scanner methodsFor: 'highlighting'!
highlightDo: aBlock
	| depth type |
	depth := 0.
	[self skipSeparators.
	 mark <= size] whileTrue: [
		(source at: mark) == $"
			ifTrue: [
				self scanComment.
				aBlock value: #comment value: tokenStart value: tokenStop]
			ifFalse: [
				self scanToken.
				type := self highlightTypeInLiteral: depth > 0.
				(tokenType == #literalArrayStart or: [tokenType == #byteArrayStart])
					ifTrue: [depth := depth + 1]
					ifFalse: [
						depth > 0 ifTrue: [
							tokenType == #leftParen ifTrue: [
								depth := depth + 1.
								type := #literalArrayStart].
							(tokenType == #rightParen or: [tokenType == #rightBracket])
								ifTrue: [depth := depth - 1]]].
				aBlock value: type value: tokenStart value: tokenStop]]
!
highlightTypeInLiteral: inLiteral
	| first |
	tokenType == #identifier ifTrue: [
		tokenValue = 'true' ifTrue: [^#true].
		tokenValue = 'false' ifTrue: [^#false].
		tokenValue = 'nil' ifTrue: [^#nil].
		inLiteral ifTrue: [^#symbol].
		tokenValue = 'self' ifTrue: [^#self].
		tokenValue = 'super' ifTrue: [^#super].
		tokenValue = 'thisContext' ifTrue: [^#thisContext].
		first := (tokenValue at: 1) value.
		(first >= 65 and: [first <= 90]) ifTrue: [^#global].
		^#identifier].
	tokenType == #keyword ifTrue: [inLiteral ifTrue: [^#symbol]. ^#keyword].
	tokenType == #binary ifTrue: [inLiteral ifTrue: [^#symbol]. ^#binary].
	tokenType == #bar ifTrue: [inLiteral ifTrue: [^#symbol]. ^#punctuation].
	(tokenType == #number or: [tokenType == #string or: [tokenType == #symbol or: [tokenType == #character]]])
		ifTrue: [^tokenType].
	(tokenType == #literalArrayStart or: [tokenType == #byteArrayStart]) ifTrue: [^#literalArrayStart].
	tokenType == #assignment ifTrue: [^#assignment].
	tokenType == #return ifTrue: [^#return].
	tokenType == #error ifTrue: [
		errorKind == #unterminatedString ifTrue: [^#string].
		^#error].
	^#punctuation
! !
