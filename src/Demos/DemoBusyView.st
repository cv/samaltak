DemoView subclass: #DemoBusyView
	instanceVariableNames: 'result running'
	classVariableNames: ''
	package: 'Demos'!

DemoBusyView comment: 'I compute for three seconds in my window''s Process when my box is clicked: the window shows the busy indicator, keeps its last frame, and stays draggable; the other windows stay live.'!

!DemoBusyView methodsFor: 'accessing'!
heading
	^'A busy window Process'
!
lines
	^Array
		with: 'Click the box: this Process computes for 3 s.'
		with: 'Meanwhile drag this window or the others.'
		with: (result isNil ifTrue: ['No result yet.'] ifFalse: ['Result: ', result])
! !

!DemoBusyView methodsFor: 'drawing'!
drawOn: c
	super drawOn: c.
	self drawButtonOn: c label: 'Compute for 3 s'
! !

!DemoBusyView methodsFor: 'events'!
buttonPressed
	| start n digits |
	start := Time millisecondClockValue.
	n := 0.
	digits := 0.
	[Time millisecondClockValue - start < 3000] whileTrue: [
		n := n + 1.
		digits := (200 factorial printString size)].
	result := n printString, ' × 200 factorial (', digits printString, ' digits) in ', (Time millisecondClockValue - start) printString, ' ms'
! !
