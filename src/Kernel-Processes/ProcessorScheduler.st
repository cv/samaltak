Object subclass: #ProcessorScheduler
	instanceVariableNames: 'quiescentProcessLists activeProcess'
	classVariableNames: 'IdleProcess TimeSliceMilliseconds'
	package: 'Kernel-Processes'!

ProcessorScheduler comment: 'I am Processor, the scheduler of Processes. quiescentProcessLists holds one run queue (LinkedList) per priority 1..80; the VM always runs the first process of the highest non-empty queue and keeps the running one in activeProcess. A process that becomes runnable at a higher priority preempts the active one, which goes to the back of its queue; the timer process (highest priority, woken at least every few milliseconds) uses this so that processes of equal priority take turns. The idle process (priority 1) sleeps in the VM when nothing else can run. My field order is fixed by the VM.'!

!ProcessorScheduler methodsFor: 'accessing'!
activeProcess
	^activeProcess
!
activePriority
	^activeProcess priority
!
quiescentProcessLists
	^quiescentProcessLists
!
highestPriority
	^quiescentProcessLists size
!
readyProcesses
	"Answer the runnable processes, highest priority first."
	| result |
	result := OrderedCollection new.
	quiescentProcessLists reverseDo: [:list | list do: [:p | result add: p]].
	^result asArray
!
allProcesses
	"Answer every process that has not terminated."
	^Process allLive
!
preemptedProcess
	"Answer the process most recently preempted by a higher-priority one."
	<primitive: 'processorLastPreempted'>
	^nil
!
idleProcess
	^IdleProcess
!
timeSlicer
	"The process that time-slices: the timer process."
	^Delay timerProcess
! !

!ProcessorScheduler methodsFor: 'priority names'!
lowestPriority
	^1
!
systemBackgroundPriority
	^20
!
userBackgroundPriority
	^30
!
userSchedulingPriority
	^40
!
userInterruptPriority
	^50
!
lowIOPriority
	^60
!
highIOPriority
	^70
!
timingPriority
	^80
! !

!ProcessorScheduler methodsFor: 'process state change'!
yield
	"Let the other runnable processes of the active priority run first."
	<primitive: 'processorYield'>
	^self primitiveFailed
!
suspendFirstAt: aPriority
	"Suspend the first runnable process at aPriority and answer it (or nil)."
	| list |
	list := quiescentProcessLists at: aPriority.
	list isEmpty ifTrue: [^nil].
	^list first suspend; yourself
!
terminateActive
	"Terminate the active process (after running its unwind blocks)."
	activeProcess terminate
!
anyProcessesAbove: aPriority
	aPriority + 1 to: quiescentProcessLists size do: [:p |
		(quiescentProcessLists at: p) isEmpty ifFalse: [^true]].
	^false
!
nextReadyProcess
	quiescentProcessLists reverseDo: [:list | list isEmpty ifFalse: [^list first]].
	^nil
!
relinquishProcessorForMicroseconds: anInteger
	"Sleep in the VM until an event, socket activity or timer is due, at most anInteger microseconds. Only the idle process does this."
	<primitive: 'processorRelinquish'>
	^self
! !

!ProcessorScheduler methodsFor: 'background processes'!
startIdleProcess
	"Start the priority-1 process that sleeps when nothing else runs."
	(IdleProcess notNil and: [IdleProcess isTerminated not]) ifTrue: [^IdleProcess].
	IdleProcess := [[true] whileTrue: [self relinquishProcessorForMicroseconds: 20000]] newProcess.
	IdleProcess priority: self lowestPriority; name: 'idle'.
	^IdleProcess resume
!
startTimeSlicer
	"Time slicing: the timer process (Delay) wakes every few milliseconds; each wakeup sends the interrupted process to the back of its run queue, so equal-priority processes take turns."
	TimeSliceMilliseconds isNil ifTrue: [TimeSliceMilliseconds := 10].
	Delay timeSliceMilliseconds: TimeSliceMilliseconds.
	^self timeSlicer
!
stopTimeSlicer
	Delay timeSliceMilliseconds: nil
!
timeSliceMilliseconds: anInteger
	TimeSliceMilliseconds := anInteger.
	Delay timeSliceMilliseconds isNil ifFalse: [Delay timeSliceMilliseconds: anInteger]
! !

!ProcessorScheduler methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'Processor'
! !

!ProcessorScheduler class methodsFor: 'instance creation'!
new
	^self error: 'There is only one Processor'
! !
