Object subclass: #UIEvent
	instanceVariableNames: 'type timeStamp modifiers'
	classVariableNames: 'EventClasses KeyNames'
	package: 'UI-Windows'!

UIEvent comment: 'I am the abstract event: PointerEvent, KeyEvent, TextEvent and TextEditingEvent are input a Window delivers to its Views; the host window events (HostResizeEvent, QuitEvent, FocusLostEvent, ScaleChangedEvent, PointerLeftEvent, ExposeEvent) only concern the InputDispatcher. type is a Symbol, timeStamp the platform''s millisecond clock, modifiers a Modifiers. fromPlatform: decodes the platform''s 8-slot event Arrays (vm/platform/README.md), real or injected, into events once; the InputDispatcher then sends dispatchTo: itself to each, and a Window''s Process sends deliverTo: itself to the input events in its queue. The class side names the platform''s event types (evMouseMove ...).'!

!UIEvent methodsFor: 'accessing'!
type
	^type
!
timeStamp
	^timeStamp
!
modifiers
	^modifiers
!
setType: aSymbol time: ms modifiers: aModifiers
	type := aSymbol.
	timeStamp := ms.
	modifiers := aModifiers
! !

!UIEvent methodsFor: 'testing'!
isPointer
	^false
!
isKey
	^false
!
isText
	^false
!
isUIEvent
	^true
! !

!UIEvent methodsFor: 'dispatching'!
dispatchTo: anInputDispatcher
	"Send anInputDispatcher the message that handles me."
	self subclassResponsibility
!
deliverTo: aWindow
	"Dispatch me to aWindow's content (in aWindow's Process)."
	self subclassResponsibility
! !

!UIEvent methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: self class name; nextPut: $(; print: type; nextPut: $)
! !

!UIEvent class methodsFor: 'platform event types'!
evMouseMove
	"The platform's event types: the PF_EV_* constants of VMPlatformModule (VM-Platform)."
	^1
!
evMouseDown
	^2
!
evMouseUp
	^3
!
evWheel
	^4
!
evKeyDown
	^5
!
evKeyUp
	^6
!
evTextInput
	^7
!
evWindowResized
	^8
!
evWindowCloseRequest
	^9
!
evQuit
	^10
!
evFocusGained
	^11
!
evFocusLost
	^12
!
evDisplayScaleChanged
	^13
!
evMouseLeave
	^14
!
evWindowExposed
	^15
!
evTextEditing
	^16
!
eventClasses
	"Platform event type -> the class that decodes it (fromPlatform:); types not in here are ignored."
	EventClasses isNil ifFalse: [^EventClasses].
	EventClasses := Dictionary new.
	{self evMouseMove. self evMouseDown. self evMouseUp. self evWheel} do: [:each | EventClasses at: each put: PointerEvent].
	EventClasses
		at: self evKeyDown put: KeyEvent;
		at: self evKeyUp put: KeyEvent;
		at: self evTextInput put: TextEvent;
		at: self evTextEditing put: TextEditingEvent;
		at: self evWindowResized put: HostResizeEvent;
		at: self evWindowCloseRequest put: QuitEvent;
		at: self evQuit put: QuitEvent;
		at: self evFocusLost put: FocusLostEvent;
		at: self evDisplayScaleChanged put: ScaleChangedEvent;
		at: self evMouseLeave put: PointerLeftEvent;
		at: self evWindowExposed put: ExposeEvent.
	^EventClasses
! !

!UIEvent class methodsFor: 'decoding'!
fromPlatform: anArray
	"Answer the event for a platform event Array, or nil for types I ignore (focus gained)."
	| eventClass |
	eventClass := self eventClasses at: (anArray at: 1) ifAbsent: [^nil].
	^eventClass decode: anArray
!
decode: anArray
	"Answer an instance of me for a platform event Array of one of my types."
	self subclassResponsibility
!
timeFrom: anArray
	^(anArray at: 2) ifNil: [Time millisecondClockValue]
!
modifiersFrom: anArray
	^Modifiers bits: (anArray at: 6)
!
keyFor: keyCode
	"A Symbol for named keys, a lowercase Character for printable keys."
	keyCode isNil ifTrue: [^#unknown].
	(keyCode > 32 and: [keyCode < 127]) ifTrue: [^Character value: keyCode].
	^self keyNames at: keyCode ifAbsent: [#unknown]
!
keyNames
	| table |
	KeyNames isNil ifFalse: [^KeyNames].
	KeyNames := Dictionary new.
	table := #(13 #return 27 #escape 8 #backspace 9 #tab 127 #delete 32 #space
		16r4000004F #right 16r40000050 #left 16r40000051 #down 16r40000052 #up
		16r4000004A #home 16r4000004D #end 16r4000004B #pageUp 16r4000004E #pageDown
		16r40000049 #insert 16r40000058 #enter
		16r400000E1 #shift 16r400000E5 #shift 16r400000E0 #control 16r400000E4 #control
		16r400000E2 #option 16r400000E6 #option 16r400000E3 #command 16r400000E7 #command).
	1 to: table size by: 2 do: [:i | KeyNames at: (table at: i) put: (table at: i + 1)].
	1 to: 12 do: [:i | KeyNames at: 16r40000039 + i put: ('f', i printString) asSymbol].
	^KeyNames
!
keyCodeFor: aKey
	"The platform keycode of a key (Symbol or Character), for injecting events."
	aKey isCharacter ifTrue: [^aKey asLowercase value].
	self keyNames keysAndValuesDo: [:code :name | name == aKey ifTrue: [^code]].
	^0
! !
