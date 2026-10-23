Object subclass: #CompilerScope
	instanceVariableNames: 'outer inlined entries numArgs numTemps slotNames'
	classVariableNames: ''
	package: 'Compiler'!

CompilerScope comment: 'I am a lexical scope during code generation: a method, a real block (its own context), or an inlined block (whose arguments and temporaries live in the enclosing real scope). entries maps names to {index. isArgument}; numArgs, numTemps and slotNames describe the frame of a real scope.'!

!CompilerScope class methodsFor: 'instance creation'!
outer: aScopeOrNil inlined: aBoolean
	^self new setOuter: aScopeOrNil inlined: aBoolean
! !

!CompilerScope methodsFor: 'initialization'!
setOuter: aScopeOrNil inlined: aBoolean
	outer := aScopeOrNil.
	inlined := aBoolean.
	entries := Dictionary new.
	numArgs := 0.
	numTemps := 0.
	slotNames := OrderedCollection new
! !

!CompilerScope methodsFor: 'accessing'!
outer
	^outer
!
isInlined
	^inlined
!
realScope
	"Answer the scope whose context holds my variables."
	^inlined ifTrue: [outer realScope] ifFalse: [self]
!
numArgs
	^numArgs
!
numTemps
	^numTemps
!
slotNames
	^slotNames asArray
! !

!CompilerScope methodsFor: 'declaring'!
declares: aString
	^entries includesKey: aString
!
declareArgument: aString
	"Declare a real argument (method or real block). Arguments precede temporaries."
	| index |
	inlined ifTrue: [^self declareSlot: aString argument: true].
	index := numArgs.
	numArgs := numArgs + 1.
	slotNames add: aString.
	entries at: aString put: (Array with: index with: true).
	^index
!
declareTemporary: aString
	^self declareSlot: aString argument: false
!
declareSlot: aString argument: aBoolean
	| index |
	index := self realScope allocateSlotNamed: aString.
	entries at: aString put: (Array with: index with: aBoolean).
	^index
!
allocateSlotNamed: aString
	"Allocate a temporary slot in my frame (I am a real scope)."
	| index |
	index := numArgs + numTemps.
	numTemps := numTemps + 1.
	slotNames add: aString.
	^index
!
indexOf: aString
	^(entries at: aString) at: 1
! !

!CompilerScope methodsFor: 'lookup'!
lookup: aString
	"Answer {index. depth. isArgument} or nil. depth counts the contexts between the current one and the one holding the variable."
	| scope depth entry |
	scope := self.
	depth := 0.
	[scope notNil] whileTrue: [
		entry := scope entryAt: aString.
		entry notNil ifTrue: [^Array with: (entry at: 1) with: depth with: (entry at: 2)].
		scope isInlined ifFalse: [depth := depth + 1].
		scope := scope outer].
	^nil
!
entryAt: aString
	^entries at: aString ifAbsent: [nil]
! !
