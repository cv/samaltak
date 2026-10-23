Link subclass: #Process
	instanceVariableNames: 'suspendedContext priority myList name cpuTime window errorHandler terminated'
	classVariableNames: 'Registry RegistryMutex'
	package: 'Kernel-Processes'!

Process comment: 'I am a green thread: a chain of Contexts (suspendedContext, while I am not running) scheduled by the ProcessorScheduler at my priority (1..80). myList is the LinkedList I wait in: a run queue of the scheduler or a Semaphore; nil while I am running or suspended. cpuTime counts the microseconds I ran (maintained by the VM). The first six fields are fixed by the VM; window and errorHandler belong to the UI (a window''s process, a per-process unhandled error handler).'!

!Process methodsFor: 'accessing'!
suspendedContext
	^suspendedContext
!
suspendedContext: aContext
	suspendedContext := aContext
!
priority
	^priority
!
priority: anInteger
	"Set my priority; a runnable process moves to the run queue of the new priority."
	| wasRunnable |
	(anInteger between: Processor lowestPriority and: Processor highestPriority)
		ifFalse: [^self error: 'Invalid priority: ', anInteger printString].
	wasRunnable := self isRunnable.
	wasRunnable ifTrue: [self primSuspend].
	priority := anInteger.
	wasRunnable ifTrue: [self primResume]
!
suspendingList
	"Answer the run queue or Semaphore I am waiting in, or nil."
	^myList
!
name
	^name ifNil: ['a Process']
!
name: aString
	name := aString
!
cpuTime
	"Answer the microseconds I have run so far."
	^cpuTime ifNil: [0]
!
window
	^window
!
window: aWindow
	window := aWindow
!
errorHandler
	"Answer a one-argument block that handles my unhandled errors, or nil for the system default."
	^errorHandler
!
errorHandler: aBlock
	errorHandler := aBlock
!
stack
	"Answer my contexts, innermost first."
	| top |
	top := self isActiveProcess ifTrue: [thisContext sender] ifFalse: [suspendedContext].
	^top isNil ifTrue: [#()] ifFalse: [top stack]
! !

!Process methodsFor: 'changing process state'!
resume
	"Make me runnable again. Answer myself."
	self isTerminated ifTrue: [^self error: 'Cannot resume a terminated process'].
	^self primResume
!
suspend
	"Stop me until resume. Answer the list I was waiting in (or nil)."
	^self primSuspend
!
terminate
	"Stop me for good after running my pending unwind blocks (ensure:, ifCurtailed:)."
	| ctx unwindBlock |
	self isActiveProcess ifTrue: [
		ctx := thisContext.
		[(ctx := ctx findNextUnwindContextUpTo: nil) isNil] whileFalse: [
			(ctx tempAt: 2) isNil ifTrue: [
				ctx tempAt: 2 put: true.
				unwindBlock := ctx tempAt: 1.
				thisContext terminateTo: ctx.
				unwindBlock value]].
		thisContext terminateTo: nil.
		terminated := true.
		self primSuspend.
		^self].
	self isTerminated ifTrue: [^self].
	myList isNil ifFalse: [self primSuspend].
	terminated := true.
	ctx := suspendedContext.
	suspendedContext := nil.
	[ctx isNil] whileFalse: [
		(ctx isUnwindContext and: [(ctx tempAt: 2) isNil]) ifTrue: [
			ctx tempAt: 2 put: true.
			(ctx tempAt: 1) value].
		ctx := ctx sender]
!
signalException: anException
	"Signal anException in me. If I am waiting on a Semaphore I wake up to handle it and, if it is resumed, wait again."
	| oldList |
	self isActiveProcess ifTrue: [^anException signal].
	self isTerminated ifTrue: [^self].
	oldList := myList isNil ifTrue: [nil] ifFalse: [self primSuspend].
	suspendedContext := Context
		sender: suspendedContext
		receiver: self
		method: (Process >> #pvtSignal:list:)
		arguments: (Array with: anException with: oldList).
	oldList isNil ifFalse: [self primResume]
! !

!Process methodsFor: 'testing'!
isActiveProcess
	^self == Processor activeProcess
!
isTerminated
	self isActiveProcess ifTrue: [^false].
	^terminated == true or: [suspendedContext isNil]
!
isSuspended
	"Answer whether I am neither running, nor runnable, nor waiting, nor terminated."
	^myList isNil and: [self isActiveProcess not and: [self isTerminated not]]
!
isWaiting
	"Answer whether I am blocked on a Semaphore."
	^myList notNil and: [myList class ~~ LinkedList]
!
isRunnable
	"Answer whether I am in a run queue, ready to run."
	^myList notNil and: [myList class == LinkedList]
!
isRunning
	^self isActiveProcess
! !

!Process methodsFor: 'printing'!
printOn: aStream
	| ctx |
	aStream nextPutAll: 'a Process'.
	name isNil ifFalse: [aStream space; print: name].
	aStream nextPutAll: ' (priority '; print: priority; nextPut: $).
	ctx := self isActiveProcess ifTrue: [nil] ifFalse: [suspendedContext].
	ctx isNil ifFalse: [aStream nextPutAll: ' in '; print: ctx]
!
longPrintOn: aStream
	self printOn: aStream.
	aStream nextPut: Character lf.
	self stack do: [:ctx | aStream tab; print: ctx; nextPut: Character lf]
! !

!Process methodsFor: 'private'!
primResume
	<primitive: 'processResume'>
	^self primitiveFailed
!
primSuspend
	<primitive: 'processSuspend'>
	^nil
!
pvtSignal: anException list: aList
	"I run on top of my interrupted stack (see signalException:). Signal, wait again if I was waiting, then continue where I was interrupted."
	| interrupted |
	anException signal.
	(aList notNil and: [aList class ~~ LinkedList]) ifTrue: [aList wait].
	interrupted := thisContext sender.
	interrupted stackp > 0 ifTrue: [^interrupted jump].
	self continueAt: interrupted
!
continueAt: aContext
	"Abandon my current stack and continue aContext exactly as it is. A return (or jump) would push a value onto aContext, so a process switch does it: a helper sets my suspendedContext once I am suspended and resumes me."
	[[self isSuspended or: [self isTerminated]] whileFalse: [Processor yield].
	 self isTerminated ifFalse: [
		suspendedContext := aContext.
		self primResume]]
			forkAt: priority.
	self primSuspend
!
initialize
	cpuTime := 0
! !

!Process class methodsFor: 'instance creation'!
forContext: aContext priority: anInteger
	"Answer a suspended Process that runs aContext when resumed."
	^self register: (self new
		suspendedContext: aContext;
		setPriority: anInteger;
		yourself)
! !

!Process class methodsFor: 'registry'!
initialize
	"Register the processes created before the registry existed (the bootstrap process). Every later process registers itself in forContext:priority:."
	Registry := WeakArray new: 64.
	RegistryMutex := Semaphore forMutualExclusion.
	Process allInstances do: [:each | self register: each]
!
register: aProcess
	"Remember aProcess weakly (a terminated process that nobody references is collected and its slot reused); answer it."
	RegistryMutex critical: [
		| slot |
		slot := Registry indexOf: nil.
		slot = 0 ifTrue: [
			slot := Registry size + 1.
			Registry := (WeakArray new: Registry size * 2)
				replaceFrom: 1 to: Registry size with: Registry startingAt: 1;
				yourself].
		Registry at: slot put: aProcess].
	^aProcess
!
allLive
	"Every process that has not terminated, from the registry: no heap scan (Process allInstances walks the whole heap inside one primitive, which nothing can preempt)."
	^RegistryMutex critical: [
		(Registry asArray select: [:each | each notNil and: [each isTerminated not]])]
! !

!Process methodsFor: 'private'!
setPriority: anInteger
	priority := anInteger
! !
