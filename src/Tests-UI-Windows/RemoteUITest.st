UIWindowsTestCase subclass: #RemoteUITest
	instanceVariableNames: 'savedRegistry savedPointer savedWindowId'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

RemoteUITest comment: 'Tests the window system under remote control: the snapshot text of the World, clicks and drags on refs through the generic UI commands (injected input), the screenshot command.'!

!RemoteUITest methodsFor: 'running'!
setUp
	super setUp.
	savedRegistry := RemoteControl registryState.
	savedPointer := RemoteInputDevice default pointer.
	savedWindowId := RemoteInputDevice default windowId.
	UIRemote installOn: world
!
tearDown
	Animation timeScale: 1.
	UIRemote uninstall.
	RemoteControl registryState: savedRegistry.
	RemoteInputDevice default pointer: savedPointer; windowId: savedWindowId.
	super tearDown
!
send: aDictionary
	^RemoteControl dispatch: (RemoteRequest on: aDictionary)
!
cmd: aString
	^Dictionary new at: 'cmd' put: aString; yourself
! !

!RemoteUITest methodsFor: 'tests'!
testSnapshotText
	| w text lines |
	w := self open: RecordingTestView new title: 'System Browser: Window' at: (18 @ 44 extent: 600 @ 400).
	text := (self send: (self cmd: 'snapshot')) at: 'text'.
	lines := text lines.
	self assert: (lines first beginsWith: 'screen "1000x700" theme=blue-book').
	self assert: (lines first includesSubstring: 'focus=@w1').
	self assert: (lines anySatisfy: [:l | l beginsWith: 'topbar @top']).
	self assert: (lines includes: 'window @w1 "System Browser: Window" [18,44 600x400] focused process=#', w process identityHash printString, ' waiting').
	self assert: (lines includes: '  button @w1.close "close"').
	self assert: (lines includes: '  handle @w1.resize "resize"').
	self assert: (lines anySatisfy: [:l | l beginsWith: '  canvas @w1.view'])
!
testClickOnRefGoesThroughInjectedInput
	| v w r |
	v := RecordingTestView new.
	w := self open: v title: 'Remote' at: (100 @ 100 extent: 300 @ 200).
	r := self send: ((self cmd: 'click') at: 'target' put: '@w1.view'; yourself).
	self assert: (r at: 'ok').
	self settle.
	self assert: (v eventsOfType: #down) size equals: 1.
	self assert: (v eventsOfType: #down) first position equals: v extent / 2
!
testDoubleClickOnRef
	"samaltak-ctl dblclick: two presses at one point, the second a double click."
	| v |
	v := RecordingTestView new.
	self open: v title: 'Remote' at: (100 @ 100 extent: 300 @ 200).
	self send: ((self cmd: 'click') at: 'target' put: '@w1.view'; at: 'count' put: 2; yourself).
	self settle.
	self assert: ((v eventsOfType: #down) collect: [:e | e clickCount]) asArray equals: #(1 2)
!
testClickInSlowMotion
	| v r start |
	v := RecordingTestView new.
	self open: v title: 'Remote' at: (100 @ 100 extent: 300 @ 200).
	RemoteInputDevice default pointer: 600 @ 500.
	Animation timeScale: 10.
	start := Time millisecondClockValue.
	r := self send: ((self cmd: 'click') at: 'target' put: '@w1.view'; yourself).
	self assert: (r at: 'ok').
	"100 ms of pointer travel take a second"
	self assert: Time millisecondClockValue - start >= 800.
	self settle.
	self assert: (v eventsOfType: #down) size equals: 1.
	self assert: (v eventsOfType: #down) first position equals: v extent / 2.
	"the on-screen pointer is where the click went"
	self assert: (self waitFor: [world remotePointer shown = RemoteInputDevice default pointer] timeout: 2000)
!
testDrawnPointerIsTheDispatchersInSlowMotion
	"During a travel in slow motion every frame draws the pointer where the input dispatcher last saw it (where hover goes), not behind it."
	| device |
	device := RemoteInputDevice default.
	device pointer: 200 @ 200.
	Animation timeScale: 10.
	(device planner moveTo: 900 @ 600) do: [:delay :event |
		device inject: event.
		self assert: (self waitFor: [world dispatcher pointer = ((event at: 3) @ (event at: 4))] timeout: 2000).
		world waitForFrames: 2.
		self assert: world remotePointer shown equals: world dispatcher pointer]
!
testPressWaitsForTheDrawnPointer
	"The press of a remote click is injected only once a frame showed the pointer where it presses."
	| v device shownAtPress |
	v := RecordingTestView new.
	self open: v title: 'Remote' at: (100 @ 100 extent: 300 @ 200).
	device := RemoteInputDevice default.
	self send: ((self cmd: 'hover') at: 'target' put: '950,650'; yourself).
	self assert: (self waitFor: [world remotePointer hasShown: 950 @ 650] timeout: 5000).
	device injector: [:event |
		event first = 2 ifTrue: [shownAtPress := world remotePointer hasShown: (event at: 3) @ (event at: 4)].
		device primInjectEvent: event].
	[self send: ((self cmd: 'click') at: 'target' put: '@w1.view'; yourself)] ensure: [device injector: nil].
	self assert: shownAtPress == true.
	self settle.
	self assert: (v eventsOfType: #down) size equals: 1
!
testClickRaisesCoveredWindow
	| a b wa |
	a := RecordingTestView new.
	b := RecordingTestView new.
	wa := self open: a title: 'Covered' at: (100 @ 100 extent: 300 @ 200).
	self open: b title: 'Cover' at: (100 @ 100 extent: 300 @ 200).
	self send: ((self cmd: 'click') at: 'target' put: '@w1.view'; yourself).
	self settle.
	self assert: world activeWindow == wa.
	self assert: (a eventsOfType: #down) size equals: 1.
	self assert: (b eventsOfType: #down) isEmpty
!
testDragWindowAndCloseByRef
	| w origin r |
	w := self open: RecordingTestView new title: 'Movable' at: (100 @ 100 extent: 300 @ 200).
	origin := w bounds origin.
	r := self send: ((self cmd: 'drag') at: 'target' put: '@w1'; at: 'dx' put: 120; at: 'dy' put: 40; yourself).
	self assert: (r at: 'ok').
	self settle.
	self assert: w bounds origin equals: origin + (120 @ 40).
	r := self send: ((self cmd: 'resize') at: 'target' put: '@w1'; at: 'w' put: 420; at: 'h' put: 260; yourself).
	self assert: (r at: 'ok').
	self settle.
	self assert: w bounds extent equals: 420 @ 260.
	self send: ((self cmd: 'click') at: 'target' put: '@w1.close'; yourself).
	self settle.
	self assert: w isClosed
!
testScreenshotCommand
	| path r bytes |
	self open: (RecordingTestView new color: Color ultramarine; yourself) title: 'Shot' at: (100 @ 100 extent: 300 @ 200).
	path := self scratchPath: 'shot.png'.
	r := self send: ((self cmd: 'screenshot') at: 'path' put: path; at: 'scale' put: 1; yourself).
	self assert: (r at: 'ok').
	self assert: (r at: 'w') equals: 1000.
	self assert: (r at: 'h') equals: 700.
	bytes := File readBytes: path.
	self assert: (bytes copyFrom: 2 to: 4) asString equals: 'PNG'.
	r := self send: ((self cmd: 'screenshot') at: 'path' put: path; at: 'target' put: '@w1'; at: 'scale' put: 2; yourself).
	self assert: (r at: 'w') equals: 600.
	self assert: (r at: 'h') equals: 400.
	File delete: path
!
testStateAndIdle
	| r |
	self open: RecordingTestView new title: 'State' at: (100 @ 100 extent: 300 @ 200).
	self assert: (RemoteControl waitUntilIdleFor: 3000).
	r := self send: (self cmd: 'state').
	self assert: (r at: 'focus') equals: '@w1'.
	self assert: ((r at: 'windows') first at: 'title') equals: 'State'.
	r := self send: ((self cmd: 'wait') at: 'frames' put: 2; yourself).
	self assert: (r at: 'ok')
! !
