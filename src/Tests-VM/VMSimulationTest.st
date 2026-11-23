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
testRetiredPrimitivesAbsentInSimulation
	| entries |
	entries := (VMSimulation modules: VMModule vmModules) primitiveEntries.
	(File readText: 'tests/vm/ffi_cutover_slots.tsv') lines do: [:line |
		(line notEmpty and: [line first ~= $#]) ifTrue: [
			| row id name |
			row := line substrings.
			id := row first asInteger.
			name := row second.
			self deny: (entries anySatisfy: [:entry | entry first = id or: [(entry at: 3) = name]])
				description: ['Retired simulator primitive: ', line]]]
!
testStaticPreparedEntriesAreRestricted
	| sim backend entry |
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	backend := sim moduleOrLibrary: 'FFIStubMemory'.
	self deny: backend canMapFFIStubs.
	entry := backend staticCoreEntry: 'core_stdout_text' signature: 16rD7.
	self deny: entry equals: 0.
	self assert: ((sim memory objectAt: entry) isKindOf: FunctionPointer).
	self assert: (backend staticCoreEntry: 'core_stdout_text' signature: 16rE7) equals: 0.
	self assert: (backend staticCoreEntry: 'printf' signature: 16rD7) equals: 0.
	self assert: (backend staticCoreEntry: 'platform_files_open' signature: 16r831) equals: 0
!
testMiniImageInSimulation
	| image sim status |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	status := sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Arith'}.
	self assert: status equals: 0.
	self assert: sim stdoutContents equals: (File readText: 'vm/tests/expected/Arith.txt')
!
testMiniImageServicesInSimulation
	"Exercise UTC, float formatting and fractionPart in the same mini guest as the VM's Misc test."
	| image sim status |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	status := sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Misc'}.
	self assert: status equals: 0.
	self assert: sim stdoutContents , sim stderrContents equals: (File readText: 'vm/tests/expected/Misc.txt')
!
testMiniSnapshotInSimulation
	"The guest reads a path from the simulated environment and persists state through the simulated C file API."
	| image snapshot modules sim saved |
	image := self scratchDirectory , '/mini.image'.
	snapshot := self scratchDirectory , '/snapshot.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	modules := VMModule vmModules select: [:c | c packageName ~= 'VM-Platform'].
	sim := VMSimulation modules: modules.
	sim environment at: 'MINI_SNAPSHOT' put: snapshot.
	self assert: (sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'Snapshot'}) equals: 0.
	saved := sim stdoutContents.
	sim := VMSimulation modules: modules.
	self assert: (sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. snapshot. '--headless'}) equals: 0.
	self assert: saved , sim stdoutContents equals: (File readText: 'vm/tests/expected/Snapshot.txt')
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
	 VMMain compile: 'banner <function> ^''edited''' classified: 'running'.
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
	[VMMain compile: 'banner <function> ^''edited''' classified: 'running'.
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
