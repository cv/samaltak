Object subclass: #SystemMonitorSample
	instanceVariableNames: 'time interval oldUsed oldBudget edenSize edenFill allocated scavenges scavengeMicros fullGCs fullGCMicros cpu idle unaccounted'
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorSample comment: 'I am one sample of the System Monitor: the interval (µs) ending at time, the heap gauges at time (old space in use and its budget, eden''s size and estimated fill), what happened in the interval (bytes allocated, scavenges and full GCs with their pauses) and the CPU the Processes used in it (cpu: Process, µs pairs of those that ran, the idle Process aside; unaccounted: the µs of Processes that ended; idle: the rest).'!

!SystemMonitorSample methodsFor: 'accessing'!
time
	^time
!
interval
	^interval
!
start
	^time - interval
!
oldUsed
	^oldUsed
!
oldBudget
	^oldBudget
!
edenSize
	^edenSize
!
edenFill
	"Estimated (SystemMonitorData>>edenFillAfter:)."
	^edenFill
!
allocated
	^allocated
!
scavenges
	^scavenges
!
scavengeMicros
	^scavengeMicros
!
fullGCs
	^fullGCs
!
fullGCMicros
	^fullGCMicros
!
cpu
	"Process, µs pairs, flat."
	^cpu
!
idle
	^idle
!
unaccounted
	^unaccounted
! !

!SystemMonitorSample methodsFor: 'derived'!
allocationRate
	"Bytes per second."
	^allocated * 1000000.0 / (interval max: 1)
!
gcCount
	^scavenges + fullGCs
!
gcMicros
	^scavengeMicros + fullGCMicros
!
timeFor: aProcess
	1 to: cpu size by: 2 do: [:i | (cpu at: i) == aProcess ifTrue: [^cpu at: i + 1]].
	^0
!
processesDo: aBlock
	"aBlock value: aProcess value: µs, for each Process that ran."
	1 to: cpu size by: 2 do: [:i | aBlock value: (cpu at: i) value: (cpu at: i + 1)]
!
busy
	"The µs the VM ran Smalltalk (not idle)."
	^interval - idle max: 0
!
vmShare
	"0..1"
	^(self busy / (interval max: 1)) asFloat min: 1.0
! !

!SystemMonitorSample methodsFor: 'private'!
setTime: t interval: dt
	time := t.
	interval := dt
!
setOld: used budget: budget edenSize: size fill: fill
	oldUsed := used.
	oldBudget := budget.
	edenSize := size.
	edenFill := fill
!
setAllocated: bytes scavenges: n micros: us fullGCs: m micros: fullUs
	allocated := bytes.
	scavenges := n.
	scavengeMicros := us.
	fullGCs := m.
	fullGCMicros := fullUs
!
setCpu: pairs idle: idleMicros unaccounted: rest
	cpu := pairs.
	idle := idleMicros.
	unaccounted := rest
! !
