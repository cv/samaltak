Object subclass: #NvCudaMemory
	instanceVariableNames: 'device address size session'
	classVariableNames: ''
	package: 'System-CUDA'!

NvCudaMemory comment: 'I am memory an NvCudaDevice allocated for the GPU and the CPU both: CUDA''s pinned host memory (cudaMallocHost; on the GB10 the GPU''s own memory, which it reads at full speed), at one address for both (unified addressing: gpuAddress = cpuAddress), zeroed. The VM knows me as a live CUDA allocation, so a cuBLAS call or a kernel launched through the bindings may take my address as a device pointer. NvMemory''s protocol; offsets are 0-based bytes. CUDA keeps the CPU''s and the GPU''s views coherent: what a kernel wrote is there once its fence is reached, what the CPU wrote before a launch the kernel sees. Of one VM session: after a snapshot is restored I am gone (isFreed), never a stale address.

	m := gpu allocate: 4096.
	m uint32At: 0 put: 7; uint32At: 0.             "7"
	m gpuAddress                                     "what a kernel parameter names"'!

!NvCudaMemory methodsFor: 'initialization'!
device: anNvCudaDevice size: n
	device := anNvCudaDevice.
	size := (n max: 1) + 16rFFF // 16r1000 * 16r1000.
	address := CudaRuntimeAPI cudaMallocHost: size.
	session := CudaLibraryAPI session.
	"synchronous for pinned host memory"
	[CudaRuntimeAPI cudaMemset: address value: 0 count: size] ifCurtailed: [self free]
! !

!NvCudaMemory methodsFor: 'accessing'!
size
	^size
!
gpuAddress
	^address
!
cpuAddress
	^address
!
address
	^address
!
isFreed
	^address isNil or: [session ~= CudaLibraryAPI session]
! !

!NvCudaMemory methodsFor: 'reading and writing'!
check: offset size: n
	(offset >= 0 and: [offset + n <= size]) ifFalse: [^self error: 'offset ', offset printString, ' outside ', size printString, ' bytes'].
	self isFreed ifTrue: [^self error: 'freed GPU memory, or of an earlier VM session']
!
uint32At: offset
	self check: offset size: 4.
	^Machine uint32At: address + offset
!
uint32At: offset put: anInteger
	self check: offset size: 4.
	^Machine uint32At: address + offset put: anInteger
!
uint64At: offset
	self check: offset size: 8.
	^Machine uint64At: address + offset
!
uint64At: offset put: anInteger
	self check: offset size: 8.
	^Machine uint64At: address + offset put: anInteger
!
bytesAt: offset count: n
	self check: offset size: n.
	^Machine bytesAt: address + offset count: n
!
bytesAt: offset put: aByteArray
	self check: offset size: aByteArray size.
	Machine bytesAt: address + offset put: aByteArray
!
fill: n bytes: aByteArray from: offset
	"Copy aByteArray (a pattern) over n bytes from offset, repeating it."
	| at |
	self check: offset size: n.
	at := 0.
	[at < n] whileTrue: [| k |
		k := aByteArray size min: n - at.
		Machine copy: k from: aByteArray at: 0 to: address + offset + at at: 0.
		at := at + k]
! !

!NvCudaMemory methodsFor: 'freeing'!
free
	"Return me to CUDA (cudaFreeHost). Safe to call twice. The GPU must be done with me (NvComputeGPU waits for the launches that use me first)."
	address isNil ifTrue: [^self].
	[session = CudaLibraryAPI session ifTrue: [CudaRuntimeAPI cudaFreeHost: address]]
		ensure: [address := nil. device notNil ifTrue: [device forget: self]]
! !
