SoftwareGPU subclass: #NvComputeGPU
	instanceVariableNames: 'gpu compute kernels memories fences lastFence scratch starts batch batchStarts batchSlots batchTarget batchClip batchUsed arena arenaOffset stamps stampCount recent blocks'
	classVariableNames: ''
	package: 'Graphics-NV'!

NvComputeGPU comment: 'I am a GPU device on an NVIDIA GPU (the GB10) without its graphics driver: a SoftwareGPU (the gpu primitives'' protocol, handles, errors, the Renderer''s shader only; docs/platform.md) whose memory is the GPU''s (NvDevice, System-NV: system memory both reach) and whose pixel work is the raster kernels (NvRasterKernels: PlatformRaster''s as CUDA kernels, bit-exact with it), launched on one compute channel (NvCompute). docs/nv-gpu.md.

	gpu := NvComputeGPU on: aDisplay.        "opens the GPU; an error where there is none"
	GPUPlatform display: d device: gpu       "or --gpu nv (SAMALTAK_GPU=nv): GPUPlatform chooses me"

Textures, buffers and back buffers are NvMemory (the addresses SoftwareGPU keeps are their CPU addresses). A clear is a raster_fill, a blit raster_blit. Draws are batched: consecutive draws into one target (a pass''s, or several passes'') collect their RasterDrawParams (the pass''s state), and are launched together as raster_batch_prims then raster_batch_tiles (the params in an arena of GPU memory reused as a ring, one scratch) when anything else comes: another target, a clear, a blit, a CPU access, a submit. Launches are queued in order and run while the CPU goes on. The CPU waits only where it touches memory a queued launch uses: an upload, a download, a present, freeing; each memory remembers the fence of the last launch that used it. Fences are the channel''s: done when the GPU reached them. fenceElapsed is the GPU''s time for the command buffer: the GPU''s clock written (a timestamp release) before its first clear, draw or blit and after its last, in a ring of 256 slots. shaderLanguage is ''raster'': not software (isSoftware is false), and no shader is compiled.

My display presents the BGRA8 back buffer from its CPU address: hosted a HostFramePresenter (SDL_GPU, the VM''s window), on UEFI it would be FirmwareDisplay (the firmware''s screen) once System-NV runs there. close closes the GPU (everything I made goes with it).'!

!NvComputeGPU methodsFor: 'initialization'!
setDisplay: aDisplay
	| cubin |
	super setDisplay: aDisplay.
	memories := Dictionary new.
	fences := Dictionary new.
	starts := Dictionary new.
	lastFence := 0.
	self resetBatch.
	gpu := NvDevice open.
	stampCount := 0.
	recent := Array new: 64.
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
	"The NvDevice."
	^gpu
!
compute
	^compute
!
close
	"Close the GPU; every texture, buffer and back buffer goes with it. Safe to call twice."
	gpu isNil ifTrue: [^self].
	[gpu close] ensure: [
		gpu := compute := scratch := arena := stamps := nil.
		self resetBatch.
		memories := Dictionary new.
		fences := Dictionary new]
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
	f isNil ifTrue: [^nil].
	(self at: f) command: lastFence; address: slot; size: nil.
	slot isNil ifFalse: [(self at: f) width: (self stamp: slot * 32 + 16)].
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
	starts removeKey: h ifAbsent: [].
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
	| fence |
	fence := compute launch: (kernels at: aName) grid: grid block: (blocks at: aName) parameters: bytes.
	recent at: fence \\ 64 + 1 put: (Array with: fence with: aName with: grid with: bytes).
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
	batchUsed := Set new
!
flush
	"Launch the batched draws: raster_batch_prims, raster_batch_tiles over the union of their clips."
	| draws startsOf slots target clip used n bytes at p base |
	batch isEmpty ifTrue: [^self].
	draws := batch. startsOf := batchStarts. slots := batchSlots. target := batchTarget. clip := batchClip. used := batchUsed.
	self resetBatch.
	clip isNil ifTrue: [^self].
	n := draws size.
	bytes := ByteArray new: n * 200 + (n + 1 * 8).
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
	used := used asArray, (Array with: target with: scratch cpuAddress with: arena cpuAddress).
	self launch: 'raster_batch_prims' grid: slots + NvRasterKernels batchChunk - 1 // NvRasterKernels batchChunk parameters: p using: used.
	self launch: 'raster_batch_tiles' grid: ((clip at: 3) - (clip at: 1) + 15 // 16) * ((clip at: 4) - (clip at: 2) + 15 // 16)
		parameters: p using: used
!
arenaFor: byteCount
	"Where in the arena (GPU memory for batches' draws, used as a ring) byteCount bytes go; when it starts over, the GPU must be done with what it held."
	| at |
	(arena isNil or: [arena size < byteCount]) ifTrue: [
		arena isNil ifFalse: [self free: arena cpuAddress].
		arena := nil.
		arena := memories at: (self allocate: (byteCount * 2 max: 16r100000)).
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
	"only the kernels use it: the GPU may cache it"
	scratch := gpu allocate: (byteCount * 2 max: 16r100000) gpuCached: true.
	memories at: scratch cpuAddress put: scratch.
	^scratch
! !

!NvComputeGPU methodsFor: 'memory and pixels'!
allocate: byteCount
	| m |
	m := gpu allocate: (byteCount max: 1).
	memories at: m cpuAddress put: m.
	^m cpuAddress
!
free: address
	| m |
	self touch: address.
	m := memories removeKey: address ifAbsent: [^self].
	m free
!
touch: address
	"Wait for the launches that use the memory at address (the batched draws launched first)."
	| f |
	self flush.
	f := fences removeKey: address ifAbsent: [^self].
	compute wait: f
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
	batchUsed add: aBuffer address.
	texture = 0 ifFalse: [batchUsed add: texture].
	"The scissor within the target holds the draw's clip; the batch's tiles cover the union."
	x0 := (st at: 6) max: 0.
	y0 := (st at: 7) max: 0.
	x1 := (st at: 6) + (st at: 8) min: (st at: 2).
	y1 := (st at: 7) + (st at: 9) min: (st at: 3).
	(x0 < x1 and: [y0 < y1]) ifTrue: [
		batchClip := batchClip isNil
			ifTrue: [Array with: x0 with: y0 with: x1 with: y1]
			ifFalse: [Array with: ((batchClip at: 1) min: x0) with: ((batchClip at: 2) min: y0) with: ((batchClip at: 3) max: x1) with: ((batchClip at: 4) max: y1)]]
!
blit: s rect: sr to: d rect: dr linear: aBoolean
	| p |
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
	self launch: 'raster_blit' grid: (Array with: (d at: 2) + 255 // 256 with: ((d at: 3) min: 65535)) parameters: p
		using: (Array with: s first with: d first)
!
present: aSwapchainTexture
	"Once the GPU has drawn it."
	self touch: aSwapchainTexture address.
	super present: aSwapchainTexture
! !

!NvComputeGPU class methodsFor: 'testing'!
isAvailable
	"Whether there may be an NVIDIA GPU to open here (on: may still fail)."
	^NvDevice isAvailable
! !
