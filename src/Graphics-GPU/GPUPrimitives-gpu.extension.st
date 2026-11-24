!GPUPrimitives class methodsFor: 'platform - commands'!
setViewport: pass x: x y: y width: w height: h
	| binding result |
	binding := GPUPlatformFFI viewportCall.
	"Legacy accepts Float or SmallInteger, not arbitrary Number coercions."
	(binding isNil or: [(self ffiViewportNumber: x) not or: [(self ffiViewportNumber: y) not
		or: [(self ffiViewportNumber: w) not or: [(self ffiViewportNumber: h) not]]]]) ifTrue: [
		^self ffiRejected: 'gpuSetViewport'].
	result := binding tryInvoke5: pass with: x asFloat with: y asFloat with: w asFloat with: h asFloat.
	result == false ifTrue: [^self ffiRejected: 'gpuSetViewport'].
	result = 0 ifTrue: [^self fail: 'gpuSetViewport'].
	^self
!
ffiViewportNumber: aNumber
	| cls |
	cls := aNumber class.
	^cls == SmallFloat64 or: [cls == BoxedFloat64 or: [cls == SmallInteger]]
!
setScissor: pass x: x y: y width: w height: h
	| binding result |
	binding := GPUPlatformFFI scissorCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke5: pass with: x with: y with: w with: h].
	result == false ifTrue: [^self ffiRejected: 'gpuSetScissor'].
	result = 0 ifTrue: [^self fail: 'gpuSetScissor'].
	^self
!
endPass: pass
	| binding result |
	binding := GPUPlatformFFI endPassCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: pass].
	result == false ifTrue: [^self ffiRejected: 'gpuEndPass'].
	result = 0 ifTrue: [^self fail: 'gpuEndPass'].
	^self
! !

!GPUPrimitives class methodsFor: 'platform - submission'!
submit: commandBuffer fence: wantFence
	| binding result |
	binding := GPUPlatformFFI submitCall.
	(binding isNil or: [wantFence ~~ true and: [wantFence ~~ false]]) ifTrue: [
		^self ffiRejected: 'gpuSubmit'].
	result := binding tryInvoke2: commandBuffer with: (wantFence ifTrue: [1] ifFalse: [0]).
	result == false ifTrue: [^self ffiRejected: 'gpuSubmit'].
	result < 0 ifTrue: [^self fail: 'gpuSubmit'].
	^result = 0 ifTrue: [nil] ifFalse: [result]
!
fenceDone: fence
	| binding result |
	binding := GPUPlatformFFI fenceDoneCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: fence].
	result == false ifTrue: [^self ffiRejected: 'gpuFenceDone'].
	result < 0 ifTrue: [^self fail: 'gpuFenceDone'].
	^result = 1
!
fenceElapsed: fence
	| binding result |
	binding := GPUPlatformFFI fenceElapsedCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: fence].
	result == false ifTrue: [^self ffiRejected: 'gpuFenceElapsed'].
	result = -2 ifTrue: [^self fail: 'gpuFenceElapsed'].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
waitFence: fence
	| binding result |
	binding := GPUPlatformFFI waitFenceCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: fence].
	result == false ifTrue: [^self ffiRejected: 'gpuWaitFence'].
	result = 0 ifTrue: [^self fail: 'gpuWaitFence'].
	^self
! !

!GPUPrimitives class methodsFor: 'platform - pass creation'!
acquireSwapchain: commandBuffer window: window
	| binding bytes result |
	binding := GPUPlatformFFI swapchainCall.
	binding isNil ifTrue: [^self ffiRejected: 'gpuAcquireSwapchain'].
	bytes := ByteArray new: 12.
	result := binding tryInvoke3: commandBuffer with: window with: {bytes. 1. 12}.
	result == false ifTrue: [^self ffiRejected: 'gpuAcquireSwapchain'].
	result < 0 ifTrue: [^self fail: 'gpuAcquireSwapchain'].
	result = 0 ifTrue: [^nil].
	^{bytes uint32At: 1. bytes uint32At: 5. bytes uint32At: 9}
!
beginPass: commandBuffer target: texture clear: rgbaOrNil
	| binding result |
	rgbaOrNil isNil
		ifTrue: [
			binding := GPUPlatformFFI beginLoadCall.
			result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: commandBuffer with: texture]]
		ifFalse: [
			(rgbaOrNil class instSpec = VMConstants fVar and: [rgbaOrNil basicSize = 4 and: [
				(1 to: 4) allSatisfy: [:i | self ffiViewportNumber: (rgbaOrNil basicAt: i)]]]) ifFalse: [
					^self ffiRejected: 'gpuBeginPass'].
			binding := GPUPlatformFFI beginClearCall.
			result := binding isNil ifTrue: [false] ifFalse: [
				binding tryInvoke6: commandBuffer with: texture
					with: (rgbaOrNil basicAt: 1) asFloat with: (rgbaOrNil basicAt: 2) asFloat
					with: (rgbaOrNil basicAt: 3) asFloat with: (rgbaOrNil basicAt: 4) asFloat]].
	result == false ifTrue: [^self ffiRejected: 'gpuBeginPass'].
	result = 0 ifTrue: [^self fail: 'gpuBeginPass'].
	^result
! !

!GPUPrimitives class methodsFor: 'platform - transfers'!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	| binding data result |
	binding := GPUPlatformFFI uploadBufferCall.
	binding isNil ifTrue: [^self ffiRejected: 'gpuUploadBuffer'].
	data := GPUPlatformFFI transferBytesFor: bytes.
	data isNil ifTrue: [^self ffiRejected: 'gpuUploadBuffer'].
	result := binding tryInvoke3: buffer with: {data. 1. byteCount} with: dstOffset.
	result == false ifTrue: [^self ffiRejected: 'gpuUploadBuffer'].
	result = 0 ifTrue: [^self fail: 'gpuUploadBuffer'].
	^self
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	"bytes: a ByteArray (Bitmap), or the address (an Integer) of h rows of bytesPerRow bytes outside the heap."
	| binding data region result |
	bytes isInteger ifTrue: [^self uploadTexture: texture address: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow].
	binding := GPUPlatformFFI uploadTextureCall.
	binding isNil ifTrue: [^self ffiRejected: 'gpuUploadTexture'].
	region := GPUPlatformFFI regionFrom: {x. y. w. h. bytesPerRow}.
	data := GPUPlatformFFI transferBytesFor: bytes.
	(region isNil or: [data isNil]) ifTrue: [^self ffiRejected: 'gpuUploadTexture'].
	result := binding tryInvoke3: texture with: {data. 1. data size} with: {region. 1. 20}.
	result == false ifTrue: [^self ffiRejected: 'gpuUploadTexture'].
	result = 0 ifTrue: [^self fail: 'gpuUploadTexture'].
	^self
!
uploadTexture: texture address: address x: x y: y width: w height: h bytesPerRow: bytesPerRow
	"h rows of bytesPerRow bytes at address, outside the heap (an NvComputeGPU's back buffer): a primitive, as the image passes no addresses through the FFI."
	<primitive: 'gpuUploadTextureAddress'>
	^self fail: 'gpuUploadTexture'
!
download: texture x: x y: y width: w height: h into: bytes
	| binding data region result |
	binding := GPUPlatformFFI downloadCall.
	(binding isNil or: [bytes isReadOnlyObject]) ifTrue: [^self ffiRejected: 'gpuDownload'].
	region := GPUPlatformFFI regionFrom: {x. y. w. h}.
	data := GPUPlatformFFI transferBytesFor: bytes.
	(region isNil or: [data isNil]) ifTrue: [^self ffiRejected: 'gpuDownload'].
	result := binding tryInvoke3: texture with: {region. 1. 16} with: {data. 1. data size}.
	result == false ifTrue: [^self ffiRejected: 'gpuDownload'].
	result = 0 ifTrue: [^self fail: 'gpuDownload'].
	data == bytes ifFalse: [GPUPlatformFFI copyTransferBytes: data into: bytes].
	^bytes
! !

!GPUPrimitives class methodsFor: 'platform - devices and resources'!
createDevice: debug
	<ffiSite>
	| result |
	(debug ~~ true and: [debug ~~ false]) ifTrue: [^self ffiRejected: 'gpuCreateDevice'].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_device' (i32) i32))
		tryInvoke1: (debug ifTrue: [1] ifFalse: [0]).
	result == false ifTrue: [^self ffiRejected: 'gpuCreateDevice'].
	result = 0 ifTrue: [^self fail: 'gpuCreateDevice'].
	^result
!
claim: dev window: window
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_claim_window' (i32 i32) i32))
		tryInvoke2: dev with: window.
	result == false ifTrue: [^self ffiRejected: 'gpuClaimWindow'].
	result = 0 ifTrue: [^self fail: 'gpuClaimWindow'].
	^self
!
swapchainFormat: dev window: window
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_swapchain_format' (i32 i32) i32))
		tryInvoke2: dev with: window.
	result == false ifTrue: [^self ffiRejected: 'gpuSwapchainFormat'].
	result = 0 ifTrue: [^self fail: 'gpuSwapchainFormat'].
	^result
!
createTexture: dev width: w height: h format: format usage: usage
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_texture' (i32 i32 i32 i32 i32) i32))
		tryInvoke5: dev with: w with: h with: format with: usage.
	result == false ifTrue: [^self ffiRejected: 'gpuCreateTexture'].
	result = 0 ifTrue: [^self fail: 'gpuCreateTexture'].
	^result
!
createSampler: dev linear: linear repeat: repeat
	<ffiSite>
	| result |
	((linear ~~ true and: [linear ~~ false]) or: [repeat ~~ true and: [repeat ~~ false]]) ifTrue: [
		^self ffiRejected: 'gpuCreateSampler'].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_sampler' (i32 i32 i32) i32))
		tryInvoke3: dev with: (linear ifTrue: [1] ifFalse: [0]) with: (repeat ifTrue: [1] ifFalse: [0]).
	result == false ifTrue: [^self ffiRejected: 'gpuCreateSampler'].
	result = 0 ifTrue: [^self fail: 'gpuCreateSampler'].
	^result
!
createBuffer: dev usage: usage size: size
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_buffer' (i32 i32 u32) i32))
		tryInvoke3: dev with: usage with: size.
	result == false ifTrue: [^self ffiRejected: 'gpuCreateBuffer'].
	result = 0 ifTrue: [^self fail: 'gpuCreateBuffer'].
	^result
!
release: handle
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_release' (i32) i32)) tryInvoke1: handle.
	result == false ifTrue: [^self ffiRejected: 'gpuRelease'].
	result = 0 ifTrue: [^self fail: 'gpuRelease'].
	^self
!
acquireCommandBuffer: dev
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_acquire_command_buffer' (i32) i32)) tryInvoke1: dev.
	result == false ifTrue: [^self ffiRejected: 'gpuAcquireCommandBuffer'].
	result = 0 ifTrue: [^self fail: 'gpuAcquireCommandBuffer'].
	^result
!
waitIdle: dev
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_wait_idle' (i32) i32)) tryInvoke1: dev.
	result == false ifTrue: [^self ffiRejected: 'gpuWaitIdle'].
	result = 0 ifTrue: [^self fail: 'gpuWaitIdle'].
	^self
!
shaderLanguage: dev
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_shader_language' (i32) i32)) tryInvoke1: dev.
	result == false ifTrue: [^self ffiRejected: 'gpuShaderLanguage'].
	result = 1 ifTrue: [^'msl' copy].
	result = 2 ifTrue: [^'glsl' copy].
	^self fail: 'gpuShaderLanguage'
! !

!GPUPrimitives class methodsFor: 'platform - render bindings'!
bindPipeline: pass pipeline: pipeline
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_bind_pipeline' (i32 i32) i32))
		tryInvoke2: pass with: pipeline.
	result == false ifTrue: [^self ffiRejected: 'gpuBindPipeline'].
	result = 0 ifTrue: [^self fail: 'gpuBindPipeline'].
	^self
!
bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_bind_vertex_buffer' (i32 i32 i32 u32) i32))
		tryInvoke4: pass with: slot with: buffer with: offset.
	result == false ifTrue: [^self ffiRejected: 'gpuBindVertexBuffer'].
	result = 0 ifTrue: [^self fail: 'gpuBindVertexBuffer'].
	^self
!
bindTexture: pass slot: slot texture: texture sampler: sampler
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_bind_texture' (i32 i32 i32 i32) i32))
		tryInvoke4: pass with: slot with: texture with: sampler.
	result == false ifTrue: [^self ffiRejected: 'gpuBindTexture'].
	result = 0 ifTrue: [^self fail: 'gpuBindTexture'].
	^self
!
pushUniforms: commandOrPass stage: stage slot: slot bytes: bytes
	<ffiSite>
	| data result |
	data := GPUPlatformFFI transferBytesFor: bytes.
	data isNil ifTrue: [^self ffiRejected: 'gpuPushUniforms'].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_push_uniforms' (i32 i32 i32 bytesWithLength) i32))
		tryInvoke4: commandOrPass with: stage with: slot with: {data. 1. data size}.
	result == false ifTrue: [^self ffiRejected: 'gpuPushUniforms'].
	result = 0 ifTrue: [^self fail: 'gpuPushUniforms'].
	^self
! !

!GPUPrimitives class methodsFor: 'platform - shaders'!
compileShader: glsl stage: stage
	<ffiSite>
	| source result |
	source := WindowPlatformFFI cTextBytes: glsl.
	source isNil ifTrue: [^self ffiRejected: 'gpuCompileShader'].
	result := FFIPagedPlatformOutput capture: [:receipt |
		(self ffiSite: #(call 'platform' 'platform_gpu_compile_shader' (bytesWithLength i32 writableBytesWithLength) i32))
			tryInvoke3: {source. 1. source size} with: stage with: {receipt. 1. 16}].
	result == false ifTrue: [^self ffiRejected: 'gpuCompileShader'].
	result class == ByteArray ifFalse: [^self fail: 'gpuCompileShader'].
	^result
! !

!GPUPrimitives class methodsFor: 'platform - blit'!
blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: linear
	<ffiSite>
	| rects result |
	((GPUPlatformFFI isVector: srcRect size: 4) and: [
		(GPUPlatformFFI isVector: dstRect size: 4) and: [linear == true or: [linear == false]]]) ifFalse: [
		^self ffiRejected: 'gpuBlit'].
	rects := GPUPlatformFFI regionFrom: ((1 to: 8) collect: [:i |
		i <= 4 ifTrue: [srcRect basicAt: i] ifFalse: [dstRect basicAt: i - 4]]).
	rects isNil ifTrue: [^self ffiRejected: 'gpuBlit'].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_blit' (i32 i32 i32 i32 bytesWithLength) i32))
		tryInvoke5: cmd with: src with: dst with: (linear ifTrue: [1] ifFalse: [0]) with: {rects. 1. 32}.
	result == false ifTrue: [^self ffiRejected: 'gpuBlit'].
	result = 0 ifTrue: [^self fail: 'gpuBlit'].
	^self
! !

!GPUPrimitives class methodsFor: 'platform - shader resources'!
createShader: dev source: source entry: entry stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	<ffiSite>
	| kind code entryBytes config result |
	kind := source class == ByteArray ifTrue: [1] ifFalse: [0].
	code := kind = 1 ifTrue: [source] ifFalse: [WindowPlatformFFI cTextBytes: source].
	entryBytes := WindowPlatformFFI cTextBytes: entry.
	(code isNil or: [entryBytes isNil])
		ifTrue: [result := false]
		ifFalse: [
			config := GPUPlatformFFI regionFrom: {kind. stage. samplers. uniforms. storageBuffers. storageTextures}.
			result := config isNil ifTrue: [false] ifFalse: [
				config := config , entryBytes.
				(self ffiSite: #(call 'platform' 'platform_gpu_create_shader' (i32 bytesWithLength bytesWithLength) i32))
					tryInvoke3: dev with: {code. 1. code size} with: {config. 1. config size}]].
	result == false ifTrue: [
		^self ffiRejected: 'gpuCreateShader'].
	result = 0 ifTrue: [^self fail: 'gpuCreateShader'].
	^result
!
createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: prim blend: blend format: format
	<ffiSite>
	| config result |
	config := (attributes class instSpec = VMConstants fVar and: [attributes basicSize <= 32 and: [attributes basicSize even]])
		ifTrue: [GPUPlatformFFI regionFrom: {stride. prim. blend. format} ,
			((1 to: attributes basicSize) collect: [:i | attributes basicAt: i])]
		ifFalse: [nil].
	result := config isNil ifTrue: [false] ifFalse: [
		(self ffiSite: #(call 'platform' 'platform_gpu_create_pipeline' (i32 i32 i32 bytesWithLength) i32))
			tryInvoke4: dev with: vs with: fs with: {config. 1. config size}].
	result == false ifTrue: [
		^self ffiRejected: 'gpuCreatePipeline'].
	result = 0 ifTrue: [^self fail: 'gpuCreatePipeline'].
	^result
! !

!GPUPrimitives class methodsFor: 'platform - draw'!
draw: pass count: count first: first
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_draw' (i32 u32 u32) i32))
		tryInvoke3: pass with: count with: first.
	result == false ifTrue: [^self ffiRejected: 'gpuDraw'].
	result = 1 ifFalse: [^self fail: 'gpuDraw'].
	^self
! !
