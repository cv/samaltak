Object subclass: #InputQueue
	instanceVariableNames: 'events lock semaphoreIndex armed dropped extent position buttons clicks downButton downTime downPosition'
	classVariableNames: 'Current MaxEvents'
	package: 'System-Devices'!

InputQueue comment: 'I am the event queue where the image drives the input devices itself (UEFI): what the VM''s queue is elsewhere (docs/platform.md, Events), with the same 8-slot Arrays, the same FIFO of at most MaxEvents (more are dropped and counted) and the same semaphore, signaled once when events are pending and armed again by next:. The drivers report key strokes and the pointer; I make the events: a key stroke is a keyDown, its textInput (a character without ctrl or cmd) and a keyUp; the pointer is a move, then the buttons that changed (clicks within 400 ms and 4 pixels count up), then the wheel; injected events (remote control) join the same queue. InputQueue current is the running one (nil on an operating system).'!

!InputQueue methodsFor: 'initialization'!
initialize
	events := OrderedCollection new.
	lock := Semaphore forMutualExclusion.
	semaphoreIndex := 0.
	armed := true.
	dropped := 0.
	extent := 1 @ 1.
	position := 0 @ 0.
	buttons := 0.
	clicks := 0.
	downButton := 0.
	downTime := 0.
	downPosition := 0 @ 0
! !

!InputQueue methodsFor: 'queue'!
push: anArray
	"Queue anArray (8 slots); signal the semaphore if armed."
	| index |
	index := lock critical: [
		events size >= MaxEvents
			ifTrue: [dropped := dropped + 1. 0]
			ifFalse: [
				events addLast: anArray.
				(armed and: [semaphoreIndex ~= 0]) ifTrue: [armed := false. semaphoreIndex] ifFalse: [0]]].
	index ~= 0 ifTrue: [self signal: index]
!
signal: anIndex
	(Smalltalk vm externalObjects at: anIndex ifAbsent: [nil]) ifNotNil: [:s | s signal]
!
next: anArray
	"Fill anArray (8 slots) with the next event and answer it, or answer nil; arm the semaphore again."
	| e |
	e := lock critical: [
		armed := true.
		events isEmpty ifTrue: [nil] ifFalse: [events removeFirst]].
	e isNil ifTrue: [^nil].
	anArray replaceFrom: 1 to: 8 with: e startingAt: 1.
	^anArray
!
inject: anArray
	"Queue a copy of anArray as if it came from a device (timeMs nil: now)."
	| e |
	(anArray size >= 8 and: [(anArray at: 1) isInteger and: [(anArray at: 1) > 0]]) ifFalse: [^self error: 'not an event'].
	e := (anArray copyFrom: 1 to: 8) asArray.
	(e at: 2) isInteger ifFalse: [e at: 2 put: Time millisecondClockValue].
	e at: 3 put: (e at: 3) asFloat.
	e at: 4 put: (e at: 4) asFloat.
	(e at: 5) isInteger ifFalse: [e at: 5 put: 0].
	(e at: 6) isInteger ifFalse: [e at: 6 put: 0].
	(e at: 7) isArray ifTrue: [e at: 7 put: (e at: 7) first asFloat @ (e at: 7) last asFloat].
	(e at: 7) isPoint ifTrue: [e at: 7 put: (e at: 7) x asFloat @ (e at: 7) y asFloat].
	self push: e
!
semaphoreIndex: anInteger
	"Signal the external semaphore anInteger when events are pending (0: none)."
	| index |
	index := lock critical: [
		semaphoreIndex := anInteger.
		armed := true.
		(events notEmpty and: [anInteger ~= 0]) ifTrue: [armed := false. anInteger] ifFalse: [0]].
	index ~= 0 ifTrue: [self signal: index]
!
dropped
	"Events dropped because the queue was full."
	^dropped
!
isEmpty
	^events isEmpty
! !

!InputQueue methodsFor: 'devices'!
extent: aPoint
	"The screen's size in pixels: the pointer stays inside, starting at its centre."
	extent := aPoint.
	position := extent // 2
!
position
	^position
!
event: type key: keyOrButton modifiers: mods extra: extra
	^{type. Time millisecondClockValue. position x asFloat. position y asFloat. keyOrButton. mods. extra. 1}
!
keyStroke: keycode modifiers: mods text: aStringOrNil
	"A key pressed and released (the firmware reports no releases), with the text it typed."
	self push: (self event: 5 key: keycode modifiers: mods extra: false).
	aStringOrNil isNil ifFalse: [self push: (self event: 7 key: 0 modifiers: mods extra: aStringOrNil)].
	self push: (self event: 6 key: keycode modifiers: mods extra: false)
!
pointerAt: aPoint buttons: mask wheel: dy
	"The pointer is at aPoint (pixels; clamped to the screen), with buttons (1 left, 4 right) held, and the wheel turned by dy; answer whether it moved."
	| p moved |
	p := (aPoint x max: 0) @ (aPoint y max: 0).
	p := (p x min: extent x - 1) @ (p y min: extent y - 1).
	moved := p ~= position.
	moved ifTrue: [
		position := p.
		self push: (self event: 1 key: buttons modifiers: 0 extra: nil)].
	self button: 1 mask: 1 held: mask.
	self button: 3 mask: 4 held: mask.
	buttons := mask.
	dy ~= 0 ifTrue: [self push: (self event: 4 key: 0 modifiers: 0 extra: 0.0 @ dy asFloat)].
	^moved
!
button: button mask: mask held: held
	"A down or up event if button (1 left, 3 right) changed."
	| down now |
	(held bitAnd: mask) = (buttons bitAnd: mask) ifTrue: [^self].
	down := (held bitAnd: mask) ~= 0.
	now := Time millisecondClockValue.
	down ifTrue: [
		clicks := (button = downButton and: [now - downTime <= 400 and: [(position x - downPosition x) abs <= 4 and: [(position y - downPosition y) abs <= 4]]])
			ifTrue: [clicks + 1]
			ifFalse: [1].
		downButton := button.
		downTime := now.
		downPosition := position].
	self push: (self event: (down ifTrue: [2] ifFalse: [3]) key: button modifiers: 0 extra: clicks)
! !

!InputQueue class methodsFor: 'class initialization'!
initialize
	MaxEvents := 4096
! !

!InputQueue class methodsFor: 'accessing'!
current
	^Current
!
current: anInputQueue
	Current := anInputQueue
!
inject: anArray
	"Inject into the running queue; false if there is none (the VM has the queue)."
	Current isNil ifTrue: [^false].
	Current inject: anArray.
	^true
!
droppedEvents
	^Current isNil ifTrue: [0] ifFalse: [Current dropped]
! !
