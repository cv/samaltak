Object subclass: #Cuda
	instanceVariableNames: 'session blas rng device compute kernels'
	classVariableNames: 'Default'
	package: 'System-CUDA'!

Cuda comment: 'I am the CUDA device as NVIDIA''s CUDA libraries see it (docs/cuda.md): the runtime''s implicit context (its primary context on device 0, made on first use), its cuBLAS handle and cuRAND generator, made once a VM session. CudaArray and CudaMatrix keep data in its memory; CudaEvent times work on it; CuOpt solves on it. Everything goes through the generated bindings (CudaRuntimeAPI, CudaDriverAPI, CublasAPI, CurandAPI, CuOptAPI).

	Cuda isAvailable.
	Cuda summary.          "the device, its memory, the library versions"
	((CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6)) * (CudaMatrix rows: 3 cols: 2 values: #(1 0 0 1 1 1))) asRows'!

!Cuda class methodsFor: 'testing'!
isAvailable
	"Whether the CUDA runtime is here with a device."
	CudaRuntimeAPI isAvailable ifFalse: [^false].
	^([CudaRuntimeAPI cudaGetDeviceCount] on: CudaError do: [:e | 0]) > 0
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
synchronize
	"Wait until the device has done all work queued so far."
	CudaRuntimeAPI cudaDeviceSynchronize
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
	self isAvailable ifFalse: [^'no CUDA here (no libcudart, or no device)'].
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
	^kernels at: key ifAbsent: [| r |
		r := NvRtc compile: cudaSource options: (Array with: '-arch=', self compute device arch with: '-std=c++17').
		r first isNil ifTrue: [^self error: 'NVRTC: ', r last].
		kernels at: key put: ((NvCubin on: r first) kernelNamed: aString)]
! !
