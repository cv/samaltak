SoftwareGPU subclass: #NvComputeGPU
	instanceVariableNames: 'gpu compute kernels memories fences lastFence scratch starts'
	classVariableNames: ''
	package: 'Graphics-NV'!

NvComputeGPU comment: 'I am a GPU device on an NVIDIA GPU (the GB10) without its graphics driver: a SoftwareGPU (the gpu primitives'' protocol, handles, errors, the Renderer''s shader only; docs/platform.md) whose memory is the GPU''s (NvDevice, System-NV: system memory both reach) and whose pixel work is the raster kernels (NvRasterKernels: PlatformRaster''s as CUDA kernels, bit-exact with it), launched on one compute channel (NvCompute). docs/nv-gpu.md.

	gpu := NvComputeGPU on: aDisplay.        "opens the GPU; an error where there is none"
	GPUPlatform display: d device: gpu       "or --gpu nv (SAMALTAK_GPU=nv): GPUPlatform chooses me"

Textures, buffers and back buffers are NvMemory (the addresses SoftwareGPU keeps are their CPU addresses). A clear is a raster_fill, a draw raster_prims then raster_tiles (the RasterDrawParams of the pass''s state, a scratch shared by the draws), a blit raster_blit; they are queued when called, in order, and run while the CPU goes on. The CPU waits only where it touches memory a queued launch uses: an upload, a download, a present, freeing; each memory remembers the fence of the last launch that used it. Fences are the channel''s: done when the GPU reached them, fenceElapsed the µs from the command buffer''s first launch to when I saw it done. shaderLanguage is ''raster'': not software (isSoftware is false), and no shader is compiled.

My display presents the BGRA8 back buffer from its CPU address: hosted a HostFramePresenter (SDL_GPU, the VM''s window), on UEFI it would be FirmwareDisplay (the firmware''s screen) once System-NV runs there. close closes the GPU (everything I made goes with it).'!

!NvComputeGPU methodsFor: 'initialization'!
setDisplay: aDisplay
	| cubin |
	super setDisplay: aDisplay.
	memories := Dictionary new.
	fences := Dictionary new.
	starts := Dictionary new.
	lastFence := 0.
	gpu := NvDevice open.
	[compute := gpu newCompute.
	cubin := NvCubin on: NvRasterKernels cubin.
	kernels := Dictionary new.
	NvRasterKernels kernelNames do: [:name | kernels at: name put: (cubin kernelNamed: name)]]
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
		gpu := compute := scratch := nil.
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
	compute wait: lastFence
! !

!NvComputeGPU methodsFor: 'commands'!
submit: cmd fence: wantFence
	"Present what cmd acquired (once the GPU drew it); a fence for what was launched so far, or nil."
	| start f |
	start := starts at: cmd ifAbsent: [nil].
	f := super submit: cmd fence: wantFence.
	f isNil ifTrue: [^nil].
	(self at: f) command: lastFence; address: start; size: nil.
	^f
!
waitFence: fence
	| f |
	f := self at: fence kind: #fence for: 'gpuWaitFence'.
	compute wait: f command.
	self isDone: f
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
	"A fence object: command the channel's fence value, address its command buffer's first launch (µs, nil if none), size its elapsed µs once done."
	aFence size notNil ifTrue: [^true].
	compute channel completedValue >= aFence command ifFalse: [^false].
	aFence size: (aFence address isNil ifTrue: [0] ifFalse: [Time microsecondClockValue - aFence address]).
	^true
!
charge: cmd since: t0
	starts at: cmd ifAbsent: [starts at: cmd put: t0].
	super charge: cmd since: t0
!
drop: h
	starts removeKey: h ifAbsent: [].
	super drop: h
!
gpuAddress: address
	"The GPU address of the memory whose CPU address is address."
	^(memories at: address) gpuAddress
!
launch: aName grid: grid parameters: bytes using: addresses
	"Queue the raster kernel aName (256 threads a block) with its parameter struct; the memory at addresses waits for it."
	| fence |
	fence := compute launch: (kernels at: aName) grid: grid block: 256 arguments: (Array with: bytes).
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
ensureScratch: byteCount
	"A draw's scratch (raster_prims writes it, raster_tiles reads it) of at least byteCount bytes."
	(scratch notNil and: [scratch size >= byteCount]) ifTrue: [^scratch].
	scratch notNil ifTrue: [self free: scratch cpuAddress].
	scratch := nil.
	^scratch := memories at: (self allocate: (byteCount * 2 max: 16r100000))
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
	"Wait for the launches that use the memory at address."
	| f |
	f := fences removeKey: address ifAbsent: [^self].
	compute wait: f
!
fill: address count: n bytesPerPixel: bpp value: anInteger
	| p |
	n > 0 ifFalse: [^self].
	p := ByteArray new: (NvRasterKernels sizeOf: #RasterFillParams).
	self put: (self gpuAddress: address) at: 0 in: p.
	self put: n at: 8 in: p.
	self put32: bpp at: 16 in: p.
	self put32: anInteger at: 20 in: p.
	self launch: 'raster_fill' grid: (n + 255 // 256 min: 4096) parameters: p using: (Array with: address)
!
draw: st buffer: aBuffer offset: byteOffset first: first count: count
	"RasterDrawParams from the state (SoftwareRaster's: target width height format blend, scissor, viewport, viewSize, translate, texture and its width height format, linear repeat), then raster_prims and raster_tiles."
	| slots p target texture cw ch used |
	slots := count // 3.
	slots > 0 ifFalse: [^self].
	self ensureScratch: (NvRasterKernels drawScratchBytes: count).
	target := st at: 1.
	texture := st at: 18.
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
	self put: scratch gpuAddress at: 168 in: p.
	self put32: (st at: 4) at: 176 in: p.
	self put32: (st at: 5) at: 180 in: p.
	self put32: (st at: 21) at: 184 in: p.
	self put32: (st at: 22) at: 188 in: p.
	self put32: (st at: 23) at: 192 in: p.
	used := texture = 0
		ifTrue: [Array with: target with: aBuffer address with: scratch cpuAddress]
		ifFalse: [Array with: target with: aBuffer address with: scratch cpuAddress with: texture].
	self launch: 'raster_prims' grid: slots + 255 // 256 parameters: p using: used.
	"Enough 16 x 16 tiles for the scissor within the target: the clip raster_prims writes is inside it."
	cw := ((st at: 6) + (st at: 8) min: (st at: 2)) - ((st at: 6) max: 0).
	ch := ((st at: 7) + (st at: 9) min: (st at: 3)) - ((st at: 7) max: 0).
	(cw > 0 and: [ch > 0]) ifTrue: [
		self launch: 'raster_tiles' grid: (cw + 15 // 16) * (ch + 15 // 16) parameters: p using: used]
!
blit: s rect: sr to: d rect: dr linear: aBoolean
	| p |
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
