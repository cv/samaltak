VMPlatformModule subclass: #PlatformGPU
	instanceVariableNames: 'objs logAdapter watches nwatches npending watchLock watchCond watcherStarted drawBindingEpoch'
	classVariableNames: 'K_BUF K_CMD K_DEV K_FENCE K_PASS K_PIPE K_SAMPLER K_SHADER K_SWAP K_TEX LOG_ERROR_SIZE MAX_CLAIMS'
	package: 'VM-Platform'!

PlatformGPU comment: 'A thin SDL_GPU wrapper with handles (one table for all kinds; dev = the handle of the object''s device).

Uploads are batched: each device keeps one open copy pass on its own command buffer and one growing transfer buffer; the batch is submitted right before the next gpuSubmit/gpuDownload, so uploads execute before any command buffer submitted after them.

Fence timing: a watcher thread polls the pending fences every 200 µs while any are pending and stamps when each completed, so callers learn the submit-to-completion time of a fence without blocking or spinning on the VM thread. Its entries (watches) are indexed by fence handle and guarded by watchLock.'!

!PlatformGPU class methodsFor: 'declaring'!
declarations
	^#((objs 'pf_table[1]') (logAdapter FFISDLLogAdapter)
		(watches 'fence_watch *') (nwatches int32_t) (npending int32_t) (watchLock 'pthread_mutex_t[1]') (watchCond 'pthread_cond_t[1]')
		(watcherStarted bool) (drawBindingEpoch int32_t 1))
!
initialize
	K_DEV := 1.
	K_SHADER := 2.
	K_PIPE := 3.
	K_TEX := 4.
	K_SAMPLER := 5.
	K_BUF := 6.
	K_CMD := 7.
	K_PASS := 8.
	K_FENCE := 9.
	K_SWAP := 10.
	MAX_CLAIMS := 16.
	LOG_ERROR_SIZE := 2048
! !

!PlatformGPU methodsFor: 'private'!
get: h kind: kind what: what
	"The object of handle h of kind; NULL (and the error set) if it is none."
	<function>
	| o |
	o := common table: objs at: h kind: kind.
	o isNull ifTrue: [common setError: 'bad %s handle %d' with: what with: h].
	^o
!
deviceOf: o
	<function>
	<returns: 'gpu_dev *'>
	^(common table: objs at: o dev kind: K_DEV) ptr
!
device: h
	<function>
	<returns: 'gpu_dev *'>
	| o |
	o := self get: h kind: K_DEV what: 'device'.
	o isNull ifTrue: [^self null].
	^o ptr
!
target: tex
	"A texture or swapchain texture."
	<function>
	| o |
	o := common table: objs at: tex kind: -1.
	(o isNull or: [o kind ~= K_TEX and: [o kind ~= K_SWAP]]) ifTrue: [
		common setError: 'bad texture handle %d' with: tex.
		^self null].
	^o
!
pass: h
	<function>
	<returns: 'SDL_GPURenderPass *'>
	| o |
	o := self get: h kind: K_PASS what: 'render pass'.
	o isNull ifTrue: [^self null].
	^o ptr
!
sdlFail: what
	"Set the error from SDL (or the log); answer 0."
	<function>
	| e captured |
	e := sdl getError.
	(e at: 0) = 0 ifTrue: [
		captured := self local: 'char[LOG_ERROR_SIZE]'.
		logAdapter copyShaderError: captured size: LOG_ERROR_SIZE.
		e := captured].
	common setError: '%s: %s' with: what with: e.
	^0
!
sdlFormat: f
	<function>
	^f caseOf: {
		[PF_TEX_R8] -> [sdlGpu SDL_GPU_TEXTUREFORMAT_R8_UNORM].
		[PF_TEX_RGBA8] -> [sdlGpu SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM].
		[PF_TEX_BGRA8] -> [sdlGpu SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM]} otherwise: [sdlGpu SDL_GPU_TEXTUREFORMAT_INVALID]
!
vertexFormat: f
	<function>
	^f caseOf: {
		[PF_VA_FLOAT] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_FLOAT].
		[PF_VA_FLOAT2] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2].
		[PF_VA_FLOAT3] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3].
		[PF_VA_FLOAT4] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4].
		[PF_VA_UBYTE4_NORM] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM].
		[PF_VA_UBYTE4] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4].
		[PF_VA_UINT] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_UINT].
		[PF_VA_INT] -> [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_INT]} otherwise: [sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_INVALID]
!
primitiveType: prim
	^prim caseOf: {
		[PF_PRIM_TRIANGLES] -> [sdlGpu SDL_GPU_PRIMITIVETYPE_TRIANGLELIST].
		[PF_PRIM_TRIANGLE_STRIP] -> [sdlGpu SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP].
		[PF_PRIM_LINES] -> [sdlGpu SDL_GPU_PRIMITIVETYPE_LINELIST].
		[PF_PRIM_LINE_STRIP] -> [sdlGpu SDL_GPU_PRIMITIVETYPE_LINESTRIP]} otherwise: [sdlGpu SDL_GPU_PRIMITIVETYPE_POINTLIST]
!
add: kind pointer: ptr device: dev
	"A new handle of kind for ptr on device dev."
	| h |
	h := common table: objs add: kind pointer: ptr.
	(objs v + h) dev: dev.
	^h
!
isPassOrSwapchain: h of: cmd
	^((objs v + h) kind = K_SWAP or: [(objs v + h) kind = K_PASS]) and: [(objs v + h) i = cmd]
! !

!PlatformGPU methodsFor: 'devices'!
init
	"From platform_interface_init."
	<function>
	posixThreads mutexInit: watchLock attributes: self null.
	posixThreads condInit: watchCond attributes: self null
!
bytesPerPixel: format
	<export>
	^format = PF_TEX_R8 ifTrue: [1] ifFalse: [4]
!
createDevice: debug
	<export>
	| d h |
	platform init.
	"SDL_CreateGPUDevice needs the video subsystem"
	windows videoInit ifFalse: [^0].
	logAdapter enableShaderCapture ifFalse: [
		common setError: 'out of memory installing SDL log capture'.
		^0].
	d := self cCoerce: (libc calloc: 1 size: (self sizeof: 'gpu_dev')) to: 'gpu_dev *'.
	d isNull ifTrue: [
		common setError: 'out of memory'.
		^0].
	d dev: (sdlGpu createDevice: host shaderFormats debug: debug name: self null).
	d dev isNull ifTrue: [
		libc free: d.
		^self sdlFail: 'SDL_CreateGPUDevice'].
	h := common table: objs add: K_DEV pointer: d.
	(objs v + h) dev: h.
	^h
!
shaderLanguage: dev
	"What source createShader: takes on dev: 'msl' (Metal), 'glsl' (SPIR-V devices: compiled by the host), NULL on error."
	<export>
	| d f |
	d := self device: dev.
	d isNull ifTrue: [^self null].
	f := sdlGpu shaderFormats: d dev.
	(f bitAnd: sdlGpu SDL_GPU_SHADERFORMAT_MSL) ~= 0 ifTrue: [^'msl'].
	(f bitAnd: sdlGpu SDL_GPU_SHADERFORMAT_SPIRV) ~= 0 ifTrue: [^'glsl'].
	common setError: 'the device takes neither MSL nor SPIR-V shaders'.
	^self null
!
claimWindow: dev window: win
	<export>
	<var: #slot type: 'int'>
	| d w slot mode |
	d := self device: dev.
	w := windows sdlWindow: win.
	(d isNull or: [w isNull]) ifTrue: [^false].
	slot := -1.
	0 to: MAX_CLAIMS - 1 do: [:i |
		(d claimed at: i) = win ifTrue: [^true].
		((d claimed at: i) = 0 and: [slot < 0]) ifTrue: [slot := i]].
	slot < 0 ifTrue: [
		common setError: 'too many claimed windows'.
		^false].
	(sdlGpu claimWindow: d dev window: w) ifFalse: [
		self sdlFail: 'SDL_ClaimWindowForGPUDevice'.
		^false].
	"Never block the VM thread on vsync: Metal offers IMMEDIATE (no display sync; the macOS compositor still prevents visible tearing)."
	mode := sdlGpu SDL_GPU_PRESENTMODE_VSYNC.
	(sdlGpu windowSupportsPresentMode: d dev window: w mode: sdlGpu SDL_GPU_PRESENTMODE_MAILBOX)
		ifTrue: [mode := sdlGpu SDL_GPU_PRESENTMODE_MAILBOX]
		ifFalse: [
			(sdlGpu windowSupportsPresentMode: d dev window: w mode: sdlGpu SDL_GPU_PRESENTMODE_IMMEDIATE) ifTrue: [
				mode := sdlGpu SDL_GPU_PRESENTMODE_IMMEDIATE]].
	(sdlGpu setSwapchainParameters: d dev window: w composition: sdlGpu SDL_GPU_SWAPCHAINCOMPOSITION_SDR mode: mode) ifFalse: [
		self sdlFail: 'SDL_SetGPUSwapchainParameters'.
		^false].
	d claimed at: slot put: win.
	^true
!
windowClosing: win
	"Release window win from the devices that claimed it."
	<export>
	| d |
	1 to: objs n - 1 do: [:h |
		(objs v + h) kind = K_DEV ifTrue: [
			d := self cCoerce: (objs v + h) ptr to: 'gpu_dev *'.
			0 to: MAX_CLAIMS - 1 do: [:i |
				(d claimed at: i) = win ifTrue: [
					sdlGpu waitForIdle: d dev.
					sdlGpu releaseWindow: d dev window: (windows sdlWindow: win).
					d claimed at: i put: 0]]]]
!
swapchainFormat: dev window: win
	"PF_TEX_*, 0 on error."
	<export>
	| d w f |
	d := self device: dev.
	w := windows sdlWindow: win.
	(d isNull or: [w isNull]) ifTrue: [^0].
	f := sdlGpu swapchainTextureFormat: d dev window: w.
	PF_TEX_R8 to: PF_TEX_BGRA8 do: [:i | (self sdlFormat: i) = f ifTrue: [^i]].
	common setError: 'unsupported swapchain format %d' with: f asInt32.
	^0
!
waitIdle: dev
	<export>
	| d |
	d := self device: dev.
	d isNull ifTrue: [^false].
	self uploadFlush: d.
	(sdlGpu waitForIdle: d dev) ifTrue: [^true].
	self sdlFail: 'SDL_WaitForGPUIdle'.
	^false
! !

!PlatformGPU methodsFor: 'resources'!
createShader: dev source: source entry: entry stage: stage samplers: samplers uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
	"source is in the device's shaderLanguage: MSL, or GLSL compiled to SPIR-V by the host (entry is then main)."
	<export>
	| d spirv size h |
	d := self device: dev.
	d isNull ifTrue: [^0].
	((sdlGpu shaderFormats: d dev) bitAnd: sdlGpu SDL_GPU_SHADERFORMAT_MSL) ~= 0 ifTrue: [
		^self createShader: d handle: dev code: (self cCoerce: source to: 'Uint8 *') size: (libc strlen: source)
			format: sdlGpu SDL_GPU_SHADERFORMAT_MSL entry: entry stage: stage samplers: samplers
			uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures].
	size := self local: 'size_t'.
	spirv := host compileShader: source stage: stage size: size.
	spirv isNull ifTrue: [^0].
	h := self createShader: d handle: dev code: spirv size: size value format: sdlGpu SDL_GPU_SHADERFORMAT_SPIRV
		entry: entry stage: stage samplers: samplers
		uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures.
	libc free: spirv.
	^h
!
createShader: dev spirv: code size: n entry: entry stage: stage samplers: samplers uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
	"A shader from SPIR-V already compiled (compileShader:stage:size:), on a device that takes SPIR-V; no compiler runs."
	<export>
	<var: #code type: 'const uint8_t *'>
	| d |
	d := self device: dev.
	d isNull ifTrue: [^0].
	((sdlGpu shaderFormats: d dev) bitAnd: sdlGpu SDL_GPU_SHADERFORMAT_SPIRV) = 0 ifTrue: [
		common setError: 'the device does not take SPIR-V'.
		^0].
	^self createShader: d handle: dev code: (self cCoerce: code to: 'Uint8 *') size: n format: sdlGpu SDL_GPU_SHADERFORMAT_SPIRV
		entry: entry stage: stage samplers: samplers
		uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
!
compileShader: source stage: stage size: sizeOut
	"SPIR-V compiled from GLSL source by the host (malloc'd, its size in sizeOut), to keep and give createShader:spirv:...; NULL with the compiler's log as the error, or where GLSL is not compiled (macOS)."
	<export>
	^host compileShader: source stage: stage size: sizeOut
!
createShader: d handle: dev code: code size: n format: format entry: entry stage: stage samplers: samplers uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
	<var: #d type: 'gpu_dev *'>
	<var: #code type: 'Uint8 *'>
	<var: #format type: 'SDL_GPUShaderFormat'>
	| ci s h |
	ci := self local: 'SDL_GPUShaderCreateInfo'.
	ci code_size: n.
	ci code: code.
	ci format: format.
	ci entrypoint: entry.
	ci stage: (stage = PF_STAGE_FRAGMENT ifTrue: [sdlGpu SDL_GPU_SHADERSTAGE_FRAGMENT] ifFalse: [sdlGpu SDL_GPU_SHADERSTAGE_VERTEX]).
	ci num_samplers: samplers.
	ci num_storage_textures: storageTextures.
	ci num_storage_buffers: storageBuffers.
	ci num_uniform_buffers: uniformBuffers.
	sdl clearError.
	logAdapter clearShaderError.
	s := sdlGpu createShader: d dev info: ci.
	s isNull ifTrue: [^self sdlFail: 'SDL_CreateGPUShader'].
	h := self add: K_SHADER pointer: s device: dev.
	(objs v + h) i: (stage = PF_STAGE_FRAGMENT ifTrue: [PF_STAGE_FRAGMENT] ifFalse: [PF_STAGE_VERTEX]).
	"Only pipelines with no declared shader resources are eligible for a checked procedural draw."
	(objs v + h) w: ((samplers = 0 and: [uniformBuffers = 0 and: [storageBuffers = 0 and: [storageTextures = 0]]])
		ifTrue: [1] ifFalse: [0]).
	^h
!
createPipeline: dev vertexShader: vs fragmentShader: fs stride: stride attributes: attrs count: nattrs primitive: prim blend: blend targetFormat: targetFormat
	"Attribute i becomes location i in vertex buffer slot 0."
	<export>
	| d v f va vb ct bs ci p procedural h |
	d := self device: dev.
	v := self get: vs kind: K_SHADER what: 'vertex shader'.
	f := self get: fs kind: K_SHADER what: 'fragment shader'.
	(d isNull or: [v isNull or: [f isNull]]) ifTrue: [^0].
	(nattrs < 0 or: [nattrs > 16]) ifTrue: [
		common setError: 'bad attribute count'.
		^0].
	(self sdlFormat: targetFormat) = sdlGpu SDL_GPU_TEXTUREFORMAT_INVALID ifTrue: [
		common setError: 'bad target format %d' with: targetFormat.
		^0].
	(prim < 0 or: [prim > PF_PRIM_POINTS]) ifTrue: [
		common setError: 'bad primitive type %d' with: prim.
		^0].
	va := self local: 'SDL_GPUVertexAttribute[16]'.
	0 to: nattrs - 1 do: [:i |
		(va at: i) location: i.
		(va at: i) buffer_slot: 0.
		(va at: i) format: (self vertexFormat: (attrs at: i) format).
		(va at: i) offset: (attrs at: i) offset.
		(va at: i) format = sdlGpu SDL_GPU_VERTEXELEMENTFORMAT_INVALID ifTrue: [
			common setError: 'bad vertex format %d' with: (attrs at: i) format.
			^0]].
	vb := self local: 'SDL_GPUVertexBufferDescription'.
	vb slot: 0.
	vb pitch: stride.
	vb input_rate: sdlGpu SDL_GPU_VERTEXINPUTRATE_VERTEX.
	ct := self local: 'SDL_GPUColorTargetDescription'.
	ct format: (self sdlFormat: targetFormat).
	blend ~= PF_BLEND_NONE ifTrue: [
		bs := ct fieldAddress: #blend_state.
		bs src_color_blendfactor: (blend = PF_BLEND_ALPHA ifTrue: [sdlGpu SDL_GPU_BLENDFACTOR_SRC_ALPHA] ifFalse: [sdlGpu SDL_GPU_BLENDFACTOR_ONE]).
		bs dst_color_blendfactor: sdlGpu SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA.
		bs color_blend_op: sdlGpu SDL_GPU_BLENDOP_ADD.
		bs src_alpha_blendfactor: sdlGpu SDL_GPU_BLENDFACTOR_ONE.
		bs dst_alpha_blendfactor: sdlGpu SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA.
		bs alpha_blend_op: sdlGpu SDL_GPU_BLENDOP_ADD.
		bs enable_blend: true].
	ci := self local: 'SDL_GPUGraphicsPipelineCreateInfo'.
	ci vertex_shader: v ptr.
	ci fragment_shader: f ptr.
	ci vertex_input_state vertex_buffer_descriptions: vb.
	ci vertex_input_state num_vertex_buffers: (nattrs ~= 0 ifTrue: [1] ifFalse: [0]).
	ci vertex_input_state vertex_attributes: va.
	ci vertex_input_state num_vertex_attributes: nattrs.
	ci primitive_type: (self primitiveType: prim).
	ci rasterizer_state fill_mode: sdlGpu SDL_GPU_FILLMODE_FILL.
	ci rasterizer_state cull_mode: sdlGpu SDL_GPU_CULLMODE_NONE.
	ci target_info color_target_descriptions: ct.
	ci target_info num_color_targets: 1.
	p := sdlGpu createGraphicsPipeline: d dev info: ci.
	p isNull ifTrue: [^self sdlFail: 'SDL_CreateGPUGraphicsPipeline'].
	procedural := nattrs = 0 and: [v dev = dev and: [f dev = dev and: [
		v i = PF_STAGE_VERTEX and: [f i = PF_STAGE_FRAGMENT and: [v w = 1 and: [f w = 1]]]]]].
	h := self add: K_PIPE pointer: p device: dev.
	h > 0 ifTrue: [
		(objs v + h) fmt: targetFormat.
		(objs v + h) w: (procedural ifTrue: [1] ifFalse: [0])].
	^h
!
createTexture: dev width: w height: h format: format usage: usage
	"usage: PF_TEXUSE_* bits."
	<export>
	| d ci t th o |
	d := self device: dev.
	d isNull ifTrue: [^0].
	(w <= 0 or: [h <= 0 or: [(self sdlFormat: format) = sdlGpu SDL_GPU_TEXTUREFORMAT_INVALID or: [(usage bitAnd: 3) = 0]]]) ifTrue: [
		common setError: 'bad texture parameters'.
		^0].
	ci := self local: 'SDL_GPUTextureCreateInfo'.
	ci type: sdlGpu SDL_GPU_TEXTURETYPE_2D.
	ci format: (self sdlFormat: format).
	ci usage: (((usage bitAnd: PF_TEXUSE_SAMPLER) ~= 0 ifTrue: [sdlGpu SDL_GPU_TEXTUREUSAGE_SAMPLER] ifFalse: [0])
		bitOr: ((usage bitAnd: PF_TEXUSE_COLOR_TARGET) ~= 0 ifTrue: [sdlGpu SDL_GPU_TEXTUREUSAGE_COLOR_TARGET] ifFalse: [0])).
	ci width: w.
	ci height: h.
	ci layer_count_or_depth: 1.
	ci num_levels: 1.
	t := sdlGpu createTexture: d dev info: ci.
	t isNull ifTrue: [^self sdlFail: 'SDL_CreateGPUTexture'].
	th := common table: objs add: K_TEX pointer: t.
	o := objs v + th.
	o dev: dev.
	o w: w.
	o h: h.
	o fmt: format.
	o i: usage.
	^th
!
createSampler: dev linear: linear repeat: repeat
	<export>
	| d f a ci s |
	d := self device: dev.
	d isNull ifTrue: [^0].
	f := linear ifTrue: [sdlGpu SDL_GPU_FILTER_LINEAR] ifFalse: [sdlGpu SDL_GPU_FILTER_NEAREST].
	a := repeat ifTrue: [sdlGpu SDL_GPU_SAMPLERADDRESSMODE_REPEAT] ifFalse: [sdlGpu SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE].
	ci := self local: 'SDL_GPUSamplerCreateInfo'.
	ci min_filter: f.
	ci mag_filter: f.
	ci mipmap_mode: sdlGpu SDL_GPU_SAMPLERMIPMAPMODE_NEAREST.
	ci address_mode_u: a.
	ci address_mode_v: a.
	ci address_mode_w: a.
	s := sdlGpu createSampler: d dev info: ci.
	s isNull ifTrue: [^self sdlFail: 'SDL_CreateGPUSampler'].
	^self add: K_SAMPLER pointer: s device: dev
!
createBuffer: dev usage: usage size: size
	"usage: PF_BUFUSE_VERTEX."
	<export>
	| d ci b h |
	d := self device: dev.
	d isNull ifTrue: [^0].
	(usage ~= PF_BUFUSE_VERTEX or: [size = 0]) ifTrue: [
		common setError: 'bad buffer parameters'.
		^0].
	ci := self local: 'SDL_GPUBufferCreateInfo'.
	ci usage: sdlGpu SDL_GPU_BUFFERUSAGE_VERTEX.
	ci size: size.
	b := sdlGpu createBuffer: d dev info: ci.
	b isNull ifTrue: [^self sdlFail: 'SDL_CreateGPUBuffer'].
	h := self add: K_BUF pointer: b device: dev.
	(objs v + h) i: size.
	^h
!
textureSize: tex width: w height: h format: format
	<export>
	| o |
	o := self target: tex.
	o isNull ifTrue: [^false].
	w value: o w.
	h value: o h.
	format value: o fmt.
	^true
! !

!PlatformGPU methodsFor: 'uploads'!
uploadFlush: d
	"Submit the device's batch of uploads."
	<function>
	d upCmd isNull ifTrue: [^self].
	sdlGpu endCopyPass: d upPass.
	sdlGpu submitCommandBuffer: d upCmd.
	d upCmd: self null.
	d upPass: self null.
	d upUsed: 0
!
uploadReserve: d bytes: n offset: off
	"Map n bytes of the batch transfer buffer at off; the caller fills them, unmaps the buffer and records the copy on d upPass."
	<function>
	<var: #cap type: 'uint32_t'>
	| need cap ci p |
	"The rounded allocation is grown by powers of two in uint32_t; never wrap either size or cursor."
	n > 16r80000000 ifTrue: [
		common setError: 'GPU upload exceeds transfer buffer capacity'.
		^self null].
	need := (n + 15) bitAnd: 15 bitInvert32.
	d upUsed asUInt64 + need > d upCap ifTrue: [
		self uploadFlush: d.
		need > d upCap ifTrue: [
			cap := 16r400000.
			[cap < need] whileTrue: [cap := (cap asUInt64 << 1) asUInt32].
			d upTb notNull ifTrue: [sdlGpu releaseTransferBuffer: d dev buffer: d upTb].
			ci := self local: 'SDL_GPUTransferBufferCreateInfo'.
			ci usage: sdlGpu SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD.
			ci size: cap.
			d upTb: (sdlGpu createTransferBuffer: d dev info: ci).
			d upCap: (d upTb notNull ifTrue: [cap] ifFalse: [0]).
			d upTb isNull ifTrue: [
				self sdlFail: 'SDL_CreateGPUTransferBuffer'.
				^self null]]].
	d upCmd isNull ifTrue: [
		d upCmd: (sdlGpu acquireCommandBuffer: d dev).
		d upCmd isNull ifTrue: [
			self sdlFail: 'SDL_AcquireGPUCommandBuffer'.
			^self null].
		d upPass: (sdlGpu beginCopyPass: d upCmd)].
	"cycle at the start of a batch: the previous batch may still be in flight"
	p := self cCoerce: (sdlGpu mapTransferBuffer: d dev buffer: d upTb cycle: d upUsed = 0) to: 'uint8_t *'.
	p isNull ifTrue: [
		self sdlFail: 'SDL_MapGPUTransferBuffer'.
		^self null].
	off value: d upUsed.
	d upUsed: d upUsed + need.
	^p + off value
!
uploadBuffer: buf data: data count: n offset: dstOffset
	<var: #data type: 'const void *'>
	<export>
	| o d off p src dst |
	o := self get: buf kind: K_BUF what: 'buffer'.
	o isNull ifTrue: [^false].
	n = 0 ifTrue: [^true].
	dstOffset asUInt64 + n > o i asUInt64 ifTrue: [
		common setError: 'upload out of buffer bounds'.
		^false].
	d := self deviceOf: o.
	off := self local: 'uint32_t'.
	p := self uploadReserve: d bytes: n offset: off.
	p isNull ifTrue: [^false].
	libc memcpy: p from: data size: n.
	sdlGpu unmapTransferBuffer: d dev buffer: d upTb.
	src := self local: 'SDL_GPUTransferBufferLocation'.
	src transfer_buffer: d upTb.
	src offset: off value.
	dst := self local: 'SDL_GPUBufferRegion'.
	dst buffer: o ptr.
	dst offset: dstOffset.
	dst size: n.
	sdlGpu uploadToBuffer: d upPass source: src destination: dst cycle: false.
	^true
!
uploadTexture: tex data: data length: len x: x y: y width: w height: h bytesPerRow: bytesPerRow
	<var: #data type: 'const void *'>
	<export>
	| o row d off p src dst |
	o := self get: tex kind: K_TEX what: 'texture'.
	o isNull ifTrue: [^false].
	row := w asUInt64 * (self bytesPerPixel: o fmt) asUInt64.
	(x < 0 or: [y < 0 or: [w <= 0 or: [h <= 0 or: [x asInt64 + w > o w or: [y asInt64 + h > o h
		or: [bytesPerRow <= 0 or: [row * h asUInt64 > 16r80000000
		or: [bytesPerRow asUInt64 < row or: [len < (((h - 1) asUInt64 * bytesPerRow asUInt64) + row)]]]]]]]]]) ifTrue: [
			common setError: 'bad texture upload region'.
			^false].
	d := self deviceOf: o.
	off := self local: 'uint32_t'.
	p := self uploadReserve: d bytes: (row * h asUInt64) asUInt32 offset: off.
	p isNull ifTrue: [^false].
	bytesPerRow asUInt64 = row
		ifTrue: [libc memcpy: p from: data size: row * h asUInt64]
		ifFalse: [
			0 to: h - 1 do: [:r |
				libc memcpy: p + (r asUInt64 * row) from: (self cCoerce: data to: 'uint8_t *') + (r asUInt64 * bytesPerRow asUInt64) size: row]].
	sdlGpu unmapTransferBuffer: d dev buffer: d upTb.
	src := self local: 'SDL_GPUTextureTransferInfo'.
	src transfer_buffer: d upTb.
	src offset: off value.
	src pixels_per_row: w.
	src rows_per_layer: h.
	dst := self local: 'SDL_GPUTextureRegion'.
	dst texture: o ptr.
	dst x: x.
	dst y: y.
	dst w: w.
	dst h: h.
	dst d: 1.
	sdlGpu uploadToTexture: d upPass source: src destination: dst cycle: false.
	^true
!
download: tex x: x y: y width: w height: h into: dst length: dstLen
	"Synchronous; BGRA8 is converted to RGBA8."
	<var: #dst type: 'void *'>
	<export>
	| o n d ci cb cp region info f p s t pixel v |
	o := self get: tex kind: K_TEX what: 'texture'.
	o isNull ifTrue: [^false].
	n := (w asUInt64 * h asUInt64) * (self bytesPerPixel: o fmt) asUInt64.
	(x < 0 or: [y < 0 or: [w <= 0 or: [h <= 0 or: [x asInt64 + w > o w or: [y asInt64 + h > o h
		or: [n > 16rFFFFFFFF or: [dstLen < n]]]]]]]) ifTrue: [
		common setError: 'bad download region'.
		^false].
	d := self deviceOf: o.
	self uploadFlush: d.
	n > d downCap ifTrue: [
		d downTb notNull ifTrue: [sdlGpu releaseTransferBuffer: d dev buffer: d downTb].
		ci := self local: 'SDL_GPUTransferBufferCreateInfo'.
		ci usage: sdlGpu SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD.
		ci size: n asUInt32.
		d downTb: (sdlGpu createTransferBuffer: d dev info: ci).
		d downCap: (d downTb notNull ifTrue: [n asUInt32] ifFalse: [0]).
		d downTb isNull ifTrue: [
			self sdlFail: 'SDL_CreateGPUTransferBuffer'.
			^false]].
	cb := sdlGpu acquireCommandBuffer: d dev.
	cb isNull ifTrue: [
		self sdlFail: 'SDL_AcquireGPUCommandBuffer'.
		^false].
	cp := sdlGpu beginCopyPass: cb.
	region := self local: 'SDL_GPUTextureRegion'.
	region texture: o ptr.
	region x: x.
	region y: y.
	region w: w.
	region h: h.
	region d: 1.
	info := self local: 'SDL_GPUTextureTransferInfo'.
	info transfer_buffer: d downTb.
	info pixels_per_row: w.
	info rows_per_layer: h.
	sdlGpu downloadFromTexture: cp source: region destination: info.
	sdlGpu endCopyPass: cp.
	f := self local: 'SDL_GPUFence *'.
	f value: (sdlGpu submitCommandBufferAndAcquireFence: cb).
	f value isNull ifTrue: [
		self sdlFail: 'SDL_SubmitGPUCommandBufferAndAcquireFence'.
		^false].
	sdlGpu waitForFences: d dev waitAll: true fences: f count: 1.
	sdlGpu releaseFence: d dev fence: f value.
	p := self cCoerce: (sdlGpu mapTransferBuffer: d dev buffer: d downTb cycle: false) to: 'uint8_t *'.
	p isNull ifTrue: [
		self sdlFail: 'SDL_MapGPUTransferBuffer'.
		^false].
	o fmt = PF_TEX_BGRA8
		ifTrue: [
			s := self cCoerce: p to: 'uint32_t *'.
			t := self cCoerce: dst to: 'uint8_t *'.
			pixel := self local: 'uint32_t'.
			0 to: (n quo: 4) asInt64 - 1 do: [:i |
				v := s at: i.
				pixel value: (((v bitAnd: 16rFF00FF00) bitOr: ((v >> 16) bitAnd: 16rFF)) bitOr: ((v bitAnd: 16rFF) asUInt64 << 16)) asUInt32.
				libc memcpy: t + (i * 4) from: pixel size: 4]]
		ifFalse: [libc memcpy: dst from: p size: n].
	sdlGpu unmapTransferBuffer: d dev buffer: d downTb.
	^true
! !

!PlatformGPU methodsFor: 'command buffers and passes'!
acquireCommandBuffer: dev
	<export>
	| d c |
	d := self device: dev.
	d isNull ifTrue: [^0].
	c := sdlGpu acquireCommandBuffer: d dev.
	c isNull ifTrue: [^self sdlFail: 'SDL_AcquireGPUCommandBuffer'].
	^self add: K_CMD pointer: c device: dev
!
acquireSwapchain: cmd window: win width: w height: h
	"0: none available (not an error if no error is set)."
	<export>
	| c sw t tw th dev fmt sh o |
	c := self get: cmd kind: K_CMD what: 'command buffer'.
	sw := windows sdlWindow: win.
	common setError: ''.
	(c isNull or: [sw isNull]) ifTrue: [^0].
	(windows isHidden: win) ifTrue: [^0].
	t := self local: 'SDL_GPUTexture *'.
	tw := self local: 'Uint32'.
	th := self local: 'Uint32'.
	(sdlGpu acquireSwapchainTexture: c ptr window: sw texture: t width: tw height: th) ifFalse: [
		^self sdlFail: 'SDL_AcquireGPUSwapchainTexture'].
	"too many frames in flight: try again later"
	t value isNull ifTrue: [^0].
	dev := c dev.
	fmt := self swapchainFormat: dev window: win.
	sh := common table: objs add: K_SWAP pointer: t value.
	o := objs v + sh.
	o dev: dev.
	o w: tw value.
	o h: th value.
	o fmt: fmt.
	o i: cmd.
	w value: tw value.
	h value: th value.
	^sh
!
beginPass: cmd target: tex clear: clear
	"clear: RGBA, NULL = load."
	<export>
	| c t ci p dev h fmt trackedTarget |
	c := self get: cmd kind: K_CMD what: 'command buffer'.
	t := self target: tex.
	(c isNull or: [t isNull]) ifTrue: [^0].
	ci := self local: 'SDL_GPUColorTargetInfo'.
	ci texture: t ptr.
	ci load_op: (clear notNull ifTrue: [sdlGpu SDL_GPU_LOADOP_CLEAR] ifFalse: [sdlGpu SDL_GPU_LOADOP_LOAD]).
	ci store_op: sdlGpu SDL_GPU_STOREOP_STORE.
	clear notNull ifTrue: [
		ci clear_color r: (clear at: 0).
		ci clear_color g: (clear at: 1).
		ci clear_color b: (clear at: 2).
		ci clear_color a: (clear at: 3)].
	p := sdlGpu beginRenderPass: c ptr targets: ci count: 1 depthStencil: self null.
	p isNull ifTrue: [^self sdlFail: 'SDL_BeginGPURenderPass'].
	dev := c dev.
	fmt := t fmt.
	"Track an ordinary owned color attachment under the current lifetime epoch."
	trackedTarget := (t kind = K_TEX and: [t dev = dev and: [(t i bitAnd: PF_TEXUSE_COLOR_TARGET) ~= 0]])
		ifTrue: [drawBindingEpoch] ifFalse: [0].
	h := self add: K_PASS pointer: p device: dev.
	h > 0 ifTrue: [
		(objs v + h) i: cmd.
		(objs v + h) h: trackedTarget.
		(objs v + h) fmt: fmt.
		"An overlapping legacy pass invalidates certification for this command until it is consumed."
		c := objs v + cmd.
		c w: (c w = 0 ifTrue: [h] ifFalse: [-1])].
	^h
!
setViewport: pass x: x y: y width: w height: h
	<var: #w type: 'float'>
	<var: #h type: 'float'>
	<var: #x type: 'float'>
	<var: #y type: 'float'>
	<export>
	| p vp |
	p := self pass: pass.
	p isNull ifTrue: [^false].
	vp := self local: 'SDL_GPUViewport'.
	vp x: x.
	vp y: y.
	vp w: w.
	vp h: h.
	vp min_depth: 0.0.
	vp max_depth: 1.0.
	sdlGpu setViewport: p viewport: vp.
	^true
!
setScissor: pass x: x y: y width: w height: h
	<export>
	| p r |
	p := self pass: pass.
	p isNull ifTrue: [^false].
	r := self local: 'SDL_Rect'.
	r x: x.
	r y: y.
	r w: w.
	r h: h.
	sdlGpu setScissor: p rect: r.
	^true
!
bindPipeline: pass pipeline: pipe
	<export>
	| p o |
	p := self get: pass kind: K_PASS what: 'render pass'.
	p isNull ifTrue: [^false].
	o := self get: pipe kind: K_PIPE what: 'pipeline'.
	o isNull ifTrue: [^false].
	sdlGpu bindGraphicsPipeline: p ptr pipeline: o ptr.
	p w: ((p dev = o dev and: [p fmt = o fmt]) ifTrue: [pipe] ifFalse: [-1]).
	^true
!
bindVertexBuffer: pass slot: slot buffer: buf offset: offset
	<export>
	| p o b |
	p := self pass: pass.
	p isNull ifTrue: [^false].
	o := self get: buf kind: K_BUF what: 'buffer'.
	o isNull ifTrue: [^false].
	b := self local: 'SDL_GPUBufferBinding'.
	b buffer: o ptr.
	b offset: offset.
	sdlGpu bindVertexBuffers: p firstSlot: slot asUInt32 bindings: b count: 1.
	^true
!
bindTexture: pass slot: slot texture: tex sampler: sampler
	<export>
	| p t s b |
	p := self pass: pass.
	p isNull ifTrue: [^false].
	t := self get: tex kind: K_TEX what: 'texture'.
	s := self get: sampler kind: K_SAMPLER what: 'sampler'.
	(t isNull or: [s isNull]) ifTrue: [^false].
	b := self local: 'SDL_GPUTextureSamplerBinding'.
	b texture: t ptr.
	b sampler: s ptr.
	sdlGpu bindFragmentSamplers: p firstSlot: slot asUInt32 bindings: b count: 1.
	^true
!
pushUniforms: cmdOrPass stage: stage slot: slot data: data count: n
	<var: #data type: 'const void *'>
	<export>
	| o |
	o := common table: objs at: cmdOrPass kind: -1.
	(o notNull and: [o kind = K_PASS]) ifTrue: [o := common table: objs at: o i asInt32 kind: K_CMD].
	(o isNull or: [o kind ~= K_CMD]) ifTrue: [
		common setError: 'bad command buffer handle %d' with: cmdOrPass.
		^false].
	stage = PF_STAGE_FRAGMENT
		ifTrue: [sdlGpu pushFragmentUniformData: o ptr slot: slot asUInt32 data: data length: n]
		ifFalse: [sdlGpu pushVertexUniformData: o ptr slot: slot asUInt32 data: data length: n].
	^true
!
draw: pass vertices: vertexCount first: firstVertex
	<export>
	| p |
	p := self pass: pass.
	p isNull ifTrue: [^false].
	sdlGpu drawPrimitives: p vertices: vertexCount asUInt32 instances: 1 firstVertex: firstVertex asUInt32 firstInstance: 0.
	^true
!
endPass: pass
	<export>
	| p c |
	p := self get: pass kind: K_PASS what: 'render pass'.
	p isNull ifTrue: [^false].
	sdlGpu endRenderPass: p ptr.
	c := common table: objs at: p i asInt32 kind: K_CMD.
	(c notNull and: [c w = pass]) ifTrue: [c w: 0].
	common table: objs remove: pass.
	^true
!
blit: cmd source: src rect: sr destination: dst rect: dr linear: linear
	"Rects: x y w h."
	<export>
	| c s t full bi |
	c := self get: cmd kind: K_CMD what: 'command buffer'.
	s := self get: src kind: K_TEX what: 'texture'.
	t := self target: dst.
	(c isNull or: [s isNull or: [t isNull]]) ifTrue: [^false].
	full := (dr at: 0) = 0 and: [(dr at: 1) = 0 and: [(dr at: 2) = t w and: [(dr at: 3) = t h]]].
	bi := self local: 'SDL_GPUBlitInfo'.
	bi source texture: s ptr.
	bi source x: (sr at: 0).
	bi source y: (sr at: 1).
	bi source w: (sr at: 2).
	bi source h: (sr at: 3).
	bi destination texture: t ptr.
	bi destination x: (dr at: 0).
	bi destination y: (dr at: 1).
	bi destination w: (dr at: 2).
	bi destination h: (dr at: 3).
	bi load_op: (full ifTrue: [sdlGpu SDL_GPU_LOADOP_DONT_CARE] ifFalse: [sdlGpu SDL_GPU_LOADOP_LOAD]).
	bi filter: (linear ifTrue: [sdlGpu SDL_GPU_FILTER_LINEAR] ifFalse: [sdlGpu SDL_GPU_FILTER_NEAREST]).
	sdlGpu blitTexture: c ptr info: bi.
	^true
!
submit: cmd fence: wantFence ok: ok
	"The fence handle or 0; ok tells whether it went well."
	<export>
	| c cb dev f h |
	c := self get: cmd kind: K_CMD what: 'command buffer'.
	ok value: false.
	c isNull ifTrue: [^0].
	self uploadFlush: (self deviceOf: c).
	cb := self cCoerce: c ptr to: 'SDL_GPUCommandBuffer *'.
	dev := c dev.
	1 to: objs n - 1 do: [:k | (self isPassOrSwapchain: k of: cmd) ifTrue: [common table: objs remove: k]].
	common table: objs remove: cmd.
	wantFence ifFalse: [
		(sdlGpu submitCommandBuffer: cb) ifFalse: [^self sdlFail: 'SDL_SubmitGPUCommandBuffer'].
		ok value: true.
		^0].
	f := sdlGpu submitCommandBufferAndAcquireFence: cb.
	f isNull ifTrue: [^self sdlFail: 'SDL_SubmitGPUCommandBufferAndAcquireFence'].
	h := self add: K_FENCE pointer: f device: dev.
	self watch: h fence: f device: (self deviceOf: objs v + h) dev.
	ok value: true.
	^h
! !

!PlatformGPU methodsFor: 'fences'!
monoUs
	<function>
	| ts |
	ts := self local: 'struct timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
!
fenceWatcher: unused
	"The watcher thread: stamp the pending fences that completed, every 200 µs while any are pending."
	<function>
	| nap w |
	nap := self local: 'struct timespec'.
	posixThreads mutexLock: watchLock.
	[[npending = 0] whileTrue: [posixThreads condWait: watchCond mutex: watchLock].
	 0 to: nwatches - 1 do: [:i |
		w := watches + i.
		(w active and: [sdlGpu queryFence: w d fence: w f]) ifTrue: [
			w doneUs: self monoUs.
			w active: false.
			npending := npending - 1]].
	 posixThreads mutexUnlock: watchLock.
	 nap tv_sec: 0.
	 nap tv_nsec: 200000.
	 posixThreads nanosleep: nap remaining: self null.
	 posixThreads mutexLock: watchLock] repeat
!
watch: h fence: f device: d
	<function>
	| n nw w t |
	posixThreads mutexLock: watchLock.
	h >= nwatches ifTrue: [
		n := h + 64.
		nw := self cCoerce: (libc realloc: watches size: n asUInt64 * (self sizeof: 'fence_watch')) to: 'fence_watch *'.
		nw isNull ifTrue: [
			posixThreads mutexUnlock: watchLock.
			^self].
		libc memset: nw + nwatches value: 0 size: (n - nwatches) asUInt64 * (self sizeof: 'fence_watch').
		watches := nw.
		nwatches := n].
	w := watches + h.
	w active ifTrue: [npending := npending - 1].
	w f: f.
	w d: d.
	w submitUs: self monoUs.
	w doneUs: -1.
	w active: true.
	npending := npending + 1.
	watcherStarted ifFalse: [
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #fenceWatcher:) argument: self null) = 0 ifTrue: [
			posix pthreadDetach: t value.
			watcherStarted := true]].
	posixThreads condSignal: watchCond.
	posixThreads mutexUnlock: watchLock
!
unwatch: h
	<function>
	posixThreads mutexLock: watchLock.
	h < nwatches ifTrue: [
		(watches + h) active ifTrue: [npending := npending - 1].
		libc memset: watches + h value: 0 size: (self sizeof: 'fence_watch')].
	posixThreads mutexUnlock: watchLock
!
fenceElapsed: fence
	"µs from the fence's submit to its completion; -1 pending, -2 bad handle."
	<export>
	| r w |
	(self get: fence kind: K_FENCE what: 'fence') isNull ifTrue: [^-2].
	r := -1.
	posixThreads mutexLock: watchLock.
	fence < nwatches ifTrue: [
		w := watches + fence.
		(w f notNull and: [w doneUs >= 0]) ifTrue: [r := w doneUs - w submitUs]].
	posixThreads mutexUnlock: watchLock.
	^r
!
waitFence: fence
	<export>
	| o f |
	o := self get: fence kind: K_FENCE what: 'fence'.
	o isNull ifTrue: [^false].
	f := self local: 'SDL_GPUFence *'.
	f value: o ptr.
	(sdlGpu waitForFences: (self deviceOf: o) dev waitAll: true fences: f count: 1) ifTrue: [^true].
	self sdlFail: 'SDL_WaitForGPUFences'.
	^false
!
fenceDone: fence
	"1 done, 0 pending, -1 error."
	<export>
	| o |
	o := self get: fence kind: K_FENCE what: 'fence'.
	o isNull ifTrue: [^-1].
	^(sdlGpu queryFence: (self deviceOf: o) dev fence: o ptr) ifTrue: [1] ifFalse: [0]
! !

!PlatformGPU methodsFor: 'release'!
release: h
	"Release the object of handle h (not a device)."
	<function>
	| o dv |
	o := objs v + h.
	dv := (self deviceOf: o) dev.
	o kind caseOf: {
		[K_SHADER] -> [sdlGpu releaseShader: dv shader: o ptr].
		[K_PIPE] -> [
			self invalidateDrawBindings.
			sdlGpu releaseGraphicsPipeline: dv pipeline: o ptr].
		[K_TEX] -> [
			self invalidateDrawBindings.
			sdlGpu releaseTexture: dv texture: o ptr].
		[K_SAMPLER] -> [sdlGpu releaseSampler: dv sampler: o ptr].
		[K_BUF] -> [sdlGpu releaseBuffer: dv buffer: o ptr].
		[K_FENCE] -> [
			self unwatch: h.
			sdlGpu releaseFence: dv fence: o ptr].
		[K_CMD] -> [
			sdlGpu cancelCommandBuffer: o ptr.
			1 to: objs n - 1 do: [:k | (self isPassOrSwapchain: k of: h) ifTrue: [common table: objs remove: k]]]}
		otherwise: [].
	common table: objs remove: h
!
releaseDevice: dh
	<function>
	| d |
	d := self cCoerce: (objs v + dh) ptr to: 'gpu_dev *'.
	self uploadFlush: d.
	sdlGpu waitForIdle: d dev.
	1 to: objs n - 1 do: [:h | (h ~= dh and: [(objs v + h) kind ~= 0 and: [(objs v + h) dev = dh]]) ifTrue: [self release: h]].
	0 to: MAX_CLAIMS - 1 do: [:i |
		(d claimed at: i) ~= 0 ifTrue: [sdlGpu releaseWindow: d dev window: (windows sdlWindow: (d claimed at: i))]].
	d upTb notNull ifTrue: [sdlGpu releaseTransferBuffer: d dev buffer: d upTb].
	d downTb notNull ifTrue: [sdlGpu releaseTransferBuffer: d dev buffer: d downTb].
	sdlGpu destroyDevice: d dev.
	libc free: d.
	common table: objs remove: dh
!
releaseHandle: h
	"A device releases everything created on it; passes and swapchain textures end with their command buffer."
	<export>
	| o |
	o := common table: objs at: h kind: -1.
	o isNull ifTrue: [
		common setError: 'bad GPU handle %d' with: h.
		^false].
	(o kind = K_PASS or: [o kind = K_SWAP]) ifTrue: [
		common setError: 'pass/swapchain handles end with their command buffer'.
		^false].
	o kind = K_DEV
		ifTrue: [self releaseDevice: h]
		ifFalse: [self release: h].
	^true
!
shutdown
	<export>
	1 to: objs n - 1 do: [:h | (objs v + h) kind = K_DEV ifTrue: [self releaseDevice: h]]
!
handleCounts: out
	"devices shaders pipelines textures samplers buffers fences"
	<export>
	out at: 0 put: (common table: objs count: K_DEV).
	out at: 1 put: (common table: objs count: K_SHADER).
	out at: 2 put: (common table: objs count: K_PIPE).
	out at: 3 put: (common table: objs count: K_TEX).
	out at: 4 put: (common table: objs count: K_SAMPLER).
	out at: 5 put: (common table: objs count: K_BUF).
	out at: 6 put: (common table: objs count: K_FENCE)
! !

VMStruct subclass: #GpuDev
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

GpuDev comment: 'A device: its upload batch (transfer buffer, command buffer and copy pass), its download transfer buffer, the windows it claimed.'!

!GpuDev class methodsFor: 'declaring'!
fields
	^#((dev 'SDL_GPUDevice *') (upTb 'SDL_GPUTransferBuffer *') (upCap uint32_t) (upUsed uint32_t) (upCmd 'SDL_GPUCommandBuffer *')
		(upPass 'SDL_GPUCopyPass *') (downTb 'SDL_GPUTransferBuffer *') (downCap uint32_t) (claimed 'int32_t[MAX_CLAIMS]'))
! !

VMStruct subclass: #FenceWatch
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

FenceWatch comment: 'A watched fence: when it was submitted and when the watcher saw it complete (-1 = not yet).'!

!FenceWatch class methodsFor: 'declaring'!
fields
	^#((f 'SDL_GPUFence *') (d 'SDL_GPUDevice *') (submitUs int64_t) (doneUs int64_t) (active bool))
! !

VMStruct subclass: #PfVattr
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfVattr comment: 'A vertex attribute: format (PF_VA_*) and offset.'!

!PfVattr class methodsFor: 'declaring'!
fields
	^#((format int32_t) (offset int32_t))
! !
