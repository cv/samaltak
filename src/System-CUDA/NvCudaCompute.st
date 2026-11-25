Object subclass: #NvCudaCompute
	instanceVariableNames: 'device stream fenceMemory launched written programs modules stampFunction session'
	classVariableNames: ''
	package: 'System-CUDA'!

NvCudaCompute comment: 'I launch compute kernels (NvKernel, from an NvCubin: the precompiled raster kernels, NVRTC''s cubins) through libcuda, with NvCompute''s protocol: a kernel''s cubin is loaded once (cuModuleLoadData; the driver places its code, constant banks and data and sizes its local memory), its function looked up once (cuModuleGetFunction), and a launch is cuLaunchKernel with the parameter area as one buffer (NvKernel parameterBytes:), on the default stream of the CUDA runtime''s primary context: the stream cuBLAS and cuRAND work on, so a kernel''s results are their operands in order, with no copy and no host round trip.

	compute := NvCudaDevice open newCompute.        "or Cuda compute: the session''s"
	compute run: kernel grid: 16 block: 256 arguments: {aCudaArray. 4000}

Arguments are as NvKernel parameterBytes: takes them, and CudaArrays and NvCudaMemory (their addresses). launch:grid:block:arguments: is asynchronous and answers a fence value; wait: waits for it (polling a word the stream writes, cuStreamWriteValue64, written when a fence is first waited for or asked about: a launch costs one call), run:... launches and waits. I am also my own channel (NvChannel''s fence, wait:, sync, completedValue, timestamp:payload:; its L2 flushes do nothing: CUDA keeps the CPU coherent), so NvComputeGPU runs on me unchanged. forget: unloads a kernel''s module once no kernel of it is left; close everything.'!

!NvCudaCompute methodsFor: 'initialization'!
device: anNvCudaDevice
	device := anNvCudaDevice.
	stream := 0.
	launched := written := 0.
	programs := IdentityDictionary new.
	modules := IdentityDictionary new.
	session := CudaLibraryAPI session.
	fenceMemory := device allocate: 4096
! !

!NvCudaCompute methodsFor: 'accessing'!
device
	^device
!
channel
	"What NvComputeGPU asks for fences and timestamps: I am my own channel."
	^self
!
stream
	"The CUDA stream I launch on: 0, the default stream (cuBLAS's and cuRAND's)."
	^stream
!
programs
	"aKernel -> its CUfunction handle, for the kernels launched and not forgotten."
	^programs
!
modules
	"cubin bytes -> (CUmodule handle, kernels of it launched)."
	^modules
!
isOpen
	^programs notNil and: [session = CudaLibraryAPI session]
! !

!NvCudaCompute methodsFor: 'launching'!
run: aKernel grid: grid block: block arguments: values
	"Launch and wait until the grid has run."
	self wait: (self launch: aKernel grid: grid block: block arguments: values)
!
launch: aKernel grid: grid block: block arguments: values
	"Queue a launch of aKernel; answer its fence value."
	^self launch: aKernel grid: grid block: block parameters: (aKernel parameterBytes: (values collect: [:v | self argument: v]))
!
argument: anObject
	"A kernel argument: a CudaArray or GPU memory as its address."
	(anObject isKindOf: CudaArray) ifTrue: [^anObject address].
	(anObject isKindOf: NvCudaMemory) ifTrue: [^anObject gpuAddress].
	^anObject
!
launch: aKernel grid: grid block: block parameters: params
	"Queue a launch of aKernel with params as its parameter area (parameterBytes:'s bytes); answer its fence value."
	| g b p f |
	g := self triple: grid.
	b := self triple: block.
	(b inject: 1 into: [:x :y | x * y]) > (aKernel maxThreads ifNil: [1024])
		ifTrue: [^self error: aKernel name, ' allows at most ', (aKernel maxThreads ifNil: [1024]) printString, ' threads per block'].
	((g at: 1) between: 1 and: 16r7FFFFFFF) & ((g at: 2) between: 1 and: 65535) & ((g at: 3) between: 1 and: 65535)
		ifFalse: [^self error: 'bad grid ', g printString].
	params size > aKernel parameterSize ifTrue: [^self error: aKernel name, ' takes ', aKernel parameterSize printString, ' bytes of parameters'].
	p := params size = aKernel parameterSize
		ifTrue: [params]
		ifFalse: [(ByteArray new: aKernel parameterSize) replaceFrom: 1 to: params size with: params startingAt: 1; yourself].
	f := self functionFor: aKernel.
	CudaDriverAPI cuLaunchKernel: f gridDimX: (g at: 1) gridDimY: (g at: 2) gridDimZ: (g at: 3)
		blockDimX: (b at: 1) blockDimY: (b at: 2) blockDimZ: (b at: 3) sharedMemBytes: 0 hStream: stream extra: p.
	^launched := launched + 1
!
functionFor: aKernel
	"aKernel's CUfunction, its cubin loaded as a module on first use."
	^programs at: aKernel ifAbsent: [| entry f |
		aKernel cubin isNil ifTrue: [^self error: aKernel name, ' has no cubin to load'].
		self isOpen ifFalse: [^self error: 'this NvCudaCompute is closed, or of an earlier VM session'].
		entry := modules at: aKernel cubin ifAbsent: [
			modules at: aKernel cubin put: (Array with: (CudaDriverAPI cuModuleLoadData: aKernel cubin) with: 0)].
		f := CudaDriverAPI cuModuleGetFunction: entry first name: aKernel name.
		entry at: 2 put: (entry at: 2) + 1.
		programs at: aKernel put: f]
!
triple: anIntegerOrArray
	| t |
	anIntegerOrArray isInteger ifTrue: [^Array with: anIntegerOrArray with: 1 with: 1].
	(anIntegerOrArray size between: 1 and: 3) ifFalse: [^self error: 'grid and block take 1 to 3 dimensions'].
	t := Array new: 3 withAll: 1.
	t replaceFrom: 1 to: anIntegerOrArray size with: anIntegerOrArray startingAt: 1.
	^t
!
forget: aKernel
	"Forget aKernel's function; its module goes, once the GPU has run everything queued, with the last kernel of it."
	| entry |
	programs removeKey: aKernel ifAbsent: [^self].
	entry := modules at: aKernel cubin ifAbsent: [^self].
	entry at: 2 put: (entry at: 2) - 1.
	(entry at: 2) > 0 ifTrue: [^self].
	self sync.
	modules removeKey: aKernel cubin.
	CudaDriverAPI cuModuleUnload: entry first
! !

!NvCudaCompute methodsFor: 'fences'!
fence
	"A fence after the work queued so far; answer its value."
	launched := launched + 1.
	self writeFence.
	^launched
!
lastFence
	^launched
!
completedValue
	"The last fence value the GPU reached."
	written < launched ifTrue: [self writeFence].
	^fenceMemory uint64At: 0
!
writeFence
	"The stream writes the newest fence value once the work queued before it is done (with a memory barrier first)."
	CudaDriverAPI cuStreamWriteValue64: stream addr: fenceMemory gpuAddress value: launched flags: 0.
	written := launched
!
wait: value
	self wait: value timeoutMilliseconds: 5000
!
wait: value timeoutMilliseconds: ms
	"Return once the GPU has reached the fence value; poll without pause (as NvChannel), asking the stream now and then whether it failed (a kernel that faulted: a CudaError), an error after ms."
	| deadline n |
	(fenceMemory uint64At: 0) >= value ifTrue: [^self].
	value > written ifTrue: [self writeFence].
	deadline := Time utcMicroseconds + (ms * 1000).
	n := 0.
	[(fenceMemory uint64At: 0) >= value] whileFalse: [
		n := n + 1.
		n \\ 4096 = 0 ifTrue: [
			CudaRuntimeAPI cudaStreamQuery: stream.
			Time utcMicroseconds > deadline ifTrue: [
				^self error: 'GPU timeout waiting for fence ', value printString, ' (at ', (fenceMemory uint64At: 0) printString, ')']]]
!
sync
	"Return once the GPU has run all the work queued."
	self wait: self fence
!
timestamp: gpuAddress payload: value
	"Once the work before it is done, the GPU writes its clock (ns, %globaltimer) at gpuAddress + 8, then value at gpuAddress (64 bits each): NvChannel's timestamp release, as a one-thread kernel (PTX the driver compiles once)."
	| p |
	p := ByteArray new: 16.
	CudaLibraryAPI put64: gpuAddress at: 1 in: p.
	CudaLibraryAPI put64: value at: 9 in: p.
	CudaDriverAPI cuLaunchKernel: self stampFunction gridDimX: 1 gridDimY: 1 gridDimZ: 1
		blockDimX: 1 blockDimY: 1 blockDimZ: 1 sharedMemBytes: 0 hStream: stream extra: p
!
stampFunction
	^stampFunction ifNil: [| m |
		m := CudaDriverAPI cuModuleLoadData: self class stampPtx.
		modules at: self class stampPtx put: (Array with: m with: 1).
		stampFunction := CudaDriverAPI cuModuleGetFunction: m name: 'samaltak_stamp']
!
flushL2
	"Nothing to do: CUDA keeps what kernels write coherent with the CPU at fences."
!
flushAndInvalidateL2
	"Nothing to do: CUDA makes what the CPU wrote visible to the next launch."
! !

!NvCudaCompute methodsFor: 'closing'!
close
	"Wait for my launches, unload my modules, free my fence word. Safe to call twice."
	programs isNil ifTrue: [^self].
	[self isOpen ifTrue: [
		[self wait: self fence timeoutMilliseconds: 2000] on: Error do: [:e | ].
		modules do: [:entry | [CudaDriverAPI cuModuleUnload: entry first] on: Error do: [:e | ]]]]
		ensure: [
			fenceMemory notNil ifTrue: [[fenceMemory free] on: Error do: [:e | ]].
			programs := modules := stampFunction := fenceMemory := nil.
			device forgetCompute: self]
! !

!NvCudaCompute class methodsFor: 'kernels'!
stampPtx
	"A kernel writing the GPU's clock and a payload (timestamp:payload:), as PTX, NUL-terminated."
	^('.version 7.0
.target sm_80
.address_size 64
.visible .entry samaltak_stamp(.param .u64 at, .param .u64 payload)
{
	.reg .b64 %rd<4>;
	ld.param.u64 %rd1, [at];
	ld.param.u64 %rd2, [payload];
	mov.u64 %rd3, %globaltimer;
	st.global.u64 [%rd1+8], %rd3;
	membar.sys;
	st.global.u64 [%rd1], %rd2;
	ret;
}
', (String with: (Character value: 0))) asByteArray
! !
