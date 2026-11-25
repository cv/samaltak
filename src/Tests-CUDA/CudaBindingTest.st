TestCase subclass: #CudaBindingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaBindingTest comment: 'Tests the CUDA bindings (System-CUDA) without a GPU: the marshalling of packs and out-parameters, the generated constants and status names, and that a forged handle or device pointer is refused before any library call (CudaArgumentError where the libraries are here, CudaUnavailable where not). CudaGpuTest uses the device.'!

!CudaBindingTest methodsFor: 'tests'!
testPackLayout
	| pack |
	pack := CudaLibraryAPI pack: {#[1 2 3]. #[]. #[9 8 7 6 5 4 3 2 1]}.
	self assert: (CudaLibraryAPI uint64At: 1 of: pack) equals: 48.
	self assert: (CudaLibraryAPI uint64At: 9 of: pack) equals: 3.
	self assert: (CudaLibraryAPI uint64At: 17 of: pack) equals: 56.
	self assert: (CudaLibraryAPI uint64At: 25 of: pack) equals: 0.
	self assert: (CudaLibraryAPI uint64At: 33 of: pack) equals: 56.
	self assert: (CudaLibraryAPI uint64At: 41 of: pack) equals: 9.
	self assert: (pack copyFrom: 49 to: 51) equals: #[1 2 3].
	self assert: (pack copyFrom: 57 to: 65) equals: #[9 8 7 6 5 4 3 2 1].
	self assert: pack size equals: 72
!
testUnpack
	| pack out |
	pack := CudaLibraryAPI pack: {#[1 2]. #[3 4 5]}.
	out := ByteArray new: 3.
	CudaLibraryAPI unpack: pack at: 2 into: out.
	self assert: out equals: #[3 4 5]
!
testOutParameters
	| bytes |
	bytes := ByteArray new: 24.
	CudaLibraryAPI put64: (1 bitShift: 64) - 5 at: 1 in: bytes.
	CudaLibraryAPI put64: 16r123456789A at: 9 in: bytes.
	bytes float64At: 17 put: 2.5.
	self assert: (CudaLibraryAPI outs: bytes at: 1 kind: #int) equals: -5.
	self assert: (CudaLibraryAPI outs: bytes at: 1 kind: #uint) equals: (1 bitShift: 64) - 5.
	self assert: (CudaLibraryAPI outs: bytes at: 2 kind: #int) equals: 16r123456789A.
	self assert: (CudaLibraryAPI outs: bytes at: 3 kind: #float) equals: 2.5
!
testConstants
	self assert: (CublasAPI constant: 'CUBLAS_OP_T') equals: 1.
	self assert: (CurandAPI constant: 'CURAND_RNG_PSEUDO_DEFAULT') equals: 100.
	self assert: (CuOptAPI constant: 'CUOPT_TERMINATION_STATUS_OPTIMAL') equals: 1.
	self assert: (CudaRuntimeAPI constant: 'cudaErrorNotReady') equals: 600.
	self should: [CublasAPI constant: 'NO_SUCH_THING'] raise: Error
!
testStatusNamesWithoutTheLibrary
	"cuRAND and cuOpt have no status strings of their own: the generator made them from the headers."
	self hasExports ifFalse: [^self skip: 'this VM has no cuda_* exports'].
	self assert: (CurandAPI statusName: 101) equals: 'CURAND_STATUS_NOT_INITIALIZED'.
	self assert: (CuOptAPI statusName: 4) equals: 'CUOPT_VALIDATION_ERROR'
!
testRejectionMessages
	| e |
	e := CudaArgumentError library: CublasAPI function: 'cublasSgemm' code: -4.
	self assert: (CublasAPI rejectionText: -4) equals: 'a device pointer outside the live allocations, or an extent past the end of one'.
	self assert: e statusName isNil
!
testForgedHandleRefused
	| e |
	e := self errorOf: [CublasAPI cublasSgemm: 12345 transa: 0 transb: 0 m: 2 n: 2 k: 2 alpha: 1.0 a: 4096 lda: 2 b: 4096 ldb: 2 beta: 0.0 c: 4096 ldc: 2].
	self assert: (e isKindOf: CudaError).
	CublasAPI isAvailable ifTrue: [
		self assert: e class equals: CudaArgumentError.
		self assert: e code equals: -3.
		self assert: ('*not a live handle*' match: e messageText)]
!
testForgedDevicePointerRefused
	| e |
	e := self errorOf: [CudaRuntimeAPI cudaMemcpyDtoH: (ByteArray new: 8) src: 16r7F0000001000 count: 8].
	self assert: (e isKindOf: CudaError).
	CudaRuntimeAPI isAvailable ifTrue: [
		self assert: e class equals: CudaArgumentError.
		self assert: e code equals: -4].
	e := self errorOf: [CudaRuntimeAPI cudaFree: 16r7F0000001000].
	self assert: (e isKindOf: CudaError)
!
testSessionIsStable
	self assert: CudaLibraryAPI session equals: CudaLibraryAPI session.
	self hasExports ifTrue: [self deny: CudaLibraryAPI session = 0]
! !

!CudaBindingTest methodsFor: 'private'!
hasExports
	^CudaLibraryAPI session ~= 0
!
errorOf: aBlock
	aBlock on: Error do: [:e | ^e].
	^nil
! !
