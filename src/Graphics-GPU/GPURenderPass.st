Object subclass: #GPURenderPass
	instanceVariableNames: 'commandBuffer handle'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPURenderPass comment: 'I am a render pass of a GPUCommandBuffer into one color target. Bind a pipeline, vertex buffer, textures and uniforms, draw, and end me before starting the next pass.'!

!GPURenderPass methodsFor: 'private'!
setCommandBuffer: aCommandBuffer handle: anInteger
	commandBuffer := aCommandBuffer.
	handle := anInteger
! !

!GPURenderPass methodsFor: 'accessing'!
commandBuffer
	^commandBuffer
! !

!GPURenderPass methodsFor: 'recording'!
pipeline: aGPUPipeline
	GPUPlatform bindPipeline: handle pipeline: aGPUPipeline handle
!
vertexBuffer: aGPUBuffer
	self vertexBuffer: aGPUBuffer offset: 0
!
vertexBuffer: aGPUBuffer offset: byteOffset
	GPUPlatform bindVertexBuffer: handle slot: 0 buffer: aGPUBuffer handle offset: byteOffset
!
texture: aGPUTexture sampler: aGPUSampler slot: slot
	GPUPlatform bindTexture: handle slot: slot texture: aGPUTexture handle sampler: aGPUSampler handle
!
uniforms: bytes
	"Push bytes (16-byte padded) as vertex uniform slot 0."
	GPUPlatform pushUniforms: handle stage: 0 slot: 0 bytes: bytes
!
fragmentUniforms: bytes
	GPUPlatform pushUniforms: handle stage: 1 slot: 0 bytes: bytes
!
scissor: anArray
	"anArray is {x. y. w. h} in target pixels."
	GPUPlatform setScissor: handle x: (anArray at: 1) y: (anArray at: 2) width: (anArray at: 3) height: (anArray at: 4)
!
scissorX: x y: y width: w height: h
	GPUPlatform setScissor: handle x: x y: y width: w height: h
!
viewport: anArray
	"anArray is {x. y. w. h} in target pixels."
	GPUPlatform setViewport: handle x: (anArray at: 1) y: (anArray at: 2) width: (anArray at: 3) height: (anArray at: 4)
!
draw: vertexCount from: firstVertex
	GPUPlatform draw: handle count: vertexCount first: firstVertex
!
end
	GPUPlatform endPass: handle.
	handle := nil
! !
