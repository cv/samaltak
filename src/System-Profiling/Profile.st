Object subclass: #Profile
	instanceVariableNames: 'profiler start stop process allSamples allAllocations allFrames allMarks samples allocations created statsNow'
	classVariableNames: ''
	package: 'System-Profiling'!

Profile comment: 'I am a view onto the profiler''s data: a time range (microsecond clock; start/stop nil means unbounded) and optionally one Process. I decode the rings once when created (a consistent snapshot) and answer samples, allocations, frames and marks in range, call trees (tallyTree, flameRoot, allocationTree), leaves, top allocation sites, per-process percentages and a MessageTally-style report (tallyString). from:to: and for: answer narrower Profiles over the same snapshot, e.g. for a range selected in the frame timeline.'!

!Profile methodsFor: 'accessing'!
profiler
	^profiler
!
process
	"Answer the Process I am restricted to, or nil for all."
	^process
!
start
	"Answer the start of my range (the oldest data if unbounded)."
	^start ifNil: [self dataStart]
!
stop
	^stop ifNil: [created]
!
duration
	"Answer the length of my range in µs."
	^self stop - self start
!
samples
	"Answer the CPU samples in range (idle samples included, see isIdle), oldest first."
	^samples ifNil: [samples := self filter: allSamples]
!
busySamples
	"Answer the CPU samples in range without the idle process."
	^self samples withoutIdle
!
allocations
	"Answer the allocation samples in range; each weighs the sampling interval in bytes."
	^allocations ifNil: [allocations := self filter: allAllocations]
!
frames
	"Answer the FrameRecords overlapping my range, oldest first."
	^(allFrames select: [:f | f overlapsFrom: self start to: self stop]) asArray
!
marks
	^(allMarks select: [:m | m time between: self start and: self stop]) asArray
!
samplesFor: aProcess
	^self samples samplesFor: aProcess
!
allocationsFor: aProcess
	^self allocations samplesFor: aProcess
!
microsPerSample
	"Answer the mean µs one CPU sample stands for."
	| all n |
	all := self samplesForTiming.
	n := all size.
	^n < 2
		ifTrue: [profiler interval]
		ifFalse: [(all last time - all first time) / (n - 1)]
! !

!Profile methodsFor: 'processes'!
processes
	"Answer the sampled Processes, most samples first (the idle process included)."
	^self samples processes
!
sampleCountFor: aProcess
	^self samples weightFor: aProcess
!
percentFor: aProcess
	"Answer the percentage of all samples in range attributed to aProcess."
	^self samples percentFor: aProcess
!
processSummary
	"Answer Arrays {process. label. samples. percent of samples}, most samples first."
	| total |
	total := self samples totalWeight.
	^self samples processWeights collect: [:a |
		Array
			with: a key
			with: (Profiler labelFor: a key)
			with: a value
			with: (total = 0 ifTrue: [0.0] ifFalse: [a value * 100.0 / total])]
!
idlePercent
	| total |
	total := self samples size.
	^total = 0 ifTrue: [0.0] ifFalse: [self samples idle size * 100.0 / total]
! !

!Profile methodsFor: 'trees'!
tallyTree
	"Answer the call tree (root, processes, frames outermost first) of the busy samples."
	^self busySamples tallyTree
!
flameRoot
	^self tallyTree
!
leaves
	"Answer Associations ProfileFrame -> samples ending there, most first."
	^self busySamples leaves
!
allocationTree
	"Answer the call tree of the allocation samples, weighted by bytes."
	^self allocations tallyTree
!
allocationFlameRoot
	^self allocationTree
!
topAllocationSites
	^self allocations topSites
!
topAllocationSites: n
	^self allocations topSites: n
! !

!Profile methodsFor: 'narrowing'!
from: startMicros to: stopMicros
	"Answer a Profile over the same snapshot, restricted to the range."
	^self copy setStart: startMicros stop: stopMicros process: process
!
for: aProcess
	"Answer a Profile over the same snapshot, restricted to aProcess."
	^self copy setStart: start stop: stop process: aProcess
!
frame: aFrameRecord
	"Answer a Profile of the time aFrameRecord took."
	^self from: aFrameRecord start to: aFrameRecord end
! !

!Profile methodsFor: 'statistics'!
statisticsDelta
	"Answer {deltas. micros. last}: the VMStatistics differences over my range, the µs it covers and the VMStatistics at its end, from the profiler's checkpoints."
	| a b |
	a := profiler statisticsAt: self start.
	b := (stop isNil or: [stop >= created])
		ifTrue: [Array with: created with: statsNow]
		ifFalse: [profiler statisticsAt: stop].
	(a isNil or: [b isNil]) ifTrue: [^nil].
	^Array with: (b at: 2) - (a at: 2) with: (b at: 1) - (a at: 1) with: (b at: 2)
! !

!Profile methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Profile('''; nextPutAll: (process isNil ifTrue: ['all Processes'] ifFalse: [Profiler labelFor: process]);
		nextPutAll: ''', '; nextPutAll: (Profiler printMicros: self duration);
		nextPutAll: ', '; print: self samples size; nextPutAll: ' samples)'
!
tallyString
	^String new: 4000 streamContents: [:s | self printTallyOn: s]
!
printTallyOn: aStream
	self printTallyOn: aStream threshold: 0.5
!
printTallyOn: aStream threshold: percent
	"Print a Squeak MessageTally-style report: **Tree** (per process), **Leaves**, **Memory**, **GCs**. Nodes under percent of the total are left out."
	| root total ms lf |
	lf := String with: Character lf.
	root := self tallyTree.
	total := root weight.
	ms := self microsPerSample / 1000.0.
	aStream nextPutAll: ' - '; print: total; nextPutAll: ' tallies, '; print: (total * ms) rounded; nextPutAll: ' msec.'.
	process isNil ifTrue: [
		aStream nextPutAll: '  (idle excluded: '; nextPutAll: (self idlePercent printShowingDecimalPlaces: 1); nextPutAll: '%)'].
	aStream nextPutAll: lf; nextPutAll: '   sampled every '; print: profiler interval; nextPutAll: ' µs over ';
		nextPutAll: (Profiler printMicros: self duration); nextPutAll: lf; nextPutAll: lf.
	aStream nextPutAll: '**Tree**'; nextPutAll: lf.
	root children do: [:procNode |
		aStream nextPutAll: '--------------------------------'; nextPutAll: lf;
			nextPutAll: 'Process: ('; print: (procNode process isNil ifTrue: ['?'] ifFalse: [procNode process priority]);
			nextPutAll: ') '; print: procNode process identityHash; nextPutAll: ': '; nextPutAll: procNode name; nextPutAll: lf;
			nextPutAll: '--------------------------------'; nextPutAll: lf.
		self printNodes: procNode children on: aStream depth: 0 total: total ms: ms threshold: percent].
	aStream nextPutAll: lf; nextPutAll: '**Leaves**'; nextPutAll: lf.
	self leaves do: [:a |
		(a value * 100.0 / total) >= percent ifTrue: [
			self printPercent: a value of: total width: 5 on: aStream.
			aStream nextPutAll: ' {'; print: (a value * ms) rounded; nextPutAll: 'ms} '; nextPutAll: a key label; nextPutAll: lf]].
	self printMemoryOn: aStream.
	self printGCsOn: aStream
!
printNodes: nodes on: aStream depth: depth total: total ms: ms threshold: percent
	nodes do: [:node |
		(node weight * 100.0 / total) >= percent ifTrue: [
			depth timesRepeat: [aStream nextPutAll: '  |'].
			self printPercent: node weight of: total width: (depth = 0 ifTrue: [5] ifFalse: [4]) on: aStream.
			aStream nextPutAll: ' {'; print: (node weight * ms) rounded; nextPutAll: 'ms} '; nextPutAll: node name;
				nextPut: Character lf.
			self printNodes: node children on: aStream depth: depth + 1 total: total ms: ms threshold: percent]]
!
printPercent: weight of: total width: width on: aStream
	| s |
	s := (total = 0 ifTrue: [0.0] ifFalse: [weight * 100.0 / total]) printShowingDecimalPlaces: 1.
	width - s size timesRepeat: [aStream space].
	aStream nextPutAll: s; nextPut: $%
!
printMemoryOn: aStream
	| delta stats seconds bytes lf |
	lf := String with: Character lf.
	delta := self statisticsDelta.
	bytes := self allocations totalWeight.
	aStream nextPutAll: lf; nextPutAll: '**Memory**'; nextPutAll: lf.
	aStream tab; nextPutAll: 'sampled'; tab; tab; nextPutAll: '+'; print: bytes; nextPutAll: ' bytes  ('; print: self allocations size;
		nextPutAll: ' samples × '; nextPutAll: (Profiler printBytes: profiler allocationInterval); nextPutAll: ')'; nextPutAll: lf.
	delta isNil ifTrue: [^self].
	stats := delta at: 3.
	seconds := ((delta at: 2) max: 1) / 1000000.0.
	aStream tab; nextPutAll: 'young'; tab; tab; nextPutAll: '+'; print: (delta at: 1) bytesAllocated; nextPutAll: ' bytes allocated'; nextPutAll: lf.
	aStream tab; nextPutAll: 'tenured'; tab; nextPutAll: '+'; print: (delta at: 1) bytesTenured; nextPutAll: ' bytes'; nextPutAll: lf.
	aStream tab; nextPutAll: 'old'; tab; tab; print: stats oldBytesUsed; nextPutAll: ' bytes used of '; print: stats oldBudget; nextPutAll: lf.
	aStream tab; nextPutAll: 'rate'; tab; tab; nextPutAll: (Profiler printBytes: ((delta at: 1) bytesAllocated / seconds) rounded); nextPutAll: '/s'; nextPutAll: lf
!
printGCsOn: aStream
	| delta d micros lf |
	lf := String with: Character lf.
	aStream nextPutAll: '**GCs**'; nextPutAll: lf.
	delta := self statisticsDelta.
	delta isNil ifTrue: [^self].
	d := delta at: 1.
	micros := (delta at: 2) max: 1.
	self printGC: 'scavenges' count: d scavenges micros: d scavengeMicroseconds over: micros on: aStream.
	self printGC: 'full' count: d fullGCs micros: d fullGCMicroseconds over: micros on: aStream.
	aStream tab; nextPutAll: 'switches'; tab; print: d processSwitches; nextPutAll: ' process switches'; nextPutAll: lf
!
printGC: aString count: n micros: gcMicros over: micros on: aStream
	aStream tab; nextPutAll: aString; tab; print: n; nextPutAll: ' totalling ';
		nextPutAll: (gcMicros / 1000.0 printShowingDecimalPlaces: 1); nextPutAll: ' ms (';
		nextPutAll: (gcMicros * 100.0 / micros printShowingDecimalPlaces: 1); nextPutAll: '% of the range)'.
	n > 0 ifTrue: [aStream nextPutAll: ', '; nextPutAll: (gcMicros / 1000.0 / n printShowingDecimalPlaces: 2); nextPutAll: ' ms average'].
	aStream nextPut: Character lf
! !

!Profile methodsFor: 'private'!
setProfiler: aProfiler from: startMicros to: stopMicros
	profiler := aProfiler.
	allSamples := aProfiler cpuSamples.
	allAllocations := aProfiler allocationSamples.
	allFrames := aProfiler allFrames.
	allMarks := aProfiler allMarks.
	created := Time microsecondClockValue.
	statsNow := Smalltalk vm statistics.
	self setStart: startMicros stop: stopMicros process: nil
!
setProfiler: aProfiler samples: cpuSampleSet allocations: allocationSampleSet frames: frameArray marks: markArray
	profiler := aProfiler.
	allSamples := cpuSampleSet.
	allAllocations := allocationSampleSet.
	allFrames := frameArray.
	allMarks := markArray.
	created := Time microsecondClockValue.
	statsNow := Smalltalk vm statistics.
	self setStart: nil stop: nil process: nil
!
setStart: startMicros stop: stopMicros process: aProcess
	start := startMicros.
	stop := stopMicros.
	process := aProcess.
	samples := allocations := nil
!
filter: aSampleSet
	(process isNil and: [start isNil and: [stop isNil]]) ifTrue: [^aSampleSet].
	^aSampleSet select: [:each |
		(process isNil or: [each process == process])
			and: [(start isNil or: [each time >= start]) and: [stop isNil or: [each time <= stop]]]]
!
dataStart
	| t |
	t := created.
	allSamples isEmpty ifFalse: [t := t min: allSamples first time].
	allAllocations isEmpty ifFalse: [t := t min: allAllocations first time].
	allFrames isEmpty ifFalse: [t := t min: allFrames first start].
	^t
!
samplesForTiming
	"Answer the CPU samples of all processes in range (for the time one sample stands for)."
	^process isNil ifTrue: [self samples] ifFalse: [(self copy setStart: start stop: stop process: nil) samples]
! !

!Profile class methodsFor: 'instance creation'!
profiler: aProfiler samples: cpuSampleSet allocations: allocationSampleSet frames: frameArray marks: markArray
	"Answer a Profile over samples decoded already (e.g. a ProfileAggregate's), as of now."
	^self new setProfiler: aProfiler samples: cpuSampleSet allocations: allocationSampleSet frames: frameArray marks: markArray
! !
