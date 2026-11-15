ArrayedCollection subclass: #String
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

String comment: 'I am the abstract class of sequences of Characters. ByteString holds code points up to 255 in bytes, WideString any code point in 32-bit units; storing a wide Character into a ByteString turns it into a WideString. Strings compare by code points; = ignores the representation, and hash (FNV-1a over code points) is the same for equal Strings and Symbols. String new: answers a ByteString.'!

!String methodsFor: 'accessing'!
at: index
	<primitive: 'stringAt'>
	^self errorSubscriptBounds: index
!
at: index put: aCharacter
	<primitive: 'stringAtPut'>
	^self primAt: index failedToPut: aCharacter
!
primAt: index failedToPut: aCharacter
	self isReadOnlyObject ifTrue: [
		^self modificationForbiddenFor: #at:put: index: index value: aCharacter].
	aCharacter isCharacter ifFalse: [^self error: 'Strings only store Characters'].
	index isInteger ifFalse: [^self errorNonIntegerIndex].
	(index between: 1 and: self size) ifFalse: [^self errorSubscriptBounds: index].
	^self errorImproperStore
!
size
	<primitive: 'basicSize'>
	^self basicSize
!
lineCount
	^self lines size
!
indexOf: anObject
	^self indexOf: anObject startingAt: 1
!
indexOf: anObject startingAt: start
	"Answer the index of the first element equal to anObject at or after start, 0 if none."
	<primitive: 'stringIndexOf'>
	start to: self size do: [:i | (self at: i) = anObject ifTrue: [^i]].
	^0
!
indexOf: anObject startingAt: start ifAbsent: aBlock
	| i |
	i := self indexOf: anObject startingAt: start.
	^i = 0 ifTrue: [aBlock value] ifFalse: [i]
!
indexOfSubCollection: aString startingAt: start
	"Answer the index where aString begins at or after start, 0 if it does not occur."
	<primitive: 'stringIndexOfSubstring'>
	^super indexOfSubCollection: aString startingAt: start
! !

!String methodsFor: 'private'!
streamAt: index put: aCharacter
	"Like at:put:, but answer nil if aCharacter needs a WideString (WriteStream then widens)."
	<primitive: 'stringAtPut'>
	(aCharacter isCharacter and: [aCharacter value > 255 and: [self isWideString not and: [self isReadOnlyObject not]]])
		ifTrue: [^nil].
	^self at: index put: aCharacter
! !

!String methodsFor: 'comparing'!
= aString
	"Answer whether aString is a String (or Symbol) with the same characters."
	self == aString ifTrue: [^true].
	aString isString ifFalse: [^false].
	self size = aString size ifFalse: [^false].
	^(self compare: aString) = 0
!
hash
	"FNV-1a over the code points, the same function as Symbol>>hash."
	<primitive: 'stringHash'>
	| h |
	h := 2166136261.
	self do: [:c | h := ((h bitXor: c value) * 16777619) bitAnd: 16rFFFFFFFF].
	^h bitAnd: 16r3FFFFFFF
!
compare: aString
	"Answer -1, 0 or 1 comparing code points."
	<primitive: 'stringCompare'>
	| n |
	aString isString ifFalse: [^self error: 'Can only compare with a String'].
	n := self size min: aString size.
	1 to: n do: [:i |
		| a b |
		a := (self at: i) value.
		b := (aString at: i) value.
		a < b ifTrue: [^-1].
		a > b ifTrue: [^1]].
	self size < aString size ifTrue: [^-1].
	self size > aString size ifTrue: [^1].
	^0
!
< aString
	^(self compare: aString) < 0
!
<= aString
	^(self compare: aString) <= 0
!
> aString
	^(self compare: aString) > 0
!
>= aString
	^(self compare: aString) >= 0
!
max: aString
	^self > aString ifTrue: [self] ifFalse: [aString]
!
min: aString
	^self < aString ifTrue: [self] ifFalse: [aString]
!
caseInsensitiveCompare: aString
	"Answer -1, 0 or 1 comparing the code points of our lowercase characters, as compare: does those of asLowercase copies."
	<primitive: 'stringCaseInsensitiveCompare'>
	| n |
	n := self size min: aString size.
	1 to: n do: [:i |
		| a b |
		a := self at: i.
		b := aString at: i.
		a == b ifFalse: [
			a := a asLowercase value.
			b := b asLowercase value.
			a = b ifFalse: [^a < b ifTrue: [-1] ifFalse: [1]]]].
	^(self size - aString size) sign
!
sameAs: aString
	"Answer whether aString has the same characters, ignoring case."
	^self size = aString size and: [(self caseInsensitiveCompare: aString) = 0]
!
caseInsensitiveLessOrEqual: aString
	^(self caseInsensitiveCompare: aString) <= 0
!
includesSubstring: aString
	^(self indexOfSubCollection: aString startingAt: 1) > 0
!
includesSubstring: aString caseSensitive: aBoolean
	aBoolean ifTrue: [^self includesSubstring: aString].
	^self asLowercase includesSubstring: aString asLowercase
!
beginsWith: aString
	^super beginsWith: aString
!
startsWith: aString
	^self beginsWith: aString
!
match: aString
	"Answer whether aString matches the receiver as a pattern: * matches any sequence, # any one character; case-insensitive."
	^self asLowercase matchPattern: 1 against: aString asLowercase at: 1
!
matchPattern: p against: aString at: s
	| pi si |
	pi := p.
	si := s.
	[pi <= self size] whileTrue: [
		| c |
		c := self at: pi.
		c = $* ifTrue: [
			pi = self size ifTrue: [^true].
			si to: aString size + 1 do: [:k |
				(self matchPattern: pi + 1 against: aString at: k) ifTrue: [^true]].
			^false].
		si > aString size ifTrue: [^false].
		(c = $# or: [c = (aString at: si)]) ifFalse: [^false].
		pi := pi + 1.
		si := si + 1].
	^si > aString size
! !

!String methodsFor: 'testing'!
includes: anObject
	^(self indexOf: anObject startingAt: 1) > 0
!
occurrencesOf: anObject
	| n i |
	n := 0.
	i := 0.
	[(i := self indexOf: anObject startingAt: i + 1) > 0] whileTrue: [n := n + 1].
	^n
!
isString
	^true
!
isSymbol
	^false
!
isByteString
	^false
!
isWideString
	^false
!
isLiteral
	^true
!
isAllDigits
	^self notEmpty and: [self allSatisfy: [:c | c isDigit]]
!
isAllSeparators
	^self allSatisfy: [:c | c isSeparator]
!
isOctetString
	"Answer whether every code point fits in a byte."
	^self allSatisfy: [:c | c value < 256]
!
isValidSelector
	^self numArgs >= 0
! !

!String methodsFor: 'enumerating'!
collect: aBlock
	"Answer a String of the Characters aBlock answers (widening if needed)."
	| stream |
	stream := WriteStream on: (String new: self size).
	1 to: self size do: [:i | stream nextPut: (aBlock value: (self at: i))].
	^stream contents
! !

!String methodsFor: 'converting'!
asString
	^self
!
asSymbol
	"Answer the unique Symbol with my characters."
	^Symbol intern: self
!
asNumber
	"Answer the number I describe, or nil."
	^Number readFrom: self ifFail: [nil]
!
asInteger
	"Answer the integer formed by the first run of digits (with a preceding minus), or nil."
	| start stop negative value |
	start := self findFirst: [:c | c isDigit].
	start = 0 ifTrue: [^nil].
	negative := start > 1 and: [(self at: start - 1) = $-].
	stop := start.
	[stop < self size and: [(self at: stop + 1) isDigit]] whileTrue: [stop := stop + 1].
	value := 0.
	start to: stop do: [:i | value := value * 10 + (self at: i) digitValue].
	^negative ifTrue: [value negated] ifFalse: [value]
!
asUppercase
	<primitive: 'stringAsUppercase'>
	^self collect: [:c | c asUppercase]
!
asLowercase
	<primitive: 'stringAsLowercase'>
	^self collect: [:c | c asLowercase]
!
capitalized
	| copy |
	self isEmpty ifTrue: [^self].
	copy := self asString copy.
	copy at: 1 put: (copy at: 1) asUppercase.
	^copy
!
uncapitalized
	| copy |
	self isEmpty ifTrue: [^self].
	copy := self asString copy.
	copy at: 1 put: (copy at: 1) asLowercase.
	^copy
!
asWideString
	| w |
	w := WideString new: self size.
	1 to: self size do: [:i | w at: i put: (self at: i)].
	^w
!
asByteString
	"Answer a ByteString with my characters; they must all fit in a byte."
	| b |
	b := ByteString new: self size.
	1 to: self size do: [:i | b at: i put: (self at: i)].
	^b
!
asByteArray
	"Answer my code points as bytes (they must fit); see utf8Encoded."
	| bytes |
	bytes := ByteArray new: self size.
	1 to: self size do: [:i | bytes at: i put: (self at: i) value].
	^bytes
!
utf8Encoded
	"Answer a ByteArray with my UTF-8 encoding, always well-formed: a surrogate code point (U+D800-DFFF), which has none, becomes U+FFFD."
	| stream |
	stream := WriteStream on: (ByteArray new: self size).
	self do: [:c |
		| cp |
		cp := c value.
		(cp between: 16rD800 and: 16rDFFF) ifTrue: [cp := 16rFFFD].
		cp < 16r80
			ifTrue: [stream nextPut: cp]
			ifFalse: [
				cp < 16r800
					ifTrue: [
						stream nextPut: 16rC0 + (cp bitShift: -6).
						stream nextPut: 16r80 + (cp bitAnd: 16r3F)]
					ifFalse: [
						cp < 16r10000
							ifTrue: [
								stream nextPut: 16rE0 + (cp bitShift: -12).
								stream nextPut: 16r80 + ((cp bitShift: -6) bitAnd: 16r3F).
								stream nextPut: 16r80 + (cp bitAnd: 16r3F)]
							ifFalse: [
								stream nextPut: 16rF0 + (cp bitShift: -18).
								stream nextPut: 16r80 + ((cp bitShift: -12) bitAnd: 16r3F).
								stream nextPut: 16r80 + ((cp bitShift: -6) bitAnd: 16r3F).
								stream nextPut: 16r80 + (cp bitAnd: 16r3F)]]]].
	^stream contents
!
substrings
	"Answer an Array of the words separated by white space."
	^self substrings: (String with: Character space with: Character tab with: Character cr with: Character lf) , (String with: Character newPage)
!
substrings: separators
	"Answer an Array of the pieces between separator characters (a String, a Collection or a Character)."
	| seps result start |
	seps := separators isCharacter ifTrue: [String with: separators] ifFalse: [separators].
	result := OrderedCollection new.
	start := nil.
	1 to: self size do: [:i |
		(seps includes: (self at: i))
			ifTrue: [
				start isNil ifFalse: [
					result add: (self copyFrom: start to: i - 1).
					start := nil]]
			ifFalse: [start isNil ifTrue: [start := i]]].
	start isNil ifFalse: [result add: (self copyFrom: start to: self size)].
	^result asArray
!
subStrings
	^self substrings
!
subStrings: separators
	^self substrings: separators
!
splitOn: aString
	"Answer the pieces between occurrences of aString (a separator sequence), keeping empty pieces."
	| result start index sep |
	sep := aString isCharacter ifTrue: [String with: aString] ifFalse: [aString].
	result := OrderedCollection new.
	start := 1.
	[(index := self indexOfSubCollection: sep startingAt: start) > 0] whileTrue: [
		result add: (self copyFrom: start to: index - 1).
		start := index + sep size].
	result add: (self copyFrom: start to: self size).
	^result asArray
!
lines
	"Answer an Array of my lines, split at cr, lf or crlf."
	| result start cr lf end |
	result := OrderedCollection new.
	start := 1.
	cr := self indexOf: Character cr startingAt: 1.
	lf := self indexOf: Character lf startingAt: 1.
	[cr > 0 or: [lf > 0]] whileTrue: [
		end := (cr = 0 or: [lf > 0 and: [lf < cr]]) ifTrue: [lf] ifFalse: [cr].
		result add: (self copyFrom: start to: end - 1).
		start := (end = cr and: [lf = (cr + 1)]) ifTrue: [lf + 1] ifFalse: [end + 1].
		(cr > 0 and: [cr < start]) ifTrue: [cr := self indexOf: Character cr startingAt: start].
		(lf > 0 and: [lf < start]) ifTrue: [lf := self indexOf: Character lf startingAt: start]].
	start <= self size ifTrue: [result add: (self copyFrom: start to: self size)].
	^result asArray
!
keywords
	"Answer the keywords of a selector: 'at:put:' keywords = #('at:' 'put:')."
	| result start |
	(self isEmpty or: [self last ~= $:]) ifTrue: [^Array with: self].
	result := OrderedCollection new.
	start := 1.
	1 to: self size do: [:i |
		(self at: i) = $: ifTrue: [
			result add: (self copyFrom: start to: i).
			start := i + 1]].
	^result asArray
!
numArgs
	"Answer the number of arguments of the selector I spell, or -1 if I am not a selector."
	| first colons |
	self isEmpty ifTrue: [^-1].
	first := self at: 1.
	(first isLetter or: [first = $_]) ifTrue: [
		colons := self occurrencesOf: $:.
		colons = 0 ifTrue: [
			^(self allSatisfy: [:c | c isAlphaNumeric or: [c = $_]]) ifTrue: [0] ifFalse: [-1]].
		self last = $: ifFalse: [^-1].
		^colons].
	^(self allSatisfy: [:c | c isSpecial]) ifTrue: [1] ifFalse: [-1]
! !

!String methodsFor: 'copying'!
, aString
	"Answer the concatenation; WideString if either part needs it."
	| result |
	aString isString ifFalse: [^super , aString].
	result := ((self isWideString or: [aString isWideString]) ifTrue: [WideString] ifFalse: [ByteString])
		new: self size + aString size.
	result replaceFrom: 1 to: self size with: self startingAt: 1.
	result replaceFrom: self size + 1 to: result size with: aString startingAt: 1.
	^result
!
copyWith: aCharacter
	| result |
	result := ((self isWideString or: [aCharacter isCharacter and: [aCharacter value > 255]])
		ifTrue: [WideString] ifFalse: [ByteString]) new: self size + 1.
	result replaceFrom: 1 to: self size with: self startingAt: 1.
	result at: self size + 1 put: aCharacter.
	^result
!
copyReplaceFrom: start to: stop with: replacement
	"Answer a copy with start..stop replaced; a WideString if either part needs it."
	| result endReplacement newSize |
	(replacement isString and: [replacement isWideString and: [self isWideString not]])
		ifFalse: [^super copyReplaceFrom: start to: stop with: replacement].
	newSize := self size - (stop - start + 1) + replacement size.
	endReplacement := start - 1 + replacement size.
	result := WideString new: newSize.
	1 to: start - 1 do: [:i | result at: i put: (self at: i)].
	result replaceFrom: start to: endReplacement with: replacement startingAt: 1.
	stop + 1 to: self size do: [:i | result at: endReplacement + i - stop put: (self at: i)].
	^result
!
copyReplaceAll: oldString with: newString
	^super copyReplaceAll: oldString with: newString
!
trimBoth
	"Answer a copy without leading and trailing white space."
	^self trimBoth: [:c | c isSeparator]
!
trimBoth: aBlock
	| start stop |
	start := 1.
	stop := self size.
	[start <= stop and: [aBlock value: (self at: start)]] whileTrue: [start := start + 1].
	[stop >= start and: [aBlock value: (self at: stop)]] whileTrue: [stop := stop - 1].
	^self copyFrom: start to: stop
!
trimmed
	^self trimBoth
!
trimLeft
	| start |
	start := 1.
	[start <= self size and: [(self at: start) isSeparator]] whileTrue: [start := start + 1].
	^self copyFrom: start to: self size
!
trimRight
	| stop |
	stop := self size.
	[stop >= 1 and: [(self at: stop) isSeparator]] whileTrue: [stop := stop - 1].
	^self copyFrom: 1 to: stop
!
padLeftTo: width with: aCharacter
	self size >= width ifTrue: [^self].
	^(String new: width - self size withAll: aCharacter), self
!
padRightTo: width with: aCharacter
	self size >= width ifTrue: [^self].
	^self, (String new: width - self size withAll: aCharacter)
!
padLeftTo: width
	^self padLeftTo: width with: Character space
!
padRightTo: width
	^self padRightTo: width with: Character space
!
format: arguments
	"Replace {1}, {2}... by the corresponding elements of arguments (or {key} by dictionary values), using asString. \{ escapes a brace."
	| stream i c |
	stream := WriteStream on: (String new: self size).
	i := 1.
	[i <= self size] whileTrue: [
		c := self at: i.
		(c = $\ and: [i < self size and: [(self at: i + 1) = ${]])
			ifTrue: [stream nextPut: ${. i := i + 2]
			ifFalse: [
				c = ${
					ifTrue: [
						| close key value |
						close := self indexOf: $} startingAt: i + 1.
						close = 0 ifTrue: [^self error: 'Unmatched { in format string'].
						key := self copyFrom: i + 1 to: close - 1.
						value := arguments isDictionary
							ifTrue: [arguments at: key ifAbsent: [arguments at: key asSymbol]]
							ifFalse: [arguments at: key asInteger].
						stream nextPutAll: value asString.
						i := close + 1]
					ifFalse: [stream nextPut: c. i := i + 1]]].
	^stream contents
!
withCRs
	"Answer a copy with each backslash replaced by a carriage return."
	^self collect: [:c | c = $\ ifTrue: [Character cr] ifFalse: [c]]
!
surroundedBy: aString
	^aString, self, aString
! !

!String methodsFor: 'printing'!
printOn: aStream
	"Print with quotes, doubling embedded quotes: 'it''s'."
	aStream nextPut: $'.
	self do: [:c |
		c = $' ifTrue: [aStream nextPut: $'].
		aStream nextPut: c].
	aStream nextPut: $'
!
storeOn: aStream
	self printOn: aStream
!
displayOn: aStream
	aStream nextPutAll: self
!
displayString
	^self copy
! !

!String methodsFor: 'private'!
species
	^self isWideString ifTrue: [WideString] ifFalse: [ByteString]
! !

!String class methodsFor: 'instance creation'!
new
	^self == String ifTrue: [ByteString new: 0] ifFalse: [self basicNew: 0]
!
new: size
	"String new: answers a ByteString; it widens itself when it has to hold a wide Character."
	^self == String ifTrue: [ByteString new: size] ifFalse: [self basicNew: size]
!
new: size withAll: aCharacter
	| result |
	result := (self classForCharacters: (Array with: aCharacter)) basicNew: size.
	result atAllPut: aCharacter.
	^result
!
with: aCharacter
	^(self withAll: (Array with: aCharacter))
!
with: first with: second
	^self withAll: (Array with: first with: second)
!
with: first with: second with: third
	^self withAll: (Array with: first with: second with: third)
!
with: first with: second with: third with: fourth
	^self withAll: (Array with: first with: second with: third with: fourth)
!
withAll: aCollection
	"Answer a String with the characters of aCollection, a WideString up front if any needs it (no widening later)."
	| result i |
	result := (self classForCharacters: aCollection) basicNew: aCollection size.
	i := 0.
	aCollection do: [:c | result at: (i := i + 1) put: c].
	^result
!
classForCharacters: aCollection
	"String and ByteString answer ByteString unless a character needs 32 bits."
	(self == String or: [self == ByteString]) ifFalse: [^self].
	(aCollection isString and: [aCollection isWideString not]) ifTrue: [^ByteString].
	^(aCollection anySatisfy: [:c | c isCharacter and: [c value > 255]])
		ifTrue: [WideString]
		ifFalse: [ByteString]
!
cr
	^self with: Character cr
!
lf
	^self with: Character lf
!
crlf
	^self with: Character cr with: Character lf
!
tab
	^self with: Character tab
!
space
	^self with: Character space
!
empty
	^self new: 0
!
fromByteArray: aByteArray
	^aByteArray asString
!
fromUTF8: aByteArray
	^aByteArray utf8Decoded
! !
