TestCase subclass: #LowtalkTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

LowtalkTest comment: 'Lowtalk programs run the same as Smalltalk (VMSimulation) and as C (VMTranslator, then cc).'!

!LowtalkTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!LowtalkTest methodsFor: 'helpers'!
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
	^'sum=55
counter=5
table=49
squares=140
chain=66
distance=3
fib=6765
clamp=255
case=19
overflow=-1
nooverflow=42
wrap=-5
untag=-3
twice=42
hash=167703939
loop=9
'
! !

!LowtalkTest methodsFor: 'tests'!
testSampleInSimulation
	| sim |
	sim := VMSimulation modules: {LowtalkSample}.
	self assert: (sim runMain: LowtalkSample arguments: #('sample')) equals: 0.
	self assert: sim stdoutContents equals: self sampleOutput , 'argc=1 sample
'
!
testSampleInC
	| run |
	run := self compileAndRun: {LowtalkSample} header: 'sample' arguments: #().
	self assert: run exitCode equals: 0.
	self assert: (run output copyFrom: 1 to: self sampleOutput size) equals: self sampleOutput.
	self assert: ((run output allButFirst: self sampleOutput size) beginsWith: 'argc=1 ')
! !
