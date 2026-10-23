Object subclass: #GPUFence
	instanceVariableNames: 'handle'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUFence comment: 'I signal the completion of a submitted command buffer. Release me when done (wait does it for you); if I am garbage collected, my handle is released for you.'!

!GPUFence methodsFor: 'private'!
setHandle: anInteger
	handle := anInteger.
	WeakRegistry default add: self executor: (GPUHandleExecutor new device: nil handle: anInteger session: nil)
! !

!GPUFence methodsFor: 'waiting'!
wait
	"Block until the GPU finished the command buffer, then release me."
	handle isNil ifTrue: [^self].
	GPUPlatform waitFence: handle.
	self release
!
isDone
	handle isNil ifTrue: [^true].
	^GPUPlatform fenceDone: handle
!
elapsedMicroseconds
	"µs from my submit to the GPU's completion of the work before me (stamped by the platform's fence watcher), or nil while pending."
	handle isNil ifTrue: [^nil].
	^GPUPlatform fenceElapsed: handle
!
release
	handle isNil ifTrue: [^self].
	GPUPlatform release: handle.
	handle := nil.
	WeakRegistry default remove: self
! !
