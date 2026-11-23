Object subclass: #GPUPlatformFFI
	instanceVariableNames: ''
	classVariableNames: 'ViewportCall ScissorCall EndPassCall SubmitCall FenceDoneCall FenceElapsedCall WaitFenceCall SwapchainCall BeginLoadCall BeginClearCall UploadBufferCall UploadTextureCall DownloadCall'
	package: 'Graphics-GPU'!

GPUPlatformFFI comment: 'Private binding cache for the opt-in GPUPrimitives FFI methods. Bindings are symbolic and reprepare after a snapshot. Only false means the wrapper did not enter native code.'!

!GPUPlatformFFI class methodsFor: 'commands'!
viewportCall
	^ViewportCall ifNil: [ViewportCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_set_viewport' (i32 f64 f64 f64 f64) i32)]
!
scissorCall
	^ScissorCall ifNil: [ScissorCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_set_scissor' (i32 i32 i32 i32 i32) i32)]
!
endPassCall
	^EndPassCall ifNil: [EndPassCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_end_pass' (i32) i32)]
! !

!GPUPlatformFFI class methodsFor: 'submission'!
submitCall
	^SubmitCall ifNil: [SubmitCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_submit' (i32 i32) i32)]
!
fenceDoneCall
	^FenceDoneCall ifNil: [FenceDoneCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_fence_done' (i32) i32)]
!
fenceElapsedCall
	^FenceElapsedCall ifNil: [FenceElapsedCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_fence_elapsed' (i32) i64)]
!
waitFenceCall
	^WaitFenceCall ifNil: [WaitFenceCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_wait_fence' (i32) i32)]
! !

!GPUPlatformFFI class methodsFor: 'pass creation'!
swapchainCall
	^SwapchainCall ifNil: [SwapchainCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_acquire_swapchain' (i32 i32 writableBytesWithLength) i32)]
!
beginLoadCall
	^BeginLoadCall ifNil: [BeginLoadCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_begin_load' (i32 i32) i32)]
!
beginClearCall
	^BeginClearCall ifNil: [BeginClearCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_begin_clear' (i32 i32 f64 f64 f64 f64) i32)]
! !

!GPUPlatformFFI class methodsFor: 'transfers'!
uploadBufferCall
	^UploadBufferCall ifNil: [UploadBufferCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_upload_buffer' (i32 bytesWithLength u32) i32)]
!
uploadTextureCall
	^UploadTextureCall ifNil: [UploadTextureCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_upload_texture' (i32 bytesWithLength bytesWithLength) i32)]
!
downloadCall
	^DownloadCall ifNil: [DownloadCall := PlatformFFI bind:
		#(call 'platform' 'platform_gpu_download' (i32 bytesWithLength writableBytesWithLength) i32)]
!
regionFrom: integers
	"Do not silently truncate a Point/Rectangle component or accept coerced numerics."
	| bytes offset |
	bytes := ByteArray new: integers size * 4.
	offset := 1.
	integers do: [:v |
		(v class == SmallInteger and: [v between: -16r80000000 and: 16r7FFFFFFF]) ifFalse: [^nil].
		bytes uint32At: offset put: (v bitAnd: 16rFFFFFFFF).
		offset := offset + 4].
	^bytes
! !

!GPUPlatformFFI class methodsFor: 'owned shader compiler output'!
shaderOutputFrom: producer
	"One receipt and at most one producer invocation. False alone means no entry."
	<ffiSite>
	| receipt copy release status token count result offset page |
	receipt := ByteArray new: 16.
	copy := self ffiSite: #(call 'platform' 'platform_gpu_shader_copy' (u64 u64 writableBytesWithLength) i32).
	release := self ffiSite: #(call 'platform' 'platform_gpu_shader_release' (u64) i32).
	[
		status := producer value: receipt.
		status == false ifTrue: [^false].
		status = 1 ifFalse: [^GPUPrimitives fail: 'gpuCompileShader'].
		token := FFIWire uint64At: 1 in: receipt.
		count := FFIWire uint64At: 9 in: receipt.
		(token > 0 and: [count <= 16r7FFFFFFF8]) ifFalse: [^GPUPrimitives fail: 'gpuCompileShader'].
		result := ByteArray new: count.
		offset := 0.
		[offset < count] whileTrue: [
			page := 1048576 min: count - offset.
			(copy tryInvoke3: token with: offset with: {result. offset + 1. page}) = 1
				ifFalse: [^GPUPrimitives fail: 'gpuCompileShader'].
			offset := offset + page].
		^result
	] ensure: [
		"Read the receipt even if an unwind interrupted delivery of native status."
		token := FFIWire uint64At: 1 in: receipt.
		token = 0 ifFalse: [
			(release tryInvoke1: token) == false ifTrue: [FFIError signal: 'GPU shader output release refused']]]
! !
