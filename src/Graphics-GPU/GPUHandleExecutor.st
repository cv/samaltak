Object subclass: #GPUHandleExecutor
	instanceVariableNames: 'device handle session backend'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUHandleExecutor comment: 'I release the platform handle of a GPUResource that was garbage collected (see WeakRegistry). I hold a copy of the handle, its session and the GPU backend that made it (GPUPlatform device), never the resource itself.'!

!GPUHandleExecutor methodsFor: 'accessing'!
device: aDevice handle: anInteger session: aSession
	device := aDevice.
	handle := anInteger.
	session := aSession.
	backend := GPUPlatform device
! !

!GPUHandleExecutor methodsFor: 'finalization'!
finalize
	"Release the handle if it belongs to the current session (handles of earlier VM processes are gone); without a device (a fence) there is no session to check."
	(handle notNil and: [device isNil or: [session == device session]]) ifTrue: [backend release: handle].
	handle := nil
! !
