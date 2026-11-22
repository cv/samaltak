Object subclass: #GPUCommandBuffer
	instanceVariableNames: 'device handle'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUCommandBuffer comment: 'I record one frame of GPU work: render passes, blits, uniform pushes, the swapchain acquire. Submit me exactly once.'!

!GPUCommandBuffer methodsFor: 'private'!
setDevice: aDevice handle: anInteger
	device := aDevice.
	handle := anInteger
! !

!GPUCommandBuffer methodsFor: 'accessing'!
device
	^device
!
handle
	^handle
! !

!GPUCommandBuffer methodsFor: 'recording'!
beginPassOn: aTexture clear: aColorArrayOrNil
	"Start a render pass into aTexture, cleared to {r. g. b. a} (floats 0..1) or keeping its contents when nil."
	^GPURenderPass new setCommandBuffer: self handle: (GPUPlatform beginPass: handle target: aTexture handle clear: aColorArrayOrNil)
!
blit: sourceTexture to: destinationTexture
	"Copy all of sourceTexture onto all of destinationTexture (scaling linearly if the sizes differ)."
	self blit: sourceTexture rect: {0. 0. sourceTexture width. sourceTexture height}
		to: destinationTexture rect: {0. 0. destinationTexture width. destinationTexture height}
		linear: true
!
blit: sourceTexture rect: srcArray to: destinationTexture rect: dstArray linear: aBoolean
	"Rects are {x. y. w. h} in pixels."
	GPUPlatform blit: handle source: sourceTexture handle rect: srcArray destination: destinationTexture handle rect: dstArray linear: aBoolean
!
presentDamage: scissors
	"Present only the rectangles scissors ({x. y. width. height} pixels) of the swapchain texture I acquired, where the path keeps the rest from the last frame (GPUSwapchain>>keepsContents): the firmware's screen, an uploaded frame."
	GPUPlatform presentDamage: handle rects: scissors
!
pushVertexUniforms: bytes slot: slot
	GPUPlatform pushUniforms: handle stage: 0 slot: slot bytes: bytes
!
pushFragmentUniforms: bytes slot: slot
	GPUPlatform pushUniforms: handle stage: 1 slot: slot bytes: bytes
!
acquireSwapchainTexture: aGPUSwapchain
	"Answer the swapchain's texture for this frame (valid until submit), or nil if the window cannot be drawn now."
	| info |
	info := GPUPlatform acquireSwapchain: handle window: aGPUSwapchain handle.
	info isNil ifTrue: [^nil].
	^(GPUTexture new setDevice: device width: (info at: 2) height: (info at: 3) format: #bgra8 usage: nil)
		setTransientHandle: (info at: 1);
		yourself
! !

!GPUCommandBuffer methodsFor: 'submitting'!
submit
	GPUPlatform submit: handle fence: false.
	handle := nil
!
submitWithFence
	"Submit and answer a GPUFence that completes when the GPU has executed me."
	| fence |
	fence := GPUPlatform submit: handle fence: true.
	handle := nil.
	^GPUFence new setHandle: fence
! !
