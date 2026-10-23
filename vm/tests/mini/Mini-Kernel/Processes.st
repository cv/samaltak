Object subclass: #Link
	instanceVariableNames: 'nextLink'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Link subclass: #Process
	instanceVariableNames: 'suspendedContext priority myList name cpuTime extra'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #LinkedList
	instanceVariableNames: 'firstLink lastLink'
	classVariableNames: ''
	package: 'Mini-Kernel'!

LinkedList subclass: #Semaphore
	instanceVariableNames: 'excessSignals'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #ProcessorScheduler
	instanceVariableNames: 'quiescentProcessLists activeProcess'
	classVariableNames: ''
	package: 'Mini-Kernel'!

!Process methodsFor: 'scheduling'!
setContext: aContext priority: p
	suspendedContext := aContext.
	priority := p.
	cpuTime := 0
!
priority
	^priority
!
priority: p
	priority := p
!
name
	^name
!
name: aString
	name := aString
!
cpuTime
	^cpuTime
!
cpuMicroseconds
	<primitive: 'processCpuTime'>
	^nil
!
suspendedContext
	^suspendedContext
!
resume
	<primitive: 'processResume'>
	^self error: 'resume failed'
!
suspend
	<primitive: 'processSuspend'>
	^nil
!
terminate
	self == Processor activeProcess ifTrue: [^self suspend].
	myList == nil ifFalse: [self suspend].
	suspendedContext := nil
! !

!LinkedList methodsFor: 'accessing'!
isEmpty
	^firstLink == nil
! !

!Semaphore methodsFor: 'synchronization'!
signal
	<primitive: 'semaphoreSignal'>
!
wait
	<primitive: 'semaphoreWait'>
!
excessSignals
	^excessSignals
! !

!Semaphore class methodsFor: 'instances'!
new
	^self basicNew initSignals
! !

!Semaphore methodsFor: 'private'!
initSignals
	excessSignals := 0
! !

!ProcessorScheduler methodsFor: 'scheduling'!
activeProcess
	^activeProcess
!
yield
	<primitive: 'processorYield'>
!
lastPreempted
	<primitive: 'processorLastPreempted'>
!
relinquish: us
	<primitive: 'processorRelinquish'>
!
terminateActive
	activeProcess suspend
!
signal: aSemaphore atMilliseconds: ms
	<primitive: 'signalAtMilliseconds'>
!
sleep: ms
	| s |
	s := Semaphore new.
	self signal: s atMilliseconds: Smalltalk millisecondClock + ms.
	s wait
! !
