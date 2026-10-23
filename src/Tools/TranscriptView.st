ToolPane subclass: #TranscriptView
	instanceVariableNames: 'editor clearButton listener pending lock flushQueued'
	classVariableNames: ''
	package: 'Tools'!

TranscriptView comment: 'I show the Transcript live: everything any Process writes to it (Transcript show:) arrives through a Transcript listener, is buffered and appended in my window''s Process, at most once per redraw; the view follows the end while the caret is there. clear empties the Transcript.'!

!TranscriptView methodsFor: 'initialization'!
initialize
	super initialize.
	lock := Semaphore forMutualExclusion.
	pending := WriteStream on: (String new: 256).
	flushQueued := false.
	editor := ToolTextEditor new name: 'text'; title: 'transcript'; readOnly: true; highlighting: false; yourself.
	editor text: Transcript contents.
	editor caret: editor size.
	clearButton := Button label: 'clear' action: [self clear].
	clearButton name: 'clear'.
	self addAll: (Array with: editor with: clearButton)
!
minimumWindowExtent
	^200 @ 80
! !

!TranscriptView methodsFor: 'accessing'!
editor
	^editor
!
text
	^editor text
! !

!TranscriptView methodsFor: 'layout'!
layout
	| e |
	editor isNil ifTrue: [^self].
	editor bounds: self localBounds.
	e := clearButton preferredExtent.
	clearButton bounds: ((self width - e x - 22) @ 6 extent: e)
! !

!TranscriptView methodsFor: 'drawing'!
drawOn: aCanvas
	"The clear button shows while my window is the active one (the prototype shows it on hover)."
	| w |
	w := self window.
	clearButton setVisible: (w notNil and: [w isFocused]).
	super drawOn: aCanvas
! !

!TranscriptView methodsFor: 'live text'!
startListening
	listener := [:text | self received: text].
	Transcript addListener: listener
!
received: aString
	"Any Process: buffer, and ask my window to append once."
	| w schedule |
	w := self window.
	schedule := false.
	lock critical: [
		pending nextPutAll: aString.
		(flushQueued not and: [w notNil]) ifTrue: [flushQueued := true. schedule := true]].
	schedule ifTrue: [w do: [self flushPending]]
!
flushPending
	| text |
	lock critical: [
		text := pending contents.
		pending := WriteStream on: (String new: 256).
		flushQueued := false].
	text isEmpty ifTrue: [^self].
	editor appendText: text.
	editor size > 120000 ifTrue: [self trim]
!
trim
	| keep |
	keep := editor text last: 60000.
	editor text: keep.
	editor caret: editor size
!
clear
	Transcript clear.
	editor text: ''
!
windowClosed
	listener isNil ifFalse: [Transcript removeListener: listener].
	listener := nil
! !

!TranscriptView class methodsFor: 'opening'!
openIn: aRectangle
	| view window |
	view := self new.
	view startListening.
	window := view openIn: aRectangle title: 'Transcript'.
	window do: [view flushPending. view editor caret: view editor size].
	^window
!
initialize
	ToolsMenu register: 'Transcript' order: 30 action: [:point |
		self openIn: (Tools placeAt: point extent: 520 @ 210)]
! !
