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
testLazyIdentityHashHeader
	| sim memory object header seed hash |
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	memory := sim module: ObjectMemory.
	memory memoryInit: 1024 * 1024 survivor: 0 maxHeap: 64 * 1024 * 1024.
	seed := memory hashSeed.
	object := memory allocObj: 0 format: VMConstants fBytes slots: 2.
	self assert: memory hashSeed equals: seed.
	header := (memory header: object) bitOr: (1 << 59).
	self assert: ((header >> 37) bitAnd: 16r3FFFFF) equals: 0.
	memory header: object put: header.
	hash := memory hashOf: object.
	self assert: (hash between: 1 and: 16r3FFFFF).
	self assert: (memory header: object) equals: (header bitOr: (hash << 37)).
	self deny: memory hashSeed equals: seed.
	seed := memory hashSeed.
	self assert: (memory hashOf: object) equals: hash.
	self assert: memory hashSeed equals: seed
!
testRetiredPrimitivesAbsentInSimulation
	| entries |
	entries := (VMSimulation modules: VMModule vmModules) primitiveEntries.
	#('ffi_cutover_slots.tsv' 'guest_display_retired_slots.tsv') do: [:file |
		(File readText: 'tests/vm/', file) lines do: [:line |
			(line notEmpty and: [line first ~= $#]) ifTrue: [
				| row id name |
				row := line substrings.
				id := row first asInteger.
				name := row second.
				self deny: (entries anySatisfy: [:entry | entry first = id or: [(entry at: 3) = name]])
					description: ['Retired simulator primitive: ', line]]]]
!
testStaticPreparedEntriesAreRestricted
	| sim backend entry |
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	backend := sim moduleOrLibrary: 'FFIStubMemory'.
	self deny: backend canMapFFIStubs.
	entry := backend staticCoreEntry: 'core_stdout_text' signature: 16r0D07.
	self deny: entry equals: 0.
	self assert: ((sim memory objectAt: entry) isKindOf: FunctionPointer).
	self assert: (backend staticCoreEntry: 'core_stdout_text' signature: 16r0E07) equals: 0.
	self assert: (backend staticCoreEntry: 'printf' signature: 16r0D07) equals: 0.
	self assert: (backend staticCoreEntry: 'platform_files_open' signature: 16r080301) equals: 0
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
testSmalltalk80PackedFramesAndInputAcrossGC
	| image sim screen status filled scrolled glyphs |
	image := self buildSmalltalk80Probe.
	sim := self guestSimulationOn: (screen := RecordingDisplay new).
	self fork: [status := self runSmalltalk80: image in: sim] at: Processor userBackgroundPriority.
	"Three bytes per row at 19 pixels wide. Check every byte, including row padding."
	filled := #[
		16rFE 16rA0 0
		16rF2 16rC0 0
		16rF1 16r2B 16r20
		16r0F 16r84 16rC0
		16r0F 16r80 0], (ByteArray new: 33).
	scrolled := #[
		16rFE 16rA0 0
		16rE5 16r84 0
		16rE2 16r50 0
		16r1F 16r0D 16r60
		16r1F 0 16r80
		16r01 16rF0 16rE0], (ByteArray new: 30).
	glyphs := #[
		0     16r03 16rE0
		16r42 16r03 16rE0
		16r42 16r03 16rE0
		16r42 16r01 16rE0
		16r42 16r01 16rE0
		16r7E 16r01 16rE0
		16r42 16r01 16rE0
		16r42 0     0
		16r42 16r01 16rE0
		16r42 16r01 16rE0
		16r42 16r01 16rE0
		0     16r01 16rE0
		0     16r01 16rE0
		0     16r03 16rE0
		0     16r03 16rE0
		0     16r03 16rE0].
	self assert: (self waitFor: [
		status notNil or: [(sim stdoutContents includesSubstring: 'Awaiting input before flush')
			and: [screen lastFrame = filled]]] timeout: 60000)
		description: [sim stdoutContents, sim stderrContents].
	self assert: screen extent equals: 19 @ 16.
	self assert: screen lastFrame equals: filled.
	screen queueEvent: #(1 10 5 0 1).
	"Input crossed the bridge, but the guest has not called flush again."
	self assert: (self waitFor: [sim stdoutContents includesSubstring: 'Received input before flush'] timeout: 30000)
		description: [sim stdoutContents, sim stderrContents].
	self assert: screen lastFrame equals: filled.
	screen queueEvent: #(3 15 9 0 2); queueEvent: #(2 16 10 0 0).
	1 to: 45 do: [:i | screen key: 65 + (i \\ 26) modifiers: (i bitAnd: 15)].
	self assert: (self waitFor: [status notNil or: [screen lastFrame = scrolled]] timeout: 30000)
		description: [sim stdoutContents, sim stderrContents].
	self assert: screen lastFrame equals: scrolled.
	screen key: 32 modifiers: 8.
	self assert: (self waitFor: [status notNil or: [screen lastFrame = glyphs]] timeout: 30000)
		description: [sim stdoutContents, sim stderrContents].
	self assert: screen lastFrame equals: glyphs.
	screen key: 13 modifiers: 0.
	self assert: (self waitFor: [status notNil] timeout: 30000).
	self assert: status = 0 description: [sim stdoutContents, sim stderrContents]
!
testSmalltalk80GuestPrintsIt
	"Drag the real guest Workspace, then type on its last line and print with Cmd-P."
	| sim screen frame reversedSeven |
	sim := self startSmalltalk80On: (screen := RecordingDisplay new).
	"Move the Workspace from 16@40 to 24@48 using the title tab."
	screen queueEvent: #(1 25 28 0 0); queueEvent: #(3 33 36 0 0); queueEvent: #(2 33 36 0 0).
	self assert: (self waitFor: [
		frame := screen lastFrame.
		(self inkAt: 16 @ 41 in: frame) = 0 and: [(self inkAt: 24 @ 49 in: frame) = 1]] timeout: 30000)
		description: ['The guest Workspace did not move'].
	'3 + 4' do: [:c | screen key: c value modifiers: 0].
	screen key: $p value modifiers: 8.
	self assert: (self waitFor: [sim stdoutContents includesSubstring: '3 + 4 --> 7 ('] timeout: 60000).
	"The result occupies the seventh 7-pixel cell on line 9 (after the expression and a space).
	Each expected row is MSB-left, black=1; reversed text is white on black."
	reversedSeven := #[16rFE 16rFE 16rFE 16r02 16rFA 16rF6 16rF6 16rEE
		16rEE 16rDE 16rDE 16rBE 16rBE 16rFE 16rFE 16rFE].
	self assert: (self waitFor: [self glyphAt: 70 @ 179 in: screen lastFrame equals: reversedSeven] timeout: 30000)
		description: ['The printed result did not appear selected in the guest frame']
!
testSmalltalk80GuestShowsAnEditedVMMethod
	"The animation's title reads VMMain>>banner again every second."
	| screen original initial edited origin |
	original := VMMain compiledMethodAt: #banner.
	self startSmalltalk80On: (screen := RecordingDisplay new).
	origin := 351 @ 192.
	initial := #[0 0 0 16r78 16r84 16r84 16r80 16r60 16r18 16r04 16r84 16r84 16r78 0 0 0].
	edited := #[0 0 0 0 0 0 16r78 16r84 16r84 16rFC 16r80 16r84 16r78 0 0 0].
	self assert: (self waitFor: [self glyphAt: origin in: screen lastFrame equals: initial] timeout: 30000).
	[VMMain compile: 'banner <function> ^''edited''' classified: 'running'.
	 self assert: (self waitFor: [self glyphAt: origin in: screen lastFrame equals: edited] timeout: 30000)]
		ensure: [VMMain addSelector: #banner withMethod: original]
!
testSmalltalk80GuestNeedsTheSimulator
	"Without a mailbox attachment, the guest reports that it has no display and exits."
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
	| image sim |
	image := self scratchDirectory , '/st80.image'.
	ImageBuilder buildFrom: 'st80' to: image.
	sim := self guestSimulationOn: aDisplay.
	self fork: [self runSmalltalk80: image in: sim] at: Processor userBackgroundPriority.
	self assert: (self waitFor: [(sim stdoutContents includesSubstring: 'Smalltalk-80 on')
		and: [aDisplay extent = (640 @ 400) and: [aDisplay lastFrame anySatisfy: [:byte | byte ~= 0]]]]
		timeout: 60000) description: [sim stdoutContents, sim stderrContents].
	^sim
!
guestSimulationOn: aDisplay
	^VMGuestSimulation
		modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform'])
		display: aDisplay
!
runSmalltalk80: image in: sim
	^sim runMain: VMMain arguments: {'samaltak'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'}
!
buildSmalltalk80Probe
	"Build the unmodified ST80 renderer, but substitute the probe for the desk at bootstrap."
	| sources image packages bootPath bootstrap |
	sources := self scratchDirectory , '/st80-probe'.
	Directory create: sources.
	packages := File readText: 'st80/packages.txt'.
	File writeText: packages to: sources , '/packages.txt'.
	packages lines do: [:raw |
		| line name from to |
		line := raw trimBoth.
		(line notEmpty and: [line first ~= $#]) ifTrue: [
			name := line substrings first.
			from := 'st80/' , name , '/'.
			to := sources , '/' , name , '/'.
			Directory create: to.
			((Directory fileNames: from) select: [:f | f endsWith: '.st']) do: [:file |
				File writeText: (File readText: from , file) to: to , file]]].
	bootPath := sources , '/ST80-UI/SystemDictionary.extension.st'.
	bootstrap := File readText: bootPath.
	self assert: (bootstrap includesSubstring: 'ScreenController open').
	File writeText: (bootstrap copyReplaceAll: 'ScreenController open' with: 'ST80DisplayProbe new run') to: bootPath.
	File writeText: (File readText: 'tests/vm/st80_display_probe.st') to: sources , '/ST80-UI/ST80DisplayProbe.st'.
	image := self scratchDirectory , '/st80-probe.image'.
	ImageBuilder buildFrom: sources to: image.
	^image
!
inkAt: p in: packed
	"Read a pixel of the stock 640x400 desk. Do not draw into the host frame."
	^((packed at: (p y * 80) + (p x // 8) + 1) bitShift: (p x \\ 8) - 7) bitAnd: 1
!
glyphAt: p in: packed equals: expectedRows
	0 to: expectedRows size - 1 do: [:dy |
		| row |
		row := 0.
		0 to: 6 do: [:dx |
			row := (row bitShift: 1) + (self inkAt: p + (dx @ dy) in: packed)].
		row * 2 = (expectedRows at: dy + 1) ifFalse: [^false]].
	^true
! !
