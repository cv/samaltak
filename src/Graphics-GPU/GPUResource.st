Object subclass: #GPUResource
	instanceVariableNames: 'device handle session'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUResource comment: 'I am the abstract class of GPU objects that outlive a frame (shaders, pipelines, textures, samplers, buffers, swapchains). I keep my creation parameters and (re)create my platform handle on first use in each session (see GPUDevice). Subclasses implement createHandle. A resource that is garbage collected releases its handle (WeakRegistry default, GPUHandleExecutor).'!

!GPUResource methodsFor: 'accessing'!
device
	^device
!
handle
	"Answer my platform handle, creating it if this session has none yet."
	(handle notNil and: [session == device session]) ifTrue: [^handle].
	session := device session.
	handle := self createHandle.
	self registerForFinalization.
	self handleCreated.
	^handle
!
isAlive
	"Answer whether I hold a handle valid in this session."
	^handle notNil and: [session == device session]
! !

!GPUResource methodsFor: 'private'!
setDevice: aGPUDevice
	device := aGPUDevice
!
createHandle
	^self subclassResponsibility
!
handleCreated
	"Hook run after a new handle was created."
!
registerForFinalization
	"Release the new handle when I am collected."
	WeakRegistry default
		remove: self;
		add: self executor: (GPUHandleExecutor new device: device handle: handle session: session)
! !

!GPUResource methodsFor: 'releasing'!
release
	"Free the platform object now; it is re-created if I am used again."
	self isAlive ifTrue: [GPUPlatform release: handle].
	handle := nil.
	WeakRegistry default remove: self
! !
