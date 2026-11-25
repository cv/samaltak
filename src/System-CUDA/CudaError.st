Error subclass: #CudaError
	instanceVariableNames: 'library function code'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaError comment: 'I am signaled when a CUDA library refuses a call: library is its binding class (CublasAPI, CudaRuntimeAPI, ...), function the C function, code the status it returned. messageText has the library''s own name and description of the status (cudaGetErrorName/cudaGetErrorString, cublasGetStatusName/String, ...), e.g. ''cudaMalloc: cudaErrorMemoryAllocation (out of memory)''. Subclasses: CudaUnavailable (no such library or export here), CudaArgumentError (the VM refused the arguments before the call). docs/cuda.md.'!

!CudaError class methodsFor: 'instance creation'!
library: aClass function: aString code: anInteger
	^self new setLibrary: aClass function: aString code: anInteger
! !

!CudaError methodsFor: 'accessing'!
setLibrary: aClass function: aString code: anInteger
	library := aClass.
	function := aString.
	code := anInteger
!
library
	^library
!
function
	^function
!
code
	^code
!
statusName
	"The library's name for my status, e.g. CUBLAS_STATUS_INVALID_VALUE."
	^code isNil ifTrue: [nil] ifFalse: [library statusName: code]
!
messageText
	| name description |
	messageText notNil ifTrue: [^messageText].
	name := self statusName.
	description := library statusDescription: code.
	^String streamContents: [:s |
		s nextPutAll: function; nextPutAll: ': '; nextPutAll: (name ifNil: [code printString]).
		(description notNil and: [description ~= name]) ifTrue: [s nextPutAll: ' ('; nextPutAll: description; nextPut: $)]]
! !
