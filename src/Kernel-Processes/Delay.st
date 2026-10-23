Object subclass: #Delay
	instanceVariableNames: 'delayDuration resumptionTime delaySemaphore'
	classVariableNames: 'AccessProtect PendingRequests SampleHook SavedDelays SliceDue SliceMilliseconds SuspendedDelays TimerProcess TimingSemaphore'
	package: 'Kernel-Processes'!

Delay comment: 'I suspend the active process for delayDuration milliseconds: (Delay forMilliseconds: 100) wait.

Waiting delays are kept, sorted by resumptionTime (millisecond clock), in SuspendedDelays, which only the timer process (''timer interrupt watcher'', priority 80) touches; it also time-slices (timeSliceMilliseconds:) and runs the profiler''s sampleHook after each wakeup. A waiting process queues a request (under AccessProtect) and signals TimingSemaphore; the timer process applies the requests, signals the delays that are due, and asks the VM (primitive signalAtMilliseconds) to signal TimingSemaphore when the next one is due. Across snapshots the remaining times are saved and the timer is re-armed (shutDown / startUp).'!

!Delay methodsFor: 'initialization'!
setDelay: milliseconds
	delayDuration := milliseconds
! !

!Delay methodsFor: 'accessing'!
delayDuration
	^delayDuration
!
resumptionTime
	^resumptionTime
!
resumptionTime: anInteger
	resumptionTime := anInteger
! !

!Delay methodsFor: 'delaying'!
wait
	"Suspend the active process for my duration."
	delaySemaphore := Semaphore new.
	resumptionTime := Time millisecondClockValue + delayDuration.
	self schedule.
	[delaySemaphore wait] ifCurtailed: [self unschedule]
! !

!Delay methodsFor: 'signalling'!
signal: anObject
	"Without waiting: send anObject #signal from the timer process when my duration has passed (a Semaphore, or any object answering signal, which must be quick and must not wait). cancel prevents it."
	delaySemaphore := anObject.
	resumptionTime := Time millisecondClockValue + delayDuration.
	self schedule
!
cancel
	resumptionTime isNil ifFalse: [self unschedule]
! !

!Delay methodsFor: 'testing'!
isExpired
	^resumptionTime notNil and: [Time millisecondClockValue >= resumptionTime]
! !

!Delay methodsFor: 'private'!
schedule
	self class request: #schedule for: self
!
unschedule
	self class request: #unschedule for: self
!
signalWaitingProcess
	"The timer process found me due."
	[delaySemaphore signal] on: Error do: [:e | e return: nil]
! !

!Delay methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Delay('; print: delayDuration; nextPutAll: ' ms)'
! !

!Delay class methodsFor: 'instance creation'!
forMilliseconds: milliseconds
	^self new setDelay: milliseconds rounded
!
forSeconds: seconds
	^self forMilliseconds: seconds * 1000
!
forDuration: milliseconds
	^self forMilliseconds: milliseconds
! !

!Delay class methodsFor: 'class initialization'!
initialize
	AccessProtect := Semaphore forMutualExclusion.
	PendingRequests := OrderedCollection new.
	SuspendedDelays := SortedCollection sortBlock: [:a :b | a resumptionTime <= b resumptionTime].
	TimingSemaphore := Semaphore new
! !

!Delay class methodsFor: 'timer process'!
startTimerEventLoop
	"Start (or restart) the timer process."
	TimerProcess isNil ifFalse: [TimerProcess terminate].
	TimerProcess := [[true] whileTrue: [
		TimingSemaphore wait.
		self handleTimerEvent.
		SampleHook isNil ifFalse: [SampleHook value]]] newProcess.
	TimerProcess priority: Processor timingPriority; name: 'timer interrupt watcher'.
	TimerProcess resume
!
timeSliceMilliseconds: anIntegerOrNil
	"Also wake the timer process at least every anIntegerOrNil ms (nil: only for delays). Each wakeup preempts the running process to the back of its run queue, so processes of equal priority take turns: the timer process is the time slicer too."
	SliceMilliseconds := anIntegerOrNil.
	TimingSemaphore signal
!
timeSliceMilliseconds
	^SliceMilliseconds
!
timingSemaphore
	"The Semaphore my process waits on (the VM's timer semaphore). The profiler has the VM signal it for sampler ticks too."
	^TimingSemaphore
!
sampleHook: aBlockOrNil
	"A block my process evaluates after each wakeup (the profiler records its samples there: sampling is timer-interrupt-driven). It must be quick and must not wait."
	SampleHook := aBlockOrNil
!
sampleHook
	^SampleHook
!
timerProcess
	^TimerProcess
!
request: aSymbol for: aDelay
	AccessProtect critical: [PendingRequests addLast: aSymbol -> aDelay].
	TimingSemaphore signal
!
handleTimerEvent
	"Run in the timer process: apply pending requests, signal due delays, re-arm the VM timer (for the next delay, or the next time slice if sooner)."
	| requests now next |
	requests := PendingRequests isEmpty ifTrue: [#()] ifFalse: [
		AccessProtect critical: [
			| r |
			r := PendingRequests.
			PendingRequests := OrderedCollection new.
			r]].
	requests do: [:request |
		request key == #schedule
			ifTrue: [SuspendedDelays add: request value]
			ifFalse: [SuspendedDelays remove: request value ifAbsent: []]].
	now := Time millisecondClockValue.
	[SuspendedDelays notEmpty and: [SuspendedDelays first resumptionTime <= now]]
		whileTrue: [SuspendedDelays removeFirst signalWaitingProcess].
	next := SuspendedDelays isEmpty ifTrue: [nil] ifFalse: [SuspendedDelays first resumptionTime].
	SliceMilliseconds isNil ifFalse: [
		"The slice deadline only moves when it is reached (other wakeups, e.g. sampler ticks, must not postpone it)."
		(SliceDue isNil or: [now >= SliceDue or: [SliceDue - now > SliceMilliseconds]]) ifTrue: [SliceDue := now + SliceMilliseconds].
		next := next isNil ifTrue: [SliceDue] ifFalse: [next min: SliceDue]].
	next isNil ifFalse: [self primSignal: TimingSemaphore atMilliseconds: next]
!
primSignal: aSemaphore atMilliseconds: millisecondClockValue
	"Ask the VM to signal aSemaphore when the millisecond clock reaches millisecondClockValue (nil cancels)."
	<primitive: 'signalAtMilliseconds'>
	^self primitiveFailed
! !

!Delay class methodsFor: 'snapshots'!
shutDown
	"Before a snapshot: set the waiting delays aside with relative resumption times, since the millisecond clock restarts."
	| now |
	self primSignal: nil atMilliseconds: 0.
	now := Time millisecondClockValue.
	SavedDelays := SuspendedDelays asArray.
	SavedDelays do: [:d | d resumptionTime: d resumptionTime - now].
	SuspendedDelays := SortedCollection sortBlock: [:a :b | a resumptionTime <= b resumptionTime]
!
startUp
	"After a snapshot was written or resumed: put the waiting delays back with absolute times and re-arm the timer."
	| now |
	SavedDelays isNil ifTrue: [^self].
	now := Time millisecondClockValue.
	SavedDelays do: [:d |
		d resumptionTime: d resumptionTime + now.
		SuspendedDelays add: d].
	SavedDelays := nil.
	TimingSemaphore signal
! !
