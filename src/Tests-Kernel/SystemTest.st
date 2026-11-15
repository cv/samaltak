TestCase subclass: #SystemTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

SystemTest comment: 'Tests Smalltalk (globals, packages, the VM facade), the Transcript, Time, Date, Random and the startup machinery.'!

!SystemTest methodsFor: 'tests'!
testGlobals
	self assert: (Smalltalk at: #Object) == Object.
	self assert: (Smalltalk includesKey: #Transcript).
	self assert: (Smalltalk includesKey: #Processor).
	self assert: (Smalltalk at: #Smalltalk) == Smalltalk.
	self assert: (Smalltalk classNamed: 'Point class') == Point class.
	self assert: (Smalltalk classNamed: 'NoSuchClassAnywhere') isNil.
	self assert: (Smalltalk allClasses includes: Object).
	self assert: (Smalltalk allClasses includes: SystemDictionary).
	self deny: (Smalltalk allClasses anySatisfy: [:c | c isMeta]).
	Smalltalk at: #KernelTestGlobal put: 42.
	self assert: (Smalltalk at: #KernelTestGlobal) = 42.
	Smalltalk removeKey: #KernelTestGlobal.
	self deny: (Smalltalk includesKey: #KernelTestGlobal).
	self assert: Smalltalk printString = 'Smalltalk'.
	self assert: (Smalltalk at: #Undeclared) isDictionary
!
testPackages
	| names |
	names := Smalltalk packages collect: [:p | p name].
	self assert: names first = 'Kernel-Objects'.
	self assert: (names includes: 'Tests-Kernel').
	self assert: (names indexOf: 'Kernel-Objects') < (names indexOf: 'System-Support').
	self assert: (Smalltalk packageNamed: 'Kernel-Numbers') layer = 0.
	self assert: ((Smalltalk packageNamed: 'Kernel-Numbers') classes includes: SmallInteger).
	self assert: ((Smalltalk packageNamed: 'Kernel-Objects') classesInLoadOrder indexOf: ProtoObject) = 1
!
testVirtualMachine
	self assert: (Smalltalk vm arguments includes: '--test').
	self assert: Smalltalk isHeadless.
	self assert: Smalltalk isRunningTests.
	self assert: (Smalltalk vm primitiveNames includes: 'intAdd').
	self assert: Smalltalk vm statistics bytesAllocated > 0.
	self assert: Smalltalk vm imagePath notEmpty.
	self assert: (Smalltalk vm getenv: 'NO_SUCH_VARIABLE_HOPEFULLY') isNil.
	self assert: Smalltalk vm garbageCollect > 0.
	self assert: Smalltalk vm droppedEvents >= 0
!
testExternalSemaphores
	| vm a b i j |
	vm := Smalltalk vm.
	a := Semaphore new.
	b := Semaphore new.
	i := vm registerExternalSemaphore: a.
	[self assert: (vm externalObjects at: i) == a.
	 vm unregisterExternalSemaphore: i.
	 self assert: (vm externalObjects at: i) isNil.
	 j := vm registerExternalSemaphore: b.
	 self assert: j equals: i.
	 vm unregisterExternalSemaphore: nil.
	 self assert: (vm externalObjects at: j) == b]
		ensure: [vm unregisterExternalSemaphore: i; unregisterExternalSemaphore: j]
!
testExternalSemaphoresGrow
	| vm size indices |
	vm := Smalltalk vm.
	size := vm externalObjects size.
	indices := OrderedCollection new.
	[(vm externalObjects identityIndexOf: nil) > 0] whileTrue: [indices add: (vm registerExternalSemaphore: Semaphore new)].
	[indices add: (vm registerExternalSemaphore: Semaphore new).
	 self assert: indices last equals: size + 1.
	 self assert: vm externalObjects size > size]
		ensure: [indices do: [:each | vm unregisterExternalSemaphore: each]]
!
testStatistics
	| a b d |
	a := Smalltalk vm statistics.
	Smalltalk vm scavenge.
	b := Smalltalk vm statistics.
	d := b - a.
	self assert: d scavenges >= 1.
	self assert: d gcCount equals: d scavenges + d fullGCs.
	self assert: b oldBudget > 0.
	self assert: (VMStatistics counters: #(1 2 3)) weakSlotsCleared equals: 0.
	self assert: (VMStatistics counters: (1 to: 20) asArray) weakSlotsCleared equals: 12.
	self assert: (VMStatistics counters: (1 to: 20) asArray) contextsMaterialized equals: 13.
	self assert: (VMStatistics counters: (1 to: 20) asArray) frameFlushes equals: 14.
	self assert: b counters size equals: VMStatistics counterNames size.
	self assert: (b printString includesSubstring: 'scavenges: ')
!
testTranscript
	| text old listener |
	text := OrderedCollection new.
	listener := [:s | text add: s].
	old := Transcript echo.
	Transcript echo: false.
	[Transcript addListener: listener.
	 Transcript show: 'hello'; cr; print: 42; tab; show: 3; cr; display: 'x'; flush]
		ensure: [
			Transcript removeListener: listener.
			Transcript echo: old].
	self assert: (text inject: '' into: [:a :b | a, b]) = ('hello', (String with: Character lf), '42', (String with: Character tab), '3', (String with: Character lf), 'x').
	self assert: (Transcript contents endsWith: 'x')
!
testTime
	| t start |
	t := Time now.
	self assert: (t hours between: 0 and: 23).
	self assert: (t minutes between: 0 and: 59).
	self assert: t printString size = 8.
	self assert: (Time fromSeconds: 3661) printString = '01:01:01'.
	start := Time millisecondClockValue.
	self assert: start isInteger.
	self assert: Time microsecondClockValue >= (start * 1000 - 1000).
	self assert: (Time millisecondsToRun: [(Delay forMilliseconds: 10) wait]) >= 9.
	self assert: Time utcMicroseconds > 1700000000000000
!
testThreadCpuTime
	"The VM thread's CPU time covers the active Process's."
	| t0 p0 t1 p1 |
	t0 := Smalltalk vm threadCpuMicroseconds.
	p0 := Processor activeProcess cpuMicroseconds.
	[Processor activeProcess cpuMicroseconds - p0 < 20000] whileTrue.
	t1 := Smalltalk vm threadCpuMicroseconds.
	p1 := Processor activeProcess cpuMicroseconds.
	self assert: t1 - t0 >= (p1 - p0 - 1000).
	self assert: t1 - t0 < 10000000
!
testDate
	| d |
	d := Date year: 2026 month: 10 day: 22.
	self assert: d printString = '2026-10-22'.
	self assert: d dayOfWeekName = 'Thursday'.
	self assert: (Date fromDays: 0) printString = '1970-01-01'.
	self assert: (Date fromDays: d daysSinceEpoch) = d.
	self assert: (d addDays: 10) printString = '2026-11-01'.
	self assert: ((Date year: 2024 month: 3 day: 1) subtractDays: 1) day = 29.
	self assert: (Date isLeapYear: 2000).
	self deny: (Date isLeapYear: 1900).
	self assert: Date today year >= 2025.
	self assert: (Date year: 2000 month: 1 day: 1) < d
!
testRandom
	| r values |
	r := Random seed: 12345.
	values := (1 to: 1000) collect: [:i | r next].
	self assert: (values allSatisfy: [:v | v >= 0.0 and: [v < 1.0]]).
	self assert: values asSet size > 990.
	self assert: ((1 to: 1000) collect: [:i | r nextInt: 6]) asSet = (1 to: 6) asSet.
	self assert: ((Random seed: 1) next: 5) = ((Random seed: 1) next: 5)
!
testStartUpLists
	self assert: (Smalltalk startUpList includes: #Delay).
	self assert: (Smalltalk shutDownList includes: #Delay).
	self assert: Smalltalk mainProcess notNil.
	self assert: Delay timerProcess priority = 80
!
testStage2Steps
	| before |
	before := Smalltalk stage2Steps size.
	Smalltalk addStage2Step: [1] named: 'kernel test step'.
	Smalltalk addStage2Step: [2] named: 'kernel test step'.
	self assert: Smalltalk stage2Steps size = (before + 1).
	self assert: (Smalltalk stage2Steps detect: [:s | s key = 'kernel test step']) value value = 2.
	Smalltalk removeStage2StepNamed: 'kernel test step'.
	self assert: Smalltalk stage2Steps size = before
! !
