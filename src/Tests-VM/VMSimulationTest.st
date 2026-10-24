TestCase subclass: #VMSimulationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

VMSimulationTest comment: 'The VM core, run as Smalltalk (VMSimulation), boots the mini kernel image and prints what the C VM prints.'!

!VMSimulationTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!VMSimulationTest methodsFor: 'tests'!
testMiniImageInSimulation
	| image sim status |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName = 'VM-Core']).
	status := sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Arith'}.
	self assert: status equals: 0.
	self assert: sim stdoutContents equals: (File readText: 'vm/tests/expected/Arith.txt')
!
testGuestShowsAnEditedVMMethodAtOnce
	"The VM Simulator's guest prints VMMain>>banner every second; recompiling it changes the next line, no restart."
	| image sim original |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName = 'VM-Core']).
	original := VMMain compiledMethodAt: #banner.
	self fork: [sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Guest'}] at: Processor userBackgroundPriority.
	[self assert: (self waitFor: [sim stdoutContents includesSubstring: 'Samaltak VM | tick 1 | 1 squared = 1'] timeout: 30000).
	 VMMain compile: 'banner <c: ''const char *vm_banner(void)''> ^''edited''' classified: 'running'.
	 self assert: (self waitFor: [sim stdoutContents includesSubstring: 'edited | tick'] timeout: 30000)]
		ensure: [VMMain addSelector: #banner withMethod: original]
! !
