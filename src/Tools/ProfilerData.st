Object subclass: #ProfilerData
	instanceVariableNames: 'profiler live cpu allocations cpuSamples allocationSamples barList barTotals dropped hidden marks now oldest range filter frozen rangeCpu rangeAllocations profile rangeProfile summary total busy'
	classVariableNames: ''
	package: 'Tools'!

ProfilerData comment: 'I am what the Profiler window shows: the profiler''s data narrowed to a time range (nil: the whole ring) and a Process filter (#all: all but idle, or a Process). Live, I am a view of a ProfilerLive taken at one refresh: its ProfileAggregates answer the call trees, per-process counts and allocation sites without rebuilding anything, the filter picks a Process''s subtree. A pinned range freezes me (frozen: copies of the samples and frames): the range''s trees are then ProfileAggregates built once from its samples. Terminated Processes with the same label (short-lived ones such as each ''remote request'') count as one (the aggregates merge them; keyOf: answers the Process standing for them). Trees are ProfileNodes. All times are µs of the microsecond clock.'!

!ProfilerData methodsFor: 'accessing'!
profiler
	^profiler
!
profile
	"Answer a Profile of my snapshot (made when asked; the tally's memory and GC sections, the frame records, the evaluator)."
	^profile ifNil: [
		profile := Profile profiler: profiler samples: self allCpuSamples allocations: self allAllocationSamples
			frames: (barList asArray collect: [:b | b record]) marks: marks]
!
isFrozen
	^frozen
!
now
	"Answer when the data were taken."
	^now
!
oldest
	^oldest
!
range
	^range
!
range: anArrayOrNil
	"Narrow to {start. stop} (µs), or nil for the whole ring."
	range = anArrayOrNil ifTrue: [^self].
	range := anArrayOrNil.
	rangeCpu := rangeAllocations := rangeProfile := summary := nil
!
filter
	^filter
!
filter: aProcessOrAll
	filter == aProcessOrAll ifTrue: [^self].
	filter := aProcessOrAll.
	summary := nil
!
idleProcess
	^profiler idleProcess
!
rangeStart
	^range isNil ifTrue: [self oldest] ifFalse: [range first]
!
rangeStop
	^range isNil ifTrue: [self now] ifFalse: [range last]
!
rangeProfile
	^rangeProfile ifNil: [
		rangeProfile := range isNil ifTrue: [self profile] ifFalse: [self profile from: range first to: range last]]
!
filteredProfile
	"The range, restricted to the filter's Process (the evaluator's Profiler last answers the whole ring)."
	^filter == #all ifTrue: [self rangeProfile] ifFalse: [self rangeProfile for: filter]
!
memoryProfile
	"A Profile of the range and filter over the aggregates' samples (not copied: use it right away), for the tally's memory and GC sections."
	| p |
	p := Profile profiler: profiler samples: self cpuAggregate samples allocations: self allocationAggregate samples frames: #() marks: #().
	filter == #all ifFalse: [p := p for: filter].
	^p
!
microsPerSample
	"Answer the mean µs one CPU sample in range stands for."
	| all n |
	all := self cpuAggregate samples.
	n := all size.
	^n < 2
		ifTrue: [profiler interval]
		ifFalse: [(all last time - all first time) / (n - 1)]
!
marks
	^marks
!
cpuAggregate
	"Answer the ProfileAggregate of the CPU samples in range."
	range isNil ifTrue: [^cpu ifNil: [cpu := ProfileAggregate kind: #cpu samples: cpuSamples asArray profiler: profiler]].
	^rangeCpu ifNil: [rangeCpu := ProfileAggregate kind: #cpu samples: (self inRange: self allCpuSamples) profiler: profiler]
!
allocationAggregate
	range isNil ifTrue: [
		frozen ifFalse: [^live updatedAllocations].
		^allocations ifNil: [allocations := ProfileAggregate kind: #allocation samples: allocationSamples asArray profiler: profiler]].
	^rangeAllocations ifNil: [
		rangeAllocations := ProfileAggregate kind: #allocation samples: (self inRange: self allAllocationSamples) profiler: profiler]
!
samples
	"Answer the CPU samples in range (idle included)."
	^self cpuAggregate samples
! !

!ProfilerData methodsFor: 'processes'!
keyOf: aProcess
	"The Process a sample of aProcess counts for: itself while it lives, else the first terminated Process with its label."
	aProcess isNil ifTrue: [^nil].
	^self cpuAggregate groupOf: aProcess
!
summary
	"Answer rows {key. label. samples. percent}: All but idle first (key #all), then each sampled Process, most samples first (terminated ones under 0.1% left out); the filter's Process is kept (with 0) when it has no samples in range."
	| agg counts rows |
	summary isNil ifFalse: [^summary].
	agg := self cpuAggregate.
	total := agg totalWeight.
	busy := agg busyWeight.
	counts := OrderedCollection new.
	agg tracks do: [:t | t process isNil ifFalse: [counts add: t process -> t node weight]].
	rows := OrderedCollection new.
	rows add: (Array with: #all with: 'All but idle' with: busy with: (self percent: busy)).
	((counts reject: [:a | a key ~~ filter and: [a key isTerminated and: [(self percent: a value) < 0.1]]]) asArray
		sort: [:a :b | a value > b value or: [a value = b value and: [(self labelFor: a key) <= (self labelFor: b key)]]])
			do: [:a | rows add: (Array with: a key with: (self labelFor: a key) with: a value with: (self percent: a value))].
	(filter ~~ #all and: [(counts anySatisfy: [:a | a key == filter]) not])
		ifTrue: [rows add: (Array with: filter with: (self labelFor: filter) with: 0 with: 0.0)].
	^summary := rows asArray
!
totalSamples
	self summary.
	^total
!
busySamples
	self summary.
	^busy
!
percent: n
	^total = 0 ifTrue: [0.0] ifFalse: [n * 100.0 / total]
!
labelFor: aProcess
	aProcess == #all ifTrue: [^'All but idle'].
	^Profiler labelFor: aProcess
!
titleFor: aProcessOrAll
	aProcessOrAll == #all ifTrue: [^'all Processes'].
	^'Process ''', (self labelFor: aProcessOrAll), ''''
!
isIdle: aProcess
	^aProcess == profiler idleProcess
! !

!ProfilerData methodsFor: 'trees'!
cpuTree
	"Answer the call tree of the CPU samples in range passing the filter (all: the busy samples)."
	filter == #all ifTrue: [^self cpuAggregate root].
	^(self cpuAggregate nodeFor: filter) ifNil: [ProfileNode name: (self titleFor: filter) process: filter]
!
allocationTree
	"Answer the call tree of the allocation samples in range passing the filter, in bytes."
	filter == #all ifTrue: [^self allocationAggregate root].
	^(self allocationAggregate nodeFor: filter) ifNil: [ProfileNode name: (self titleFor: filter) process: filter]
!
leaves
	"Answer Associations ProfileFrame -> samples ending in it (CPU tree), heaviest first."
	^self cpuAggregate leavesFor: (filter == #all ifTrue: [nil] ifFalse: [filter])
!
topSites: n
	"Answer the heaviest AllocationSites in range passing the filter."
	^self allocationAggregate topSites: n for: (filter == #all ifTrue: [nil] ifFalse: [filter])
! !

!ProfilerData methodsFor: 'frames'!
bars
	"Answer the ProfilerFrameBars of the whole snapshot, oldest first."
	^barList
!
droppedCount
	^dropped
!
barTotals
	"Answer an IdentityDictionary Process -> CPU µs in all bars."
	^barTotals ifNil: [
		barTotals := IdentityDictionary new.
		barList do: [:bar |
			bar record processTimes keysAndValuesDo: [:p :us | barTotals at: p put: (barTotals at: p ifAbsent: [0]) + us]].
		barTotals]
!
barsFrom: t0 to: t1
	"Answer the bars overlapping t0..t1, oldest first."
	| all lo hi result i |
	all := barList.
	lo := 1.
	hi := all size + 1.
	[lo < hi] whileTrue: [ | mid |
		mid := lo + hi // 2.
		(all at: mid) end < t0 ifTrue: [lo := mid + 1] ifFalse: [hi := mid]].
	result := OrderedCollection new.
	i := lo.
	[i <= all size and: [(all at: i) start <= t1]] whileTrue: [
		result add: (all at: i).
		i := i + 1].
	^result
!
barsInRange
	^self barsFrom: self rangeStart to: self rangeStop
!
barAt: microseconds
	"Answer the bar whose interval contains microseconds, or nil."
	| all lo hi mid |
	all := barList.
	lo := 1.
	hi := all size.
	[lo <= hi] whileTrue: [
		mid := lo + hi // 2.
		(all at: mid) end < microseconds
			ifTrue: [lo := mid + 1]
			ifFalse: [
				(all at: mid) start > microseconds
					ifTrue: [hi := mid - 1]
					ifFalse: [^all at: mid]]].
	^nil
!
displayHidden
	^hidden
! !

!ProfilerData methodsFor: 'freezing'!
frozen
	"Answer a copy of me that no longer follows the profiler (for a pinned range)."
	frozen ifTrue: [^self].
	^self copy setFrozenCpu: cpu samplesCopy allocations: live updatedAllocations samplesCopy bars: barList asArray
! !

!ProfilerData methodsFor: 'printing'!
ringStats
	"Answer e.g. '16,041 samples · last 15.8 s · 1.0 MB ring'."
	^(frozen ifTrue: [cpuSamples size] ifFalse: [cpu size]) asStringWithCommas, ' samples ', '·', ' last ',
		(ProfilerFormat seconds: self now - self oldest), ' ', '·', ' ',
		(Profiler printBytes: profiler byteSize), ' ring'
! !

!ProfilerData methodsFor: 'private'!
setLive: aProfilerLive filter: aProcessOrAll range: anArrayOrNil
	| t |
	profiler := aProfilerLive profiler.
	live := aProfilerLive.
	cpu := aProfilerLive cpu.
	allocations := aProfilerLive allocations.
	barList := aProfilerLive bars bars.
	barTotals := aProfilerLive bars totals.
	dropped := aProfilerLive bars droppedCount.
	hidden := aProfilerLive bars displayHidden.
	marks := profiler allMarks.
	now := aProfilerLive now.
	t := now.
	cpu oldestTime isNil ifFalse: [t := t min: cpu oldestTime].
	barList isEmpty ifFalse: [t := t min: barList first record start].
	oldest := t.
	frozen := false.
	filter := aProcessOrAll ifNil: [#all].
	range := anArrayOrNil
!
setFrozenCpu: cpuSampleSet allocations: allocationSampleSet bars: anArray
	cpuSamples := cpuSampleSet.
	allocationSamples := allocationSampleSet.
	barList := anArray.
	barTotals := barTotals copy.
	frozen := true.
	"Live aggregates go on changing: the whole snapshot gets aggregates of its own when asked."
	cpu := allocations := nil.
	rangeCpu := rangeAllocations := rangeProfile := profile := summary := nil
!
allCpuSamples
	^frozen ifTrue: [cpuSamples] ifFalse: [cpu samplesCopy]
!
allAllocationSamples
	^frozen ifTrue: [allocationSamples] ifFalse: [live updatedAllocations samplesCopy]
!
inRange: aSampleSet
	| t0 t1 |
	t0 := range first.
	t1 := range last.
	^(aSampleSet select: [:s | s time between: t0 and: t1]) asArray
! !

!ProfilerData class methodsFor: 'instance creation'!
live: aProfilerLive filter: aProcessOrAll range: anArrayOrNil
	^self new setLive: aProfilerLive filter: aProcessOrAll range: anArrayOrNil
! !
