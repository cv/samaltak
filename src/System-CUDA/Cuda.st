Object subclass: #Cuda
	instanceVariableNames: 'session blas rng device compute kernels solver solverParams fftPlans workspace bufferSizes fused fusedOrder scratch'
	classVariableNames: 'Default Compilers FftPlanLimit WorkspaceLimit'
	package: 'System-CUDA'!

Cuda comment: 'I am the CUDA device as NVIDIA''s CUDA libraries see it (docs/cuda.md): the runtime''s implicit context (its primary context on device 0, made on first use), its cuBLAS handle, cuRAND generator and cuSOLVER handle, made once a VM session, and its caches: cuFFT plans by shape (fftPlan:kind:type:batch:, the last fftPlanLimit), one work area for the libraries'' calls (workspace:) and their buffer sizes by shape, the kernels compiled from Smalltalk (kernelNamed:source:, CudaExpression''s fused kernels: fusedKernel:source:; their cubins in an NvRtcCache, compiler). releaseCaches frees the plans and the work area now; a new session (a restored snapshot) starts without them. CudaArray and CudaMatrix keep data in its memory; CudaEvent times work on it; CuOpt solves on it. Everything goes through the generated bindings (CudaRuntimeAPI, CudaDriverAPI, CublasAPI, CurandAPI, CusolverAPI, CufftAPI, CuOptAPI).

	Cuda isAvailable.
	Cuda summary.          "the device, its memory, the library versions"
	((CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6)) * (CudaMatrix rows: 3 cols: 2 values: #(1 0 0 1 1 1))) asRows'!

!Cuda class methodsFor: 'testing'!
isAvailable
	"Whether the CUDA runtime is here with a device."
	CudaRuntimeAPI isAvailable ifFalse: [^false].
	^([CudaRuntimeAPI cudaGetDeviceCount] on: CudaError do: [:e | 0]) > 0
!
unavailableReason
	"Why isAvailable is false, or nil: the runtime is not here, or its own words for having no device, e.g. 'cudaGetDeviceCount: cudaErrorNoDevice (no CUDA-capable device is detected)' (the Linux appliance without a GPU), 'cudaErrorInsufficientDriver' (no nvidia.ko, or one of another version)."
	| n |
	CudaRuntimeAPI isAvailable ifFalse: [^'no CUDA runtime (libcudart: SAMALTAK_CUDA_LIBS names the directories to look in)'].
	n := [CudaRuntimeAPI cudaGetDeviceCount] on: CudaError do: [:e | ^e messageText].
	n > 0 ifFalse: [^'no device'].
	^nil
! !

!Cuda class methodsFor: 'accessing'!
default
	"The device of this VM session."
	(Default notNil and: [Default isCurrent]) ifFalse: [Default := self new setSession].
	^Default
!
session
	^CudaLibraryAPI session
!
blas
	^self default blas
!
rng
	^self default rng
!
compute
	"This session's NvCudaCompute: kernels launched on the stream cuBLAS and cuRAND use, so they and CudaArrays work together in order."
	^self default compute
!
kernelNamed: aString source: cudaSource
	"The kernel aString (extern ""C"") of the CUDA C++ cudaSource, compiled by NVRTC for this device (once a session per source): an NvKernel for Cuda compute.

	k := Cuda kernelNamed: 'scale' source: 'extern ""C"" __global__ void scale(float *a, float s, int n) { int i = blockIdx.x * blockDim.x + threadIdx.x; if (i < n) a[i] *= s; }'.
	Cuda compute run: k grid: 4 block: 256 arguments: {aCudaArray. 2.0. 1000}"
	^self default kernelNamed: aString source: cudaSource
!
solver
	^self default solver
!
solverParams
	^self default solverParams
!
synchronize
	"Wait until the device has done all work queued so far."
	CudaRuntimeAPI cudaDeviceSynchronize
!
fftPlan: dims kind: aSymbol type: aType batch: anInteger
	^self default fftPlan: dims kind: aSymbol type: aType batch: anInteger
!
workspace: bytes
	^self default workspace: bytes
!
releaseWorkspace: anArray
	^self default releaseWorkspace: anArray
!
bufferSize: key ifAbsent: aBlock
	^self default bufferSize: key ifAbsent: aBlock
!
releaseCaches
	"Free this session's kept cuFFT plans, work area and fused kernels now (they are made again when needed)."
	(Default notNil and: [Default isCurrent]) ifTrue: [Default releaseCaches]
! !

!Cuda class methodsFor: 'settings'!
fftPlanLimit
	"How many cuFFT plans a session keeps (each holds its work area on the device)."
	^FftPlanLimit ifNil: [8]
!
fftPlanLimit: anInteger
	FftPlanLimit := anInteger
!
workspaceLimit
	"The largest work area a session keeps for the libraries (bytes); a larger one is made and freed by the call that needs it."
	^WorkspaceLimit ifNil: [1024 * 1024 * 1024]
!
workspaceLimit: anInteger
	WorkspaceLimit := anInteger
! !

!Cuda class methodsFor: 'describing'!
deviceName
	| buffer end |
	buffer := ByteArray new: 256.
	CudaDriverAPI cuInit: 0.
	CudaDriverAPI cuDeviceGetName: buffer len: 256 dev: (CudaDriverAPI cuDeviceGet: 0).
	end := buffer indexOf: 0.
	^(buffer copyFrom: 1 to: (end = 0 ifTrue: [256] ifFalse: [end - 1])) asString
!
memoryInfo
	"{free bytes. total bytes} of the device."
	^CudaRuntimeAPI cudaMemGetInfo
!
computeCapability
	^(CudaRuntimeAPI cudaDeviceGetAttribute: (CudaRuntimeAPI constant: 'cudaDevAttrComputeCapabilityMajor') device: 0) printString , '.' ,
		(CudaRuntimeAPI cudaDeviceGetAttribute: (CudaRuntimeAPI constant: 'cudaDevAttrComputeCapabilityMinor') device: 0) printString
!
multiprocessorCount
	^CudaRuntimeAPI cudaDeviceGetAttribute: (CudaRuntimeAPI constant: 'cudaDevAttrMultiProcessorCount') device: 0
!
versionString: anInteger
	"CUDA's version numbers: 13000 is 13.0."
	^(anInteger // 1000) printString , '.' , (anInteger \\ 1000 // 10) printString
!
summary
	"One line about the device and the libraries, e.g. NVIDIA GB10, compute 12.1, 48 SMs, 119.6 GB (110.2 free); CUDA runtime 13.0, driver 13.0; cuBLAS 130100; cuRAND 10400."
	| memory gb |
	self isAvailable ifFalse: [^'no CUDA here: ' , self unavailableReason].
	memory := self memoryInfo.
	gb := [:bytes | (bytes / 1.0e9 printShowingDecimalPlaces: 1) , ' GB'].
	^String streamContents: [:s |
		s nextPutAll: self deviceName; nextPutAll: ', compute '; nextPutAll: self computeCapability;
			nextPutAll: ', '; print: self multiprocessorCount; nextPutAll: ' SMs, ';
			nextPutAll: (gb value: memory last); nextPutAll: ' ('; nextPutAll: (gb value: memory first); nextPutAll: ' free); CUDA runtime ';
			nextPutAll: (self versionString: CudaRuntimeAPI cudaRuntimeGetVersion); nextPutAll: ', driver ';
			nextPutAll: (self versionString: CudaRuntimeAPI cudaDriverGetVersion).
		CublasAPI isAvailable ifTrue: [s nextPutAll: '; cuBLAS '; print: (CublasAPI cublasGetVersion: self blas)].
		CurandAPI isAvailable ifTrue: [s nextPutAll: '; cuRAND '; print: CurandAPI curandGetVersion].
		CusolverAPI isAvailable ifTrue: [s nextPutAll: '; cuSOLVER '; print: CusolverAPI cusolverGetVersion].
		CufftAPI isAvailable ifTrue: [s nextPutAll: '; cuFFT '; print: CufftAPI cufftGetVersion].
		CuOptAPI isAvailable ifTrue: [s nextPutAll: '; cuOpt '; nextPutAll: CuOpt version]]
! !

!Cuda methodsFor: 'accessing'!
setSession
	session := CudaLibraryAPI session
!
isCurrent
	^session = CudaLibraryAPI session
!
blas
	"This session's cuBLAS handle (made on first use)."
	^blas ifNil: [blas := CublasAPI cublasCreate]
!
rng
	"This session's cuRAND generator (the default pseudo-random one)."
	^rng ifNil: [rng := CurandAPI curandCreateGenerator: (CurandAPI constant: 'CURAND_RNG_PSEUDO_DEFAULT')]
!
compute
	"This session's NvCudaCompute (on an NvCudaDevice of its own; made on first use)."
	^compute ifNil: [
		device := NvCudaDevice open.
		compute := device newCompute]
!
kernelNamed: aString source: cudaSource
	| key |
	kernels isNil ifTrue: [kernels := Dictionary new].
	key := aString -> cudaSource.
	^kernels at: key ifAbsent: [| cubin |
		cubin := self compiler cubinFor: cudaSource ifFail: [:log | ^self error: 'NVRTC: ', log].
		kernels at: key put: ((NvCubin on: cubin) kernelNamed: aString)]
!
compiler
	"The NvRtcCache of this device's code (-arch=sm_121 on the GB10): cubins by their source's SHA-256, kept across sessions."
	| arch |
	arch := self compute device arch.
	Compilers isNil ifTrue: [Compilers := Dictionary new].
	^Compilers at: arch ifAbsent: [Compilers at: arch put: (NvRtcCache options: (Array with: '-arch=', arch with: '-std=c++17'))]
!
fusedKernel: signature source: sourceBlock
	"The kernel samaltak_fused of the CUDA C++ sourceBlock makes, for the expressions of the shape signature (CudaExpression: types, broadcasting, operations): compiled the first time a session (or found by its source's hash in compiler), nil if it does not compile or there is no NVRTC (remembered too). The last 256 shapes are kept."
	| kernel |
	fused isNil ifTrue: [fused := Dictionary new. fusedOrder := OrderedCollection new].
	^fused at: signature ifAbsent: [
		kernel := NvRtc isAvailable ifTrue: [
			(self compiler cubinFor: sourceBlock value ifFail: [:log | CudaExpression noteFailure: log. nil])
				ifNotNil: [:cubin | (NvCubin on: cubin) kernelNamed: 'samaltak_fused']].
		[fused size >= 256 and: [fusedOrder notEmpty]] whileTrue: [
			(fused removeKey: fusedOrder removeFirst ifAbsent: [nil]) ifNotNil: [:old | compute notNil ifTrue: [compute forget: old]]].
		fusedOrder addLast: signature.
		fused at: signature put: kernel]
!
fusedKernelCount
	^fused isNil ifTrue: [0] ifFalse: [(fused select: [:k | k notNil]) size]
!
fftPlan: dims kind: aSymbol type: aType batch: anInteger
	"A cuFFT plan for batch transforms of the shape dims, of kind #r2c, #c2r or #c2c (both directions), in aType: kept from an earlier call (the most recently used first), or made and kept; past fftPlanLimit the least recently used is destroyed. Do not release it: releaseCaches does, and a new session forgets them."
	| shape real plan |
	fftPlans isNil ifTrue: [fftPlans := OrderedCollection new].
	shape := dims asArray.
	real := CudaArray realTypeOf: aType.
	plan := fftPlans detect: [:p | p kind == aSymbol and: [p type == real and: [p batch = anInteger and: [p shape = shape]]]] ifNone: [nil].
	plan notNil ifTrue: [
		plan isAlive ifTrue: [
			fftPlans first == plan ifFalse: [fftPlans remove: plan. fftPlans addFirst: plan].
			^plan].
		fftPlans remove: plan].
	plan := CudaFFTPlan shape: shape kind: aSymbol type: aType batch: anInteger.
	fftPlans addFirst: plan.
	[fftPlans size > self class fftPlanLimit] whileTrue: [fftPlans removeLast release].
	^plan
!
fftPlans
	"The kept cuFFT plans, the most recently used first."
	^fftPlans ifNil: [#()]
!
workspace: bytes
	"Device memory of at least bytes bytes for a library call's work area (cuSOLVER's): this session's one, grown as asked, up to workspaceLimit; a larger one is the call's own. Calls run on the one stream one after another, so each can use it whole. Give it back with releaseWorkspace:."
	bytes > self class workspaceLimit ifTrue: [^CudaArray workspace: bytes].
	(workspace notNil and: [workspace isAlive and: [workspace byteSize >= bytes]]) ifTrue: [^workspace].
	(workspace notNil and: [workspace isAlive]) ifTrue: [workspace release].
	workspace := nil.
	workspace := CudaArray workspace: (bytes max: 65536).
	^workspace
!
releaseWorkspace: anArray
	"A call is done with anArray, which workspace: gave it: free it unless it is the session's kept one."
	(anArray isNil or: [anArray == workspace]) ifTrue: [^self].
	anArray release
!
bufferSize: key ifAbsent: aBlock
	"A library's work area size for key (the routine, the shape and the type), asked once (aBlock: the library's *BufferSize call) and kept."
	bufferSizes isNil ifTrue: [bufferSizes := Dictionary new].
	^bufferSizes at: key ifAbsent: [
		bufferSizes size >= 512 ifTrue: [bufferSizes := Dictionary new].
		bufferSizes at: key put: aBlock value]
!
reductionScratch
	"A float64 CudaArray of 4096 values for a reduction's partial results, taken (give it back with returnScratch:): a reduction reads it back before another can use it."
	| s |
	s := scratch.
	scratch := nil.
	(s notNil and: [s isAlive]) ifTrue: [^s].
	^CudaArray new: 4096 type: #float64
!
returnScratch: anArray
	(scratch isNil and: [anArray isAlive]) ifTrue: [^scratch := anArray].
	anArray release
!
releaseCaches
	"Free the kept cuFFT plans, work area and reduction scratch, and forget the fused kernels (their modules unloaded)."
	fftPlans notNil ifTrue: [fftPlans do: [:p | p release]. fftPlans := nil].
	(workspace notNil and: [workspace isAlive]) ifTrue: [workspace release].
	(scratch notNil and: [scratch isAlive]) ifTrue: [scratch release].
	workspace := scratch := bufferSizes := nil.
	fused notNil ifTrue: [
		compute notNil ifTrue: [fused do: [:k | k notNil ifTrue: [compute forget: k]]].
		fused := fusedOrder := nil]
!
solver
	"This session's cuSOLVER dense handle (made on first use)."
	^solver ifNil: [solver := CusolverAPI cusolverDnCreate]
!
solverParams
	"The cusolverDnParams of the 64-bit API's calls (the default algorithms)."
	^solverParams ifNil: [solverParams := CusolverAPI cusolverDnCreateParams]
! !
