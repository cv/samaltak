Object subclass: #RemoteInputDevice
	instanceVariableNames: 'pointer windowId injector settleMilliseconds timeScaleBlock'
	classVariableNames: 'Default'
	package: 'System-Remote'!

RemoteInputDevice comment: 'I am the virtual input device: I play RemoteInputPlans by injecting their events into the platform''s input queue (primitive injectEvent:), the same path real input takes, and then wait for the image to settle (RemoteControl waitUntilIdleFor:). I remember where the virtual pointer is, so the next plan travels from there; the UI may set pointer (e.g. to the real mouse position) and windowId (the host window events belong to). Tests replace the injector with a block that records the events.'!

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
planner
	"Answer a RemoteInputPlanner starting at my pointer."
	^RemoteInputPlanner new pointer: pointer; windowId: windowId; timeScale: self timeScale; yourself
! !

!RemoteInputDevice methodsFor: 'playing'!
play: aPlan
	"Inject aPlan's events with their delays; answer whether the image settled afterwards."
	aPlan do: [:delay :event |
		delay > 0 ifTrue: [(Delay forMilliseconds: delay) wait].
		self inject: event].
	^self settle
!
play: aPlan settle: milliseconds
	"Like play:, waiting at most milliseconds (0: not at all) for the image to settle."
	aPlan do: [:delay :event |
		delay > 0 ifTrue: [(Delay forMilliseconds: delay) wait].
		self inject: event].
	milliseconds <= 0 ifTrue: [^true].
	^RemoteControl waitUntilIdleFor: milliseconds
!
inject: anEvent
	((anEvent first between: 1 and: 4)) ifTrue: [pointer := (anEvent at: 3) @ (anEvent at: 4)].
	injector isNil ifFalse: [^injector value: anEvent].
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
