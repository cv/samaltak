UIEvent subclass: #KeyEvent
	instanceVariableNames: 'key keyCode repeat'
	classVariableNames: ''
	package: 'UI-Windows'!

KeyEvent comment: 'I am a key press (#down) or release (#up). key is a Symbol for named keys (#left #right #up #down #return #enter #backspace #delete #escape #tab #home #end #pageUp #pageDown #space, #f1 ..., #shift #control #option #command) or a lowercase Character for printable keys; keyCode the platform keycode; isRepeat for auto-repeat. Typed text arrives separately as TextEvents.'!

!KeyEvent methodsFor: 'accessing'!
key
	^key
!
keyCode
	^keyCode
!
isRepeat
	^repeat == true
!
setKey: aKey keyCode: anInteger repeat: aBoolean
	key := aKey.
	keyCode := anInteger.
	repeat := aBoolean
! !

!KeyEvent methodsFor: 'testing'!
isKey
	^true
!
isDown
	^type == #down
!
isUp
	^type == #up
!
isCommand: aCharacterOrSymbol
	"Answer whether I am a key down of aCharacterOrSymbol with the command key (⌘) held."
	^type == #down and: [modifiers commandKey and: [key = aCharacterOrSymbol]]
!
isModifierKey
	^#(#shift #control #option #command) includes: key
! !

!KeyEvent methodsFor: 'dispatching'!
deliverTo: aWindow
	^aWindow dispatchKey: self
!
dispatchTo: anInputDispatcher
	^anInputDispatcher handleKey: self
! !

!KeyEvent methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'KeyEvent('; print: type; space; print: key.
	modifiers isEmpty ifFalse: [aStream space; print: modifiers].
	aStream nextPut: $)
! !

!KeyEvent class methodsFor: 'decoding'!
decode: anArray
	^self type: ((anArray at: 1) = self evKeyDown ifTrue: [#down] ifFalse: [#up]) keyCode: (anArray at: 5)
		key: (self keyFor: (anArray at: 5)) repeat: (anArray at: 7) == true
		modifiers: (self modifiersFrom: anArray) time: (self timeFrom: anArray)
! !

!KeyEvent class methodsFor: 'instance creation'!
type: aSymbol keyCode: anInteger key: aKey repeat: aBoolean modifiers: aModifiers time: ms
	^self new
		setType: aSymbol time: ms modifiers: aModifiers;
		setKey: aKey keyCode: anInteger repeat: aBoolean;
		yourself
! !
