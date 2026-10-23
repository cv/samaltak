LinkedList subclass: #Semaphore
	instanceVariableNames: 'excessSignals'
	classVariableNames: ''
	package: 'Kernel-Processes'!

Semaphore comment: 'I synchronize processes. wait blocks the active process (it joins my list) unless excessSignals > 0; signal resumes the first waiting process or counts the signal. My field order (firstLink lastLink excessSignals) is fixed by the VM; signal and wait are primitives.'!

!Semaphore methodsFor: 'initialization'!
initialize
	excessSignals := 0
! !

!Semaphore methodsFor: 'communication'!
signal
	"Resume the first waiting process, or remember the signal."
	<primitive: 'semaphoreSignal'>
	^self primitiveFailed
!
wait
	"Block the active process until I am signaled."
	<primitive: 'semaphoreWait'>
	^self primitiveFailed
!
waitTimeoutMSecs: milliseconds
	"Wait at most milliseconds. Answer true if the time ran out, false if I was signaled."
	| waiter done timedOut watchdog |
	milliseconds <= 0 ifTrue: [
		excessSignals > 0 ifTrue: [self wait. ^false].
		^true].
	waiter := Processor activeProcess.
	done := false.
	timedOut := false.
	watchdog := [
		(Delay forMilliseconds: milliseconds) wait.
		[done or: [waiter suspendingList == self]] whileFalse: [(Delay forMilliseconds: 1) wait].
		done ifFalse: [
			timedOut := true.
			waiter suspend; resume]] newProcess.
	watchdog priority: (Processor activePriority + 1 min: Processor timingPriority); name: 'timeout'.
	watchdog resume.
	self wait.
	done := true.
	timedOut ifFalse: [watchdog terminate].
	^timedOut
!
waitTimeoutSeconds: seconds
	^self waitTimeoutMSecs: seconds * 1000
!
waitIfLocked: aBlock
	excessSignals > 0 ifFalse: [^aBlock value].
	self wait
! !

!Semaphore methodsFor: 'mutual exclusion'!
critical: mutuallyExcludedBlock
	"Evaluate mutuallyExcludedBlock while holding me (a Semaphore created forMutualExclusion)."
	| caught |
	caught := false.
	^[
		self wait.
		caught := true.
		mutuallyExcludedBlock value]
			ensure: [caught ifTrue: [self signal]]
!
critical: mutuallyExcludedBlock ifLocked: alternativeBlock
	excessSignals > 0 ifFalse: [^alternativeBlock value].
	^self critical: mutuallyExcludedBlock
! !

!Semaphore methodsFor: 'accessing'!
excessSignals
	^excessSignals
!
isSignaled
	^excessSignals > 0
!
initSignals
	excessSignals := 0
!
consumeAllSignals
	excessSignals := 0
! !

!Semaphore methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Semaphore('; print: excessSignals; nextPutAll: ' signals, '; print: self size; nextPutAll: ' waiting)'
! !

!Semaphore class methodsFor: 'instance creation'!
forMutualExclusion
	"Answer a Semaphore with one signal, for critical:."
	^self new signal; yourself
! !
