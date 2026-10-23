Widget subclass: #DebuggerLink
	instanceVariableNames: 'text action hover font'
	classVariableNames: ''
	package: 'Tools'!

DebuggerLink comment: 'I am a quiet text button (prototype .dbg-proc): italic text, right-aligned, inverted (white on black) under the pointer; a click runs action. text: takes a String or a block evaluated at draw time.'!

!DebuggerLink methodsFor: 'accessing'!
text
	^(text isBlock ifTrue: [text value] ifFalse: [text]) ifNil: ['']
!
text: aStringOrBlock
	text := aStringOrBlock.
	self invalidate
!
action: aBlock
	action := aBlock
!
font
	^self fontFor: (font ifNil: [#smallItalic])
!
font: aFontOrSymbol
	font := aFontOrSymbol
!
preferredExtent
	^((self font widthOf: self text) + 8) ceiling @ 18
! !

!DebuggerLink methodsFor: 'actions'!
click
	action isNil ifFalse: [action cull: self]
! !

!DebuggerLink methodsFor: 'events'!
mouseDown: anEvent
	^anEvent button = 1
!
mouseUp: anEvent
	(self localBounds containsPoint: (self localEventPosition: anEvent)) ifTrue: [self click].
	^true
!
mouseEnter: anEvent
	hover := true.
	self invalidate.
	^true
!
mouseLeave: anEvent
	hover := false.
	self invalidate.
	^true
!
cursorAt: aPoint
	^#hand
! !

!DebuggerLink methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| inverted r |
	text isBlock ifTrue: [aCanvas noteVolatile].
	inverted := hover == true.
	r := self localBounds.
	aCanvas fillRect: r color: (inverted ifTrue: [self theme ink] ifFalse: [self theme paper]).
	aCanvas drawString: self text in: (r insetBy: 4 @ 0) font: self font
		color: (inverted ifTrue: [self theme paper] ifFalse: [self theme ink]) align: #right
! !

!DebuggerLink methodsFor: 'remote control'!
remoteRole
	^#link
!
remoteLabel
	^self text
!
remoteAction: aSymbol
	aSymbol == #click ifTrue: [^self inWindowDo: [self click]].
	^nil
! !
