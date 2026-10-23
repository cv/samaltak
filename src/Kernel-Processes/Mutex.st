Object subclass: #Mutex
	instanceVariableNames: 'semaphore owner'
	classVariableNames: ''
	package: 'Kernel-Processes'!

Mutex comment: 'I am a reentrant lock: the process that owns me may enter critical: again without blocking.'!

!Mutex methodsFor: 'initialization'!
initialize
	semaphore := Semaphore forMutualExclusion
! !

!Mutex methodsFor: 'mutual exclusion'!
critical: aBlock
	"Evaluate aBlock while owning the receiver."
	| active |
	active := Processor activeProcess.
	owner == active ifTrue: [^aBlock value].
	^semaphore critical: [
		owner := active.
		[aBlock value] ensure: [owner := nil]]
! !

!Mutex methodsFor: 'accessing'!
owner
	^owner
!
isOwned
	^owner notNil
! !
