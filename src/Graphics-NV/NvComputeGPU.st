SoftwareGPU subclass: #NvComputeGPU
	instanceVariableNames: 'gpu compute kernels memories fences lastFence scratch starts batch batchStarts batchSlots batchTarget batchClip batchUsed arena arenaOffset stamps stampCount recent blocks cached gpuDirty l2Stale fragmentUniforms shaderKernels launchCount spans gpuSpan ranges batchRanges batchRects waitCount'
	classVariableNames: ''
	package: 'Graphics-NV'!

NvComputeGPU comment: 'I am a GPU device on an NVIDIA GPU (the GB10) without its graphics driver: a SoftwareGPU (the gpu primitives'' protocol, handles, errors, the Renderer''s shader only; docs/platform.md) whose memory is the GPU''s (NvCudaDevice, System-CUDA: CUDA''s pinned host memory, which the GPU and the CPU reach at one address) and whose pixel work is the raster kernels (NvRasterKernels: PlatformRaster''s as CUDA kernels, bit-exact with it), launched through libcuda (NvCudaCompute: cuModuleLoadData, cuLaunchKernel) on the CUDA runtime''s context and default stream, the one cuBLAS and CudaArray use. docs/nv-gpu.md.

libcuda is my one backend: where NVIDIA''s CUDA userspace is not (no libcuda or CUDA runtime, or no device: the appliance without its CUDA root), isAvailable is false and GPUPlatform renders in software instead, saying why (unavailableReason). The RM-ioctl backend (System-NV''s own RM client) was removed: docs/nv-rm.md.

	gpu := NvComputeGPU on: aDisplay.        "opens the GPU; an error where there is none"
	GPUPlatform display: d device: gpu       "or --gpu nv (SAMALTAK_GPU=nv): GPUPlatform chooses me"

Textures, buffers and back buffers are NvCudaMemory (the addresses SoftwareGPU keeps are their CPU addresses). A clear is a raster_fill, a blit raster_blit. Draws are batched: consecutive draws into one target (a pass''s, or several passes'') collect their RasterDrawParams (the pass''s state), and are launched together as raster_batch_prims then raster_batch_tiles (the params in an arena of GPU memory reused as a ring, one scratch) when anything else comes: another target, a clear, a blit, a CPU access, a submit. Launches are queued in order and run while the CPU goes on. The CPU waits only where it touches memory a queued launch uses: an upload, a download, a present, freeing; each memory remembers the fence of the last launch that used it. Fences are the channel''s: done when the GPU reached them. fenceElapsed is the GPU''s time for the command buffer: the GPU''s clock written (a timestamp release) before its first clear, draw or blit and after its last, in a ring of 256 slots. shaderLanguage is ''raster'': not software (isSoftware is false); the Renderer''s shader is the raster kernels.

FragmentShaders run too (GPUDevice>>runsFragmentShaders, fragmentShaderLanguage #glsl): a fragment shader with entry main is GLSL (FragmentShader''s prelude and source), which NvShaderCompiler makes a kernel of (precompiled, or by NVRTC; a ShaderError if it does not compile); its pipeline (a triangle over an RGBA8 target, no blending, no vertices) draws by launching that kernel over the pass''s target, a thread a pixel, with the fragment uniforms pushed to slot 0 as its uniform block. A kernel''s GPU memory goes when the last pipeline using it is released.

My display presents the BGRA8 back buffer from its CPU address: hosted a HostFramePresenter (SDL_GPU, the VM''s window), on the appliance a KmsDisplay (the image''s own KMS screen). close closes the GPU (everything I made goes with it).'!

!NvComputeGPU methodsFor: 'initialization'!
setDisplay: aDisplay
	| cubin |
	super setDisplay: aDisplay.
	memories := Dictionary new.
	fences := Dictionary new.
	starts := Dictionary new.
	lastFence := launchCount := gpuSpan := waitCount := 0.
	ranges := Dictionary new.
	self resetBatch.
	gpu := self class openDevice.
	stampCount := 0.
	recent := Array new: 64.
	cached := Set new.
	gpuDirty := l2Stale := false.
	fragmentUniforms := Dictionary new.
	shaderKernels := Dictionary new.
	[compute := gpu newCompute.
	stamps := gpu allocate: 256 * 32.
	cubin := NvCubin on: NvRasterKernels cubin.
	kernels := Dictionary new.
	blocks := Dictionary new.
	NvRasterKernels kernelNames do: [:name |
		kernels at: name put: (cubin kernelNamed: name).
		blocks at: name put: ((NvRasterKernels kernel: name) at: #block)]]
		ifCurtailed: [self close]
! !

!NvComputeGPU methodsFor: 'accessing'!
gpu
	"The NvCudaDevice."
	^gpu
!
compute
	^compute
!
launchCount
	"How many kernels I launched (raster kernels, fragment shaders), since I was made."
	^launchCount
!
waitCount
	"How often the CPU waited for launches to finish before touching memory (uploads, downloads, presents, frees), since I was made."
	^waitCount
!
measureSpans
	"From now on give every command buffer that does GPU work an end stamp too, and add its span (first launch to last done, GPU clock) to gpuSpanMicroseconds."
	spans isNil ifTrue: [spans := OrderedCollection new. gpuSpan := 0]
!
gpuSpanMicroseconds
	"The GPU µs of the command buffers submitted since measureSpans and done so far, from their first launch's stamp to their last's."
	| e at |
	spans isNil ifTrue: [^0].
	[spans notEmpty] whileTrue: [
		e := spans first.
		at := e first * 32.
		(stamps uint64At: at + 16) = (e at: 2)
			ifTrue: [gpuSpan := gpuSpan + (((stamps uint64At: at + 24) - (stamps uint64At: at + 8) max: 0) // 1000). spans removeFirst]
			ifFalse: [stampCount - (e at: 2) > 200 ifFalse: [^gpuSpan]. spans removeFirst]].
	^gpuSpan
!
mark: anInteger
	"A marker in the launch stream for a profiler (nsys): on libcuda a one-thread-a-block kernel of anInteger blocks."
	self flush.
	(compute respondsTo: #marker:) ifTrue: [compute marker: anInteger]
!
close
	"Close the GPU; every texture, buffer and back buffer goes with it. Safe to call twice."
	gpu isNil ifTrue: [^self].
	[[self flush. gpuDirty ifTrue: [self writeBackL2]] on: Error do: [:e | ].
	gpu close] ensure: [
		gpu := compute := scratch := arena := stamps := nil.
		self resetBatch.
		memories := Dictionary new.
		cached := Set new.
		fences := Dictionary new.
		ranges := Dictionary new.
		shaderKernels := Dictionary new.
		fragmentUniforms := Dictionary new]
! !

!NvComputeGPU methodsFor: 'device'!
shaderLanguage: dev
	"What createShader: takes: 'raster', the Renderer's shader on the raster kernels (the source is ignored)."
	self device: dev for: 'gpuShaderLanguage'.
	^'raster'
!
waitIdle: dev
	self device: dev for: 'gpuWaitIdle'.
	self flush.
	compute wait: lastFence
! !

!NvComputeGPU methodsFor: 'fragment shaders'!
runsFragmentShaders: dev
	"Whether GLSL fragment shaders run: NVRTC is here, or some are precompiled."
	self device: dev for: 'gpuRunsFragmentShaders'.
	^NvShaderCompiler canBuildAny
!
canBuildFragmentShader: dev source: aString
	"Whether the fragment shader aString (FragmentShader's prelude and its source) can be made a kernel here."
	self device: dev for: 'gpuCanBuildFragmentShader'.
	^NvShaderCompiler canBuild: aString
!
fragmentShaderReady: dev source: aString
	"Whether the fragment shader aString would be made a kernel at once; if not, NVRTC compiles it in the background now."
	self device: dev for: 'gpuFragmentShaderReady'.
	^NvShaderCompiler isReady: aString
!
createShader: dev source: source entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	"A GLSL fragment shader (entry main) is compiled to a kernel now (a ShaderError if it does not compile); other shaders are the Renderer's, as on a SoftwareGPU."
	| h key |
	(stage = 1 and: [entryName = 'main']) ifFalse: [
		^super createShader: dev source: source entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures].
	self device: dev for: 'gpuCreateShader'.
	key := self kernelKeyFor: source.
	h := super createShader: dev source: source entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures.
	(self at: h) command: key; extra: (shaderKernels at: key).
	^h
!
kernelKeyFor: aString
	"The key of the kernel of the GLSL fragment shader aString, made (once per key) and kept in shaderKernels: (kernel pipelines)."
	| cubin key |
	cubin := NvShaderCompiler cubinFor: aString.
	key := NvShaderCompiler keyFor: aString.
	shaderKernels at: key ifAbsent: [
		shaderKernels at: key put: (Array with: ((NvCubin on: cubin) kernelNamed: 'gl_fragment') with: 0 with: (NvShaderCompiler uniformSizeFor: aString))].
	^key
!
createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
	"A fragment shader's pipeline: one triangle over an RGBA8 target, no vertices, no blending."
	| f entry |
	f := self at: fs.
	(f notNil and: [f kind == #shader and: [f command notNil]]) ifFalse: [
		^super createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat].
	self device: dev for: 'gpuCreatePipeline'.
	(stride = 0 and: [attributes isEmpty and: [primitiveType = 0 and: [blend = 0 and: [targetFormat = 2]]]])
		ifFalse: [^self fail: 'gpuCreatePipeline' because: 'a fragment shader here covers an RGBA8 target with one triangle, unblended'].
	entry := shaderKernels at: f command ifAbsentPut: [f extra at: 2 put: 0; yourself].
	entry at: 2 put: (entry at: 2) + 1.
	^self add: ((SoftwareGPUObject kind: #pipeline) device: dev; format: targetFormat; extra: 0; command: f command; yourself)
!
pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
	"Fragment slot 0 is a fragment shader's uniform block."
	| o |
	super pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes.
	(stage = 1 and: [slot = 0]) ifTrue: [
		o := self at: commandBufferOrPass.
		fragmentUniforms at: (o kind == #pass ifTrue: [o command] ifFalse: [commandBufferOrPass]) put: bytes copy]
!
draw: pass count: vertexCount first: firstVertex
	| p |
	p := self at: pass kind: #pass for: 'gpuDraw'.
	(p pipeline notNil and: [p pipeline command notNil]) ifFalse: [^super draw: pass count: vertexCount first: firstVertex].
	vertexCount < 3 ifTrue: [^self].
	self shade: p
!
shade: aPass
	"Run the pass's fragment shader over its target: its kernel, a thread a pixel; the parameters the target's address, width and height, and the address of the uniforms (in the arena, the block's size at least, zeroes after what was pushed)."
	| t entry kernel u params t0 at |
	(self at: aPass targetHandle) == aPass target ifFalse: [^self].
	t := aPass target.
	t format = 2 ifFalse: [^self fail: 'gpuDraw' because: 'a fragment shader draws into RGBA8'].
	entry := shaderKernels at: aPass pipeline command ifAbsent: [^self fail: 'gpuDraw' because: 'the shader''s kernel is gone'].
	kernel := entry first.
	t0 := Time microsecondClockValue.
	self flush.
	u := ByteArray new: ((entry at: 3) max: 16).
	(fragmentUniforms at: aPass command ifAbsent: [#[]]) ifNotNil: [:pushed |
		u replaceFrom: 1 to: (pushed size min: u size) with: pushed startingAt: 1].
	at := (self arenaFor: u size + 16) + 15 // 16 * 16.
	arena bytesAt: at put: u.
	params := ByteArray new: kernel parameterSize.
	self put: (self gpuAddress: t address) at: 0 in: params.
	self put32: t width at: 8 in: params.
	self put32: t height at: 12 in: params.
	self put: arena gpuAddress + at at: 16 in: params.
	self launchKernel: kernel grid: (Array with: t width + 15 // 16 with: t height + 15 // 16) block: 256 parameters: params using: (Array with: t address with: arena cpuAddress).
	self charge: aPass command since: t0
!
releaseKernelOf: aPipeline
	"aPipeline is released: the kernel's GPU memory goes with the last pipeline using it."
	| entry |
	entry := shaderKernels at: aPipeline command ifAbsent: [^self].
	entry at: 2 put: (entry at: 2) - 1.
	(entry at: 2) > 0 ifTrue: [^self].
	shaderKernels removeKey: aPipeline command.
	compute isNil ifTrue: [^self].
	self flush.
	compute forget: entry first
! !

!NvComputeGPU methodsFor: 'commands'!
beginPass: cmd target: texture clear: rgbaOrNil
	self started: cmd.
	^super beginPass: cmd target: texture clear: rgbaOrNil
!
blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: aBoolean
	self started: cmd.
	^super blit: cmd source: src rect: srcRect destination: dst rect: dstRect linear: aBoolean
!
submit: cmd fence: wantFence
	"Present what cmd acquired (once the GPU drew it); a fence for what was launched so far, or nil."
	| slot f |
	self flush.
	slot := starts at: cmd ifAbsent: [nil].
	f := super submit: cmd fence: wantFence.
	f isNil ifTrue: [
		(spans notNil and: [slot notNil]) ifTrue: [spans add: (Array with: slot with: (self stamp: slot * 32 + 16))].
		^nil].
	(self at: f) command: lastFence; address: slot; size: nil.
	slot isNil ifFalse: [(self at: f) width: (self stamp: slot * 32 + 16)].
	(spans notNil and: [slot notNil]) ifTrue: [spans add: (Array with: slot with: (self at: f) width)].
	^f
!
waitFence: fence
	| f |
	f := self at: fence kind: #fence for: 'gpuWaitFence'.
	compute wait: f command.
	[self isDone: f] whileFalse
!
fenceDone: fence
	^self isDone: (self at: fence kind: #fence for: 'gpuFenceDone')
!
fenceElapsed: fence
	"µs from the first launch of the fence's command buffer to when I saw the fence done (0 while it is not)."
	| f |
	f := self at: fence kind: #fence for: 'gpuFenceElapsed'.
	^(self isDone: f) ifTrue: [f size] ifFalse: [0]
! !

!NvComputeGPU methodsFor: 'private'!
isDone: aFence
	"A fence object: command the channel's fence value, address its command buffer's stamp pair (nil if it did no GPU work), width the payload its end stamp carries, size its GPU µs once done."
	| at |
	aFence size notNil ifTrue: [^true].
	compute channel completedValue >= aFence command ifFalse: [^false].
	aFence address isNil ifTrue: [aFence size: 0. ^true].
	at := aFence address * 32.
	(stamps uint64At: at + 16) = aFence width ifFalse: [^false].
	aFence size: ((stamps uint64At: at + 24) - (stamps uint64At: at + 8) max: 0) // 1000.
	^true
!
started: cmd
	"Before cmd's first GPU work: the GPU's clock into the next stamp pair's first half."
	starts at: cmd ifAbsent: [| slot |
		self flush.
		slot := stampCount \\ 256.
		starts at: cmd put: slot.
		self stamp: slot * 32]
!
stamp: offset
	"The GPU's clock at offset in stamps once the work before is done; answer the payload that says it is there."
	stampCount := stampCount + 1.
	compute channel timestamp: stamps gpuAddress + offset payload: stampCount.
	^stampCount
!
drop: h
	| o |
	starts removeKey: h ifAbsent: [].
	fragmentUniforms removeKey: h ifAbsent: [].
	o := self at: h.
	(o notNil and: [o kind == #pipeline and: [o command notNil]]) ifTrue: [self releaseKernelOf: o].
	super drop: h
!
launchFor: aFence
	"{fence. kernel name. grid. parameter bytes} of the launch whose fence is aFence, if among the last 64; for diagnosis."
	^(recent at: aFence \\ 64 + 1) ifNotNil: [:r | r first = aFence ifTrue: [r]]
!
gpuAddress: address
	"The GPU address of the memory whose CPU address is address."
	^(memories at: address) gpuAddress
!
launch: aName grid: grid parameters: bytes using: addresses
	"Queue the raster kernel aName (as many threads a block as it is written for) with its parameter struct; the memory at addresses waits for it."
	^self launchKernel: (kernels at: aName) grid: grid block: (blocks at: aName) parameters: bytes using: addresses
!
launchKernel: aKernel grid: grid block: block parameters: bytes using: addresses
	| fence |
	l2Stale ifTrue: [
		compute channel flushAndInvalidateL2.
		l2Stale := false].
	fence := compute launch: aKernel grid: grid block: block parameters: bytes.
	launchCount := launchCount + 1.
	gpuDirty := true.
	recent at: fence \\ 64 + 1 put: (Array with: fence with: aKernel name with: grid with: bytes).
	addresses do: [:a | fences at: a put: fence].
	lastFence := fence
!
put: anInteger at: offset in: bytes
	"anInteger (or a Boolean) as a little-endian 64-bit integer, two's complement, at the 0-based offset."
	| v |
	v := anInteger == true ifTrue: [1] ifFalse: [anInteger == false ifTrue: [0] ifFalse: [anInteger]].
	v < 0 ifTrue: [v := v + 16r10000000000000000].
	bytes uint32At: offset + 1 put: (v bitAnd: 16rFFFFFFFF).
	bytes uint32At: offset + 5 put: (v bitShift: -32)
!
put32: anInteger at: offset in: bytes
	| v |
	v := anInteger == true ifTrue: [1] ifFalse: [anInteger == false ifTrue: [0] ifFalse: [anInteger]].
	bytes uint32At: offset + 1 put: (v bitAnd: 16rFFFFFFFF)
!
resetBatch
	batch := OrderedCollection new.
	batchStarts := OrderedCollection new.
	batchSlots := 0.
	batchTarget := batchClip := nil.
	batchUsed := Set new.
	batchRanges := OrderedCollection new.
	batchRects := OrderedCollection new
!
flush
	"Launch the batched draws: raster_batch_prims, raster_batch_tiles over the union of their clips."
	| draws startsOf slots target clip used read tiles n bytes at p base |
	batch isEmpty ifTrue: [^self].
	draws := batch. startsOf := batchStarts. slots := batchSlots. target := batchTarget. clip := batchClip. used := batchUsed. read := batchRanges.
	tiles := self tilesOf: batchRects within: clip.
	self resetBatch.
	clip isNil ifTrue: [^self].
	n := draws size.
	bytes := ByteArray new: n * 200 + (n + 1 * 8) + (tiles isNil ifTrue: [0] ifFalse: [tiles size]).
	tiles isNil ifFalse: [bytes replaceFrom: n * 200 + (n + 1 * 8) + 1 to: bytes size with: tiles startingAt: 1].
	draws doWithIndex: [:d :i | bytes replaceFrom: i - 1 * 200 + 1 to: i * 200 with: d startingAt: 1].
	startsOf doWithIndex: [:s :i | self put: s at: n * 200 + (i - 1 * 8) in: bytes].
	self put: slots at: n * 200 + (n * 8) in: bytes.
	self ensureScratch: NvRasterKernels batchSlotBytes * slots.
	at := self arenaFor: bytes size.
	arena bytesAt: at put: bytes.
	base := arena gpuAddress + at.
	p := ByteArray new: (NvRasterKernels sizeOf: #RasterBatchParams).
	self put: base at: 0 in: p.
	self put: base + (n * 200) at: 8 in: p.
	self put: scratch gpuAddress at: 16 in: p.
	self put: n at: 24 in: p.
	self put: slots at: 32 in: p.
	1 to: 4 do: [:i | self put: (clip at: i) at: i * 8 + 32 in: p].
	tiles isNil ifFalse: [
		self put: base + (n * 200) + (n + 1 * 8) at: 72 in: p.
		self put: tiles size // 4 at: 80 in: p].
	used := used asArray, (Array with: target with: scratch cpuAddress with: arena cpuAddress).
	self launch: 'raster_batch_prims' grid: slots + NvRasterKernels batchChunk - 1 // NvRasterKernels batchChunk parameters: p using: used.
	self launch: 'raster_batch_tiles' grid: (tiles isNil
			ifTrue: [((clip at: 3) - (clip at: 1) + 15 // 16) * ((clip at: 4) - (clip at: 2) + 15 // 16)]
			ifFalse: [tiles size // 4])
		parameters: p using: used.
	read do: [:r | (ranges at: r first ifAbsentPut: [OrderedCollection new]) add: (Array with: (r at: 2) with: (r at: 3) with: lastFence)]
!
tilesOf: rects within: clip
	"The 16 x 16 tiles (uint32 x | y << 16, in tiles, as raster_batch_tiles takes them) that the batch's clips, rects, meet, when that is clearly fewer than those of their bounds clip (a damaged frame's scattered rectangles); else nil."
	| boxTiles count seen bytes k |
	(clip isNil or: [rects isNil or: [rects size < 2]]) ifTrue: [^nil].
	boxTiles := ((clip at: 3) + 15 // 16 - ((clip at: 1) // 16)) * ((clip at: 4) + 15 // 16 - ((clip at: 2) // 16)).
	count := rects inject: 0 into: [:sum :r | sum + (((r at: 3) + 15 // 16 - ((r at: 1) // 16)) * ((r at: 4) + 15 // 16 - ((r at: 2) // 16)))].
	count * 4 > (boxTiles * 3) ifTrue: [^nil].
	seen := Set new: count * 2.
	bytes := ByteArray new: count * 4.
	k := 0.
	rects do: [:r |
		(r at: 2) // 16 to: (r at: 4) + 15 // 16 - 1 do: [:ty |
			(r at: 1) // 16 to: (r at: 3) + 15 // 16 - 1 do: [:tx | | t |
				t := (ty bitShift: 16) + tx.
				(seen includes: t) ifFalse: [
					seen add: t.
					bytes uint32At: k * 4 + 1 put: t.
					k := k + 1]]]].
	^k = count ifTrue: [bytes] ifFalse: [bytes copyFrom: 1 to: k * 4]
!
addRect: r
	"A draw's clip joins the batch's rectangles: not when one of them holds it; those it holds go; past 16 the bounds are used (nil)."
	batchRects isNil ifTrue: [^self].
	(batchRects anySatisfy: [:o | (o at: 1) <= (r at: 1) and: [(o at: 2) <= (r at: 2) and: [(o at: 3) >= (r at: 3) and: [(o at: 4) >= (r at: 4)]]]])
		ifTrue: [^self].
	batchRects := batchRects reject: [:o | (r at: 1) <= (o at: 1) and: [(r at: 2) <= (o at: 2) and: [(r at: 3) >= (o at: 3) and: [(r at: 4) >= (o at: 4)]]]].
	batchRects add: r.
	batchRects size > 16 ifTrue: [batchRects := nil]
!
arenaFor: byteCount
	"Where in the arena (GPU memory for batches' draws, used as a ring) byteCount bytes go; when it starts over, the GPU must be done with what it held."
	| at |
	(arena isNil or: [arena size < byteCount]) ifTrue: [
		arena isNil ifFalse: [self free: arena cpuAddress].
		arena := nil.
		arena := memories at: (self allocateBuffer: (byteCount * 2 max: 16r400000)).
		arenaOffset := 0].
	arenaOffset + byteCount > arena size ifTrue: [
		self touch: arena cpuAddress.
		arenaOffset := 0].
	at := arenaOffset.
	arenaOffset := arenaOffset + byteCount + 7 // 8 * 8.
	^at
!
ensureScratch: byteCount
	"A draw's scratch (raster_prims writes it, raster_tiles reads it) of at least byteCount bytes."
	(scratch notNil and: [scratch size >= byteCount]) ifTrue: [^scratch].
	scratch notNil ifTrue: [self free: scratch cpuAddress].
	scratch := nil.
	^scratch := memories at: (self allocate: (byteCount * 2 max: 16r100000))
! !

!NvComputeGPU methodsFor: 'memory and pixels'!
allocate: byteCount
	"Textures and back buffers (and the scratch): memory the GPU caches. RM's zeroes are the CPU's: the L2 is invalidated before the next launch."
	| m |
	m := gpu allocate: (byteCount max: 1) gpuCached: true.
	memories at: m cpuAddress put: m.
	cached add: m cpuAddress.
	l2Stale := true.
	^m cpuAddress
!
allocateBackBuffer: byteCount
	"A back buffer: the CPU reads every frame of it (present), so not cached (the L2 would write 8 MB back a frame)."
	^self allocateBuffer: byteCount
!
allocateBuffer: byteCount
	"Buffers (vertices, uniforms, a batch's params): written by the CPU for nearly every draw, so not cached."
	| m |
	m := gpu allocate: (byteCount max: 1).
	memories at: m cpuAddress put: m.
	^m cpuAddress
!
free: address
	| m |
	self touch: address.
	m := memories removeKey: address ifAbsent: [^self].
	cached remove: address ifAbsent: [].
	m free
!
touch: address
	"The CPU is about to read or write the memory at address: wait for the launches that use it (the batched draws launched first), and if the GPU caches it, have the L2 write what kernels wrote back (the CPU reads it, or would be overwritten by it later)."
	| f |
	self flush.
	f := fences removeKey: address ifAbsent: [0].
	(ranges removeKey: address ifAbsent: [#()]) do: [:r | f := f max: (r at: 3)].
	f > 0 ifTrue: [self wait: f].
	((cached includes: address) and: [gpuDirty]) ifTrue: [self writeBackL2]
!
touch: address from: start to: stop
	"The CPU is about to write bytes start to stop - 1 of the buffer at address (uncached): wait only for the draws that read them, batched or launched, not for every launch that used the buffer: the Renderer writes each list into its own range of its vertex ring while the GPU still draws the earlier ones."
	| f list |
	(batchRanges anySatisfy: [:r | r first = address and: [(r at: 2) < stop and: [start < (r at: 3)]]]) ifTrue: [self flush].
	f := fences removeKey: address ifAbsent: [0].
	list := ranges at: address ifAbsent: [nil].
	list isNil ifFalse: [
		list := list reject: [:r |
			((r at: 1) < stop and: [start < (r at: 2)])
				ifTrue: [f := f max: (r at: 3). true]
				ifFalse: [false]].
		list size > 64 ifTrue: [| done |
			done := compute channel completedValue.
			list := list reject: [:r | (r at: 3) <= done]].
		list isEmpty ifTrue: [ranges removeKey: address] ifFalse: [ranges at: address put: list]].
	f > 0 ifTrue: [self wait: f]
!
wait: aFence
	"Wait until the launch whose fence is aFence has run."
	waitCount := waitCount + 1.
	compute wait: aFence
!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	"SoftwareGPU's, but the CPU waits only for the draws reading the range it writes (touch:from:to:)."
	| b |
	b := self at: buffer kind: #buffer for: 'gpuUploadBuffer'.
	(byteCount between: 0 and: (self byteSizeOf: bytes)) ifFalse: [^self fail: 'gpuUploadBuffer' because: 'bad byte count'].
	byteCount = 0 ifTrue: [^self].
	(dstOffset >= 0 and: [dstOffset + byteCount <= b size]) ifFalse: [^self fail: 'gpuUploadBuffer' because: 'upload out of buffer bounds'].
	self touch: b address from: dstOffset to: dstOffset + byteCount.
	Machine copy: byteCount from: bytes at: 0 to: b address at: dstOffset
!
writeBackL2
	"Wait until the L2 has written every dirty line back (NvChannel>>flushL2 and a fence)."
	| ch |
	ch := compute channel.
	ch flushL2.
	ch wait: ch fence.
	gpuDirty := false
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	"Up to 256 KB go through the arena: the CPU copies the rows there and raster_copy writes them into the texture in launch order, as SDL_GPU's copy pass does, so the CPU waits for no launch still drawing with the texture (a glyph atlas taking a glyph, a Form changed between two draws of it). Larger ones wait for those launches and copy (SoftwareGPU's), and the L2 drops its lines before the next launch."
	| t bpp n at p r |
	t := self at: texture kind: #texture for: 'gpuUploadTexture'.
	bpp := self bytesPerPixel: t format.
	n := w * h * bpp.
	(n <= 262144 and: [h <= 65535 and: [x >= 0 and: [y >= 0 and: [w > 0 and: [h > 0 and: [x + w <= t width and: [y + h <= t height
		and: [bytesPerRow >= (w * bpp) and: [(self byteSizeOf: bytes) >= ((h - 1) * bytesPerRow + (w * bpp))]]]]]]]]])
		ifFalse: [
			r := super uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow.
			l2Stale := true.
			^r].
	self flush.
	at := self arenaFor: n.
	SoftwareRaster copy: arena cpuAddress + at stride: w * bpp from: bytes stride: bytesPerRow width: w height: h bytesPerPixel: bpp mode: 0.
	p := ByteArray new: (NvRasterKernels sizeOf: #RasterCopyParams).
	self put: (self gpuAddress: t address) + ((y * t width + x) * bpp) at: 0 in: p.
	self put: t width * bpp at: 8 in: p.
	self put: arena gpuAddress + at at: 16 in: p.
	self put: w * bpp at: 24 in: p.
	self put: w at: 32 in: p.
	self put: h at: 40 in: p.
	self put: bpp at: 48 in: p.
	self launch: 'raster_copy' grid: (Array with: w + 255 // 256 with: h) parameters: p using: (Array with: t address with: arena cpuAddress)
!
fill: address count: n bytesPerPixel: bpp value: anInteger
	| p |
	n > 0 ifFalse: [^self].
	self flush.
	p := ByteArray new: (NvRasterKernels sizeOf: #RasterFillParams).
	self put: (self gpuAddress: address) at: 0 in: p.
	self put: n at: 8 in: p.
	self put32: bpp at: 16 in: p.
	self put32: anInteger at: 20 in: p.
	self launch: 'raster_fill' grid: (n + 255 // 256 min: 4096) parameters: p using: (Array with: address)
!
draw: st buffer: aBuffer offset: byteOffset first: first count: count
	"Batch the RasterDrawParams of the state (SoftwareRaster's: target width height format blend, scissor, viewport, viewSize, translate, texture and its width height format, linear repeat) and the vertices."
	| slots p target texture x0 y0 x1 y1 |
	slots := count // 3.
	slots > 0 ifFalse: [^self].
	target := st at: 1.
	texture := st at: 18.
	batchTarget = target ifFalse: [
		self flush.
		batchTarget := target].
	p := ByteArray new: (NvRasterKernels sizeOf: #RasterDrawParams).
	self put: (self gpuAddress: target) at: 0 in: p.
	self put: (st at: 2) at: 8 in: p.
	self put: (st at: 3) at: 16 in: p.
	6 to: 9 do: [:i | self put: (st at: i) at: i - 6 * 8 + 24 in: p].
	10 to: 17 do: [:i | p float64At: i - 10 * 8 + 57 put: (st at: i) asFloat].
	texture = 0 ifFalse: [self put: (self gpuAddress: texture) at: 120 in: p].
	self put: (st at: 19) at: 128 in: p.
	self put: (st at: 20) at: 136 in: p.
	self put: (self gpuAddress: aBuffer address) + byteOffset at: 144 in: p.
	self put: first at: 152 in: p.
	self put: count at: 160 in: p.
	self put32: (st at: 4) at: 176 in: p.
	self put32: (st at: 5) at: 180 in: p.
	self put32: (st at: 21) at: 184 in: p.
	self put32: (st at: 22) at: 188 in: p.
	self put32: (st at: 23) at: 192 in: p.
	batch add: p.
	batchStarts add: batchSlots.
	batchSlots := batchSlots + slots.
	batchRanges add: (Array with: aBuffer address with: first * 40 + byteOffset with: first + count * 40 + byteOffset).
	texture = 0 ifFalse: [batchUsed add: texture].
	"The scissor within the target holds the draw's clip; the batch's tiles cover the union."
	x0 := (st at: 6) max: 0.
	y0 := (st at: 7) max: 0.
	x1 := (st at: 6) + (st at: 8) min: (st at: 2).
	y1 := (st at: 7) + (st at: 9) min: (st at: 3).
	(x0 < x1 and: [y0 < y1]) ifTrue: [
		self addRect: (Array with: x0 with: y0 with: x1 with: y1).
		batchClip := batchClip isNil
			ifTrue: [Array with: x0 with: y0 with: x1 with: y1]
			ifFalse: [Array with: ((batchClip at: 1) min: x0) with: ((batchClip at: 2) min: y0) with: ((batchClip at: 3) max: x1) with: ((batchClip at: 4) max: y1)]]
!
blit: s rect: sr to: d rect: dr linear: aBoolean
	"raster_blit over the destination rectangle (within the destination) only."
	| p w h |
	w := ((dr at: 1) + (dr at: 3) min: (d at: 2)) - ((dr at: 1) max: 0).
	h := ((dr at: 2) + (dr at: 4) min: (d at: 3)) - ((dr at: 2) max: 0).
	(w > 0 and: [h > 0 and: [(sr at: 3) > 0 and: [(sr at: 4) > 0]]]) ifFalse: [^self].
	self flush.
	p := ByteArray new: (NvRasterKernels sizeOf: #RasterBlitParams).
	self put: (self gpuAddress: s first) at: 0 in: p.
	self put: (s at: 2) at: 8 in: p.
	self put: (s at: 3) at: 16 in: p.
	self put: (self gpuAddress: d first) at: 24 in: p.
	self put: (d at: 2) at: 32 in: p.
	self put: (d at: 3) at: 40 in: p.
	1 to: 4 do: [:i |
		self put: (sr at: i) at: i * 8 + 40 in: p.
		self put: (dr at: i) at: i * 8 + 72 in: p].
	self put32: (s at: 4) at: 112 in: p.
	self put32: (d at: 4) at: 116 in: p.
	self put32: aBoolean at: 120 in: p.
	self launch: 'raster_blit' grid: (Array with: w + 255 // 256 with: (h min: 65535)) parameters: p
		using: (Array with: s first with: d first)
!
present: aSwapchainTexture rects: scissorsOrNil
	"Once the GPU has drawn it (the wait counts as nv.wait while StageTimes measures)."
	| s t |
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	self touch: aSwapchainTexture address.
	s isNil ifFalse: [s add: #'nv.wait' since: t bytes: 0].
	super present: aSwapchainTexture rects: scissorsOrNil
! !

!NvComputeGPU class methodsFor: 'testing'!
isAvailable
	"Whether there may be an NVIDIA GPU to open here: libcuda and the CUDA runtime load and see a device (on: may still fail)."
	^NvCudaDevice isAvailable
!
unavailableReason
	"Why isAvailable is false, for GPUPlatform's note."
	^'no CUDA userspace (libcuda and the CUDA runtime, with a device)'
! !

!NvComputeGPU class methodsFor: 'opening'!
openDevice
	"The GPU, open: libcuda's (NvCudaDevice)."
	^NvCudaDevice open
! !
