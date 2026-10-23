TestCase subclass: #ProfileAggregateTest
	instanceVariableNames: 'workers'
	classVariableNames: ''
	package: 'Tests-Profiling'!

ProfileAggregateTest comment: 'I test ProfileAggregate against from-scratch rebuilds on real samples: CPU-bound, allocating and compiling workers plus short-lived Processes that terminate (their tracks merge by label). Offline, a recorded stream is slid through an aggregate in random steps (append k, drop the oldest j); live, aggregates follow a small, wrapping ring at random intervals. After the steps the trees (weights, self weights and sample counts along every path), the per-Process subtrees and the allocation sites must equal a rebuild over the same samples, and equal SampleSet>>tallyTree.'!

!ProfileAggregateTest methodsFor: 'running'!
setUp
	workers := OrderedCollection new
!
tearDown
	workers do: [:p | p terminate].
	super tearDown
!
timeLimitMilliseconds
	^120000
! !

!ProfileAggregateTest methodsFor: 'workloads'!
startWorkloads
	workers add: (self fork: [[true] whileTrue: [700 factorial]] named: 'factorials' at: 30).
	workers add: (self fork: [ | x | x := 0.0. [true] whileTrue: [1 to: 500 do: [:i | x := x + i asFloat sqrt sin]]] named: 'floats' at: 30).
	workers add: (self fork: [ | keep | [true] whileTrue: [keep := (1 to: 200) collect: [:i | Array new: 50]]] named: 'allocator' at: 30).
	workers add: (self fork: [[true] whileTrue: [Compiler evaluate: '(1 to: 10) inject: 0 into: [:a :b | a + (b printString: 16) size]']] named: 'compiler' at: 30).
	"Short-lived Processes with one label: terminated ones are merged."
	workers add: (self fork: [[true] whileTrue: [
		(self fork: [ | t | t := Time millisecondClockValue. [Time millisecondClockValue - t < 8] whileTrue: [200 factorial]] named: 'burst' at: 30).
		(Delay forMilliseconds: 25) wait]] named: 'spawner' at: 31)
!
record: milliseconds with: aProfiler
	"Run the workloads for milliseconds with aProfiler as the system profiler; answer aProfiler last."
	| old |
	old := Profiler default.
	old stop.
	Profiler default: aProfiler.
	aProfiler start.
	[self startWorkloads.
	 (Delay forMilliseconds: milliseconds) wait.
	 workers do: [:p | p terminate].
	 workers := OrderedCollection new.
	 (Delay forMilliseconds: 60) wait]
		ensure: [
			aProfiler stop.
			Profiler default: old.
			old start].
	^aProfiler last
! !

!ProfileAggregateTest methodsFor: 'canonical form'!
keyOf: aNode
	aNode isProcessNode ifTrue: [
		^aNode process isTerminated
			ifTrue: ['terminated ', (Profiler labelFor: aNode process)]
			ifFalse: [aNode process]].
	^aNode frame ifNil: [aNode key]
!
canonical: aNode
	"Answer a Dictionary from paths of node keys (terminated Processes by label) to {weight. self weight. sample count}, summing nodes with equal paths."
	| d |
	d := Dictionary new.
	self add: aNode path: #() into: d.
	^d
!
canonicalChildren: aNode
	"Like canonical: for the subtrees of aNode's children (the root's own counts left out)."
	| d |
	d := Dictionary new.
	aNode children do: [:c | self add: c path: (Array with: (self keyOf: c)) into: d].
	^d
!
add: aNode path: anArray into: aDictionary
	| v |
	v := aDictionary at: anArray ifAbsent: [#(0 0 0)].
	aDictionary at: anArray put: (Array with: (v at: 1) + aNode weight with: (v at: 2) + aNode selfWeight with: (v at: 3) + aNode sampleCount).
	aNode children do: [:c | self add: c path: (anArray copyWith: (self keyOf: c)) into: aDictionary]
!
dictionaryOf: associations
	| d |
	d := Dictionary new.
	associations do: [:a | d at: a key put: a value].
	^d
!
sitesOf: anArray
	"Answer a Dictionary {frame. class} -> bytes."
	| d |
	d := Dictionary new.
	anArray do: [:site | | k |
		k := Array with: site frame with: site allocatedClass.
		d at: k put: (d at: k ifAbsent: [0]) + site bytes].
	^d
! !

!ProfileAggregateTest methodsFor: 'checks'!
assertWellFormed: anAggregate
	| trees |
	trees := Array with: anAggregate root with: anAggregate idleRoot.
	trees do: [:tree |
		tree do: [:node | | sum |
			sum := node children inject: 0 into: [:a :each | a + each weight].
			self assert: sum + node selfWeight equals: node weight.
			node == tree ifFalse: [self assert: node sampleCount > 0 description: 'a node without samples was kept'].
			node children do: [:each | self assert: each parent == node]]].
	self assert: anAggregate totalWeight equals: (anAggregate samples inject: 0 into: [:a :s | a + s weight]).
	self assert: (anAggregate tracks inject: 0 into: [:a :t | a + t node sampleCount]) equals: anAggregate size
!
assert: anAggregate equalsRebuildOf: aSampleSet
	"anAggregate's trees, subtrees and sites equal a rebuild over aSampleSet and SampleSet's own tallyTree."
	| rebuilt busy |
	self assertWellFormed: anAggregate.
	rebuilt := ProfileAggregate kind: anAggregate kind samples: aSampleSet asArray profiler: anAggregate profiler.
	self assert: (self canonical: anAggregate root) equals: (self canonical: rebuilt root).
	self assert: (self canonical: anAggregate idleRoot) equals: (self canonical: rebuilt idleRoot).
	busy := anAggregate kind == #cpu ifTrue: [aSampleSet withoutIdle] ifFalse: [aSampleSet].
	self assert: (self canonicalChildren: anAggregate root) equals: (self canonicalChildren: busy tallyTree).
	self assert: anAggregate root weight equals: busy totalWeight.
	self assert: (self dictionaryOf: (anAggregate leavesFor: nil)) equals: (self dictionaryOf: busy leaves).
	"Process filters: a Process's node equals the tree of its group's samples."
	(aSampleSet collect: [:s | s process]) asIdentitySet do: [:p | | node group |
		node := anAggregate nodeFor: p.
		self assert: node notNil description: 'no node for a sampled Process'.
		group := aSampleSet select: [:s | (anAggregate groupOf: s process) == (anAggregate groupOf: p)].
		self assert: node weight equals: group totalWeight.
		self assert: (self canonicalChildren: node) equals: (self canonicalChildren: (self subtreeOf: group tallyTree)).
		self assert: (self dictionaryOf: (anAggregate leavesFor: p)) equals: (self dictionaryOf: group leaves).
		anAggregate kind == #allocation ifTrue: [
			self assert: (self sitesOf: (anAggregate topSites: 100000 for: p)) equals: (self sitesOf: (group topSites: 100000))]].
	anAggregate kind == #allocation ifTrue: [
		self assert: (self sitesOf: (anAggregate topSites: 100000 for: nil)) equals: (self sitesOf: (aSampleSet topSites: 100000))]
!
subtreeOf: aRoot
	"A root over the frames below aRoot's process nodes (they are one group)."
	| merged |
	merged := ProfileNode root.
	aRoot children do: [:procNode | self graft: procNode into: merged].
	^merged
!
graft: aNode into: aTarget
	aNode children do: [:c | | t |
		t := aTarget childAt: c key name: c name frame: c frame process: nil.
		t add: c weight count: c sampleCount.
		t addSelf: c selfWeight.
		self graft: c into: t]
! !

!ProfileAggregateTest methodsFor: 'tests'!
testSlidingWindowEqualsRebuild
	"A recorded stream slid through aggregates in random steps; after every few steps they equal a rebuild."
	| profiler profile random |
	profiler := Profiler new.
	profile := self record: 1200 with: profiler.
	random := Random seed: 4711.
	(Array with: profile samples with: profile allocations) do: [:stream | | all agg window next steps |
		all := stream asArray.
		self assert: all size > (stream unit == #bytes ifTrue: [3] ifFalse: [100]) description: 'too few samples recorded'.
		agg := ProfileAggregate kind: (stream unit == #bytes ifTrue: [#allocation] ifFalse: [#cpu]) samples: #() profiler: profiler.
		window := OrderedCollection new.
		next := 1.
		steps := 0.
		[next <= all size] whileTrue: [ | k j chunk |
			k := (random nextInt: (stream unit == #bytes ifTrue: [3] ifFalse: [90])) min: all size - next + 1.
			chunk := all copyFrom: next to: next + k - 1.
			next := next + k.
			agg addAll: chunk.
			window addAllLast: chunk.
			j := random nextInt: ((window size * 3 // 5) max: 1).
			agg removeOldest: j.
			window removeFirst: (j min: window size).
			steps := steps + 1.
			(steps \\ 7 = 0 or: [next > all size]) ifTrue: [
				self assert: agg size equals: window size.
				self assert: (agg samples asArray collect: [:s | s serial]) equals: (window asArray collect: [:s | s serial]).
				self assert: agg equalsRebuildOf: (SampleSet unit: stream unit samples: window copy)]].
		self assert: steps >= (all size // 90 min: 10) description: 'too few steps'.
		agg removeOldest: agg size.
		self assert: agg root isLeaf description: 'nodes left after removing every sample'.
		self assert: agg tracks isEmpty description: 'tracks left after removing every sample']
!
testTerminatedProcessesMerge
	| profiler profile agg bursts track |
	profiler := Profiler new.
	profile := self record: 600 with: profiler.
	agg := ProfileAggregate kind: #cpu samples: profile samples asArray profiler: profiler.
	bursts := (profile samples collect: [:s | s process]) asIdentitySet select: [:p | p notNil and: [p name = 'burst']].
	self assert: bursts size > 3.
	track := agg trackOf: bursts anyOne.
	self assert: track isRetired.
	self assert: (bursts allSatisfy: [:p | (agg trackOf: p) == track]).
	self assert: (agg root children select: [:n | n name = 'Process ''burst''']) size equals: 1.
	self assert: track node weight equals: (profile samples select: [:s | bursts includes: s process]) size
!
testLiveFollowsAWrappingRing
	"Live aggregates of a small ring, updated at random intervals while it wraps, equal a rebuild of their samples."
	| small cpu alloc random old checks |
	small := Profiler new.
	small ringBytes: (StackRing bytes: 0 depth: small maxDepth) tableBytes + 16 + 60000.
	small allocationInterval: 1024 * 1024.
	random := Random seed: 42.
	old := Profiler default.
	old stop.
	Profiler default: small.
	small start.
	checks := 0.
	[cpu := ProfileAggregate on: small kind: #cpu.
	 alloc := ProfileAggregate on: small kind: #allocation.
	 self startWorkloads.
	 30 timesRepeat: [ | ring |
		(Delay forMilliseconds: 5 + (random nextInt: 60)) wait.
		cpu update.
		alloc update.
		ring := small buffer.
		"Everything still in the ring was folded in, nothing dropped stays."
		(Array with: cpu with: alloc) do: [:agg | | serials |
			serials := agg samples asArray collect: [:s | s serial].
			self assert: serials asSortedCollection asArray = serials description: 'samples out of order'.
			self assert: (serials isEmpty or: [ring firstSerial - serials first < 50]) description: 'dropped samples were kept'].
		(random nextInt: 3) = 1 ifTrue: [
			checks := checks + 1.
			self assert: cpu equalsRebuildOf: cpu samplesCopy.
			self assert: alloc equalsRebuildOf: alloc samplesCopy]].
	 self assert: small buffer count > (small buffer size * 3) description: 'the ring did not wrap'.
	 self assert: alloc size > 5 description: 'too few allocation samples'.
	 self assert: checks > 3 description: 'too few checks']
		ensure: [
			workers do: [:p | p terminate].
			small stop.
			Profiler default: old.
			old start]
!
testLiveMatchesTheProfilersSnapshot
	| fresh live profile serials snapshotSerials |
	fresh := Profiler new.
	live := ProfileAggregate on: fresh kind: #cpu.
	self record: 300 with: fresh.
	live update.
	profile := fresh last.
	serials := live samples asArray collect: [:s | s serial].
	snapshotSerials := profile samples asArray collect: [:s | s serial].
	self assert: serials equals: snapshotSerials.
	self assert: (self canonicalChildren: live root) equals: (self canonicalChildren: profile tallyTree).
	self deny: live update
! !
