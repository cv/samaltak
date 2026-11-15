Magnitude immediateSubclass: #Character
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Character comment: 'I am a Unicode character, encoded in the object pointer (tag 010) with my code point. Equal characters are identical. Classification, case conversion and display width follow the Unicode Character Database (Unicode, which has the details): isLetter is the general category L*, isDigit Nd (decimal digits of any script; digitValue, for number literals, knows only ASCII digits and letters), isMark M*, isUppercase Lu, isLowercase Ll, isSeparator the White_Space property; asUppercase, asLowercase, asTitlecase and caseFolded are the simple one-to-one mappings.'!

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
!
generalCategory
	"Answer my general category, e.g. #Lu (see Unicode generalCategoryTagOf:)."
	^Unicode generalCategoryTagOf: self value
!
displayWidth
	"Answer the columns I take in a terminal or a monospaced editor: 0, 1 or 2 (see Unicode displayWidthOf:)."
	^Unicode displayWidthOf: self value
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
	<primitive: 'identical'>
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
	^Unicode isLetterCode: self value
!
isDigit
	"Answer whether I am a decimal digit of any script (general category Nd); number syntax uses only $0-$9."
	^Unicode isDigitCode: self value
!
isMark
	"Answer whether I am a combining mark (general category M*)."
	^Unicode isMarkCode: self value
!
isAlphaNumeric
	^self isLetter or: [self isDigit]
!
isUppercase
	^Unicode isUppercaseCode: self value
!
isLowercase
	^Unicode isLowercaseCode: self value
!
isVowel
	"Answer whether I am one of aeiouAEIOU."
	^'aeiouAEIOU' includes: self
!
isSeparator
	"Answer whether I am white space (the White_Space property): space, tab, cr, lf, form feed, no-break spaces, U+3000..."
	^Unicode isWhiteSpaceCode: self value
!
isPunctuation
	^'.,:;!!?' includes: self
!
isSpecial
	"Answer whether I can be part of a binary selector: one of +-*/\<>=~@%|&?, or a non-ASCII math symbol (general category Sm: × ÷ ≠ ≤ → ...)."
	self value < 128 ifTrue: [^'+-*/\<>=~@%|&?,' includes: self].
	^Unicode isMathSymbolCode: self value
!
isOctetCharacter
	^self value < 256
!
isAscii
	^self value < 128
!
isPrintable
	"Answer whether I am visible or a space: not a control, format character, surrogate, unassigned code point or line or paragraph separator."
	^Unicode isPrintableCode: self value
!
isLiteral
	^true
! !

!Character methodsFor: 'converting'!
asUppercase
	^Character value: (Unicode toUppercaseCode: self value)
!
asLowercase
	^Character value: (Unicode toLowercaseCode: self value)
!
asTitlecase
	^Character value: (Unicode toTitlecaseCode: self value)
!
caseFolded
	"Answer my simple case folding, for caseless comparison (mostly asLowercase; µ folds to Greek mu)."
	^Character value: (Unicode caseFoldCode: self value)
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
	(self isPrintable and: [self isSeparator not]) ifFalse: [^aStream nextPutAll: '(Character value: '; print: self value; nextPut: $)].
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
