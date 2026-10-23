Object subclass: #WindowTimer
	instanceVariableNames: 'window block cancelled delay period'
	classVariableNames: ''
	package: 'UI-Windows'!

WindowTimer comment: 'I run a block in a window''s Process after a delay (Window>>after:do:), or every period ms while the window is open (Window>>every:do:), unless cancelled. I have no Process: a Delay makes the timer process send me #signal when I am due, and I post myself into my window''s event queue; the window''s Process then fires me (a repeating timer schedules itself again after its block ran, so runs never overlap).'!

!WindowTimer methodsFor: 'running'!
setWindow: aWindow block: aBlock
	window := aWindow.
	block := aBlock.
	cancelled := false
!
startAfter: milliseconds
	delay := Delay forMilliseconds: milliseconds.
	delay signal: self
!
startEvery: milliseconds
	period := milliseconds.
	self startAfter: milliseconds
!
signal
	"The timer process: I am due."
	(cancelled or: [window isOpen not]) ifFalse: [window enqueue: self]
!
fire
	"My window's Process."
	(cancelled or: [window isOpen not]) ifTrue: [^self].
	period isNil ifFalse: [
		[block value] ensure: [(cancelled or: [window isOpen not]) ifFalse: [self startAfter: period]].
		^self].
	block value
!
deliverTo: aWindow
	^self fire
!
cancel
	cancelled := true.
	delay isNil ifFalse: [delay cancel]
!
isCancelled
	^cancelled
! !

!WindowTimer class methodsFor: 'instance creation'!
after: milliseconds do: aBlock in: aWindow
	^self new setWindow: aWindow block: aBlock; startAfter: milliseconds; yourself
!
every: milliseconds do: aBlock in: aWindow
	^self new setWindow: aWindow block: aBlock; startEvery: milliseconds; yourself
! !
