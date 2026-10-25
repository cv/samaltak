TestCase subclass: #JitTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitTest comment: 'Machine code end to end: JitSample assembles functions into the code cache and calls them, compiled with cc (natively) and simulated (in an Arm64Emulator); the simulated VM runs the mini kernel under the template and the baseline JIT, its machine code in an Arm64Emulator.'!

!JitTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!JitTest methodsFor: 'helpers'!
compileAndRun: moduleClasses header: aString arguments: anArray
	"Translate moduleClasses into my scratch directory, compile with cc and run; answer the finished OSProcess."
	| dir build |
	dir := self scratchDirectory.
	(VMTranslator modules: moduleClasses header: aString) writeTo: dir.
	build := OSProcess run: 'cc -std=gnu11 -O1 -Wall -Wextra -Wno-unused-parameter -Wno-unused-label -Werror -o program *.c 2>&1' in: dir.
	self assert: build succeeded description: [build output].
	^OSProcess run: (OSProcess commandFor: (Array with: dir , '/program') , anArray) in: dir
!
sampleOutput
	^'notes=4
note=108
add=7
sum=5050
callback=508
fib=610
hypot=5
array=140
sign=-1
flushed=0
'
! !

!JitTest methodsFor: 'tests'!
testSampleInSimulation
	| sim |
	sim := VMSimulation modules: {JitSample. Arm64Assembler. CodeCache}.
	self assert: (sim runMain: JitSample arguments: #('jit')) equals: 0.
	self assert: sim stdoutContents equals: self sampleOutput
!
testMiniImageUnderTheJitInSimulation
	"Every method compiled on its first activation; runtime calls go from the emulated code back into the simulated runtime."
	| image sim status jit |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	status := sim runMain: VMMain arguments: {'samaltak'. '--jit'. 'template'. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'JitSmall'}.
	self assert: status equals: 0.
	self assert: sim stdoutContents equals: (File readText: 'vm/tests/expected/JitSmall.txt').
	jit := sim module: JitRuntime.
	self assert: jit statCompiled > 10.
	self assert: jit statEntries > 0.
	self assert: jit statExits > 0
!
testMiniImageUnderTheBaselineJitInSimulation
	"The baseline compiler's code in an Arm64Emulator: inline caches linked and patched, frames pushed in machine code, the runtime's lazy frames."
	| image sim status jit |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	sim := VMSimulation modules: (VMModule vmModules select: [:c | c packageName ~= 'VM-Platform']).
	status := sim runMain: VMMain arguments: {'samaltak'. '--jit'. 'baseline'. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--eden'. '1'. '--max-heap'. '64'. image. '--headless'. 'JitSmall'}.
	self assert: status equals: 0.
	self assert: sim stdoutContents equals: (File readText: 'vm/tests/expected/JitSmall.txt').
	jit := sim module: JitRuntime.
	self assert: jit statCompiled > 10.
	self assert: (sim module: JitBaselineRuntime) statLinks > 0
!
testSampleInC
	| run |
	run := self compileAndRun: {JitSample. Arm64Assembler. CodeCache} header: 'jit' arguments: #().
	self assert: run exitCode = 0 description: [run output].
	self assert: run output equals: self sampleOutput
! !
