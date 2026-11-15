UIEvent subclass: #TextEditingEvent
	instanceVariableNames: 'string cursor selectionSize'
	classVariableNames: ''
	package: 'UI-Windows'!

TextEditingEvent comment: 'I am the composition of an input method (type #editing): string is the text being composed, shown at the caret until a TextEvent commits it (or I come again with an empty string, cancelling it); each of me replaces the one before. cursor is the caret within string (0 to its size) and selectionSize the length of the part the input method is converting, in characters; nil when the input method does not say. Delivered like typed text, to the keyboard focus (handleTextEditing:).'!

!TextEditingEvent methodsFor: 'accessing'!
string
	^string
!
cursor
	^cursor
!
selectionSize
	^selectionSize
!
setString: aString cursor: anIntegerOrNil selectionSize: sizeOrNil
	string := aString.
	cursor := anIntegerOrNil.
	selectionSize := sizeOrNil
! !

!TextEditingEvent methodsFor: 'dispatching'!
deliverTo: aWindow
	^aWindow dispatchTextEditing: self
!
dispatchTo: anInputDispatcher
	^anInputDispatcher handleText: self
! !

!TextEditingEvent methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'TextEditingEvent('; print: string; space; print: cursor; nextPut: $)
! !

!TextEditingEvent class methodsFor: 'decoding'!
decode: anArray
	"x and y are the cursor and the selection's length (-1: not set)."
	| c n |
	c := (anArray at: 3) ifNotNil: [:x | x rounded].
	n := (anArray at: 4) ifNotNil: [:y | y rounded].
	^self string: ((anArray at: 7) ifNil: [''])
		cursor: ((c notNil and: [c >= 0]) ifTrue: [c])
		selectionSize: ((n notNil and: [n >= 0]) ifTrue: [n])
		modifiers: (self modifiersFrom: anArray) time: (self timeFrom: anArray)
! !

!TextEditingEvent class methodsFor: 'instance creation'!
string: aString cursor: anIntegerOrNil selectionSize: sizeOrNil modifiers: aModifiers time: ms
	^self new
		setType: #editing time: ms modifiers: aModifiers;
		setString: aString cursor: anIntegerOrNil selectionSize: sizeOrNil;
		yourself
! !
