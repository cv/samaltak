Object subclass: #CompiledMethod
	instanceVariableNames: 'selector methodClass literals bytecodes numArgs numTemps frameSize primitive source category pragmas sourceMap properties'
	classVariableNames: 'SpecialSelectors'
	package: 'Kernel-Methods'!

CompiledMethod comment: 'I am a compiled method: bytecodes (a ByteArray) plus the literals they refer to, my frame shape (numArgs, numTemps excluding args, frameSize = args + temps + max stack depth), an optional primitive number, my source and category, pragmas (Messages), and a sourceMap (pc start stop triples) for the debugger. My field order is fixed by the VM. I can answer which selectors I send and which literals I use; that drives senders/implementors queries.'!

!CompiledMethod methodsFor: 'accessing'!
selector
	^selector
!
selector: aSymbol
	selector := aSymbol
!
methodClass
	^methodClass
!
methodClass: aClass
	methodClass := aClass
!
literals
	^literals ifNil: [#()]
!
literals: anArray
	literals := anArray
!
literalAt: index
	^literals at: index
!
numLiterals
	^self literals size
!
bytecodes
	^bytecodes
!
bytecodes: aByteArray
	bytecodes := aByteArray
!
numArgs
	^numArgs
!
numArgs: anInteger
	numArgs := anInteger
!
numTemps
	"Answer the number of temporaries, excluding arguments."
	^numTemps
!
numTemps: anInteger
	numTemps := anInteger
!
frameSize
	^frameSize
!
frameSize: anInteger
	frameSize := anInteger
!
primitive
	"Answer my primitive number, 0 if none."
	^primitive ifNil: [0]
!
primitive: anInteger
	primitive := anInteger
!
primitiveNumber
	"Answer my primitive number without the error-code flag, 0 if none."
	^self primitive bitAnd: VMConstants cmPrimMask
!
primitiveName
	"Answer the name of my primitive, or nil."
	| names |
	self primitive = 0 ifTrue: [^nil].
	names := Smalltalk vm primitiveNames.
	^(primitive between: 1 and: names size)
		ifTrue: [names at: primitive]
		ifFalse: [primitive printString]
!
source
	^source
!
source: aString
	source := aString
!
sourceCode
	"Answer my source code (a String), or nil if unknown."
	^source
!
sourceCode: aString
	source := aString
!
category
	^category
!
category: aString
	category := aString
!
protocol
	^category
!
pragmas
	^pragmas ifNil: [#()]
!
pragmas: anArray
	pragmas := anArray
!
pragmaAt: aSelector
	^self pragmas detect: [:p | p selector == aSelector] ifNone: [nil]
!
sourceMap
	^sourceMap
!
sourceMap: anArray
	sourceMap := anArray
!
properties
	^properties
!
properties: aDictionary
	properties := aDictionary
!
propertyAt: aKey
	^properties isNil ifTrue: [nil] ifFalse: [properties at: aKey ifAbsent: [nil]]
!
propertyAt: aKey put: anObject
	properties isNil ifTrue: [properties := IdentityDictionary new].
	^properties at: aKey put: anObject
!
initialPC
	^0
!
endPC
	^bytecodes size - 1
!
methodReference
	^methodClass name, '>>', selector
! !

!CompiledMethod methodsFor: 'testing'!
isCompiledMethod
	^true
!
hasPrimitive
	^self primitive ~= 0
!
isUnwindMarker
	"ensure: and ifCurtailed: carry the marker primitive ensureMarker."
	^self primitive = VMConstants primEnsureMarker
!
isHandlerMarker
	"on:do: carries the marker primitive onDoMarker."
	^self primitive = VMConstants primOndoMarker
!
hasRunnablePrimitive
	"Answer whether I have a primitive the VM runs (not 0, not a marker)."
	| prim |
	prim := self primitiveNumber.
	^prim ~= 0 and: [prim ~= VMConstants primEnsureMarker and: [prim ~= VMConstants primOndoMarker]]
!
isQuick
	"Answer whether I just answer self, an instance variable or a constant."
	^self isReturnSelf or: [self isReturnField or: [self isReturnConstant]]
!
isReturnSelf
	^bytecodes size = 1 and: [(bytecodes at: 1) = 16r7A]
!
isReturnField
	^bytecodes size = 2
		and: [(bytecodes at: 2) = 16r79
		and: [(bytecodes at: 1) between: 16r10 and: 16r1F]]
!
returnField
	"Answer the 1-based index of the instance variable I answer."
	^(bytecodes at: 1) - 16r10 + 1
!
isReturnConstant
	^bytecodes size = 2
		and: [(bytecodes at: 2) = 16r79
		and: [((bytecodes at: 1) between: 16r71 and: 16r75) or: [(bytecodes at: 1) between: 16r20 and: 16r3F]]]
!
isAbstract
	"Answer whether my body is just a send of subclassResponsibility."
	^(self messages includes: #subclassResponsibility) and: [self messages size = 1]
!
refersToLiteral: anObject
	"Answer whether anObject is one of my literals (also inside literal arrays)."
	self literals do: [:lit |
		(lit == anObject or: [lit class == anObject class and: [lit = anObject]]) ifTrue: [^true].
		(lit class == Association and: [lit key == anObject]) ifTrue: [^true].
		(lit class == Array and: [lit refersToLiteral: anObject]) ifTrue: [^true]].
	^false
!
sendsSelector: aSymbol
	^self messages includes: aSymbol
! !

!CompiledMethod methodsFor: 'scanning'!
messages
	"Answer the Set of selectors I send."
	| result |
	result := IdentitySet new.
	self sendsDo: [:sel | result add: sel].
	^result
!
sendsDo: aBlock
	"Evaluate aBlock with each selector sent by my bytecodes, in order."
	self instructionsDo: [:pc :op |
		(op = 16r8D or: [op = 16r8E]) ifTrue: [aBlock value: (literals at: (bytecodes at: pc + 2) + 1)].
		(op between: 16rA0 and: 16rBF) ifTrue: [aBlock value: (self class specialSelectorAt: op - 16rA0 + 1)].
		(op between: 16rC0 and: 16rEF) ifTrue: [aBlock value: (literals at: (op bitAnd: 16r0F) + 1)].
		(op between: 16r97 and: 16r99) ifTrue: [aBlock value: (self class specialSelectorAt: (bytecodes at: pc + 4) - 16rA0 + 1)]]
!
instructionsDo: aBlock
	"Evaluate aBlock with the 0-based pc and the opcode of each instruction, including those in block bodies."
	| pc op |
	pc := 0.
	[pc < bytecodes size] whileTrue: [
		op := bytecodes at: pc + 1.
		aBlock value: pc value: op.
		pc := pc + (self class instructionLengthAt: op)]
! !

!CompiledMethod methodsFor: 'printing'!
printOn: aStream
	aStream
		nextPutAll: (methodClass isNil ifTrue: ['nil'] ifFalse: [methodClass name]);
		nextPutAll: '>>';
		nextPutAll: (selector isNil ifTrue: ['?'] ifFalse: [selector])
!
printNameOn: aStream
	self printOn: aStream
!
storeOn: aStream
	aStream nextPut: $(; nextPutAll: methodClass name; nextPutAll: ' >> '; print: selector; nextPut: $)
! !

!CompiledMethod methodsFor: 'copying'!
postCopy
	literals := literals copy
! !

!CompiledMethod class methodsFor: 'bytecodes'!
instructionLengthAt: opcode
	"Answer the size in bytes of the instruction starting with opcode. A block push (16r8F) counts as 6: its body follows inline."
	opcode < 16r80 ifTrue: [^1].
	opcode <= 16r89 ifTrue: [^2].
	opcode <= 16r8E ifTrue: [^3].
	opcode = 16r8F ifTrue: [^6].
	opcode <= 16r93 ifTrue: [^3].
	opcode = 16r94 ifTrue: [^2].
	(opcode between: 16r97 and: 16r99) ifTrue: [^4].
	^1
!
specialSelectors
	"The 32 selectors of bytecodes 16rA0..16rBF, in order."
	SpecialSelectors isNil ifTrue: [
		SpecialSelectors := #(#+ #- #< #> #<= #>= #= #~= #* #/ #\\ #@ #bitShift: #// #bitAnd: #bitOr: #at: #at:put: #size #== #~~ #value #value: #isNil #notNil #new #new: #x #y #class #value:value: #max:)].
	^SpecialSelectors
!
specialSelectorAt: index
	^self specialSelectors at: index
! !
