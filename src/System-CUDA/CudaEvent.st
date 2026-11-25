Object subclass: #CudaEvent
	instanceVariableNames: 'handle session'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaEvent comment: 'I am a CUDA event: record marks a point in the work queued on the device (the default stream), wait waits until the device passed it (polling, so other Processes run), millisecondsSince: another event the device''s time between the two. Release me, or I am destroyed when collected.

	| start stop | start := CudaEvent new record. "... queue work ..." stop := CudaEvent new record wait.
	stop millisecondsSince: start'!

!CudaEvent class methodsFor: 'instance creation'!
new
	^self basicNew create
! !

!CudaEvent methodsFor: 'using'!
isAlive
	^handle notNil and: [session = CudaLibraryAPI session]
!
create
	handle := CudaRuntimeAPI cudaEventCreate.
	session := CudaLibraryAPI session.
	WeakRegistry default add: self executor: (CudaReleaser kind: #event value: handle session: session)
!
handle
	(handle notNil and: [session = CudaLibraryAPI session]) ifFalse: [^self error: 'a CudaEvent released or of an earlier VM session'].
	^handle
!
record
	CudaRuntimeAPI cudaEventRecord: self handle stream: 0
!
isDone
	^(CudaRuntimeAPI cudaEventQuery: self handle) = 0
!
wait
	"Wait until the device has passed me, letting other Processes run."
	[self isDone] whileFalse: [(Delay forMilliseconds: 1) wait]
!
millisecondsSince: anEvent
	"The device's milliseconds from anEvent to me (both recorded and passed)."
	^CudaRuntimeAPI cudaEventElapsedTime: anEvent handle end: self handle
!
release
	(handle notNil and: [session = CudaLibraryAPI session]) ifTrue: [CudaRuntimeAPI cudaEventDestroy: handle].
	handle := nil.
	WeakRegistry default remove: self
! !
