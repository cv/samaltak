!SDL methodsFor: 'init'!
isMainThread
	<c: 'bool SDL_IsMainThread(void)'>
	^self notSimulated
! !

!SDLPlatform methodsFor: 'GPU FFI'!
ffiGpuOnMainThread
	<function>
	<returns: 'bool'>
	sdl isMainThread ifTrue: [^true].
	common setError: 'GPU calls require the SDL main thread'.
	^false
!
ffiGpuSetViewport: pass x: x y: y width: w height: h
	<function>
	<approvedFFI: 444 symbol: 'platform_gpu_set_viewport' arguments: #(1 6 6 6 6) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #x type: 'double'>
	<var: #y type: 'double'>
	<var: #w type: 'double'>
	<var: #h type: 'double'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu setViewport: pass x: x y: y width: w height: h) ifTrue: [1] ifFalse: [0]
!
ffiGpuSetScissor: pass x: x y: y width: w height: h
	<function>
	<approvedFFI: 445 symbol: 'platform_gpu_set_scissor' arguments: #(1 1 1 1 1) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu setScissor: pass x: x y: y width: w height: h) ifTrue: [1] ifFalse: [0]
!
ffiGpuEndPass: pass
	<function>
	<approvedFFI: 451 symbol: 'platform_gpu_end_pass' arguments: #(1) result: 1>
	<var: #pass type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu endPass: pass) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: 'GPU FFI - submission'!
ffiGpuSubmit: cmd fence: want
	"Failure -1, completed without fence 0, otherwise the fence handle."
	<function>
	<approvedFFI: 453 symbol: 'platform_gpu_submit' arguments: #(1 1) result: 1>
	<var: #cmd type: 'int32_t'>
	<var: #want type: 'int32_t'>
	<returns: 'int32_t'>
	| ok fence |
	self ffiGpuOnMainThread ifFalse: [^-1].
	(want ~= 0 and: [want ~= 1]) ifTrue: [
		common setError: 'bad GPU fence flag'.
		^-1].
	ok := self local: 'bool'.
	fence := gpu submit: cmd fence: want = 1 ok: ok.
	^ok value ifTrue: [fence] ifFalse: [-1]
!
ffiGpuFenceDone: fence
	<function>
	<approvedFFI: 455 symbol: 'platform_gpu_fence_done' arguments: #(1) result: 1>
	<var: #fence type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^-1].
	^gpu fenceDone: fence
!
ffiGpuFenceElapsed: fence
	<function>
	<approvedFFI: 459 symbol: 'platform_gpu_fence_elapsed' arguments: #(1) result: 3>
	<var: #fence type: 'int32_t'>
	<returns: 'int64_t'>
	self ffiGpuOnMainThread ifFalse: [^-2].
	^gpu fenceElapsed: fence
!
ffiGpuWaitFence: fence
	<function>
	<approvedFFI: 454 symbol: 'platform_gpu_wait_fence' arguments: #(1) result: 1>
	<var: #fence type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu waitFence: fence) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: 'GPU FFI - pass creation'!
ffiGpuAcquireSwapchain: cmd window: win into: out capacity: cap
	"Status -1 error, 0 no texture, 1 exact 12-byte LE record (handle, width, height)."
	<function>
	<approvedFFI: 442 symbol: 'platform_gpu_acquire_swapchain' arguments: #(1 1 9) result: 1>
	<var: #cmd type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| w h tex |
	self ffiGpuOnMainThread ifFalse: [^-1].
	cap ~= 12 ifTrue: [
		common setError: 'wrong GPU swapchain result capacity'.
		^-1].
	w := self local: 'int'.
	h := self local: 'int'.
	tex := gpu acquireSwapchain: cmd window: win width: w height: h.
	tex = 0 ifTrue: [^(common lastErrorString at: 0) = 0 ifTrue: [0] ifFalse: [-1]].
	self ffiGpuWriteU32: tex asUInt32 to: out.
	self ffiGpuWriteU32: w value asUInt32 to: out + 4.
	self ffiGpuWriteU32: h value asUInt32 to: out + 8.
	^1
!
ffiGpuWriteU32: word to: out
	<function>
	<var: #word type: 'uint32_t'>
	<var: #out type: 'uint8_t *'>
	<returns: 'void'>
	0 to: 3 do: [:i | out at: i put: ((word >> (i * 8)) bitAnd: 255) asUInt8]
!
ffiGpuBeginLoad: cmd target: tex
	<function>
	<approvedFFI: 443 symbol: 'platform_gpu_begin_load' arguments: #(1 1) result: 1>
	<var: #cmd type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	(gpu ffiCanBeginPass: cmd target: tex) ifFalse: [^0].
	^gpu beginPass: cmd target: tex clear: self null
!
ffiGpuBeginClear: cmd target: tex r: r g: g b: b a: a
	<function>
	<approvedFFI: 1443 symbol: 'platform_gpu_begin_clear' arguments: #(1 1 6 6 6 6) result: 1>
	<var: #cmd type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<var: #r type: 'double'>
	<var: #g type: 'double'>
	<var: #b type: 'double'>
	<var: #a type: 'double'>
	<returns: 'int32_t'>
	| rgba |
	self ffiGpuOnMainThread ifFalse: [^0].
	(gpu ffiCanBeginPass: cmd target: tex) ifFalse: [^0].
	rgba := self local: 'float[4]'.
	rgba at: 0 put: r.
	rgba at: 1 put: g.
	rgba at: 2 put: b.
	rgba at: 3 put: a.
	^gpu beginPass: cmd target: tex clear: rgba
! !

!SDLPlatform methodsFor: 'GPU FFI - transfers'!
ffiGpuUploadBuffer: buffer bytes: data count: n offset: off
	<function>
	<approvedFFI: 439 symbol: 'platform_gpu_upload_buffer' arguments: #(1 8 2) result: 1>
	<var: #buffer type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<var: #off type: 'uint32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	n > 16r80000000 ifTrue: [
		common setError: 'GPU upload exceeds transfer buffer capacity'.
		^0].
	^(gpu uploadBuffer: buffer data: data count: n asUInt32 offset: off) ifTrue: [1] ifFalse: [0]
!
ffiGpuReadI32: p
	<function>
	<var: #p type: 'const uint8_t *'>
	<returns: 'int32_t'>
	^((((p at: 0) asUInt32 bitOr: ((p at: 1) asUInt64 << 8))
		bitOr: ((p at: 2) asUInt64 << 16)) bitOr: ((p at: 3) asUInt64 << 24)) asInt32
!
ffiGpuUploadTexture: tex bytes: data count: n region: region size: regionSize
	"20-byte LE record: signed i32 x,y,width,height,bytesPerRow."
	<function>
	<approvedFFI: 440 symbol: 'platform_gpu_upload_texture' arguments: #(1 8 8) result: 1>
	<var: #tex type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<var: #region type: 'const uint8_t *'>
	<var: #regionSize type: 'uint64_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	regionSize ~= 20 ifTrue: [
		common setError: 'wrong GPU texture region size'.
		^0].
	^(gpu uploadTexture: tex data: data length: n
		x: (self ffiGpuReadI32: region) y: (self ffiGpuReadI32: region + 4)
		width: (self ffiGpuReadI32: region + 8) height: (self ffiGpuReadI32: region + 12)
		bytesPerRow: (self ffiGpuReadI32: region + 16)) ifTrue: [1] ifFalse: [0]
!
ffiGpuDownload: tex region: region size: regionSize into: out capacity: cap
	"16-byte LE record: signed i32 x,y,width,height. Transfer writes only the checked destination region."
	<function>
	<approvedFFI: 456 symbol: 'platform_gpu_download' arguments: #(1 8 9) result: 1>
	<var: #tex type: 'int32_t'>
	<var: #region type: 'const uint8_t *'>
	<var: #regionSize type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	regionSize ~= 16 ifTrue: [
		common setError: 'wrong GPU download region size'.
		^0].
	^(gpu download: tex x: (self ffiGpuReadI32: region) y: (self ffiGpuReadI32: region + 4)
		width: (self ffiGpuReadI32: region + 8) height: (self ffiGpuReadI32: region + 12)
		into: out length: cap) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: 'GPU FFI - devices and resources'!
ffiGpuCreateDevice: debug
	<function>
	<approvedFFI: 430 symbol: 'platform_gpu_create_device' arguments: #(1) result: 1>
	<var: #debug type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	(debug ~= 0 and: [debug ~= 1]) ifTrue: [
		common setError: 'bad GPU debug flag'.
		^0].
	^gpu createDevice: debug = 1
!
ffiGpuClaimWindow: dev window: win
	<function>
	<approvedFFI: 431 symbol: 'platform_gpu_claim_window' arguments: #(1 1) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu claimWindow: dev window: win) ifTrue: [1] ifFalse: [0]
!
ffiGpuSwapchainFormat: dev window: win
	<function>
	<approvedFFI: 432 symbol: 'platform_gpu_swapchain_format' arguments: #(1 1) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^gpu swapchainFormat: dev window: win
!
ffiGpuCreateTexture: dev width: w height: h format: format usage: usage
	<function>
	<approvedFFI: 435 symbol: 'platform_gpu_create_texture' arguments: #(1 1 1 1 1) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #format type: 'int32_t'>
	<var: #usage type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^gpu createTexture: dev width: w height: h format: format usage: usage
!
ffiGpuCreateSampler: dev linear: linear repeat: repeat
	<function>
	<approvedFFI: 436 symbol: 'platform_gpu_create_sampler' arguments: #(1 1 1) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #linear type: 'int32_t'>
	<var: #repeat type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	((linear ~= 0 and: [linear ~= 1]) or: [repeat ~= 0 and: [repeat ~= 1]]) ifTrue: [
		common setError: 'bad GPU sampler flags'.
		^0].
	^gpu createSampler: dev linear: linear = 1 repeat: repeat = 1
!
ffiGpuCreateBuffer: dev usage: usage size: size
	<function>
	<approvedFFI: 437 symbol: 'platform_gpu_create_buffer' arguments: #(1 1 2) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #usage type: 'int32_t'>
	<var: #size type: 'uint32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^gpu createBuffer: dev usage: usage size: size
!
ffiGpuRelease: h
	<function>
	<approvedFFI: 438 symbol: 'platform_gpu_release' arguments: #(1) result: 1>
	<var: #h type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu releaseHandle: h) ifTrue: [1] ifFalse: [0]
!
ffiGpuAcquireCommandBuffer: dev
	<function>
	<approvedFFI: 441 symbol: 'platform_gpu_acquire_command_buffer' arguments: #(1) result: 1>
	<var: #dev type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^gpu acquireCommandBuffer: dev
!
ffiGpuWaitIdle: dev
	<function>
	<approvedFFI: 458 symbol: 'platform_gpu_wait_idle' arguments: #(1) result: 1>
	<var: #dev type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	^(gpu waitIdle: dev) ifTrue: [1] ifFalse: [0]
!
ffiGpuShaderLanguage: dev
	<function>
	<approvedFFI: 460 symbol: 'platform_gpu_shader_language' arguments: #(1) result: 1>
	<var: #dev type: 'int32_t'>
	<returns: 'int32_t'>
	| language |
	self ffiGpuOnMainThread ifFalse: [^0].
	language := gpu shaderLanguage: dev.
	language isNull ifTrue: [^0].
	(libc strcmp: language with: 'msl') = 0 ifTrue: [^1].
	(libc strcmp: language with: 'glsl') = 0 ifTrue: [^2].
	common setError: 'unsupported GPU shader language'.
	^0
! !

!SDLPlatform methodsFor: 'GPU FFI - render bindings'!
ffiGpuBindPipeline: pass pipeline: pipeline
	<function>
	<approvedFFI: 446 symbol: 'platform_gpu_bind_pipeline' arguments: #(1 1) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #pipeline type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	(gpu ffiCanBindPipeline: pipeline to: pass) ifFalse: [^0].
	^(gpu bindPipeline: pass pipeline: pipeline) ifTrue: [1] ifFalse: [0]
!
ffiGpuBindVertexBuffer: pass slot: slot buffer: buf offset: off
	<function>
	<approvedFFI: 447 symbol: 'platform_gpu_bind_vertex_buffer' arguments: #(1 1 1 2) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #buf type: 'int32_t'>
	<var: #off type: 'uint32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	(slot < 0 or: [slot >= 16]) ifTrue: [
		common setError: 'bad vertex buffer slot'.
		^0].
	(gpu ffiCanBindBuffer: buf to: pass offset: off) ifFalse: [^0].
	^(gpu bindVertexBuffer: pass slot: slot buffer: buf offset: off) ifTrue: [1] ifFalse: [0]
!
ffiGpuBindTexture: pass slot: slot texture: tex sampler: sampler
	<function>
	<approvedFFI: 448 symbol: 'platform_gpu_bind_texture' arguments: #(1 1 1 1) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<var: #sampler type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	(slot < 0 or: [slot >= 16]) ifTrue: [
		common setError: 'bad fragment sampler slot'.
		^0].
	(gpu ffiCanBindTexture: tex sampler: sampler to: pass) ifFalse: [^0].
	^(gpu bindTexture: pass slot: slot texture: tex sampler: sampler) ifTrue: [1] ifFalse: [0]
!
ffiGpuPushUniforms: commandOrPass stage: stage slot: slot data: data count: n
	<function>
	<approvedFFI: 449 symbol: 'platform_gpu_push_uniforms' arguments: #(1 1 1 8) result: 1>
	<var: #commandOrPass type: 'int32_t'>
	<var: #stage type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	"SDL fixes the slot count; the Vulkan backend binds uniform sections of 4 KiB."
	(slot < 0 or: [slot >= 4 or: [n > 4096]]) ifTrue: [
		common setError: 'bad GPU uniform slot or byte count'.
		^0].
	^(gpu pushUniforms: commandOrPass stage: stage slot: slot data: data count: n asUInt32) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: 'GPU FFI - shaders'!
ffiGpuCompileShader: data count: n stage: stage receipt: receipt capacity: cap
	"One compiler call. Success publishes {ticket. byteCount} as two LE u64 words."
	<function>
	<approvedFFI: 461 symbol: 'platform_gpu_compile_shader' arguments: #(8 1 9) result: 1>
	<var: #data type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #stage type: 'int32_t'>
	<var: #receipt type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| source size code row |
	self ffiGpuOnMainThread ifFalse: [^-1].
	row := pagedOutput roomFor: receipt capacity: cap.
	row isNull ifTrue: [^-1].
	source := nativeCountedText copyTerminated: data size: n.
	source isNull ifTrue: [
		common setError: 'invalid or unavailable GPU shader source'.
		^-1].
	size := self local: 'size_t'.
	code := self cCoerce: (gpu compileShader: source stage: stage size: size) to: 'uint8_t *'.
	libc free: source.
	code isNull ifTrue: [^-1].
	(pagedOutput adopt: row bytes: code count: size value receipt: receipt) ifTrue: [^1].
	libc free: code.
	^-1
!
ffiPlatformCopyOutput: ticket offset: offset into: out capacity: cap
	<function>
	<approvedFFI: 1461 symbol: 'platform_output_copy' arguments: #(4 4 9) result: 1>
	<var: #ticket type: 'uint64_t'>
	<var: #offset type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	^(pagedOutput copy: ticket offset: offset into: out capacity: cap) ifTrue: [1] ifFalse: [0]
!
ffiPlatformReleaseOutput: ticket
	<function>
	<approvedFFI: 1462 symbol: 'platform_output_release' arguments: #(4) result: 1>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	^(pagedOutput release: ticket) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: 'GPU FFI - blit'!
ffiGpuBlit: cmd source: src destination: dst linear: linear rects: wire size: n
	"Exact 32-byte LE record: {src X,Y,W,H; dst X,Y,W,H}, all i32."
	<function>
	<approvedFFI: 452 symbol: 'platform_gpu_blit' arguments: #(1 1 1 1 8) result: 1>
	<var: #cmd type: 'int32_t'>
	<var: #src type: 'int32_t'>
	<var: #dst type: 'int32_t'>
	<var: #linear type: 'int32_t'>
	<var: #wire type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| sr dr |
	self ffiGpuOnMainThread ifFalse: [^0].
	(n ~= 32 or: [linear ~= 0 and: [linear ~= 1]]) ifTrue: [
		common setError: 'invalid GPU blit record'.
		^0].
	sr := self local: 'int32_t[4]'.
	dr := self local: 'int32_t[4]'.
	0 to: 3 do: [:i |
		sr at: i put: (self ffiGpuReadI32: wire + (i * 4)).
		dr at: i put: (self ffiGpuReadI32: wire + (i * 4 + 16))].
	(gpu ffiCanBlit: cmd source: src rect: sr destination: dst rect: dr) ifFalse: [^0].
	^(gpu blit: cmd source: src rect: sr destination: dst rect: dr linear: linear = 1) ifTrue: [1] ifFalse: [0]
! !

!SDLPlatform methodsFor: 'GPU FFI - shader resources'!
ffiGpuCreateShader: dev source: data size: n config: config size: cap
	"Source is GLSL/MSL text or SPIR-V bytes. Config is six LE i32 words
	(kind, stage, samplers, uniforms, storage buffers, storage textures), then the counted entry name."
	<function>
	<approvedFFI: 433 symbol: 'platform_gpu_create_shader' arguments: #(1 8 8) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #data type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #config type: 'const uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| kind stage ns nu nb nt source entry result |
	self ffiGpuOnMainThread ifFalse: [^0].
	cap < 24 ifTrue: [
		common setError: 'wrong GPU shader record size'.
		^0].
	kind := self ffiGpuReadI32: config.
	stage := self ffiGpuReadI32: config + 4.
	ns := self ffiGpuReadI32: config + 8.
	nu := self ffiGpuReadI32: config + 12.
	nb := self ffiGpuReadI32: config + 16.
	nt := self ffiGpuReadI32: config + 20.
	(kind < 0 or: [kind > 1 or: [stage < 0 or: [stage > 1 or: [
		ns < 0 or: [ns > 16 or: [nu < 0 or: [nu > 4 or: [
			nb < 0 or: [nb > 8 or: [nt < 0 or: [nt > 8]]]]]]]]]]]) ifTrue: [
		common setError: 'invalid GPU shader kind, stage, or resource counts'.
		^0].
	entry := nativeCountedText copyTerminated: config + 24 size: cap - 24.
	entry isNull ifTrue: [
		common setError: 'invalid or unavailable GPU shader entry name'.
		^0].
	source := self null.
	kind = 0
		ifTrue: [source := nativeCountedText copyTerminated: data size: n]
		ifFalse: [
			(n >= 20 and: [(n bitAnd: 3) = 0 and: [(self ffiGpuReadI32: data) = 16r07230203]]) ifTrue: [
				"Borrowed spans may be unaligned. Vulkan requires aligned SPIR-V words."
				source := libc malloc: n.
				source notNull ifTrue: [libc memcpy: source from: data size: n]]].
	source isNull ifTrue: [
		libc free: entry.
		common setError: 'invalid or unavailable GPU shader source'.
		^0].
	result := kind = 0
		ifTrue: [gpu createShader: dev source: source entry: entry stage: stage samplers: ns uniformBuffers: nu storageBuffers: nb storageTextures: nt]
		ifFalse: [gpu createShader: dev spirv: (self cCoerce: source to: 'const uint8_t *') size: n entry: entry stage: stage
			samplers: ns uniformBuffers: nu storageBuffers: nb storageTextures: nt].
	libc free: source.
	libc free: entry.
	^result
!
ffiGpuCreatePipeline: dev vertex: vs fragment: fs config: config size: n
	"LE i32 {stride, primitive, blend, targetFormat} followed by up to sixteen {attributeFormat, offset} pairs."
	<function>
	<approvedFFI: 434 symbol: 'platform_gpu_create_pipeline' arguments: #(1 1 1 8) result: 1>
	<var: #dev type: 'int32_t'>
	<var: #vs type: 'int32_t'>
	<var: #fs type: 'int32_t'>
	<var: #config type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| attrs count stride prim blend format |
	self ffiGpuOnMainThread ifFalse: [^0].
	(n < 16 or: [n > 144 or: [(n bitAnd: 7) ~= 0]]) ifTrue: [
		common setError: 'wrong GPU pipeline record size'.
		^0].
	stride := self ffiGpuReadI32: config.
	prim := self ffiGpuReadI32: config + 4.
	blend := self ffiGpuReadI32: config + 8.
	format := self ffiGpuReadI32: config + 12.
	(stride < 0 or: [blend < 0 or: [blend > 2]]) ifTrue: [
		common setError: 'invalid GPU pipeline stride or blend mode'.
		^0].
	count := ((n - 16) quo: 8) asInt32.
	attrs := self local: 'pf_vattr[16]'.
	0 to: count - 1 do: [:i |
		(attrs at: i) format: (self ffiGpuReadI32: config + (16 + (i * 8))).
		(attrs at: i) offset: (self ffiGpuReadI32: config + (20 + (i * 8)))].
	(gpu ffiCanCreatePipeline: dev vertex: vs fragment: fs stride: stride attributes: attrs count: count) ifFalse: [^0].
	^gpu createPipeline: dev vertexShader: vs fragmentShader: fs stride: stride attributes: attrs count: count
		primitive: prim blend: blend targetFormat: format
! !

!SDLPlatform methodsFor: 'GPU FFI - drawing'!
ffiGpuDrawEligibility: pass count: n first: first
	"Diagnostic procedural certification; not a requirement for drawing."
	<function>
	<approvedFFI: 1450 symbol: 'platform_gpu_draw_eligibility' arguments: #(1 1 1) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<var: #first type: 'int32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^-1].
	^gpu ffiDrawEligibility: pass count: n first: first
!
ffiGpuDraw: pass count: n first: first
	"Draw in a compatible active pass, including swapchains and resource-bound pipelines."
	<function>
	<approvedFFI: 450 symbol: 'platform_gpu_draw' arguments: #(1 2 2) result: 1>
	<var: #pass type: 'int32_t'>
	<var: #n type: 'uint32_t'>
	<var: #first type: 'uint32_t'>
	<returns: 'int32_t'>
	self ffiGpuOnMainThread ifFalse: [^0].
	(gpu ffiBoundDrawPass: pass) isNull ifTrue: [^0].
	(n ~= 0 and: [first asUInt64 + (n - 1) asUInt64 > 16rFFFFFFFF asUInt64]) ifTrue: [
		common setError: 'GPU draw vertex range overflows uint32'.
		^0].
	^(gpu draw: pass vertices: n asInt32 first: first asInt32) ifTrue: [1] ifFalse: [0]
! !
