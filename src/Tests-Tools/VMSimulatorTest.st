ToolsTestCase subclass: #VMSimulatorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

VMSimulatorTest comment: 'I test the VM Simulator window: Run boots the guest on the simulated VM below the windows'' priority, and its lines and bytecode count show up; Smalltalk-80 boots the st80/ guest onto the screen pane, which takes the keys.'!

!VMSimulatorTest methodsFor: 'tests'!
testRunShowsTheGuest
	| tool window |
	window := VMSimulator openAt: 100 @ 100.
	tool := window content.
	[window sync: [tool run].
	 self assert: (self waitFor: [(tool output includesSubstring: 'Samaltak VM | tick 1 | 1 squared = 1')] timeout: 30000).
	 self assert: tool process priority < Processor userSchedulingPriority.
	 self assert: tool simulation bytecodes > 0]
		ensure: [window sync: [tool stop]]
!
testSmalltalk80RunsOnTheScreen
	"The guest display shows in the screen pane, which has the keys: 3 + 4, cmd-P, and the guest's Compiler prints 7 (its Transcript writes the output pane)."
	| tool window |
	window := VMSimulator openAt: 100 @ 100.
	tool := window content.
	[window sync: [tool runSmalltalk80].
	 self assert: (self waitFor: [tool screen frames > 1] timeout: 60000).
	 self assert: (self waitFor: [window sync: [tool screen isFocused]]).
	 DisplayWindow injectEvent: {7. nil. 0. 0. 0. 0. '3 + 4'. world displayWindow windowId}.
	 self key: $p modifiers: self commandModifier.
	 self assert: (self waitFor: [tool output includesSubstring: '3 + 4 --> 7'] timeout: 60000).
	 self assert: (self waitFor: [tool screen latency notNil]).
	 self assert: ((window sync: [tool screen remoteState]) includes: 'size=640x400')]
		ensure: [window sync: [tool stop]]
! !
