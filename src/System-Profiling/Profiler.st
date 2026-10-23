Object subclass: #Profiler
	instanceVariableNames: 'ring ringBytes frames frameCount marks markCount statsTimes statsValues statsCount running cpuIndex interval allocInterval maxDepth frameCapacity contextSamples startTime idle frameTable lock cpuCache allocCache samplerMicros cpuSampleCount'
	classVariableNames: 'Default'
	package: 'System-Profiling'!

Profiler comment: 'I am the always-on sampling profiler. Sampling is timer-interrupt-driven: the VM signals the timer process''s Semaphore (Delay timingSemaphore; the timer process is ''timer interrupt watcher'', priority 80) every interval µs (default 1000) and after every allocInterval bytes allocated (default 256 KB), and the timer process calls me after each wakeup (Delay sampleHook:). samplerTickTake and allocationSampleTake tell what is due: for a CPU tick I record the stack of the process the timer interrupted (Processor preemptedProcess), for an allocation sample the allocating process''s stack plus the class and size of the sampled object (Context samples are only counted). Samples go into a StackRing: variable-length records with the stack inline (4-byte frame ids, at most maxDepth frames) in a preallocated buffer, exactly 1 MiB with its tables; recording never allocates, the oldest records are dropped. How many seconds the ring holds depends on the stacks (about 15 s at 1000 samples/s for the walkthrough''s mix). Samples of the idle process are kept but flagged.

The compositor reports each presented frame with Profiler recordFrame: aFrameRecord (kept in a ring of frameCapacity); Profiler mark: ''label'' drops a ProfileMark. Every 64 CPU samples I checkpoint the VM statistics for the GC and memory summaries.

Queries answer ordinary objects: Profiler last (everything still in the ring) or Profiler from: t0 to: t1 (microsecond clock) answer a Profile. Tools never call the sampling primitives (they are behind Smalltalk vm).'!

!Profiler methodsFor: 'initialization'!
initialize
	interval := 1000.
	allocInterval := 256 * 1024.
	maxDepth := 40.
	ringBytes := 1024 * 1024.
	running := false.
	frameCapacity := 1024.
	contextSamples := 0.
	samplerMicros := 0.
	cpuSampleCount := 0.
	frameTable := ProfileFrameTable new.
	lock := Semaphore forMutualExclusion
!
ringBytes: anInteger
	"Size the sample ring, tables included (only while stopped; takes effect at the next start)."
	self isRunning ifTrue: [^self error: 'Stop the profiler first'].
	ringBytes := anInteger.
	ring := nil
!
frameCapacity: anInteger
	self isRunning ifTrue: [^self error: 'Stop the profiler first'].
	frameCapacity := anInteger.
	frames := nil
!
interval: microseconds
	"Set the CPU sampling interval."
	interval := microseconds.
	self isRunning ifTrue: [Smalltalk vm samplerInterval: interval semaphoreIndex: cpuIndex]
!
allocationInterval: bytes
	allocInterval := bytes.
	self isRunning ifTrue: [Smalltalk vm allocationSamplingEvery: allocInterval semaphoreIndex: cpuIndex]
!
maxDepth: anInteger
	"Set how many frames (innermost first) a sample keeps (only while stopped)."
	self isRunning ifTrue: [^self error: 'Stop the profiler first'].
	maxDepth := anInteger min: 255.
	ring := nil
!
allocateBuffers
	ring isNil ifTrue: [ring := StackRing bytes: ringBytes depth: maxDepth. cpuCache := allocCache := nil].
	frames isNil ifTrue: [frames := Array new: frameCapacity. frameCount := 0].
	marks isNil ifTrue: [marks := Array new: 256. markCount := 0].
	statsTimes isNil ifTrue: [
		statsTimes := Array new: 256.
		statsValues := Array new: 256.
		statsCount := 0]
!
releaseBuffers
	"Drop all recorded data (done before a snapshot, so images stay small)."
	self isRunning ifTrue: [^self error: 'Stop the profiler first'].
	ring := frames := marks := statsTimes := statsValues := cpuCache := allocCache := nil.
	frameTable := ProfileFrameTable new
!
reset
	"Forget the recorded samples, frames, marks and statistics."
	ring isNil ifFalse: [ring reset].
	frameCount := markCount := statsCount := contextSamples := 0.
	cpuCache := allocCache := nil
! !

!Profiler methodsFor: 'control'!
start
	"Start sampling (idempotent)."
	self isRunning ifTrue: [^self].
	self allocateBuffers.
	idle := Processor idleProcess.
	(Delay timerProcess isNil or: [Delay timerProcess isTerminated]) ifTrue: [Delay startTimerEventLoop].
	cpuIndex := Smalltalk vm registerExternalSemaphore: Delay timingSemaphore.
	running := true.
	Delay sampleHook: [self takeSamples].
	startTime := Time microsecondClockValue.
	samplerMicros := 0.
	self checkpointStatistics.
	Smalltalk vm samplerInterval: interval semaphoreIndex: cpuIndex.
	Smalltalk vm allocationSamplingEvery: allocInterval semaphoreIndex: cpuIndex
!
stop
	"Stop sampling; the recorded data stay."
	self isRunning ifFalse: [^self].
	Smalltalk vm samplerInterval: 0 semaphoreIndex: 0.
	Smalltalk vm allocationSamplingEvery: 0 semaphoreIndex: 0.
	Delay sampleHook: nil.
	running := false.
	Smalltalk vm unregisterExternalSemaphore: cpuIndex.
	cpuIndex := nil
!
pause
	self stop
!
resume
	self start
!
isRunning
	^running == true
! !

!Profiler methodsFor: 'sampling'!
takeSamples
	"In the timer process, after each of its wakeups: record what the VM says is due (a CPU tick, allocation samples)."
	| t0 info |
	running ifFalse: [^self].
	t0 := Time microsecondClockValue.
	Smalltalk vm samplerTickTake ifTrue: [
		self recordCpuSample.
		(cpuSampleCount := cpuSampleCount + 1) \\ 64 = 0 ifTrue: [self checkpointStatistics]].
	[(info := Smalltalk vm allocationSampleTake) notNil] whileTrue: [self recordAllocationSample: info].
	samplerMicros := samplerMicros + (Time microsecondClockValue - t0)
!
recordCpuSample
	| p f |
	p := Processor preemptedProcess.
	f := 0.
	(p isNil or: [p suspendingList class ~~ LinkedList]) ifTrue: [
		"Not just preempted (nothing ran, or a higher-priority process held the CPU): count as idle."
		p := idle.
		f := 4].
	p == idle ifTrue: [f := f bitOr: 1].
	ring record: p flags: f
!
recordAllocationSample: info
	"Record the allocating process's stack. Samples of Contexts (the interpreter allocates one per activation; a JIT will not) are only counted, so the samples estimate the bytes of all other objects without bias."
	| p f |
	(info at: 1) == Context ifTrue: [^contextSamples := contextSamples + 1].
	p := Processor preemptedProcess.
	f := 0.
	(p isNil or: [p suspendingList class ~~ LinkedList]) ifTrue: [p := nil. f := 4].
	ring record: p flags: f class: (info at: 1) size: (info at: 2)
!
checkpointStatistics
	| i |
	i := statsCount \\ statsTimes size + 1.
	statsTimes at: i put: Time microsecondClockValue.
	statsValues at: i put: Smalltalk vm statistics.
	statsCount := statsCount + 1
! !

!Profiler methodsFor: 'frames and marks'!
recordFrame: aFrameRecord
	"Called by the compositor once per presented frame. Answer aFrameRecord, numbered and with the marks dropped since the previous frame."
	| previousEnd newMarks |
	frames isNil ifTrue: [self allocateBuffers].
	previousEnd := frameCount = 0
		ifTrue: [0]
		ifFalse: [(frames at: frameCount - 1 \\ frames size + 1) end].
	newMarks := self marksFrom: previousEnd + 1 to: aFrameRecord end.
	aFrameRecord setNumber: frameCount + 1 marks: newMarks.
	frames at: frameCount \\ frames size + 1 put: aFrameRecord.
	frameCount := frameCount + 1.
	^aFrameRecord
!
mark: aString
	"Drop a labelled marker into the timeline. Answer the ProfileMark."
	| mark |
	marks isNil ifTrue: [self allocateBuffers].
	mark := ProfileMark label: aString time: Time microsecondClockValue process: Processor activeProcess.
	marks at: markCount \\ marks size + 1 put: mark.
	markCount := markCount + 1.
	^mark
!
allFrames
	"Answer the FrameRecords still in the ring, oldest first."
	| n first |
	frames isNil ifTrue: [^#()].
	n := frameCount.
	first := n - frames size max: 0.
	^(first to: n - 1) asArray collect: [:k | frames at: k \\ frames size + 1]
!
allMarks
	| n first |
	marks isNil ifTrue: [^#()].
	n := markCount.
	first := n - marks size max: 0.
	^(first to: n - 1) asArray collect: [:k | marks at: k \\ marks size + 1]
!
marksFrom: startMicros to: stopMicros
	^(self allMarks select: [:m | m time between: startMicros and: stopMicros]) asArray
!
frameCount
	"Answer how many FrameRecords were recorded (the newest is numbered frameCount)."
	^frameCount ifNil: [0]
!
oldestFrameNumber
	"Answer the number of the oldest FrameRecord still in the ring."
	frames isNil ifTrue: [^self frameCount + 1].
	^(frameCount - frames size max: 0) + 1
!
framesAfter: aNumber
	"Answer the FrameRecords numbered above aNumber still in the ring, oldest first."
	| first |
	frames isNil ifTrue: [^#()].
	first := (frameCount - frames size max: 0) max: aNumber.
	^(first to: frameCount - 1) asArray collect: [:k | frames at: k \\ frames size + 1]
! !

!Profiler methodsFor: 'queries'!
last
	"Answer a Profile over everything still in the rings."
	^self from: nil to: nil
!
from: startMicros to: stopMicros
	"Answer a Profile of the samples, allocations, frames and marks between the two microsecond clock values (nil: unbounded)."
	^Profile new setProfiler: self from: startMicros to: stopMicros
!
cpuSamples
	"Answer a SampleSet of the decoded CPU samples still in the ring. Decoded samples are kept, so each call only decodes the samples recorded since the previous one."
	ring isNil ifTrue: [^SampleSet unit: #samples].
	^lock critical: [
		cpuCache := self update: cpuCache kind: #cpu weight: nil.
		SampleSet unit: #samples samples: cpuCache value copy]
!
allocationSamples
	ring isNil ifTrue: [^SampleSet unit: #bytes].
	^lock critical: [
		allocCache := self update: allocCache kind: #allocation weight: allocInterval.
		SampleSet unit: #bytes samples: allocCache value copy]
!
update: aCache kind: aSymbol weight: anIntegerOrNil
	"aCache is nil or {cursor} -> OrderedCollection of decoded samples of aSymbol, oldest first. Drop the ones no longer in the ring, decode the new ones, answer the cache."
	| samples cursor |
	cursor := aCache isNil ifTrue: [nil] ifFalse: [aCache key].
	(cursor isNil or: [(self isCurrent: cursor) not])
		ifTrue: [samples := OrderedCollection new. cursor := nil]
		ifFalse: [samples := aCache value].
	cursor := self samplesFrom: cursor kind: aSymbol weight: anIntegerOrNil do: [:s | samples add: s].
	[samples notEmpty and: [(ring isValidSerial: samples first serial) not]] whileTrue: [samples removeFirst].
	^cursor -> samples
!
samplesFrom: aCursor kind: aSymbol weight: anIntegerOrNil do: aBlock
	"Decode the samples of aSymbol (#cpu or #allocation) recorded since aCursor (nil: all in the ring), weighing anIntegerOrNil each, oldest first, into aBlock. Answer the cursor to continue from (see isCurrent:)."
	| current last |
	ring isNil ifTrue: [^nil].
	current := aCursor notNil and: [self isCurrent: aCursor].
	last := ring
		recordsFrom: (current ifTrue: [aCursor at: 3] ifFalse: [0])
		at: (current ifTrue: [aCursor at: 4] ifFalse: [nil])
		kind: aSymbol frames: frameTable do: [:s |
			anIntegerOrNil isNil ifFalse: [s weight: anIntegerOrNil].
			aBlock value: s].
	last isNil ifTrue: [last := current ifTrue: [Array with: (aCursor at: 3) with: (aCursor at: 4)] ifFalse: [Array with: -1 with: nil]].
	^Array with: ring with: ring epoch with: last first with: last last
!
samplesSince: aCursor kind: aSymbol into: aCollection
	"Add the samples of aSymbol recorded since aCursor (nil: all in the ring) to aCollection, oldest first (allocation samples weigh the sampling interval). Answer the cursor to continue from. For readers that keep their own decoded samples (ProfileAggregate)."
	ring isNil ifTrue: [^nil].
	^lock critical: [
		self samplesFrom: aCursor kind: aSymbol weight: (aSymbol == #cpu ifTrue: [nil] ifFalse: [allocInterval])
			do: [:s | aCollection add: s]]
!
isCurrent: aCursor
	"Answer whether aCursor (from samplesFrom:kind:weight:do:) still continues my ring (not reset or replaced since)."
	^aCursor notNil and: [(aCursor at: 1) == ring and: [(aCursor at: 2) = ring epoch and: [(aCursor at: 3) < ring count]]]
!
isValidSerial: anInteger
	"Answer whether the sample with serial anInteger is still in the ring."
	^ring notNil and: [ring isValidSerial: anInteger]
!
statisticsAt: microseconds
	"Answer {µs. VMStatistics}, the VM statistics checkpoint taken last at or before microseconds, or the oldest one."
	| n first best |
	statsTimes isNil ifTrue: [^nil].
	n := statsCount.
	first := n - statsTimes size max: 0.
	first to: n - 1 do: [:k | | i |
		i := k \\ statsTimes size + 1.
		(best isNil or: [(statsTimes at: i) <= microseconds]) ifTrue: [best := i]].
	^best isNil ifTrue: [nil] ifFalse: [Array with: (statsTimes at: best) with: (statsValues at: best)]
! !

!Profiler methodsFor: 'accessing'!
buffer
	"The StackRing."
	^ring
!
interval
	^interval
!
allocationInterval
	^allocInterval
!
contextSamples
	"Answer how many allocation samples hit a Context (counted, not recorded)."
	^contextSamples
!
maxDepth
	^maxDepth
!
samplerProcess
	"Samples are taken in the timer process."
	^Delay timerProcess
!
allocationSamplerProcess
	^Delay timerProcess
!
idleProcess
	^idle
!
startTime
	^startTime
!
byteSize
	"Answer the bytes of the preallocated sample ring and its tables."
	^ring isNil ifTrue: [0] ifFalse: [ring byteSize]
!
coverageMicroseconds
	"Answer how much time the samples in the ring span."
	(ring isNil or: [ring oldestTime isNil]) ifTrue: [^0].
	^ring newestTime - ring oldestTime
!
samplerMicroseconds
	"Answer the time spent recording samples since start."
	^samplerMicros
!
overhead
	"Answer the fraction of wall time spent recording samples since start."
	| elapsed |
	startTime isNil ifTrue: [^0].
	elapsed := Time microsecondClockValue - startTime.
	^elapsed = 0 ifTrue: [0] ifFalse: [self samplerMicroseconds asFloat / elapsed]
! !

!Profiler methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Profiler('.
	aStream nextPutAll: (self isRunning ifTrue: ['running'] ifFalse: ['stopped']).
	ring isNil ifFalse: [aStream nextPutAll: ', '; print: ring].
	aStream nextPut: $)
! !

!Profiler class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self.
	Smalltalk addToShutDownList: self
!
startUp: resuming
	self default start
!
shutDown: quitting
	Default isNil ifFalse: [
		Default stop.
		Default releaseBuffers]
! !

!Profiler class methodsFor: 'accessing'!
default
	^Default ifNil: [Default := self new]
!
default: aProfiler
	"Install aProfiler as the system profiler (answer the previous one); tests use this."
	| old |
	old := Default.
	Default := aProfiler.
	^old
! !

!Profiler class methodsFor: 'queries'!
last
	"Answer a Profile over everything still in the rings."
	^self default last
!
from: startMicros to: stopMicros
	^self default from: startMicros to: stopMicros
!
buffer
	^self default buffer
!
mark: aString
	^self default mark: aString
!
recordFrame: aFrameRecord
	^self default recordFrame: aFrameRecord
!
pause
	self default stop
!
resume
	self default start
!
overhead
	^self default overhead
! !

!Profiler class methodsFor: 'labels'!
labelFor: aProcess
	"Answer the name tools show for aProcess: its window's title if it has one, else its name."
	| window |
	aProcess isNil ifTrue: [^'unknown'].
	window := aProcess window.
	(window notNil and: [window respondsTo: #title]) ifTrue: [^window title asString].
	^aProcess name
!
printBytes: anInteger
	anInteger >= (1024 * 1024) ifTrue: [^(anInteger / 1048576.0 printShowingDecimalPlaces: 1), ' MB'].
	anInteger >= 1024 ifTrue: [^(anInteger // 1024) printString, ' KB'].
	^anInteger printString, ' B'
!
printMicros: anInteger
	anInteger >= 1000000 ifTrue: [^(anInteger / 1000000.0 printShowingDecimalPlaces: 2), ' s'].
	anInteger >= 100000 ifTrue: [^(anInteger // 1000) printString, ' ms'].
	^(anInteger / 1000.0 printShowingDecimalPlaces: 1), ' ms'
! !
