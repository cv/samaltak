Magnitude immediateSubclass: #Character
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Character comment: 'I am a Unicode character, encoded in the object pointer (tag 010) with my code point. Equal characters are identical. Classification and case conversion cover ASCII and Latin-1; other code points are treated as letters without case.'!

!Character methodsFor: 'accessing'!
value
	"Answer my code point."
	<primitive: 'charValue'>
	^self primitiveFailed
!
asInteger
	^self value
!
codePoint
	^self value
!
asCharacter
	^self
!
digitValue
	"Answer 0-9 for $0-$9, 10-35 for $A-$Z and $a-$z, -1 otherwise."
	| v |
	v := self value.
	(v between: 48 and: 57) ifTrue: [^v - 48].
	(v between: 65 and: 90) ifTrue: [^v - 55].
	(v between: 97 and: 122) ifTrue: [^v - 87].
	^-1
! !

!Character methodsFor: 'comparing'!
< aCharacter
	^self value < aCharacter value
!
> aCharacter
	^self value > aCharacter value
!
<= aCharacter
	^self value <= aCharacter value
!
>= aCharacter
	^self value >= aCharacter value
!
= aCharacter
	^self == aCharacter
!
hash
	^self value
!
identityHash
	^self value
! !

!Character methodsFor: 'testing'!
isCharacter
	^true
!
isLetter
	| v |
	v := self value.
	(v between: 65 and: 90) ifTrue: [^true].
	(v between: 97 and: 122) ifTrue: [^true].
	v < 192 ifTrue: [^v = 170 or: [v = 181 or: [v = 186]]].
	v < 256 ifTrue: [^v ~= 215 and: [v ~= 247]].
	^true
!
isDigit
	^self value between: 48 and: 57
!
isAlphaNumeric
	^self isLetter or: [self isDigit]
!
isUppercase
	| v |
	v := self value.
	(v between: 65 and: 90) ifTrue: [^true].
	^(v between: 192 and: 222) and: [v ~= 215]
!
isLowercase
	| v |
	v := self value.
	(v between: 97 and: 122) ifTrue: [^true].
	^(v between: 223 and: 255) and: [v ~= 247]
!
isVowel
	"Answer whether I am one of aeiouAEIOU."
	^'aeiouAEIOU' includes: self
!
isSeparator
	"Answer whether I am space, tab, cr, lf or form feed."
	| v |
	v := self value.
	^v = 32 or: [v = 9 or: [v = 13 or: [v = 10 or: [v = 12]]]]
!
isPunctuation
	^'.,:;!!?' includes: self
!
isSpecial
	"Answer whether I can be part of a binary selector."
	^'+-*/\<>=~@%|&?,' includes: self
!
isOctetCharacter
	^self value < 256
!
isAscii
	^self value < 128
!
isPrintable
	| v |
	v := self value.
	^v >= 32 and: [v ~= 127]
!
isLiteral
	^true
! !

!Character methodsFor: 'converting'!
asUppercase
	| v |
	v := self value.
	(v between: 97 and: 122) ifTrue: [^Character value: v - 32].
	((v between: 224 and: 254) and: [v ~= 247]) ifTrue: [^Character value: v - 32].
	v = 255 ifTrue: [^Character value: 376].
	^self
!
asLowercase
	| v |
	v := self value.
	(v between: 65 and: 90) ifTrue: [^Character value: v + 32].
	((v between: 192 and: 222) and: [v ~= 215]) ifTrue: [^Character value: v + 32].
	v = 376 ifTrue: [^Character value: 255].
	^self
!
asString
	^String with: self
!
asSymbol
	^Symbol intern: self asString
!
to: aCharacter
	"Answer an Array of the characters from me to aCharacter."
	^(self value to: aCharacter value) collect: [:v | Character value: v]
! !

!Character methodsFor: 'printing'!
printOn: aStream
	| name |
	name := self class constantNameFor: self.
	name isNil ifFalse: [^aStream nextPutAll: 'Character '; nextPutAll: name].
	self isPrintable ifFalse: [^aStream nextPutAll: '(Character value: '; print: self value; nextPut: $)].
	aStream nextPut: $$; nextPut: self
!
storeOn: aStream
	self printOn: aStream
!
displayOn: aStream
	aStream nextPut: self
! !

!Character methodsFor: 'copying'!
shallowCopy
	^self
!
deepCopy
	^self
! !

!Character class methodsFor: 'instance creation'!
value: anInteger
	"Answer the Character with code point anInteger."
	<primitive: 'charFromValue'>
	^self error: 'Not a valid code point: ', anInteger printString
!
codePoint: anInteger
	^self value: anInteger
!
digitValue: anInteger
	"Answer $0-$9 for 0-9 and $A-$Z for 10-35."
	^anInteger < 10
		ifTrue: [self value: anInteger + 48]
		ifFalse: [self value: anInteger + 55]
!
new
	^self error: 'Characters are created with value:'
!
basicNew
	^self error: 'Characters are created with value:'
! !

!Character class methodsFor: 'constants'!
cr
	^self value: 13
!
lf
	^self value: 10
!
newLine
	^self value: 10
!
tab
	^self value: 9
!
space
	^self value: 32
!
null
	^self value: 0
!
nul
	^self value: 0
!
backspace
	^self value: 8
!
escape
	^self value: 27
!
delete
	^self value: 127
!
newPage
	^self value: 12
!
arrowLeft
	^self value: 28
!
arrowRight
	^self value: 29
!
arrowUp
	^self value: 30
!
arrowDown
	^self value: 31
!
separators
	^String with: self space with: self tab with: self cr with: self lf
!
constantNameFor: aCharacter
	"Answer the selector naming aCharacter (e.g. 'space'), or nil."
	| v |
	v := aCharacter value.
	v = 32 ifTrue: [^'space'].
	v = 13 ifTrue: [^'cr'].
	v = 10 ifTrue: [^'lf'].
	v = 9 ifTrue: [^'tab'].
	v = 0 ifTrue: [^'null'].
	v = 8 ifTrue: [^'backspace'].
	v = 27 ifTrue: [^'escape'].
	v = 127 ifTrue: [^'delete'].
	v = 12 ifTrue: [^'newPage'].
	^nil
! !
