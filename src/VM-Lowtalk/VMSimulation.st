Object subclass: #VMSimulation
	instanceVariableNames: 'memory modules libraries functionPointers primitiveTable primitiveCount stdout stderr stdoutFile stderrFile exitCode environment arguments outputListener bytecodes clock clockOffset variableIndexes'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

VMSimulation comment: 'I run Lowtalk modules as Smalltalk: I instantiate them over a SimulatedMemory, give their variables their initial values and connect their module and library variables. The C libraries are simulated by their CLibrary classes; what the simulated program writes to stdout and stderr is collected here.

	| sim |
	sim := VMSimulation modules: {SampleModule}.
	sim run: [(sim module: SampleModule) main].
	sim stdoutContents'!

Error subclass: #VMExit
	instanceVariableNames: 'code'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

VMExit comment: 'The simulated program called exit().'!

!VMExit methodsFor: 'accessing'!
code
	^code
!
code: anInteger
	code := anInteger
! !

!VMSimulation class methodsFor: 'instance creation'!
modules: aCollectionOfClasses
	^self new setModules: aCollectionOfClasses
! !

!VMSimulation methodsFor: 'initialization'!
setModules: aCollectionOfClasses
	CTypeRegistry reset.
	memory := SimulatedMemory new.
	modules := IdentityDictionary new.
	libraries := IdentityDictionary new.
	functionPointers := Dictionary new.
	stdout := WriteStream on: String new.
	stderr := WriteStream on: String new.
	stdoutFile := SimulatedFile name: 'stdout' stream: stdout.
	stderrFile := SimulatedFile name: 'stderr' stream: stderr.
	environment := Dictionary new.
	arguments := #().
	bytecodes := clock := clockOffset := 0.
	variableIndexes := IdentityDictionary new.
	aCollectionOfClasses do: [:c |
		| m |
		(c class includesSelector: #resetSimulationCaches) ifTrue: [c resetSimulationCaches].
		m := (self simulationClassFor: c) basicNew.
		m setSimulation: self.
		modules at: c put: m].
	modules do: [:m | m initializeVariables]
!
simulationClassFor: aModuleClass
	^aModuleClass simulationClass
! !

!VMSimulation methodsFor: 'accessing'!
memory
	^memory
!
module: aClass
	^modules at: aClass
!
modules
	^modules
!
indexOfVariable: aSymbol in: aModuleClass
	"The instance variable index of a module's variable (atomic access by name)."
	^(variableIndexes at: aModuleClass ifAbsentPut: [IdentityDictionary new])
		at: aSymbol ifAbsentPut: [aModuleClass instVarIndexFor: aSymbol]
!
isModuleType: aTypeName
	| c |
	c := Smalltalk at: aTypeName asSymbol ifAbsent: [^false].
	^c isBehavior and: [(c inheritsFrom: VMModule) or: [c inheritsFrom: CLibrary]]
!
moduleOrLibrary: aTypeName
	| c |
	c := Smalltalk at: aTypeName asSymbol.
	(c inheritsFrom: CLibrary) ifTrue: [^self library: c].
	^modules at: c ifAbsent: [
		| candidates |
		candidates := modules values select: [:m | (m class includesBehavior: c) and: [m class isSimulated]].
		candidates isEmpty ifTrue: [self error: 'the simulation has no module ' , aTypeName].
		"an arch interface's module for arm64 (machine code does not run here)"
		candidates detect: [:m | m class targetArch isNil or: [m class targetArch = #arm64]] ifNone: [candidates first]]
!
library: aLibraryClass
	^libraries at: aLibraryClass ifAbsent: [
		libraries at: aLibraryClass put: (aLibraryClass new setSimulation: self; yourself)]
!
functionPointerTo: aModule selector: aSymbol
	^functionPointers at: (Array with: aModule with: aSymbol) ifAbsent: [
		functionPointers at: (Array with: aModule with: aSymbol) put: (FunctionPointer receiver: aModule selector: aSymbol)]
!
environment
	"Simulated environment variables (getenv)."
	^environment
!
arguments
	^arguments
!
arguments: anArrayOfStrings
	arguments := anArrayOfStrings
!
bytecodes
	"How many bytecodes the simulated interpreter has dispatched."
	^bytecodes
!
noteBytecode
	bytecodes := bytecodes + 1
!
microsecondClock
	"The simulated monotonic clock: the host's, but never going back (a host restarted from a snapshot taken while I ran restarts its clock)."
	| now |
	now := Time microsecondClockValue + clockOffset.
	now < clock ifTrue: [
		clockOffset := clockOffset + clock - now.
		now := clock].
	^clock := now
! !

!VMSimulation methodsFor: 'output'!
stdout
	^stdout
!
stderr
	^stderr
!
stdoutFile
	^stdoutFile
!
stderrFile
	^stderrFile
!
onOutput: aBlock
	"aBlock is evaluated with everything the simulated program writes to stdout or stderr (in the simulation's Process)."
	outputListener := aBlock
!
noteOutput: aString
	outputListener isNil ifFalse: [outputListener value: aString]
!
stdoutContents
	^stdout contents
!
stderrContents
	^stderr contents
!
exitCode
	^exitCode
! !

!VMSimulation methodsFor: 'running'!
run: aBlock
	"Evaluate aBlock (calls into the modules) until it returns or the program exits; answer the exit code (nil if it returned)."
	exitCode := nil.
	[aBlock value] on: VMExit do: [:e | exitCode := e code. e return: nil].
	^exitCode
!
exit: anInteger
	^VMExit new code: anInteger; signal
!
runMain: aModuleClass arguments: anArrayOfStrings
	"Call the module's main(argc, argv) with argv in simulated memory; answer the exit status."
	| argv m result |
	arguments := anArrayOfStrings.
	argv := memory allocate: 8 * (anArrayOfStrings size + 1).
	anArrayOfStrings doWithIndex: [:a :i | memory uint64At: argv + (8 * (i - 1)) put: (memory newCString: a)].
	m := modules at: aModuleClass.
	result := self run: [m main: anArrayOfStrings size argv: (CPointer memory: memory address: argv type: (CTypeRegistry default parse: 'char *'))].
	^result ifNil: [exitCode := 0]
! !

!VMSimulation methodsFor: 'primitives'!
primitiveEntries
	"{number. flags. name. module. selector} of the modules' primitives, sorted by number."
	| all |
	all := OrderedCollection new.
	modules keysAndValuesDo: [:c :m |
		c selectors do: [:sel |
			| method p |
			method := c compiledMethodAt: sel.
			p := (method pragmas ifNil: [#()]) detect: [:each | each selector == #vmPrimitive:name:] ifNone: [nil].
			p notNil ifTrue: [
				| flags |
				flags := ((method pragmas anySatisfy: [:each | each selector == #leaf]) ifTrue: [1] ifFalse: [0])
					+ ((method pragmas anySatisfy: [:each | each selector == #notTryable]) ifTrue: [0] ifFalse: [2]).
				all add: (Array with: (p arguments at: 1) with: flags with: (p arguments at: 2) with: m with: sel)]]].
	^(all asSortedCollection: [:a :b | (a at: 1) <= (b at: 1)]) asArray
!
primitiveTable
	primitiveTable isNil ifTrue: [self buildPrimitiveTable].
	^primitiveTable
!
primitiveCount
	primitiveTable isNil ifTrue: [self buildPrimitiveTable].
	^primitiveCount
!
buildPrimitiveTable
	| entries type base |
	entries := self primitiveEntries.
	type := CTypeRegistry default at: 'PrimitiveEntry'.
	base := memory allocate: (type size * entries size max: 1).
	primitiveTable := type load: memory at: base.
	entries doWithIndex: [:e :i |
		| entry |
		entry := primitiveTable at: i - 1.
		entry number: (e at: 1).
		entry flags: (e at: 2).
		entry name: (e at: 3).
		entry function: (self functionPointerTo: (e at: 4) selector: (e at: 5))].
	primitiveCount := entries size
! !

Object subclass: #SimulatedFile
	instanceVariableNames: 'name stream'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

SimulatedFile comment: 'A FILE * of the simulated C library: a name and the stream it writes to.'!

!SimulatedFile class methodsFor: 'instance creation'!
name: aString stream: aStream
	^self new setName: aString stream: aStream
! !

!SimulatedFile methodsFor: 'accessing'!
setName: aString stream: aStream
	name := aString.
	stream := aStream
!
name
	^name
!
stream
	^stream
! !
