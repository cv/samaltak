UIEvent subclass: #TextEvent
	instanceVariableNames: 'string'
	classVariableNames: ''
	package: 'UI-Windows'!

TextEvent comment: 'I am typed text (type #text): string is what the platform''s text input produced (one or more Characters, already composed).'!

!TextEvent methodsFor: 'accessing'!
string
	^string
!
setString: aString
	string := aString
! !

!TextEvent methodsFor: 'testing'!
isText
	^true
! !

!TextEvent methodsFor: 'dispatching'!
deliverTo: aWindow
	^aWindow dispatchText: self
!
dispatchTo: anInputDispatcher
	^anInputDispatcher handleText: self
! !

!TextEvent methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'TextEvent('; print: string; nextPut: $)
! !

!TextEvent class methodsFor: 'decoding'!
decode: anArray
	^self string: ((anArray at: 7) ifNil: ['']) modifiers: (self modifiersFrom: anArray) time: (self timeFrom: anArray)
! !

!TextEvent class methodsFor: 'instance creation'!
string: aString modifiers: aModifiers time: ms
	^self new
		setType: #text time: ms modifiers: aModifiers;
		setString: aString;
		yourself
! !
