TestCase subclass: #InputQueueTest
	instanceVariableNames: 'queue'
	classVariableNames: ''
	package: 'Tests-Devices'!

InputQueueTest comment: 'The image''s event queue (InputQueue) and the firmware keyboard''s translation (FirmwareKeyboard): the events the VM''s queue made of the same key strokes and pointer states before, the platform''s 8-slot Arrays.'!

!InputQueueTest methodsFor: 'running'!
setUp
	queue := InputQueue new.
	queue extent: 100 @ 80
!
events
	"The queued events, without their times."
	| a all |
	all := OrderedCollection new.
	[(a := queue next: (Array new: 8)) notNil] whileTrue: [
		a at: 2 put: nil.
		all add: a].
	^all asArray
!
key: scan char: char shift: state
	FirmwareKeyboard keyStroke: scan char: char shiftState: state to: queue
! !

!InputQueueTest methodsFor: 'tests'!
testACharacterIsKeyDownTextKeyUp
	self key: 0 char: $a value shift: 0.
	self assert: self events equals: {
		{5. nil. 50.0. 40.0. 97. 0. false. 1}.
		{7. nil. 50.0. 40.0. 0. 0. 'a'. 1}.
		{6. nil. 50.0. 40.0. 97. 0. false. 1}}
!
testModifiersAsOnLinux
	"EFI_SHIFT_STATE_VALID with left shift, left control, left alt (cmd) and left logo (alt); a capital is shift and the letter, control-A .. Z ctrl and the letter, without text; none without the valid bit."
	self key: 0 char: $A value shift: 0.
	self assert: (self events collect: [:e | {e first. e at: 5. e at: 6. e at: 7}]) equals: #(#(5 97 1 false) #(7 0 1 'A') #(6 97 1 false)).
	self key: 0 char: 3 shift: 16r80000004.
	self assert: (self events collect: [:e | {e first. e at: 5. e at: 6}]) equals: #(#(5 99 2) #(6 99 2)).
	self key: 0 char: $p value shift: 16r80000010.
	self assert: (self events collect: [:e | {e first. e at: 6}]) equals: #(#(5 8) #(6 8)).
	self key: 0 char: $x value shift: 16r80000040.
	self assert: (self events collect: [:e | {e first. e at: 6}]) equals: #(#(5 4) #(7 4) #(6 4)).
	self key: 0 char: $x value shift: 16r00000010.
	self assert: (self events collect: [:e | e at: 6]) equals: #(0 0 0)
!
testNamedKeys
	"Scan codes: the arrows, home, end, insert, delete, the page keys, F1 .. F12, escape; return, tab and backspace are characters."
	#(1 16r40000052 2 16r40000051 3 16r4000004F 4 16r40000050 5 16r4000004A 6 16r4000004D 7 16r40000049 8 127 9 16r4000004B 10 16r4000004E 11 16r4000003A 22 16r40000045 23 27) pairsDo: [:scan :code |
		self key: scan char: 0 shift: 0.
		self assert: (self events collect: [:e | {e first. e at: 5}]) equals: {{5. code}. {6. code}}].
	#(13 9 8) do: [:ch |
		self key: 0 char: ch shift: 0.
		self assert: (self events collect: [:e | {e first. e at: 5}]) equals: {{5. ch}. {6. ch}}].
	self key: 99 char: 0 shift: 0.
	self assert: self events isEmpty
!
testThePointer
	"A move (with the buttons held before it), then the buttons that changed, then the wheel; clamped to the screen."
	self assert: queue position equals: 50 @ 40.
	self assert: (queue pointerAt: 10.5 @ 20 buttons: 1 wheel: 0).
	self deny: (queue pointerAt: 10.5 @ 20 buttons: 0 wheel: 3).
	queue pointerAt: 500 @ -4 buttons: 4 wheel: 0.
	self assert: self events equals: {
		{1. nil. 10.5. 20.0. 0. 0. nil. 1}.
		{2. nil. 10.5. 20.0. 1. 0. 1. 1}.
		{3. nil. 10.5. 20.0. 1. 0. 1. 1}.
		{4. nil. 10.5. 20.0. 0. 0. 0.0 @ 3.0. 1}.
		{1. nil. 99.0. 0.0. 0. 0. nil. 1}.
		{2. nil. 99.0. 0.0. 3. 0. 1. 1}}
!
testClicksCount
	"Presses of one button within 400 ms and 4 pixels count up; another button, or farther, starts again."
	queue pointerAt: 10 @ 10 buttons: 1 wheel: 0.
	queue pointerAt: 10 @ 10 buttons: 0 wheel: 0.
	queue pointerAt: 13 @ 12 buttons: 1 wheel: 0.
	queue pointerAt: 13 @ 12 buttons: 0 wheel: 0.
	queue pointerAt: 13 @ 12 buttons: 4 wheel: 0.
	queue pointerAt: 13 @ 12 buttons: 0 wheel: 0.
	queue pointerAt: 13 @ 12 buttons: 4 wheel: 0.
	queue pointerAt: 13 @ 12 buttons: 0 wheel: 0.
	queue pointerAt: 30 @ 12 buttons: 4 wheel: 0.
	self assert: ((self events select: [:e | e first = 2]) collect: [:e | e at: 7]) equals: #(1 2 1 2 1)
!
testInjectedEventsJoinTheQueue
	| e |
	self key: 0 char: $a value shift: 0.
	queue inject: {7. nil. 1. 2. nil. nil. 'hé'. 1}.
	queue inject: {4. 99. 3. 4. 0. 0. #(1 2). 1}.
	e := self events.
	self assert: e size equals: 5.
	self assert: (e at: 4) equals: {7. nil. 1.0. 2.0. 0. 0. 'hé'. 1}.
	self assert: (e at: 5) equals: {4. nil. 3.0. 4.0. 0. 0. 1.0 @ 2.0. 1}.
	self should: [queue inject: {0. nil. 0. 0. 0. 0. nil. nil}] raise: Error
!
testTheSemaphoreIsSignaledOnceUntilRead
	| s index |
	s := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: s.
	[queue semaphoreIndex: index.
	self key: 0 char: $a value shift: 0.
	self key: 0 char: $b value shift: 0.
	self assert: s excessSignals equals: 1.
	queue next: (Array new: 8).
	self key: 0 char: $c value shift: 0.
	self assert: s excessSignals equals: 2.
	queue semaphoreIndex: 0] ensure: [Smalltalk vm unregisterExternalSemaphore: index]
!
testAFullQueueDrops
	| n |
	n := 0.
	[queue dropped = 0] whileTrue: [
		queue pointerAt: n \\ 50 @ 0 buttons: 0 wheel: 0.
		n := n + 1].
	self assert: n > 4000.
	self assert: self events size equals: n - 1
! !
