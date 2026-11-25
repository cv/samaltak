Object subclass: #CudaLibraryAPI
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaLibraryAPI comment: 'I am the abstract class of the generated CUDA library bindings (CudaRuntimeAPI, CudaDriverAPI, CublasAPI, CurandAPI, CuOptAPI: tools/cuda/bindgen.py writes them from NVIDIA''s headers and tools/cuda/bindings.spec). Each class-side method of a subclass calls one C function through the VM''s cuda_* exports and checks the status (check:in:allowing:), signalling CudaError with the library''s name and description of it; out-parameters come back as the answer (an Array when there are several). Handles are ids of the VM''s handle table, device pointers Integers the VM checks against its live allocations; host arrays are ByteArrays (or {aByteArray. offset. length} slices). docs/cuda.md.'!

!CudaLibraryAPI class methodsFor: 'library'!
libraryName
	^self subclassResponsibility
!
isAvailable
	"Whether the VM has this library's exports and can load the library."
	| r |
	r := [self ffiAvailable] on: Error do: [:e | false].
	^r = 1
!
constants
	^#()
!
constant: aString
	"The library constant named aString, e.g. CublasAPI constant: 'CUBLAS_OP_T'."
	| c |
	c := self constants.
	1 to: c size by: 2 do: [:i | (c at: i) = aString ifTrue: [^c at: i + 1]].
	^self error: self libraryName , ' has no constant ' , aString
!
statusName: code
	^self statusText: code kind: 0
!
statusDescription: code
	^self statusText: code kind: 1
!
statusText: code kind: kind
	| buffer n |
	code isInteger ifFalse: [^nil].
	code < 0 ifTrue: [^kind = 0 ifTrue: [nil] ifFalse: [self rejectionText: code]].
	buffer := ByteArray new: 256.
	n := [self ffiStatusText: code kind: kind into: {buffer. 1. 256}] on: Error do: [:e | false].
	(n == false or: [n <= 0]) ifTrue: [^nil].
	^(buffer copyFrom: 1 to: (n min: 256)) asString
! !

!CudaLibraryAPI class methodsFor: 'session'!
session
	"A number of this VM process (0 without the exports): handles and device pointers of another session are gone."
	| r |
	r := [self ffiSession] on: Error do: [:e | false].
	^(r == false or: [r < 0]) ifTrue: [0] ifFalse: [r]
!
liveAllocations
	"The device allocations this VM process holds (cudaMalloc, not yet cudaFree)."
	^self ffiLive: 0
!
liveHandles
	^self ffiLive: 1
!
allocatedBytes
	^self ffiLive: 2
!
allocations
	"The VM's table of the live device allocations (cudaMalloc, not yet cudaFree), in no order: an Array of base address -> bytes."
	| n bytes |
	n := self liveAllocations.
	(n isInteger and: [n > 0]) ifFalse: [^#()].
	bytes := ByteArray new: n + 16 * 16.
	n := (self ffiAllocations: (self slice: bytes)) min: bytes size // 16.
	(n isInteger and: [n > 0]) ifFalse: [^#()].
	^(1 to: n) collect: [:i | (self uint64At: i * 16 - 15 of: bytes) -> (self uint64At: i * 16 - 7 of: bytes)]
! !

!CudaLibraryAPI class methodsFor: 'checking'!
check: result in: functionName
	"A call's result: false if the FFI refused it, below zero if the VM refused its arguments."
	CudaTrace call: functionName.
	result == false ifTrue: [^(CudaUnavailable library: self function: functionName code: nil) signal: functionName , ': this VM has no CUDA exports'].
	(result isInteger and: [result < 0]) ifTrue: [^self refused: result in: functionName].
	^result
!
check: result in: functionName allowing: codes
	"A status: 0 and codes are answered, any other signals CudaError."
	| r |
	r := self check: result in: functionName.
	(r = 0 or: [codes includes: r]) ifTrue: [^r].
	^(CudaError library: self function: functionName code: r) signal
!
refused: code in: functionName
	| class |
	class := code >= -2 ifTrue: [CudaUnavailable] ifFalse: [CudaArgumentError].
	^(class library: self function: functionName code: code) signal: functionName , ': ' , (self rejectionText: code)
!
rejectionText: code
	^#('the library is not installed here (SAMALTAK_CUDA_LIBS: more directories to look in)' 'the library has no such function' 'not a live handle of that type' 'a device pointer outside the live allocations, or an extent past the end of one' 'a host buffer too short for the count' 'the handle or allocation table is full' 'arguments the binding refuses')
		at: code negated ifAbsent: ['refused (' , code printString , ')']
! !

!CudaLibraryAPI class methodsFor: 'marshalling'!
slice: anObject
	"A ByteArray (or String) as a whole slice; a slice Array as it is."
	anObject isArray ifTrue: [^anObject].
	anObject isString ifTrue: [^self slice: anObject asByteArray].
	^{anObject. 1. anObject size}
!
pack: byteArrays
	"Several host arrays as one ByteArray (vm/native/cudalib.h): (offset, length) pairs of 64-bit integers, then each array at an offset that is a multiple of 8."
	| offsets offset bytes |
	offsets := Array new: byteArrays size.
	offset := byteArrays size * 16.
	byteArrays doWithIndex: [:a :i |
		offsets at: i put: offset.
		offset := offset + ((self bytesOf: a) size + 7 // 8 * 8)].
	bytes := ByteArray new: offset.
	byteArrays doWithIndex: [:a :i | | b |
		b := self bytesOf: a.
		self put64: (offsets at: i) at: i * 16 - 15 in: bytes.
		self put64: b size at: i * 16 - 7 in: bytes.
		bytes replaceFrom: (offsets at: i) + 1 to: (offsets at: i) + b size with: b startingAt: 1].
	^bytes
!
unpack: pack at: index into: aByteArray
	"Copy the index-th array of pack back into aByteArray."
	| offset n |
	offset := self uint64At: index * 16 - 15 of: pack.
	n := (self uint64At: index * 16 - 7 of: pack) min: aByteArray size.
	aByteArray replaceFrom: 1 to: n with: pack startingAt: offset + 1
!
bytesOf: anObject
	^anObject isString ifTrue: [anObject asByteArray] ifFalse: [anObject]
!
outs: bytes at: index kind: kind
	"The index-th out-parameter, 8 bytes each: #int (signed), #uint, #float (a double)."
	| offset v |
	offset := index - 1 * 8 + 1.
	kind == #float ifTrue: [^bytes float64At: offset].
	v := self uint64At: offset of: bytes.
	(kind == #int and: [v >= (1 bitShift: 63)]) ifTrue: [^v - (1 bitShift: 64)].
	^v
!
uint64At: offset of: bytes
	^(bytes uint32At: offset) + ((bytes uint32At: offset + 4) bitShift: 32)
!
put64: anInteger at: offset in: bytes
	bytes uint32At: offset put: (anInteger bitAnd: 16rFFFFFFFF).
	bytes uint32At: offset + 4 put: ((anInteger bitShift: -32) bitAnd: 16rFFFFFFFF)
! !

!CudaLibraryAPI class methodsFor: 'ffi'!
ffiAvailable
	^false
!
ffiStatusText: code kind: kind into: slice
	^false
!
ffiSession
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'cuda_session' () i64)) tryInvoke0
!
ffiLive: kind
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'cuda_live' (i64) i64)) tryInvoke1: kind
!
ffiAllocations: slice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'cuda_allocations' (writableBytesWithLength) i64)) tryInvoke1: slice
! !
