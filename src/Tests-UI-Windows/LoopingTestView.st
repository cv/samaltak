RecordingTestView subclass: #LoopingTestView
	instanceVariableNames: 'looping loops'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

LoopingTestView comment: 'I am a test View whose window Process loops (computing) after a click until stopLooping (at most 10 s).'!

!LoopingTestView methodsFor: 'accessing'!
isLooping
	^looping == true
!
loops
	^loops ifNil: [0]
!
stopLooping
	looping := false
! !

!LoopingTestView methodsFor: 'events'!
handlePointer: anEvent
	| start |
	events add: anEvent.
	anEvent isDown ifTrue: [
		looping := true.
		loops := 0.
		start := Time millisecondClockValue.
		[looping and: [Time millisecondClockValue - start < 10000]] whileTrue: [
			loops := loops + 1.
			30 factorial].
		looping := false].
	^true
! !
