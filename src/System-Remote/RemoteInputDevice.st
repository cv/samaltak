Object subclass: #RemoteInputDevice
	instanceVariableNames: 'pointer windowId injector settleMilliseconds timeScaleBlock arrivalBlock'
	classVariableNames: 'Default'
	package: 'System-Remote'!

RemoteInputDevice comment: 'I am the virtual input device: I play RemoteInputPlans by injecting their events into the platform''s input queue (InputQueue where the image drives the input devices, else the primitive injectEvent:), the same path real input takes, and then wait for the image to settle (RemoteControl waitUntilIdleFor:). I remember where the virtual pointer is, so the next plan travels from there; the UI may set pointer (e.g. to the real mouse position) and windowId (the host window events belong to). A UI that draws the pointer sets arrivalBlock: a press, release or wheel event is injected only once the drawn pointer is at its position (waitsForPointer:), so nothing clicks before the pointer gets there. Tests replace the injector with a block that records the events. deliver: injects another device''s events (a remote display''s: RfbInput) the same way without moving my pointer.'!

!RemoteInputDevice methodsFor: 'initialization'!
initialize
	settleMilliseconds := 2000
! !

!RemoteInputDevice methodsFor: 'accessing'!
pointer
	^pointer
!
pointer: aPointOrNil
	pointer := aPointOrNil
!
windowId
	^windowId
!
windowId: anIntegerOrNil
	windowId := anIntegerOrNil
!
injector: aBlockOrNil
	"aBlock value: anEvent replaces injection into the platform queue (nil: inject)."
	injector := aBlockOrNil
!
settleMilliseconds
	^settleMilliseconds
!
settleMilliseconds: anInteger
	settleMilliseconds := anInteger
!
timeScale
	"How many times slower than normal the pointer travels (the UI's slow motion)."
	^timeScaleBlock isNil ifTrue: [1] ifFalse: [timeScaleBlock value]
!
timeScaleBlock: aBlockOrNil
	"aBlock answers the timeScale (nil: 1)."
	timeScaleBlock := aBlockOrNil
!
arrivalBlock: aBlockOrNil
	"aBlock value: aPoint answers whether the pointer the UI draws is at aPoint (nil: no drawn pointer)."
	arrivalBlock := aBlockOrNil
!
waitsForPointer: anEvent
	"Must anEvent (a press, release or wheel event) wait until the drawn pointer is at its position?"
	(arrivalBlock isNil or: [(anEvent first between: 2 and: 4) not]) ifTrue: [^false].
	^(arrivalBlock value: (anEvent at: 3) @ (anEvent at: 4)) ~~ true
!
arrivalTimeout
	"How long (ms) an event waits for the drawn pointer at most: the next frame shows where the UI saw the pointer."
	^1000
!
planner
	"Answer a RemoteInputPlanner starting at my pointer."
	^RemoteInputPlanner new pointer: pointer; windowId: windowId; timeScale: self timeScale; yourself
! !

!RemoteInputDevice methodsFor: 'playing'!
play: aPlan
	"Inject aPlan's events with their delays; answer whether the image settled afterwards."
	self injectAll: aPlan.
	^self settle
!
play: aPlan settle: milliseconds
	"Like play:, waiting at most milliseconds (0: not at all) for the image to settle."
	self injectAll: aPlan.
	milliseconds <= 0 ifTrue: [^true].
	^RemoteControl waitUntilIdleFor: milliseconds
!
injectAll: aPlan
	"In the calling Process: each event after its delay, a press, release or wheel event once the drawn pointer is there."
	aPlan do: [:delay :event | | start |
		delay > 0 ifTrue: [(Delay forMilliseconds: delay) wait].
		start := Time millisecondClockValue.
		[(self waitsForPointer: event) and: [Time millisecondClockValue - start < self arrivalTimeout]]
			whileTrue: [(Delay forMilliseconds: 10) wait].
		self inject: event]
!
inject: anEvent
	((anEvent first between: 1 and: 4)) ifTrue: [pointer := (anEvent at: 3) @ (anEvent at: 4)].
	self deliver: anEvent
!
deliver: anEvent
	"Inject anEvent without moving my (drawn) pointer: another device's input, such as a remote display's viewer, which draws its own."
	injector isNil ifFalse: [^injector value: anEvent].
	(InputQueue inject: anEvent) ifTrue: [^self].
	(self primInjectEvent: anEvent) == false ifTrue: [
		^RemoteError signal: 'injectEvent failed: ', RemoteSocket lastError]
!
settle
	"Wait (at most settleMilliseconds) until the image processed the input: no user process runnable and the UI's idle conditions hold."
	settleMilliseconds <= 0 ifTrue: [^true].
	^RemoteControl waitUntilIdleFor: settleMilliseconds
! !

!RemoteInputDevice methodsFor: 'primitives'!
primInjectEvent: anEvent
	<primitive: 'injectEvent'>
	^false
! !

!RemoteInputDevice class methodsFor: 'accessing'!
default
	^Default ifNil: [Default := self new]
!
default: aDevice
	Default := aDevice
! !
