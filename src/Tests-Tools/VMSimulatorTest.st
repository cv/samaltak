ToolsTestCase subclass: #VMSimulatorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

VMSimulatorTest comment: 'I test the VM Simulator window: Run boots the guest on the simulated VM below the windows'' priority, and its lines and bytecode count show up.'!

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
! !
