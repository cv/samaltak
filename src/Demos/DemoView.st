View subclass: #DemoView
	instanceVariableNames: 'clicks lastEvent lastKey typed'
	classVariableNames: ''
	package: 'Demos'!

DemoView comment: 'I am a simple test View for the window system without the tools (my class-side initialize makes the demo windows the startup action unless one is set): I draw some text, count clicks, echo keys and typed text, and show a hand cursor over my button-like box. My subclasses show a busy computation and an animation.'!

!DemoView methodsFor: 'initialization'!
initialize
	super initialize.
	clicks := 0.
	typed := ''
! !

!DemoView methodsFor: 'accessing'!
clicks
	^clicks
!
typed
	^typed
!
lastKey
	^lastKey
!
buttonRect
	^16 @ (self height - 44) extent: 150 @ 26
!
lines
	^#('A View in a Window, with its own Process.'
		'Drag the title bar, resize from the edges,'
		'click the boxes, type something.')
!
heading
	^'Samaltak window system'
! !

!DemoView methodsFor: 'drawing'!
drawOn: c
	| y |
	c fillRect: self localBounds color: Color white.
	c drawString: self heading at: 16 @ 12 font: Font uiBold color: Color black.
	y := 36.
	self lines do: [:line |
		c drawString: line at: 16 @ y font: Font ui color: Color black.
		y := y + 19].
	y := y + 8.
	c drawString: 'clicks: ', clicks printString at: 16 @ y font: Font code color: Color black.
	c drawString: 'typed: ', (typed size > 40 ifTrue: [typed last: 40] ifFalse: [typed]) at: 16 @ (y + 20) font: Font code color: Color black.
	lastKey isNil ifFalse: [
		c drawString: 'key: ', lastKey printString at: 16 @ (y + 40) font: Font code color: (Color named: #ink3)].
	self drawButtonOn: c label: 'Click me'
!
drawButtonOn: c label: aString
	| r |
	r := self buttonRect.
	c fillRect: r color: Color white.
	c strokeRect: r color: Color black width: 1.
	c drawString: aString in: r font: Font ui color: Color black align: #center
! !

!DemoView methodsFor: 'events'!
handlePointer: evt
	lastEvent := evt.
	evt isDown ifTrue: [
		clicks := clicks + 1.
		(self buttonRect containsPoint: evt position) ifTrue: [self buttonPressed].
		self invalidate.
		^true].
	^evt isUp
!
buttonPressed
	self world toast: 'Clicked ', clicks printString, ' times'
!
handleKey: evt
	evt isDown ifFalse: [^false].
	lastKey := evt key.
	evt key == #backspace ifTrue: [typed isEmpty ifFalse: [typed := typed allButLast]].
	self invalidate.
	^true
!
handleText: evt
	typed := typed, evt string.
	self invalidate.
	^true
!
wantsKeyboardFocus
	^true
!
cursorAt: aPoint
	^(self buttonRect containsPoint: aPoint) ifTrue: [#hand] ifFalse: [#arrow]
!
tooltipAt: aPoint
	^(self buttonRect containsPoint: aPoint) ifTrue: ['A button-like box'] ifFalse: [nil]
! !

!DemoView methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteName
	^'view'
!
remoteState
	^super remoteState, (Array with: 'clicks=', clicks printString)
!
remoteChildren
	^Array with: (DemoButtonNode view: self)
! !

!DemoView class methodsFor: 'class initialization'!
initialize
	UIWindows startupAction isNil ifTrue: [UIWindows startupAction: [self openDemoIn: World current]]
! !

!DemoView class methodsFor: 'demo'!
openDemoIn: aWorld
	"Open the demo windows; answer them."
	| welcome busy anim |
	aWorld isNil ifTrue: [^self error: 'No World'].
	anim := Window new title: 'Animation'; content: DemoAnimationView new; bounds: (560 @ 420 extent: 420 @ 220); yourself.
	busy := Window new title: 'Busy Process'; content: DemoBusyView new; bounds: (520 @ 70 extent: 460 @ 300); yourself.
	welcome := Window new title: 'Welcome to Samaltak'; content: DemoView new; bounds: (40 @ 60 extent: 440 @ 300); yourself.
	anim openIn: aWorld.
	busy openIn: aWorld.
	welcome openIn: aWorld.
	^Array with: welcome with: busy with: anim
! !
