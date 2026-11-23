!GPUPrimitives class methodsFor: 'FFI candidates - commands'!
ffiCandidateSetViewport: pass x: x y: y width: w height: h
	| binding result |
	binding := GPUPlatformFFI viewportCall.
	"Legacy accepts Float or SmallInteger, not arbitrary Number coercions."
	(binding isNil or: [(self ffiViewportNumber: x) not or: [(self ffiViewportNumber: y) not
		or: [(self ffiViewportNumber: w) not or: [(self ffiViewportNumber: h) not]]]]) ifTrue: [
		^self setViewport: pass x: x y: y width: w height: h].
	result := binding tryInvoke5: pass with: x asFloat with: y asFloat with: w asFloat with: h asFloat.
	result == false ifTrue: [^self setViewport: pass x: x y: y width: w height: h].
	result = 0 ifTrue: [^self fail: 'gpuSetViewport'].
	^self
!
ffiViewportNumber: aNumber
	^aNumber class == Float or: [aNumber class == SmallInteger]
!
ffiCandidateSetScissor: pass x: x y: y width: w height: h
	| binding result |
	binding := GPUPlatformFFI scissorCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke5: pass with: x with: y with: w with: h].
	result == false ifTrue: [^self setScissor: pass x: x y: y width: w height: h].
	result = 0 ifTrue: [^self fail: 'gpuSetScissor'].
	^self
!
ffiCandidateEndPass: pass
	| binding result |
	binding := GPUPlatformFFI endPassCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: pass].
	result == false ifTrue: [^self endPass: pass].
	result = 0 ifTrue: [^self fail: 'gpuEndPass'].
	^self
! !

!GPUPrimitives class methodsFor: 'FFI candidates - submission'!
ffiCandidateSubmit: commandBuffer fence: wantFence
	| binding result |
	binding := GPUPlatformFFI submitCall.
	(binding isNil or: [wantFence ~~ true and: [wantFence ~~ false]]) ifTrue: [
		^self submit: commandBuffer fence: wantFence].
	result := binding tryInvoke2: commandBuffer with: (wantFence ifTrue: [1] ifFalse: [0]).
	result == false ifTrue: [^self submit: commandBuffer fence: wantFence].
	result < 0 ifTrue: [^self fail: 'gpuSubmit'].
	^result = 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidateFenceDone: fence
	| binding result |
	binding := GPUPlatformFFI fenceDoneCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: fence].
	result == false ifTrue: [^self fenceDone: fence].
	result < 0 ifTrue: [^self fail: 'gpuFenceDone'].
	^result = 1
!
ffiCandidateFenceElapsed: fence
	| binding result |
	binding := GPUPlatformFFI fenceElapsedCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: fence].
	result == false ifTrue: [^self fenceElapsed: fence].
	result = -2 ifTrue: [^self fail: 'gpuFenceElapsed'].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidateWaitFence: fence
	| binding result |
	binding := GPUPlatformFFI waitFenceCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: fence].
	result == false ifTrue: [^self waitFence: fence].
	result = 0 ifTrue: [^self fail: 'gpuWaitFence'].
	^self
! !

!GPUPrimitives class methodsFor: 'FFI candidates - pass creation'!
ffiCandidateAcquireSwapchain: commandBuffer window: window
	| binding bytes result |
	binding := GPUPlatformFFI swapchainCall.
	binding isNil ifTrue: [^self acquireSwapchain: commandBuffer window: window].
	bytes := ByteArray new: 12.
	result := binding tryInvoke3: commandBuffer with: window with: {bytes. 1. 12}.
	result == false ifTrue: [^self acquireSwapchain: commandBuffer window: window].
	result < 0 ifTrue: [^self fail: 'gpuAcquireSwapchain'].
	result = 0 ifTrue: [^nil].
	^{bytes uint32At: 1. bytes uint32At: 5. bytes uint32At: 9}
!
ffiCandidateBeginPass: commandBuffer target: texture clear: rgbaOrNil
	| binding result |
	rgbaOrNil isNil
		ifTrue: [
			binding := GPUPlatformFFI beginLoadCall.
			result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: commandBuffer with: texture]]
		ifFalse: [
			(rgbaOrNil class == Array and: [rgbaOrNil size = 4 and: [
				rgbaOrNil allSatisfy: [:v | self ffiViewportNumber: v]]]) ifFalse: [
					^self beginPass: commandBuffer target: texture clear: rgbaOrNil].
			binding := GPUPlatformFFI beginClearCall.
			result := binding isNil ifTrue: [false] ifFalse: [
				binding tryInvoke6: commandBuffer with: texture
					with: (rgbaOrNil at: 1) asFloat with: (rgbaOrNil at: 2) asFloat
					with: (rgbaOrNil at: 3) asFloat with: (rgbaOrNil at: 4) asFloat]].
	result == false ifTrue: [^self beginPass: commandBuffer target: texture clear: rgbaOrNil].
	result = 0 ifTrue: [^self fail: 'gpuBeginPass'].
	^result
! !

!GPUPrimitives class methodsFor: 'FFI candidates - transfers'!
ffiCandidateUploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	| binding result |
	binding := GPUPlatformFFI uploadBufferCall.
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke3: buffer with: {bytes. 1. byteCount} with: dstOffset].
	result == false ifTrue: [^self uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset].
	result = 0 ifTrue: [^self fail: 'gpuUploadBuffer'].
	^self
!
ffiCandidateUploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	| binding region result |
	binding := GPUPlatformFFI uploadTextureCall.
	(binding isNil or: [bytes class ~~ ByteArray]) ifTrue: [
		^self uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow].
	region := GPUPlatformFFI regionFrom: {x. y. w. h. bytesPerRow}.
	region isNil ifTrue: [^self uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow].
	result := binding tryInvoke3: texture with: {bytes. 1. bytes size} with: {region. 1. 20}.
	result == false ifTrue: [^self uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow].
	result = 0 ifTrue: [^self fail: 'gpuUploadTexture'].
	^self
!
ffiCandidateDownload: texture x: x y: y width: w height: h into: bytes
	| binding region result |
	binding := GPUPlatformFFI downloadCall.
	(binding isNil or: [bytes class ~~ ByteArray]) ifTrue: [^self download: texture x: x y: y width: w height: h into: bytes].
	region := GPUPlatformFFI regionFrom: {x. y. w. h}.
	region isNil ifTrue: [^self download: texture x: x y: y width: w height: h into: bytes].
	result := binding tryInvoke3: texture with: {region. 1. 16} with: {bytes. 1. bytes size}.
	result == false ifTrue: [^self download: texture x: x y: y width: w height: h into: bytes].
	result = 0 ifTrue: [^self fail: 'gpuDownload'].
	^bytes
! !

!GPUPrimitives class methodsFor: 'FFI candidates - devices and resources'!
ffiCandidateCreateDevice: debug
	<ffiSite>
	| result |
	(debug ~~ true and: [debug ~~ false]) ifTrue: [^self createDevice: debug].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_device' (i32) i32))
		tryInvoke1: (debug ifTrue: [1] ifFalse: [0]).
	result == false ifTrue: [^self createDevice: debug].
	result = 0 ifTrue: [^self fail: 'gpuCreateDevice'].
	^result
!
ffiCandidateClaim: dev window: window
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_claim_window' (i32 i32) i32))
		tryInvoke2: dev with: window.
	result == false ifTrue: [^self claim: dev window: window].
	result = 0 ifTrue: [^self fail: 'gpuClaimWindow'].
	^self
!
ffiCandidateSwapchainFormat: dev window: window
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_swapchain_format' (i32 i32) i32))
		tryInvoke2: dev with: window.
	result == false ifTrue: [^self swapchainFormat: dev window: window].
	result = 0 ifTrue: [^self fail: 'gpuSwapchainFormat'].
	^result
!
ffiCandidateCreateTexture: dev width: w height: h format: format usage: usage
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_texture' (i32 i32 i32 i32 i32) i32))
		tryInvoke5: dev with: w with: h with: format with: usage.
	result == false ifTrue: [^self createTexture: dev width: w height: h format: format usage: usage].
	result = 0 ifTrue: [^self fail: 'gpuCreateTexture'].
	^result
!
ffiCandidateCreateSampler: dev linear: linear repeat: repeat
	<ffiSite>
	| result |
	((linear ~~ true and: [linear ~~ false]) or: [repeat ~~ true and: [repeat ~~ false]]) ifTrue: [
		^self createSampler: dev linear: linear repeat: repeat].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_sampler' (i32 i32 i32) i32))
		tryInvoke3: dev with: (linear ifTrue: [1] ifFalse: [0]) with: (repeat ifTrue: [1] ifFalse: [0]).
	result == false ifTrue: [^self createSampler: dev linear: linear repeat: repeat].
	result = 0 ifTrue: [^self fail: 'gpuCreateSampler'].
	^result
!
ffiCandidateCreateBuffer: dev usage: usage size: size
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_create_buffer' (i32 i32 u32) i32))
		tryInvoke3: dev with: usage with: size.
	result == false ifTrue: [^self createBuffer: dev usage: usage size: size].
	result = 0 ifTrue: [^self fail: 'gpuCreateBuffer'].
	^result
!
ffiCandidateRelease: handle
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_release' (i32) i32)) tryInvoke1: handle.
	result == false ifTrue: [^self release: handle].
	result = 0 ifTrue: [^self fail: 'gpuRelease'].
	^self
!
ffiCandidateAcquireCommandBuffer: dev
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_acquire_command_buffer' (i32) i32)) tryInvoke1: dev.
	result == false ifTrue: [^self acquireCommandBuffer: dev].
	result = 0 ifTrue: [^self fail: 'gpuAcquireCommandBuffer'].
	^result
!
ffiCandidateWaitIdle: dev
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_wait_idle' (i32) i32)) tryInvoke1: dev.
	result == false ifTrue: [^self waitIdle: dev].
	result = 0 ifTrue: [^self fail: 'gpuWaitIdle'].
	^self
!
ffiCandidateShaderLanguage: dev
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_shader_language' (i32) i32)) tryInvoke1: dev.
	result == false ifTrue: [^self shaderLanguage: dev].
	result = 1 ifTrue: [^'msl' copy].
	result = 2 ifTrue: [^'glsl' copy].
	^self fail: 'gpuShaderLanguage'
! !

!GPUPrimitives class methodsFor: 'FFI candidates - render bindings'!
ffiCandidateBindPipeline: pass pipeline: pipeline
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_bind_pipeline' (i32 i32) i32))
		tryInvoke2: pass with: pipeline.
	result == false ifTrue: [^self bindPipeline: pass pipeline: pipeline].
	result = 0 ifTrue: [^self fail: 'gpuBindPipeline'].
	^self
!
ffiCandidateBindVertexBuffer: pass slot: slot buffer: buffer offset: offset
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_bind_vertex_buffer' (i32 i32 i32 u32) i32))
		tryInvoke4: pass with: slot with: buffer with: offset.
	result == false ifTrue: [^self bindVertexBuffer: pass slot: slot buffer: buffer offset: offset].
	result = 0 ifTrue: [^self fail: 'gpuBindVertexBuffer'].
	^self
!
ffiCandidateBindTexture: pass slot: slot texture: texture sampler: sampler
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'platform' 'platform_gpu_bind_texture' (i32 i32 i32 i32) i32))
		tryInvoke4: pass with: slot with: texture with: sampler.
	result == false ifTrue: [^self bindTexture: pass slot: slot texture: texture sampler: sampler].
	result = 0 ifTrue: [^self fail: 'gpuBindTexture'].
	^self
!
ffiCandidatePushUniforms: commandOrPass stage: stage slot: slot bytes: bytes
	<ffiSite>
	| result |
	(bytes class ~~ ByteArray or: [bytes size > 4096]) ifTrue: [
		^self pushUniforms: commandOrPass stage: stage slot: slot bytes: bytes].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_push_uniforms' (i32 i32 i32 bytesWithLength) i32))
		tryInvoke4: commandOrPass with: stage with: slot with: {bytes. 1. bytes size}.
	result == false ifTrue: [^self pushUniforms: commandOrPass stage: stage slot: slot bytes: bytes].
	result = 0 ifTrue: [^self fail: 'gpuPushUniforms'].
	^self
! !

!GPUPrimitives class methodsFor: 'FFI candidates - shaders'!
ffiCandidateCompileShader: glsl stage: stage
	<ffiSite>
	| source result |
	source := PlatformFFI cTextBytes: glsl.
	source isNil ifTrue: [^self compileShader: glsl stage: stage].
	result := FFIOwnedOutput captureUpTo: 67108864 do: [:ticket |
		(self ffiSite: #(call 'platform' 'platform_gpu_compile_shader' (bytesWithLength i32 u64) i32))
			tryInvoke3: {source. 1. source size} with: stage with: ticket].
	result == false ifTrue: [^self compileShader: glsl stage: stage].
	result class == ByteArray ifFalse: [^self fail: 'gpuCompileShader'].
	^result
! !

!GPUPrimitives class methodsFor: 'FFI candidates - blit'!
ffiCandidateBlit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: linear
	<ffiSite>
	| rects result |
	(srcRect class == Array and: [dstRect class == Array and: [srcRect size = 4 and: [
		dstRect size = 4 and: [linear == true or: [linear == false]]]]]) ifFalse: [
		^self blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: linear].
	rects := GPUPlatformFFI regionFrom: srcRect , dstRect.
	rects isNil ifTrue: [^self blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: linear].
	result := (self ffiSite: #(call 'platform' 'platform_gpu_blit' (i32 i32 i32 i32 bytesWithLength) i32))
		tryInvoke5: cmd with: src with: dst with: (linear ifTrue: [1] ifFalse: [0]) with: {rects. 1. 32}.
	result == false ifTrue: [^self blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: linear].
	result = 0 ifTrue: [^self fail: 'gpuBlit'].
	^self
! !

!GPUPrimitives class methodsFor: 'FFI candidates - shader resources'!
ffiCandidateCreateShader: dev source: source entry: entry stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	<ffiSite>
	| kind code entryBytes config result |
	kind := source class == ByteArray ifTrue: [1] ifFalse: [0].
	code := kind = 1 ifTrue: [source] ifFalse: [PlatformFFI cTextBytes: source].
	entryBytes := PlatformFFI cTextBytes: entry.
	(code isNil or: [entryBytes isNil or: [code size > 67108864 or: [entryBytes size > 4096]]])
		ifTrue: [result := false]
		ifFalse: [
			config := GPUPlatformFFI regionFrom: {kind. stage. samplers. uniforms. storageBuffers. storageTextures}.
			result := config isNil ifTrue: [false] ifFalse: [
				config := config , entryBytes.
				(self ffiSite: #(call 'platform' 'platform_gpu_create_shader' (i32 bytesWithLength bytesWithLength) i32))
					tryInvoke3: dev with: {code. 1. code size} with: {config. 1. config size}]].
	result == false ifTrue: [
		^self createShader: dev source: source entry: entry stage: stage samplers: samplers uniformBuffers: uniforms
			storageBuffers: storageBuffers storageTextures: storageTextures].
	result = 0 ifTrue: [^self fail: 'gpuCreateShader'].
	^result
!
ffiCandidateCreatePipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: prim blend: blend format: format
	<ffiSite>
	| config result |
	config := (attributes class == Array and: [attributes size <= 32 and: [attributes size even]])
		ifTrue: [GPUPlatformFFI regionFrom: {stride. prim. blend. format} , attributes]
		ifFalse: [nil].
	result := config isNil ifTrue: [false] ifFalse: [
		(self ffiSite: #(call 'platform' 'platform_gpu_create_pipeline' (i32 i32 i32 bytesWithLength) i32))
			tryInvoke4: dev with: vs with: fs with: {config. 1. config size}].
	result == false ifTrue: [
		^self createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes
			primitive: prim blend: blend format: format].
	result = 0 ifTrue: [^self fail: 'gpuCreatePipeline'].
	^result
! !
