TestCase subclass: #JitTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitTest comment: 'Machine code end to end: JitSample assembles functions into the code cache and calls them, compiled with cc (natively) and simulated (in an Arm64Emulator).'!

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
testSampleInC
	| run |
	run := self compileAndRun: {JitSample. Arm64Assembler. CodeCache} header: 'jit' arguments: #().
	self assert: run exitCode = 0 description: [run output].
	self assert: run output equals: self sampleOutput
! !
