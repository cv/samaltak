Object subclass: #NvCudaDevice
	instanceVariableNames: 'memories computes session'
	classVariableNames: ''
	package: 'System-CUDA'!

NvCudaDevice comment: 'I am the NVIDIA GPU as NVIDIA''s CUDA userspace gives it (libcuda and the runtime, docs/cuda.md), with NvDevice''s protocol for what launches kernels: allocate: answers memory the GPU and the CPU both reach (an NvCudaMemory: CUDA''s pinned host memory, a CUDA allocation the VM knows, so cuBLAS and the image''s kernels can use it too), newCompute an NvCudaCompute (NvCompute''s protocol over cuModuleLoadData and cuLaunchKernel). Everything runs in the CUDA runtime''s primary context on device 0 and its default stream, the context and stream of Cuda, CudaArray, cuBLAS and cuRAND: a kernel launched here and a cuBLAS call on the same CudaArray are ordered on the device, without a host round trip. NvComputeGPU opens me where libcuda loads (NvComputeGPU class>>backend), System-NV''s NvDevice (the RM ioctls) elsewhere.

	NvCudaDevice during: [:gpu | | compute kernel a |
		compute := gpu newCompute.
		kernel := NvTestKernels cubin kernelNamed: ''fill''.
		a := gpu allocate: 4096.
		compute run: kernel grid: 4 block: 256 arguments: {a gpuAddress. 7. 1024}.
		a uint32At: 4092]                                          "7"

close frees what I made (memories, the computes'' modules); during: closes even when its block fails.'!

!NvCudaDevice class methodsFor: 'instance creation'!
open
	"The CUDA device, opened (its primary context made current); an error where there is no CUDA. Close it when done."
	^self new open
!
during: aBlock
	"aBlock's value with the CUDA device, open; closed after, whatever happens."
	| d |
	d := self open.
	^[aBlock value: d] ensure: [d close]
!
isAvailable
	"Whether libcuda and the CUDA runtime load here and see a device."
	^CudaDriverAPI isAvailable and: [Cuda isAvailable]
! !

!NvCudaDevice methodsFor: 'opening'!
open
	"Make the runtime's primary context on device 0 current on this thread: the driver API's module and launch calls run in it."
	CudaRuntimeAPI cudaSetDevice: 0.
	CudaRuntimeAPI cudaFree: 0.
	memories := OrderedCollection new.
	computes := OrderedCollection new.
	session := CudaLibraryAPI session
! !

!NvCudaDevice methodsFor: 'accessing'!
isOpen
	^memories notNil and: [session = CudaLibraryAPI session]
!
memories
	^memories
!
computes
	^computes
!
computeCapability
	"major * 10 + minor: 121 on the GB10."
	^(CudaRuntimeAPI cudaDeviceGetAttribute: (CudaRuntimeAPI constant: 'cudaDevAttrComputeCapabilityMajor') device: 0) * 10 +
		(CudaRuntimeAPI cudaDeviceGetAttribute: (CudaRuntimeAPI constant: 'cudaDevAttrComputeCapabilityMinor') device: 0)
!
smVersion
	"The SM version as the cubins name it (121 for sm_121)."
	^self computeCapability
!
smCount
	^Cuda multiprocessorCount
!
arch
	"NVRTC's -arch for my code: 'sm_121' on the GB10."
	^'sm_', self computeCapability printString
! !

!NvCudaDevice methodsFor: 'memory'!
allocate: size
	"size bytes (rounded up to 4 KB) of zeroed memory the GPU and the CPU reach (an NvCudaMemory); mine until freed or I close."
	^self allocate: size gpuCached: false
!
allocate: size gpuCached: aBoolean
	"As allocate: (NvDevice's protocol: CUDA keeps the GPU's caches coherent with the CPU, so whether the GPU caches it is CUDA's choice)."
	| m |
	self isOpen ifFalse: [^self error: 'the CUDA device is closed'].
	m := NvCudaMemory new device: self size: size.
	memories add: m.
	^m
!
forget: aMemory
	memories remove: aMemory ifAbsent: []
!
forgetCompute: aCompute
	computes remove: aCompute ifAbsent: []
! !

!NvCudaDevice methodsFor: 'computing'!
newCompute
	"A new NvCudaCompute: kernels launched on the default stream."
	| c |
	self isOpen ifFalse: [^self error: 'the CUDA device is closed'].
	c := NvCudaCompute new device: self.
	computes add: c.
	^c
! !

!NvCudaDevice methodsFor: 'closing'!
close
	"Free everything I made, newest first: the computes (their modules), then the memories. Safe to call twice."
	memories isNil ifTrue: [^self].
	[computes reverse do: [:c | [c close] on: Error do: [:e | ]].
	memories reverse do: [:m | [m free] on: Error do: [:e | ]]]
		ensure: [memories := computes := nil]
! !
