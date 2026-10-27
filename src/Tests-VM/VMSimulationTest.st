TestCase subclass: #VMSimulationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

VMSimulationTest comment: 'The VM core, run as Smalltalk (VMSimulation), boots the mini kernel image and prints what the C VM prints, and boots the Smalltalk-80 guest (st80/) on a guest display, which only the simulation has.'!

!VMSimulationTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!VMSimulationTest methodsFor: 'tests'!
testMiniImageInSimulation
	| image sim status |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	status := sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Arith'}.
	self assert: status equals: 0.
	self assert: sim stdoutContents equals: (File readText: 'vm/tests/expected/Arith.txt')
!
testGuestShowsAnEditedVMMethodAtOnce
	"The VM Simulator's guest prints VMMain>>banner every second; recompiling it changes the next line, no restart."
	| image sim original |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	original := VMMain compiledMethodAt: #banner.
	self fork: [sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Guest'}] at: Processor userBackgroundPriority.
	[self assert: (self waitFor: [sim stdoutContents includesSubstring: 'Samaltak VM | tick 1 | 1 squared = 1'] timeout: 30000).
	 VMMain compile: 'banner <c: ''const char *vm_banner(void)''> ^''edited''' classified: 'running'.
	 self assert: (self waitFor: [sim stdoutContents includesSubstring: 'edited | tick'] timeout: 30000)]
		ensure: [VMMain addSelector: #banner withMethod: original]
!
testSmalltalk80GuestPrintsIt
	"The guest's Workspace: type 3 + 4 on its last line, cmd-P, and the guest's own Compiler prints 7 after it, selected, and logs it on the Transcript (which also writes stdout)."
	| sim screen |
	sim := self startSmalltalk80On: (screen := RecordingDisplay new).
	'3 + 4' do: [:c | screen key: c value modifiers: 0].
	screen key: $p value modifiers: 8.
	self assert: (self waitFor: [sim stdoutContents includesSubstring: '3 + 4 --> 7 ('] timeout: 60000).
	self assert: (self waitFor: [screen hasShown: '7' rule: 1] timeout: 10000).
	self assert: (self waitFor: [screen frames > 0])
!
testSmalltalk80GuestShowsAnEditedVMMethod
	"The animation's title is VMMain>>banner, read again every second."
	| screen original |
	original := VMMain compiledMethodAt: #banner.
	self startSmalltalk80On: (screen := RecordingDisplay new).
	self assert: (screen hasShown: 'Samaltak VM' rule: 0).
	[VMMain compile: 'banner <c: ''const char *vm_banner(void)''> ^''edited''' classified: 'running'.
	 self assert: (self waitFor: [screen hasShown: 'edited' rule: 0] timeout: 30000)]
		ensure: [VMMain addSelector: #banner withMethod: original]
!
testSmalltalk80GuestNeedsTheSimulator
	"The C VM has no guest display: displayOpen fails and the guest says so."
	| image sim run |
	image := self scratchDirectory , '/st80.image'.
	ImageBuilder buildFrom: 'st80' to: image.
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. image. '--headless'}).
	self assert: run exitCode equals: 1.
	self assert: (run output includesSubstring: 'No display').
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	self assert: (sim runMain: VMMain arguments: {'samaltak'. '--eden'. '4'. '--max-heap'. '64'. image. '--headless'}) equals: 1.
	self assert: (sim stdoutContents includesSubstring: 'No display')
! !

!VMSimulationTest methodsFor: 'private'!
startSmalltalk80On: aDisplay
	"Build st80/ into the scratch directory and boot it on aDisplay below my priority; answer the simulation once the desk is up."
	| image sim |
	image := self scratchDirectory , '/st80.image'.
	ImageBuilder buildFrom: 'st80' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	sim display: aDisplay.
	self fork: [sim runMain: VMMain arguments: {'samaltak'. '--eden'. '4'. '--max-heap'. '64'. image. '--headless'}] at: Processor userBackgroundPriority.
	self assert: (self waitFor: [sim stdoutContents includesSubstring: 'Smalltalk-80 on'] timeout: 60000).
	^sim
! !
