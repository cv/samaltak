Object subclass: #GpuTools
	instanceVariableNames: ''
	classVariableNames: 'Available Session Forced'
	package: 'Tools-CUDA'!

GpuTools comment: 'I am the facade of the GPU demos (World menu › Apps › GPU, shown where CUDA is: Cuda isAvailable, asked once a VM session): the GPU Workspace (snippets of cuBLAS, cuRAND, cuOpt and what else is bound, timed against the CPU), the cuOpt window (routing and linear programs solved live), the GPU Monitor (the device, its memory, the binding''s allocations, the recent calls) and the Spectrum (a 2-D Fourier transform of a picture on the GPU, filtered and transformed back). docs/cuda.md.

	GpuTools isAvailable.
	Tools open: #gpuWorkspace. Tools open: #cuopt. Tools open: #gpuMonitor. Tools open: #spectrum.'!

!GpuTools class methodsFor: 'class initialization'!
initialize
	ToolsMenu showGroup: #gpu when: [self isAvailable]
! !

!GpuTools class methodsFor: 'testing'!
isAvailable
	"Whether this VM has CUDA with a device (asked once a VM session: the first time takes a tenth of a second)."
	Forced isNil ifFalse: [^Forced].
	(Session notNil and: [Session = CudaLibraryAPI session]) ifTrue: [^Available].
	Available := [Cuda isAvailable] on: Error do: [:e | e return: false].
	Session := CudaLibraryAPI session.
	^Available
!
cuOptAvailable
	"Whether cuOpt is here too."
	^self isAvailable and: [CuOpt isAvailable]
!
forced
	^Forced
!
forced: aBooleanOrNil
	"Make isAvailable answer aBooleanOrNil (tests of the windows without the GPU: false); nil asks CUDA again."
	Forced := aBooleanOrNil
!
unavailableText
	Forced == false ifTrue: [^'CUDA turned off (GpuTools forced: false)'].
	"Why the demos cannot run here."
	CudaRuntimeAPI isAvailable ifFalse: [^'no CUDA runtime here (libcudart: the CUDA toolkit, or SAMALTAK_CUDA_LIBS)'].
	^'no CUDA device here'
!
summary
	"NVIDIA GB10 · compute 12.1 · 48 SMs · CUDA 13.0, as the windows' headers show it."
	self isAvailable ifFalse: [^self unavailableText].
	^[Cuda deviceName , ' · compute ' , Cuda computeCapability , ' · ' , Cuda multiprocessorCount printString , ' SMs · CUDA ' , (Cuda versionString: CudaRuntimeAPI cudaRuntimeGetVersion)]
		on: Error do: [:e | e return: e messageText]
!
libraries
	"The CUDA libraries this VM can load, by name."
	| names |
	names := OrderedCollection new.
	{CudaRuntimeAPI -> 'runtime'. CublasAPI -> 'cuBLAS'. CurandAPI -> 'cuRAND'. CuOptAPI -> 'cuOpt'} do: [:each |
		each key isAvailable ifTrue: [names add: each value]].
	#(#CusolverDnAPI 'cuSOLVER' #CufftAPI 'cuFFT' #CusparseAPI 'cuSPARSE') pairsDo: [:className :label |
		(Smalltalk at: className ifAbsent: [nil]) ifNotNil: [:c | c isAvailable ifTrue: [names add: label]]].
	^names asArray
! !
