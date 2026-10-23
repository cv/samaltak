String subclass: #Symbol
	instanceVariableNames: ''
	classVariableNames: 'SymbolTable'
	package: 'Kernel-Collections'!

Symbol comment: 'I am a unique, read-only String used for selectors and names: two Symbols with the same characters are the same object, so they compare with ==. Symbol intern: (or asSymbol) finds or creates them via SymbolTable, a Set of all Symbols that is rebuilt from the existing instances at startup. ByteSymbol and WideSymbol are the two representations. Copies of a Symbol are Strings.'!

!Symbol methodsFor: 'accessing'!
at: index put: aCharacter
	^self modificationForbiddenFor: #at:put: index: index value: aCharacter
!
privateAt: index put: aCharacter
	"Only used while creating a Symbol."
	<primitive: 'stringAtPut'>
	^self primitiveFailed
! !

!Symbol methodsFor: 'comparing'!
= anObject
	^self == anObject
! !

!Symbol methodsFor: 'testing'!
isSymbol
	^true
!
isString
	^true
!
isLiteral
	^true
!
isUnary
	^self numArgs = 0
!
isBinary
	^self notEmpty and: [self first isSpecial]
!
isKeyword
	^self notEmpty and: [self last = $:]
! !

!Symbol methodsFor: 'converting'!
asString
	"Answer a String (not a Symbol) with my characters."
	| s |
	s := self species new: self size.
	s replaceFrom: 1 to: self size with: self startingAt: 1.
	^s
!
asSymbol
	^self
!
displayString
	^self asString
! !

!Symbol methodsFor: 'evaluating'!
value: anObject
	"Symbols can be used as one-argument blocks: #size value: 'abc' = 3."
	^anObject perform: self
!
value: anObject value: anArgument
	^anObject perform: self with: anArgument
!
cull: anObject
	^anObject perform: self
! !

!Symbol methodsFor: 'copying'!
shallowCopy
	^self
!
copy
	^self
!
deepCopy
	^self
! !

!Symbol methodsFor: 'printing'!
printOn: aStream
	"Print as #foo, #at:put:, #+ or #'not a selector'."
	aStream nextPut: $#.
	self isValidLiteralSymbol
		ifTrue: [aStream nextPutAll: self]
		ifFalse: [super printOn: aStream]
!
storeOn: aStream
	self printOn: aStream
!
isValidLiteralSymbol
	"Answer whether I can be written as #me without quotes."
	| first |
	self isEmpty ifTrue: [^false].
	first := self first.
	(first isLetter or: [first = $_]) ifTrue: [
		^(self allSatisfy: [:c | c isAlphaNumeric or: [c = $_ or: [c = $:]]])
			and: [(self includes: $:) not or: [self last = $:]]].
	^self allSatisfy: [:c | c isSpecial]
! !

!Symbol methodsFor: 'private'!
species
	^self isWideString ifTrue: [WideString] ifFalse: [ByteString]
! !

!Symbol class methodsFor: 'instance creation'!
intern: aString
	"Answer the unique Symbol with the characters of aString, creating it if needed."
	| symbol |
	symbol := self lookup: aString.
	symbol isNil ifFalse: [^symbol].
	symbol := (aString isOctetString ifTrue: [ByteSymbol] ifFalse: [WideSymbol]) basicNew: aString size.
	1 to: aString size do: [:i | symbol privateAt: i put: (aString at: i)].
	symbol beReadOnlyObject.
	SymbolTable add: symbol.
	^symbol
!
lookup: aString
	"Answer the existing Symbol with the characters of aString, or nil."
	^SymbolTable like: aString
!
findInterned: aString
	^self lookup: aString
!
new: size
	^self error: 'Symbols are created with intern: or asSymbol'
!
new
	^self error: 'Symbols are created with intern: or asSymbol'
!
newFrom: aString
	^self intern: aString asString
!
with: aCharacter
	^self intern: (String with: aCharacter)
!
withAll: aCollection
	^self intern: (String withAll: aCollection)
! !

!Symbol class methodsFor: 'symbol table'!
rebuildSymbolTable
	"Collect every existing Symbol into a fresh SymbolTable."
	| symbols |
	symbols := ByteSymbol allInstances, WideSymbol allInstances.
	SymbolTable := Set new: symbols size * 2.
	symbols do: [:s | SymbolTable add: s]
!
allSymbols
	^SymbolTable asArray
!
symbolTable
	^SymbolTable
! !
