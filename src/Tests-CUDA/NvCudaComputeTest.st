TestCase subclass: #NvCudaComputeTest
	instanceVariableNames: 'gpu compute cubin'
	classVariableNames: ''
	package: 'Tests-CUDA'!

NvCudaComputeTest comment: 'Tests NvCudaDevice and NvCudaCompute on the GPU (the GB10): memory, the test kernels (NvTestKernels) loaded by libcuda (cuModuleLoadData) and launched by cuLaunchKernel, their results checked from Smalltalk; fences, local memory, shared memory, constant banks, launch dimensions and limits. Then what CUDA gives besides: a kernel NVRTC compiled from a Smalltalk String writing a CudaMatrix that cuBLAS multiplies on the same stream, no host copy; the VM refusing an image that is not a whole cubin or PTX; a module''s functions going with it; timestamps. Needs a GPU and libcuda, so it does not run by default (runsByDefault): make test-nv runs it, and it fails, saying so, where there is none. tearDown closes the device, which frees what the test made.'!

!NvCudaComputeTest methodsFor: 'running'!
setUp
	NvCudaDevice isAvailable ifFalse: [^self error: 'no CUDA here (libcuda and libcudart, and a GPU): NvCudaComputeTest needs them'].
	cubin := NvTestKernels cubin.
	gpu := NvCudaDevice open
!
tearDown
	gpu notNil ifTrue: [gpu close]
!
compute
	^compute ifNil: [compute := gpu newCompute]
!
kernel: aString
	^cubin kernelNamed: aString
!
timeLimitMilliseconds
	^60000
! !

!NvCudaComputeTest methodsFor: 'tests'!
testFencesAcrossMany
	"Many fences, each the newest value; the GPU reaches the last."
	| ch f |
	ch := self compute channel.
	1 to: 5000 do: [:i |
		f := ch fence.
		f = ch lastFence ifFalse: [^self assert: false description: 'fence ', f printString, ' is not the newest, ', ch lastFence printString]].
	ch wait: f.
	self assert: ch completedValue equals: f
!
testMemory
	| m |
	m := gpu allocate: 10000.
	self assert: m size equals: 12288.
	self assert: m gpuAddress > 0.
	self assert: (m uint32At: 0) equals: 0.
	m uint64At: 8 put: 16r123456789ABCDEF.
	self assert: (m uint64At: 8) equals: 16r123456789ABCDEF.
	m bytesAt: 100 put: #[1 2 3].
	self assert: (m bytesAt: 100 count: 3) equals: #[1 2 3].
	self should: [m uint32At: 12288] raise: Error.
	m free.
	self assert: m isFreed.
	self deny: (gpu memories includes: m)
!
testFill
	| m |
	m := gpu allocate: 4096 * 4.
	self compute run: (self kernel: 'fill') grid: 16 block: 256 arguments: (Array with: m gpuAddress with: 16rCAFEF00D with: 4000).
	self assert: (m uint32At: 0) equals: 16rCAFEF00D.
	self assert: (m uint32At: 3999 * 4) equals: 16rCAFEF00D.
	self assert: (m uint32At: 4000 * 4) equals: 0
!
testVectorAdd
	| n a b c bytes |
	n := 10000.
	a := gpu allocate: n * 4.
	b := gpu allocate: n * 4.
	c := gpu allocate: n * 4.
	bytes := ByteArray new: n * 4.
	0 to: n - 1 do: [:i | bytes float32At: i * 4 + 1 put: i asFloat].
	a bytesAt: 0 put: bytes.
	0 to: n - 1 do: [:i | bytes float32At: i * 4 + 1 put: (i * 2 + 0.5)].
	b bytesAt: 0 put: bytes.
	self compute run: (self kernel: 'vadd') grid: n + 255 // 256 block: 256 arguments: (Array with: a gpuAddress with: b gpuAddress with: c gpuAddress with: n).
	bytes := c bytesAt: 0 count: n * 4.
	self assert: ((0 to: n - 1) allSatisfy: [:i | (bytes float32At: i * 4 + 1) = (i * 3 + 0.5)])
!
testLaunchDimensions
	| m |
	m := gpu allocate: 4096.
	self compute run: (self kernel: 'dims') grid: #(3 2 1) block: #(4 5 6) arguments: (Array with: m gpuAddress).
	self assert: ((0 to: 5) collect: [:i | m uint32At: i * 4]) equals: #(4 5 6 3 2 1)
!
testSharedMemory
	| m |
	m := gpu allocate: 8 * 256 * 4.
	0 to: 8 * 256 - 1 do: [:i | m uint32At: i * 4 put: i].
	self compute run: (self kernel: 'reverse256') grid: 8 block: 256 arguments: (Array with: m gpuAddress).
	self assert: (m uint32At: 0) equals: 255.
	self assert: (m uint32At: 255 * 4) equals: 0.
	self assert: (m uint32At: 256 * 4) equals: 511
!
testConstantBank
	| m |
	m := gpu allocate: 4096.
	self compute run: (self kernel: 'lookup') grid: 1 block: 64 arguments: (Array with: m gpuAddress with: 64).
	self assert: ((0 to: 5) collect: [:i | m uint32At: i * 4]) equals: #(16r11111111 16r22222223 16r33333335 16r44444447 16r11111115 16r22222227)
!
testManyLaunches
	"Launches queued back to back, one wait for the last."
	| m k fences |
	m := gpu allocate: 4096.
	k := self kernel: 'fill'.
	fences := (1 to: 200) collect: [:i | self compute launch: k grid: 1 block: 32 arguments: (Array with: m gpuAddress with: i with: 32)].
	self compute wait: fences last.
	self assert: (m uint32At: 0) equals: 200
!
testBadLaunch
	self should: [self compute launch: (self kernel: 'copy16') grid: 1 block: 512 arguments: #(0 0 0)] raise: Error.
	self should: [self compute launch: (self kernel: 'fill') grid: 1 block: 32 arguments: #(0)] raise: Error
!
testOpen
	self assert: gpu isOpen.
	self assert: gpu computeCapability >= 100.
	self assert: gpu smCount > 0.
	self assert: (gpu arch beginsWith: 'sm_')
!
testChannelFence
	| c |
	c := self compute channel.
	c sync.
	self assert: c completedValue equals: 1.
	1 to: 100 do: [:i | c fence].
	c sync.
	self assert: c completedValue equals: 102
!
testLocalMemory
	"local1k has a 1 KB stack frame: the driver gives the threads the local memory it needs; each sees its own."
	| k p n |
	k := self kernel: 'local1k'.
	self assert: k frameSize >= 1024.
	n := 3000.
	p := gpu allocate: n * 4.
	self compute run: k grid: n + 255 // 256 block: 256 arguments: (Array with: p gpuAddress with: n).
	0 to: n - 1 do: [:i |
		(p uint32At: i * 4) = (768 * i + 32640 bitAnd: 16rFFFFFFFF)
			ifFalse: [^self assert: false description: 'thread ', i printString, ': ', (p uint32At: i * 4) printString]].
	self compute run: (self kernel: 'fill') grid: 1 block: 256 arguments: (Array with: p gpuAddress with: 7 with: 1).
	self assert: (p uint32At: 0) equals: 7
!
testCloseFreesEverything
	| before |
	before := CudaLibraryAPI liveAllocations.
	self compute run: (self kernel: 'fill') grid: 1 block: 32 arguments: (Array with: (gpu allocate: 4096) gpuAddress with: 1 with: 32).
	self assert: gpu computes size equals: 1.
	gpu close.
	self deny: gpu isOpen.
	self assert: CudaLibraryAPI liveAllocations <= before.
	gpu close
!
testMemoryIsACudaAllocation
	"Memory of the device is a CUDA allocation the VM checks against: cuBLAS takes its address."
	| m |
	m := gpu allocate: 16.
	0 to: 3 do: [:i | m uint32At: i * 4 put: 16r40000000 "2.0 as a float32"].
	self assert: ((CublasAPI cublasSnrm2: Cuda blas n: 4 x: m gpuAddress incx: 1) - 4.0) abs < 1.0e-5.
	self should: [CublasAPI cublasSnrm2: Cuda blas n: 4 x: m gpuAddress + 4088 incx: 1] raise: CudaArgumentError
!
testKernelWritesACudaArray
	| a |
	a := CudaArray new: 1000 type: #float32.
	[self compute run: (self kernel: 'fill') grid: 4 block: 256 arguments: (Array with: a with: 16r3FC00000 with: 1000).
	self assert: (a asArray asSet asArray) equals: #(1.5)]
		ensure: [a release]
!
testNvrtcKernelThenCublas
	"A kernel compiled from Smalltalk (NVRTC) fills a CudaMatrix with the Hilbert matrix; cuBLAS multiplies it, after the kernel on the same stream: no host copy, no wait between."
	| k n a c rows worst |
	NvRtc isAvailable ifFalse: [^self].
	k := Cuda kernelNamed: 'hilbert' source: 'extern "C" __global__ void hilbert(float *a, int n) { int i = blockIdx.x * blockDim.x + threadIdx.x; if (i < n * n) a[i] = 1.0f / (i / n + i % n + 1); }'.
	n := 48.
	a := CudaMatrix rows: n cols: n.
	[Cuda compute launch: k grid: n * n + 255 // 256 block: 256 arguments: {a. n}.
	c := a * a.
	rows := c asRows.
	worst := 0.
	1 to: n do: [:i | 1 to: n do: [:j | | sum |
		sum := 0.0.
		1 to: n do: [:m | sum := sum + (1.0 / (i + m - 1) * (1.0 / (m + j - 1)))].
		worst := worst max: (((rows at: i) at: j) - sum) abs]].
	self assert: worst < 1.0e-5]
		ensure: [a release. c ifNotNil: [c release]]
!
testRefusedImages
	"cuModuleLoadData gets a whole CUDA ELF or NUL-terminated PTX, nothing else: the VM refuses the rest before the driver reads it."
	| e |
	#(#[] #[1 2 3] #[127 69 76 70 2 1]) do: [:bytes |
		e := [CudaDriverAPI cuModuleLoadData: bytes. nil] on: CudaArgumentError do: [:err | err].
		self assert: e notNil.
		self assert: e code equals: -7].
	e := [CudaDriverAPI cuModuleLoadData: (cubin bytes copyFrom: 1 to: cubin bytes size // 2). nil] on: CudaArgumentError do: [:err | err].
	self assert: e notNil.
	e := [CudaDriverAPI cuModuleLoadData: '.version 7.0' asByteArray. nil] on: CudaArgumentError do: [:err | err].
	self assert: e notNil
!
testUnloadForgetsFunctions
	| before m f |
	before := CudaLibraryAPI liveHandles.
	m := CudaDriverAPI cuModuleLoadData: cubin bytes.
	f := CudaDriverAPI cuModuleGetFunction: m name: 'fill'.
	self assert: CudaLibraryAPI liveHandles equals: before + 2.
	CudaDriverAPI cuModuleUnload: m.
	self assert: CudaLibraryAPI liveHandles equals: before.
	self should: [CudaDriverAPI cuFuncGetAttribute: 0 hfunc: f] raise: CudaArgumentError
!
testForgetUnloadsTheModule
	| k before |
	k := self kernel: 'fill'.
	before := CudaLibraryAPI liveHandles.
	self compute run: k grid: 1 block: 32 arguments: (Array with: (gpu allocate: 4096) gpuAddress with: 1 with: 32).
	self assert: CudaLibraryAPI liveHandles equals: before + 2.
	self compute forget: k.
	self assert: CudaLibraryAPI liveHandles equals: before
!
testTimestamp
	| m t0 |
	m := gpu allocate: 4096.
	self compute channel timestamp: m gpuAddress payload: 42.
	self compute run: (self kernel: 'fill') grid: 1 block: 32 arguments: (Array with: m gpuAddress + 64 with: 1 with: 32).
	self compute channel timestamp: m gpuAddress + 16 payload: 43.
	self compute sync.
	self assert: (m uint64At: 0) equals: 42.
	self assert: (m uint64At: 16) equals: 43.
	t0 := m uint64At: 8.
	self assert: t0 > 0.
	self assert: (m uint64At: 24) >= t0
! !

!NvCudaComputeTest class methodsFor: 'testing'!
runsByDefault
	"I need an NVIDIA GPU and libcuda: make test-nv runs me."
	^false
! !
