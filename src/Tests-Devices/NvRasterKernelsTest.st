TestCase subclass: #NvRasterKernelsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Devices'!

NvRasterKernelsTest comment: 'NvRasterKernels without a GPU: the cubin decodes to the bytes tools/nv-kernels.py checked in (size, SHA-256, an ELF64 for CUDA naming every kernel), the ABI agrees with itself (each kernel''s parameter bytes are its struct''s size), and params:with: lays out a struct. The kernels themselves run in make test-nv (tests/nv, docs/nv-kernels.md).'!

!NvRasterKernelsTest methodsFor: 'tests'!
testTheCubinIsTheCheckedInOne
	| cubin |
	cubin := NvRasterKernels cubin.
	self assert: cubin size equals: NvRasterKernels cubinSize.
	self assert: (SHA256 hash: cubin) hex asLowercase equals: NvRasterKernels cubinSHA256.
	self assert: (cubin copyFrom: 1 to: 4) equals: #[127 69 76 70].
	self assert: (cubin at: 5) equals: 2.
	self assert: (cubin at: 19) + ((cubin at: 20) * 256) equals: 190
!
testEveryKernelIsInTheCubin
	| text |
	text := NvRasterKernels cubin asString.
	NvRasterKernels kernelNames do: [:each |
		self assert: (text includesSubstring: '.text.' , each)]
!
testTheParametersAreTheirStructs
	NvRasterKernels kernelNames do: [:each | | k |
		k := NvRasterKernels kernel: each.
		self assert: (k at: #entry) equals: each.
		self assert: (k at: #paramBytes) equals: (NvRasterKernels sizeOf: (k at: #params) asSymbol).
		self assert: (k at: #paramOffset) + (k at: #paramBytes) <= (k at: #constantBank0Bytes).
		self assert: (k at: #block) equals: (each = 'raster_batch_prims' ifTrue: [NvRasterKernels batchChunk] ifFalse: [256]).
		self assert: (k at: #frameBytes) equals: 0].
	self assert: ((NvRasterKernels kernel: 'raster_tiles') at: #params) equals: ((NvRasterKernels kernel: 'raster_prims') at: #params).
	self assert: ((NvRasterKernels kernel: 'raster_batch_tiles') at: #params) equals: ((NvRasterKernels kernel: 'raster_batch_prims') at: #params).
	self assert: (NvRasterKernels drawScratchBytes: 7) equals: NvRasterKernels scratchHeader + (2 * NvRasterKernels primBytes)
!
testParamsLaysOutAStruct
	| bytes |
	bytes := NvRasterKernels params: #RasterFillParams with: {#pixels -> 16r123456789A. #count -> 2073600. #bpp -> 4. #value -> 16rFF00FF00}.
	self assert: bytes size equals: 24.
	self assert: (bytes uint32At: 1) equals: 16r3456789A.
	self assert: (bytes uint32At: 5) equals: 16r12.
	self assert: (bytes uint32At: 9) equals: 2073600.
	self assert: (bytes uint32At: 17) equals: 4.
	self assert: (bytes uint32At: 21) equals: 16rFF00FF00.
	bytes := NvRasterKernels params: #RasterBlitParams with: {#srcRect -> #(1 2 3 4). #dstRect -> {-1. 0. 5. 6}. #linear -> true}.
	self assert: (bytes uint32At: 49 + 24) equals: 4.
	self assert: (bytes uint32At: 81) equals: 16rFFFFFFFF.
	self assert: (bytes uint32At: 85) equals: 16rFFFFFFFF.
	self assert: (bytes uint32At: 121) equals: 1.
	bytes := NvRasterKernels params: #RasterDrawParams with: {#viewSizeX -> 1920}.
	self assert: (bytes float64At: 89) equals: 1920.0.
	self should: [NvRasterKernels params: #RasterFillParams with: {#nonsense -> 1}] raise: Error
! !
