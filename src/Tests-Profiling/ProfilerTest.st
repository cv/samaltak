TestCase subclass: #ProfilerTest
	instanceVariableNames: 'workers'
	classVariableNames: ''
	package: 'Tests-Profiling'!

ProfilerTest comment: 'Integration tests of the sampling profiler against real samples: CPU-bound worker processes, an allocating process, wraparound of small rings, overhead, tree consistency, range and process filtering, frame records and marks.'!

!ProfilerTest methodsFor: 'running'!
setUp
	workers := OrderedCollection new
! !

!ProfilerTest methodsFor: 'workloads'!
factorialLoop
	[true] whileTrue: [(1 to: 1000) inject: 1 into: [:product :each | product * each]]
!
floatLoop
	| x |
	x := 0.0.
	[true] whileTrue: [1 to: 1000 do: [:i | x := x + (i asFloat sqrt * 1.5) sin]]
!
compileLoop
	[true] whileTrue: [Compiler evaluate: '(1 to: 10) inject: 0 into: [:a :b | a + (b printString: 16) size]']
!
allocateArrays
	| keep |
	[true] whileTrue: [keep := Array new: 1000]
!
busyFor: milliseconds
	"Keep this process busy (deep enough stacks) for milliseconds."
	| t |
	t := Time millisecondClockValue.
	[Time millisecondClockValue - t < milliseconds] whileTrue: [300 factorial]
!
fork: aSelector named: aString
	^workers add: (self fork: [self perform: aSelector] named: aString at: Processor userBackgroundPriority)
!
sleep: milliseconds
	"Let the workers run for milliseconds (the profiled time window)."
	(Delay forMilliseconds: milliseconds) wait
!
stopWorkers
	workers do: [:p | p terminate].
	workers := OrderedCollection new
! !

!ProfilerTest methodsFor: 'helpers'!
assertConsistent: aNode
	"Every node's children plus its self weight add up to its weight."
	aNode do: [:node | | sum |
		sum := node children inject: 0 into: [:a :each | a + each weight].
		self assert: sum + node selfWeight = node weight.
		self assert: sum <= node weight.
		node children do: [:each | self assert: each parent == node]]
!
withProfiler: aProfiler do: aBlock
	"Run aBlock with aProfiler as the running system profiler, then restore the default one."
	| old |
	old := Profiler default.
	old stop.
	Profiler default: aProfiler.
	aProfiler start.
	^[aBlock value] ensure: [
		aProfiler stop.
		Profiler default: old.
		old start]
!
stackOf: aSample includes: aSelector
	^aSample stack anySatisfy: [:f | f method selector == aSelector and: [f methodClass == ProfilerTest]]
! !

!ProfilerTest methodsFor: 'tests'!
testAlwaysOn
	| profiler t0 profile |
	profiler := Profiler default.
	self assert: profiler isRunning.
	self assert: (Smalltalk startUpList includes: #Profiler).
	"Sampling is timer-interrupt-driven: the timer process records the samples."
	self assert: profiler samplerProcess == Delay timerProcess.
	self assert: profiler samplerProcess priority = 80.
	self assert: profiler interval = 1000.
	self assert: profiler byteSize = (1024 * 1024).
	t0 := Time microsecondClockValue.
	"Busy until 50 samples arrived (about 50 ms at 1000 samples/s), at most 5 s."
	[self busyFor: 10.
	profile := Profiler from: t0 to: Time microsecondClockValue.
	profile samples size < 50 and: [profile stop - t0 < 5000000]] whileTrue.
	self assert: profile samples size >= 50.
	"At most one sample per interval (1 ms), plus slack for the range boundaries."
	self assert: profile samples size <= ((profile stop - t0) // 1000 + 10).
	self assert: (profile samples allSatisfy: [:s | s time between: t0 and: profile stop]).
	self assert: ((profile samplesFor: Processor activeProcess) size * 100 / profile samples size) >= 80
!
testAttributionToProcesses
	| a b t0 t1 profile as bs total |
	t0 := Time microsecondClockValue.
	a := self fork: #factorialLoop named: 'factorials'.
	b := self fork: #floatLoop named: 'floats'.
	self sleep: 400.
	t1 := Time microsecondClockValue.
	self stopWorkers.
	profile := Profiler from: t0 to: t1.
	total := profile samples size.
	as := profile samplesFor: a.
	bs := profile samplesFor: b.
	self assert: total >= 200.
	"Equal priorities take turns, so each gets about half."
	self assert: (as size + bs size) * 100 / total >= 85.
	self assert: ((profile percentFor: a) between: 30 and: 70).
	self assert: ((profile percentFor: b) between: 30 and: 70).
	self assert: (profile processes first: 2) asSet = (Set with: a with: b).
	self assert: (profile processSummary first at: 2) = (profile processes first name).
	"Right methods: the factorial worker is in LargePositiveInteger digit code, the float worker never is."
	self assert: (as count: [:s | self stackOf: s includes: #factorialLoop]) * 100 / as size >= 95.
	self assert: (bs count: [:s | self stackOf: s includes: #floatLoop]) * 100 / bs size >= 95.
	self assert: (as noneSatisfy: [:s | self stackOf: s includes: #floatLoop]).
	self assert: (bs noneSatisfy: [:s | self stackOf: s includes: #factorialLoop]).
	self assert: ((as count: [:s | s stack anySatisfy: [:f | f label includesSubstring: 'digit']]) * 100 / as size) >= 50.
	self assert: (as leaves first: 3) notEmpty.
	self assert: ((as leaves first: 5) anySatisfy: [:assoc | assoc key methodClass == LargePositiveInteger or: [assoc key selector beginsWith: 'digit']])
!
testLabels
	| t0 profile frames block method |
	t0 := Time microsecondClockValue.
	self fork: #floatLoop named: 'floats'.
	self sleep: 100.
	self stopWorkers.
	profile := Profiler from: t0 to: Time microsecondClockValue.
	frames := Set new.
	profile samples do: [:s | frames addAll: s stack].
	method := frames detect: [:f | f isBlock not and: [f method == (ProfilerTest >> #floatLoop)]] ifNone: [nil].
	self assert: method notNil.
	self assert: method label = 'ProfilerTest>>floatLoop'.
	block := frames detect: [:f | f isBlock and: [f method == (ProfilerTest >> #fork:named:)]] ifNone: [nil].
	self assert: block notNil.
	self assert: block label = '[] in ProfilerTest>>fork:named:'.
	self assert: block printString = block label.
	"Frames are interned: equal frames are identical."
	self assert: (Profiler last samples detect: [:s | s stack includes: method] ifNone: [nil]) notNil
!
testIdleSamplesFlagged
	| t0 profile idle |
	t0 := Time microsecondClockValue.
	self sleep: 150.
	profile := Profiler from: t0 to: Time microsecondClockValue.
	idle := profile samples idle.
	self assert: profile samples size >= 50.
	self assert: idle size * 100 / profile samples size >= 80.
	self assert: (idle allSatisfy: [:s | s process == Processor idleProcess]).
	self assert: profile idlePercent >= 80.
	"Idle samples stay out of the call tree."
	self assert: profile tallyTree weight = profile busySamples size
!
testAllocationSamples
	| t0 p profile allocs sites |
	t0 := Time microsecondClockValue.
	p := self fork: #allocateArrays named: 'allocator'.
	self sleep: 300.
	self stopWorkers.
	profile := Profiler from: t0 to: Time microsecondClockValue.
	allocs := profile allocationsFor: p.
	"Arrays of 1000 slots are 8 KB: hundreds of MB in 300 ms, one sample per MB."
	self assert: allocs size >= 20.
	self assert: allocs unit = #bytes.
	self assert: allocs totalWeight = (allocs size * Profiler default allocationInterval).
	self assert: (allocs count: [:s | s allocatedClass == Array]) * 100 / allocs size >= 90.
	self assert: (allocs allSatisfy: [:s | s allocationSize > 0]).
	self assert: (allocs count: [:s | self stackOf: s includes: #allocateArrays]) * 100 / allocs size >= 90.
	sites := profile topAllocationSites.
	self assert: sites first allocatedClass == Array.
	self assert: sites first method == (ProfilerTest >> #allocateArrays).
	self assert: sites first process == p.
	self assert: (sites inject: 0 into: [:sum :each | sum + each bytes]) <= profile allocations totalWeight.
	self assertConsistent: profile allocationTree.
	self assert: profile allocationTree weight = profile allocations totalWeight.
	self assert: ((profile allocations groupBy: #class) at: Array) size = (profile allocations count: [:s | s allocatedClass == Array])
!
testRingWraparound
	| small ring t0 t1 profile serials |
	small := Profiler new.
	small ringBytes: (StackRing bytes: 0 depth: small maxDepth) tableBytes + 16 + 4096.
	self withProfiler: small do: [
		t0 := Time microsecondClockValue.
		"At least 150 ms and 150 records (≈1 per ms, fewer on a loaded machine): the ring of ≈50 wraps twice over."
		[self busyFor: 10.
		 (small buffer count < 150 or: [Time microsecondClockValue - t0 < 150000])
			and: [Time microsecondClockValue - t0 < 5000000]] whileTrue.
		t1 := Time microsecondClockValue].
	profile := small last.
	ring := small buffer.
	self assert: ring dataSize <= 4096.
	self assert: ring count > 100.
	self assert: ring size < ring count.
	self assert: profile samples size + profile allocations size = ring size.
	serials := ((profile samples asArray, profile allocations asArray) collect: [:s | s serial]) asSortedCollection asArray.
	"The most recent window survives, without gaps (CPU and allocation records share it)."
	self assert: serials last = (ring count - 1).
	self assert: serials first = ring firstSerial.
	self assert: serials = (serials first to: serials last) asArray.
	self assert: ((profile samples collect: [:s | s serial]) asArray = (profile samples collect: [:s | s serial]) asSortedCollection asArray).
	self assert: (profile samples allSatisfy: [:s | s time between: t0 and: t1]).
	self assert: profile samples first time > (t0 + 40000).
	self assert: (profile samples allSatisfy: [:s | s stack anySatisfy: [:f | f selector == #busyFor:]])
!
testInlineStacksDecodeShared
	"Each record holds its stack inline; equal stacks decode to the same Array (trees aggregate by identity)."
	| fresh profile stacks factorials compiler |
	fresh := Profiler new.
	self withProfiler: fresh do: [
		factorials := self fork: #factorialLoop named: 'factorials'.
		compiler := self fork: #compileLoop named: 'compiler'.
		self sleep: 400.
		self stopWorkers].
	profile := fresh last.
	self assert: profile samples size > 200.
	self assert: fresh buffer lostFrames = 0.
	self assert: (profile samples allSatisfy: [:s | s stack allSatisfy: [:f | f method isCompiledMethod]]).
	stacks := IdentitySet new.
	profile samples do: [:s | stacks add: s stack].
	self assert: stacks size equals: (profile samples collect: [:s | s stack]) asSet size.
	"The factorial loop has few distinct stacks (the compiler's are mostly unique)."
	stacks := IdentitySet new.
	(profile samplesFor: factorials) do: [:s | stacks add: s stack].
	self assert: stacks size * 4 < (profile samplesFor: factorials) size.
	self assert: ((profile samplesFor: factorials) allSatisfy: [:s | self stackOf: s includes: #factorialLoop]).
	self assert: ((profile samplesFor: compiler)
		allSatisfy: [:s | s isTruncated or: [self stackOf: s includes: #compileLoop]]).
	self assertConsistent: profile tallyTree
!
testHistoryFitsInOneMegabyte
	| fresh seconds |
	self assert: Profiler default byteSize = (1024 * 1024).
	"Coverage depends on the stacks: measured with two busy workers at 1000 samples/s."
	fresh := Profiler new.
	self withProfiler: fresh do: [
		self fork: #factorialLoop named: 'factorials'.
		self fork: #floatLoop named: 'floats'.
		self sleep: 300.
		self stopWorkers].
	"The ring holds dataSize / (bytes recorded per second) seconds."
	seconds := fresh buffer dataSize / (fresh buffer usedBytes / (fresh coverageMicroseconds / 1000000.0)).
	self assert: seconds >= 10
!
testStackPrimitiveMatchesFallback
	"maxDepth > 255 makes the primitive fail, so the Smalltalk fallback runs; both must agree."
	| sem blk p a b ra rb n |
	sem := Semaphore new.
	blk := nil.
	blk := [:k | k = 0 ifTrue: [sem wait] ifFalse: [blk value: k - 1]].
	p := self fork: [blk value: 12] at: Processor activePriority + 1.
	a := Array new: 601.
	b := Array new: 129.
	ra := p profilerStackInto: a maxDepth: 300.
	rb := p profilerStackInto: b maxDepth: 64.
	self assert: ra = rb.
	n := (ra bitShift: -8) bitAnd: 255.
	self assert: n > 12.
	self assert: (ra bitAnd: 255) = 0.
	self assert: (a copyFrom: 1 to: 2 * n + 1) = (b copyFrom: 1 to: 2 * n + 1).
	self assert: ((p profilerStackInto: a maxDepth: 300) bitAnd: 255) = n.
	self assert: ((p profilerStackInto: b maxDepth: 64) bitAnd: 255) = n.
	self assert: ((p profilerStackInto: (Array new: 21) maxDepth: 10) bitAnd: 16r10000) ~= 0.
	sem signal
!
testCpuMicroseconds
	| p before after busy |
	p := Processor activeProcess.
	before := p cpuMicroseconds.
	self busyFor: 30.
	after := p cpuMicroseconds.
	"cpuTime only advances at process switches; cpuMicroseconds includes the running slice."
	self assert: after - before >= 20000.
	self assert: p cpuMicroseconds >= p cpuTime.
	busy := self fork: #floatLoop named: 'floats'.
	self sleep: 50.
	busy suspend.
	self assert: busy cpuMicroseconds = busy cpuTime.
	self assert: busy cpuMicroseconds > 20000
!
testOverhead
	| profiler percent bench ratios medians |
	profiler := Profiler default.
	"The time spent recording samples while the system is busy, in the best of five 100 ms windows: the OS preempting the VM only adds to it (the first window also interns the workload's stacks)."
	percent := (1 to: 5) inject: 100 into: [:best :i | | t0 cpu0 |
		t0 := Time microsecondClockValue.
		cpu0 := profiler samplerMicroseconds.
		self busyFor: 100.
		best min: (profiler samplerMicroseconds - cpu0) * 100.0 / (Time microsecondClockValue - t0)].
	self assert: percent < 1.0 description: ['sampler time ', percent printString, '%'].
	"Wall time of a short benchmark with and without the profiler: the median ratio of 100 adjacent runs in alternating order (machine load changes little within a pair; preempted runs are outliers). The best of up to three medians: about 1.01 on a loaded machine, a phase of heavier load can add 1%."
	bench := [Time microsecondsToRun: [1 to: 6 do: [:i | 300 factorial]]].
	bench value.
	medians := OrderedCollection new.
	[[medians size < 3 and: [medians isEmpty or: [medians last >= 1.02]]] whileTrue: [
		ratios := SortedCollection new.
		1 to: 100 do: [:i | | on off |
			i odd
				ifTrue: [profiler stop. off := bench value. profiler start. on := bench value]
				ifFalse: [on := bench value. profiler stop. off := bench value. profiler start].
			ratios add: on / off].
		medians add: (ratios asArray at: 51) asFloat]] ensure: [profiler start].
	self assert: medians last < 1.02 description: ['on/off wall time ratios ', medians asArray printString]
!
testTreesConsistent
	| t0 profile root procNode |
	t0 := Time microsecondClockValue.
	self fork: #factorialLoop named: 'factorials'.
	self fork: #allocateArrays named: 'allocator'.
	self sleep: 200.
	self stopWorkers.
	profile := Profiler from: t0 to: Time microsecondClockValue.
	root := profile tallyTree.
	self assertConsistent: root.
	self assert: root weight = profile busySamples size.
	self assert: root children notEmpty.
	self assert: (root children allSatisfy: [:n | n isProcessNode]).
	procNode := root children detect: [:n | n name = 'factorials'].
	self assert: procNode weight = (profile samplesFor: procNode process) size.
	self assert: (procNode children inject: 0 into: [:a :n | a + n weight]) <= procNode weight.
	"Children are sorted heaviest first and the leaves add up to the samples."
	root do: [:n | | ws |
		ws := n children collect: [:c | c weight].
		self assert: ws asArray = (ws asArray sort: [:x :y | x >= y])].
	self assert: (profile leaves inject: 0 into: [:a :each | a + each value]) = (profile busySamples reject: [:s | s stack isEmpty]) size.
	self assert: profile flameRoot weight = root weight.
	self assertConsistent: profile allocationTree.
	self assert: ((profile samples groupBy: #method) inject: 0 into: [:a :set | a + set size]) = profile samples size.
	self assert: ((profile samples groupBy: #process) at: procNode process) size = procNode weight
!
testRangeFiltering
	| t0 mid t1 profile early late a b both |
	t0 := Time microsecondClockValue.
	a := self fork: #factorialLoop named: 'first'.
	self sleep: 150.
	self stopWorkers.
	mid := Time microsecondClockValue.
	b := self fork: #floatLoop named: 'second'.
	self sleep: 150.
	self stopWorkers.
	t1 := Time microsecondClockValue.
	profile := Profiler from: t0 to: t1.
	early := profile from: t0 to: mid.
	late := profile from: mid + 1 to: t1.
	self assert: early samples size + late samples size = profile samples size.
	self assert: (early samples allSatisfy: [:s | s time <= mid]).
	self assert: (late samples allSatisfy: [:s | s time > mid]).
	self assert: (early samplesFor: a) size * 100 / early samples size >= 85.
	self assert: (late samplesFor: b) size * 100 / late samples size >= 85.
	self assert: (early samplesFor: b) isEmpty.
	both := profile for: a.
	self assert: both process == a.
	self assert: (both samples allSatisfy: [:s | s process == a]).
	self assert: both samples size = (profile samplesFor: a) size.
	self assert: (both tallyTree children collect: [:n | n process]) asArray = (Array with: a).
	self assert: ((both from: mid + 1 to: t1) samples) isEmpty.
	self assert: (profile samples from: t0 to: mid) size = early samples size
!
testFramesAndMarks
	| profiler first records mark frame profile worst |
	profiler := Profiler default.
	first := profiler allFrames size.
	mark := Profiler mark: 'before frames'.
	self assert: mark printString = 'a ProfileMark(''before frames'')'.
	records := (1 to: 5) collect: [:i | | start end |
		start := Time microsecondClockValue.
		self busyFor: i * 3.
		end := Time microsecondClockValue.
		"The active process's cpuTime only advances at process switches, so use the wall time it ran."
		Profiler recordFrame: (FrameRecord
			start: start end: end
			processTimes: (IdentityDictionary new at: Processor activeProcess put: end - start; yourself)
			draw: 100 raster: 200 gpu: 300 gcCount: 0 gcMicros: 0
			dropped: end - start > FrameRecord budgetMicros)].
	self assert: (records collect: [:r | r number]) asArray = ((1 to: 5) collect: [:i | records first number + i - 1]) asArray.
	self assert: (records first marks includes: mark).
	self assert: (records last marks includes: mark) not.
	self assert: (records allSatisfy: [:r | r duration > 0 and: [r processTotal <= r duration]]).
	self assert: (records last timeFor: Processor activeProcess) > 0.
	profile := Profiler from: records second start to: records fourth end.
	self assert: (profile frames collect: [:f | f number]) asArray = ((records copyFrom: 2 to: 4) collect: [:f | f number]) asArray.
	worst := Profiler last frames detectMax: [:f | f duration].
	self assert: worst duration >= records last duration.
	self assert: (Profiler last marks includes: mark).
	frame := records third.
	self assert: ((profile frame: frame) samples allSatisfy: [:s | frame includesTime: s time]).
	self assert: ((profile frame: frame) samples) notEmpty.
	self assert: (frame printString beginsWith: 'a FrameRecord(#').
	self assert: profiler allFrames size >= (first + 5 min: 1024)
!
testTallyReport
	| t0 text p |
	t0 := Time microsecondClockValue.
	p := self fork: #factorialLoop named: 'factorials'.
	self sleep: 150.
	self stopWorkers.
	text := (Profiler from: t0 to: Time microsecondClockValue) tallyString.
	#('tallies' '**Tree**' '**Leaves**' '**Memory**' '**GCs**' 'Process: (30) ' ': factorials' 'ProfilerTest>>factorialLoop' 'scavenges')
		do: [:s | self assert: (text includesSubstring: s) description: s].
	self assert: ((Profiler from: t0 to: Time microsecondClockValue) printString beginsWith: 'a Profile(''all Processes'', ').
	self assert: (Profiler last samples printString beginsWith: 'a SampleSet(')
! !
