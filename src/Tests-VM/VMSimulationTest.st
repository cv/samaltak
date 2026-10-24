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
! !
