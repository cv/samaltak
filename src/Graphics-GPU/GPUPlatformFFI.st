Object subclass: #GPUPlatformFFI
	instanceVariableNames: ''
	classVariableNames: 'ViewportCall ScissorCall EndPassCall SubmitCall FenceDoneCall FenceElapsedCall WaitFenceCall SwapchainCall BeginLoadCall BeginClearCall UploadBufferCall UploadTextureCall DownloadCall'
	package: 'Graphics-GPU'!

GPUPlatformFFI comment: 'Private binding cache for the hosted GPU facade. Bindings are symbolic and reprepare after a snapshot. Only false means the wrapper did not enter native code.'!

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

!GPUPlatformFFI class methodsFor: 'transfer buffers'!
isVector: anObject size: size
	^anObject class instSpec = VMConstants fVar and: [anObject basicSize = size]
!
transferBytesFor: anObject
	"The FFI borrows exact ByteArrays. Other byte and 32-bit word objects use
	a compatible little-endian staging copy on the hosted architectures."
	| cls count copy step |
	cls := anObject class.
	cls == ByteArray ifTrue: [^anObject].
	((cls isBytes or: [cls isWords]) and: [
		cls ~~ CompiledMethod and: [(cls inheritsFrom: CompiledMethod) not]]) ifFalse: [^nil].
	count := anObject basicSize.
	step := cls isWords ifTrue: [4] ifFalse: [1].
	copy := ByteArray new: count * step.
	step = 4
		ifTrue: [1 to: count do: [:i | copy uint32At: i * 4 - 3 put: (anObject basicAt: i)]]
		ifFalse: [1 to: count do: [:i | copy at: i put: (anObject basicAt: i)]].
	^copy
!
copyTransferBytes: bytes into: anObject
	anObject class isWords
		ifTrue: [1 to: anObject basicSize do: [:i | anObject basicAt: i put: (bytes uint32At: i * 4 - 3)]]
		ifFalse: [1 to: anObject basicSize do: [:i | anObject basicAt: i put: (bytes at: i)]]
! !
