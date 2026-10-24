Object subclass: #SystemMonitorData
	instanceVariableNames: 'samples serial count lastCounters lastCpu lastTime edenFill span totals totalsFrom named'
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorData comment: 'I am what the System Monitor samples: a ring of the last few minutes of SystemMonitorSamples, taken by sample from Smalltalk vm statistics (VMStatistics) and the Processes'' cpuMicroseconds (as the Process Browser computes CPU shares). Samples are numbered (serial); sampleAt: answers one by number while it is in the ring.

For the CPU chart I keep each Process''s CPU over the shown span (span:), updated as samples come and leave, and the few busiest of them that the chart names (named, by slot; a Process keeps its slot while it stays among the busiest).

The VM does not report eden''s fill, only its size and the bytes allocated (counting eden''s content as allocated): I estimate it from the bytes allocated since a scavenge I make when I start, taking eden as full at each GC.

	SystemMonitorData new start; sample; yourself'!

!SystemMonitorData methodsFor: 'initialization'!
initialize
	super initialize.
	samples := Array new: self class capacity.
	serial := 0.
	count := 0.
	span := 60000000.
	totals := IdentityDictionary new.
	totalsFrom := 1.
	named := Array new: self class namedCount
!
start
	"Take the baseline, after a scavenge that empties eden (the start of the eden estimate)."
	| free |
	free := Smalltalk vm scavenge.
	lastCounters := Smalltalk vm statistics counters.
	edenFill := ((lastCounters at: 7) - free) max: 0.
	lastCpu := self cpuNow.
	lastTime := Time microsecondClockValue
! !

!SystemMonitorData methodsFor: 'sampling'!
sample
	"Take a sample of what happened since the previous one; answer it."
	| cpu now counters pairs idleProcess idle sum s delta |
	lastCounters isNil ifTrue: [self start].
	cpu := self cpuNow.
	counters := Smalltalk vm statistics counters.
	now := Time microsecondClockValue.
	idleProcess := Processor idleProcess.
	pairs := OrderedCollection new.
	idle := 0.
	sum := 0.
	cpu keysAndValuesDo: [:p :us |
		delta := us - (lastCpu at: p ifAbsent: [0]).
		delta > 0 ifTrue: [
			p == idleProcess
				ifTrue: [idle := delta]
				ifFalse: [pairs add: p; add: delta. sum := sum + delta]]].
	s := SystemMonitorSample new.
	s setTime: now interval: now - lastTime.
	delta := [:i | (counters at: i) - (lastCounters at: i)].
	s setAllocated: (delta value: 8) scavenges: (delta value: 1) micros: (delta value: 3) fullGCs: (delta value: 2) micros: (delta value: 4).
	edenFill := self edenFillAfter: s size: (counters at: 7).
	s setOld: (counters at: 5) budget: (counters at: 6) edenSize: (counters at: 7) fill: edenFill.
	s setCpu: pairs asArray idle: idle unaccounted: (now - lastTime - idle - sum max: 0).
	lastCounters := counters.
	lastCpu := cpu.
	lastTime := now.
	self add: s.
	^s
!
cpuNow
	"Process -> cpuMicroseconds of every live Process."
	| d |
	d := IdentityDictionary new.
	Processor allProcesses do: [:p | d at: p put: p cpuMicroseconds].
	^d
!
edenFillAfter: aSample size: edenSize
	"The previous fill plus what was allocated, less a full eden for each GC (one empties it)."
	^((edenFill + aSample allocated - (aSample gcCount * edenSize)) max: 0) min: edenSize
! !

!SystemMonitorData methodsFor: 'ring'!
add: aSample
	count = samples size ifTrue: [self forget: self firstSerial].
	serial := serial + 1.
	count := count + 1 min: samples size.
	samples at: serial - 1 \\ samples size + 1 put: aSample.
	aSample processesDo: [:p :us | totals at: p put: (totals at: p ifAbsent: [0]) + us].
	[totalsFrom <= serial and: [(self sampleAt: totalsFrom) time <= (aSample time - span)]]
		whileTrue: [self forget: totalsFrom]
!
forget: aSerial
	"The sample aSerial leaves the span (or the ring)."
	aSerial < totalsFrom ifTrue: [^self].
	(self sampleAt: aSerial) processesDo: [:p :us | | t |
		t := (totals at: p ifAbsent: [0]) - us.
		t > 0 ifTrue: [totals at: p put: t] ifFalse: [totals removeKey: p ifAbsent: [nil]]].
	totalsFrom := aSerial + 1
!
size
	^count
!
isEmpty
	^count = 0
!
serial
	"The number of the newest sample."
	^serial
!
firstSerial
	^serial - count + 1
!
sampleAt: aSerial
	^samples at: aSerial - 1 \\ samples size + 1
!
last
	^count = 0 ifTrue: [nil] ifFalse: [self sampleAt: serial]
!
serialAtOrAfter: aTime
	"The first sample at or after aTime µs (serial + 1 if none): the one whose interval holds aTime, if any."
	| lo hi mid |
	lo := self firstSerial.
	hi := serial + 1.
	[lo < hi] whileTrue: [
		mid := lo + hi // 2.
		(self sampleAt: mid) time < aTime ifTrue: [lo := mid + 1] ifFalse: [hi := mid]].
	^lo
!
sampleCovering: aTime
	"The sample whose interval holds aTime µs, or nil."
	| i s |
	i := self serialAtOrAfter: aTime.
	i > serial ifTrue: [^nil].
	s := self sampleAt: i.
	^s start <= aTime ifTrue: [s] ifFalse: [nil]
!
from: t0 to: t1 do: aBlock
	"aBlock value: aSample value: µs of its interval within t0 .. t1, for the samples overlapping it, oldest first."
	| i s |
	i := self serialAtOrAfter: t0.
	[i <= serial and: [(s := self sampleAt: i) start < t1]] whileTrue: [ | o |
		o := (s time min: t1) - (s start max: t0).
		o > 0 ifTrue: [aBlock value: s value: o].
		i := i + 1]
! !

!SystemMonitorData methodsFor: 'processes'!
span
	^span
!
span: microseconds
	"Rank the Processes by their CPU over the last microseconds."
	span = microseconds ifTrue: [^self].
	span := microseconds.
	totals := IdentityDictionary new.
	totalsFrom := count = 0 ifTrue: [serial + 1] ifFalse: [self serialAtOrAfter: self last time - span + 1].
	totalsFrom to: serial do: [:i |
		(self sampleAt: i) processesDo: [:p :us | totals at: p put: (totals at: p ifAbsent: [0]) + us]]
!
totals
	"Process -> CPU µs over the span."
	^totals
!
named
	"The named Processes by slot (nil: a free slot)."
	^named
!
updateNamed
	"Fill free slots with the busiest Processes over the span; one that is not named takes the slot of the least busy named one when it is busier by 10% and 2% of the busiest, so slots neither flicker nor swap. Answer whether they changed."
	| old ranked margin rank |
	old := named copy.
	rank := [:p | p isNil ifTrue: [-1] ifFalse: [totals at: p ifAbsent: [0]]].
	1 to: named size do: [:i | ((named at: i) notNil and: [(rank value: (named at: i)) <= 0]) ifTrue: [named at: i put: nil]].
	ranked := (totals keys asArray reject: [:p | named includes: p]) sort: [:a :b | (rank value: a) > (rank value: b)].
	margin := (totals inject: 0 into: [:m :us | m max: us]) * 0.02.
	ranked do: [:p | | free weakest |
		free := named indexOf: nil.
		free > 0
			ifTrue: [named at: free put: p]
			ifFalse: [
				weakest := (1 to: named size) inject: 1 into: [:m :i | (rank value: (named at: i)) < (rank value: (named at: m)) ifTrue: [i] ifFalse: [m]].
				(rank value: p) > ((rank value: (named at: weakest)) * 1.1 + margin) ifTrue: [named at: weakest put: p]]].
	^named ~= old
!
slotOf: aProcess
	^named indexOf: aProcess
! !

!SystemMonitorData class methodsFor: 'constants'!
capacity
	"Five minutes at 10 Hz, and room for late samples."
	^3200
!
interval
	"Milliseconds between samples."
	^100
!
namedCount
	^4
! !
