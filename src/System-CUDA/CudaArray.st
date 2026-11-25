Object subclass: #CudaArray
	instanceVariableNames: 'address count type session'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaArray comment: 'I am an array of count Floats in the CUDA device''s memory (cudaMalloc), of type #float32 or #float64. withAll: copies Smalltalk Floats to the device, asArray copies them back; fillUniform fills me on the device (cuRAND); norm, + and - run there (cuBLAS). My printString says my type, size and first values, as the Inspector shows. release frees my memory at once; otherwise it is freed when I am collected (CudaReleaser). A CudaArray of an earlier VM session (a restored snapshot) holds nothing: isAlive is false.

	(CudaArray withAll: #(1.5 2.5 3.5)) asArray
	(CudaArray new: 1000000) fillUniform; yourself'!

!CudaArray class methodsFor: 'instance creation'!
new: anInteger type: aSymbol
	^self basicNew setCount: anInteger type: aSymbol
!
new: anInteger
	^self new: anInteger type: #float32
!
withAll: anArray type: aSymbol
	^(self new: anArray size type: aSymbol) fromArray: anArray
!
withAll: anArray
	^self withAll: anArray type: #float32
!
uniform: anInteger type: aSymbol
	"anInteger random Floats in (0, 1], made on the device."
	^(self new: anInteger type: aSymbol) fillUniform
! !

!CudaArray class methodsFor: 'converting'!
elementSize: aSymbol
	^aSymbol == #float32 ifTrue: [4] ifFalse: [8]
!
bytesOf: anArray type: aSymbol
	"anArray's numbers as packed floats or doubles."
	| size bytes |
	size := self elementSize: aSymbol.
	bytes := ByteArray new: anArray size * size.
	aSymbol == #float32
		ifTrue: [anArray doWithIndex: [:v :i | bytes float32At: i - 1 * 4 + 1 put: v asFloat]]
		ifFalse: [anArray doWithIndex: [:v :i | bytes float64At: i - 1 * 8 + 1 put: v asFloat]].
	^bytes
!
valuesOf: bytes type: aSymbol
	| size |
	size := self elementSize: aSymbol.
	^aSymbol == #float32
		ifTrue: [(1 to: bytes size // 4) collect: [:i | bytes float32At: i - 1 * 4 + 1]]
		ifFalse: [(1 to: bytes size // 8) collect: [:i | bytes float64At: i - 1 * 8 + 1]]
! !

!CudaArray methodsFor: 'initializing'!
setCount: anInteger type: aSymbol
	(#(#float32 #float64) includes: aSymbol) ifFalse: [^self error: 'a CudaArray holds #float32 or #float64'].
	(anInteger isInteger and: [anInteger >= 0]) ifFalse: [^self error: 'a CudaArray''s size is an Integer >= 0'].
	count := anInteger.
	type := aSymbol.
	address := CudaRuntimeAPI cudaMalloc: (self byteSize max: 8).
	session := CudaLibraryAPI session.
	WeakRegistry default add: self executor: (CudaReleaser kind: #memory value: address session: session)
! !

!CudaArray methodsFor: 'accessing'!
size
	^count
!
type
	^type
!
elementSize
	^self class elementSize: type
!
byteSize
	^count * self elementSize
!
isAlive
	"Whether I hold device memory of this VM session."
	^address notNil and: [session = CudaLibraryAPI session]
!
address
	"My device address (an Integer the VM checks against its live allocations)."
	self isAlive ifFalse: [^self error: 'this ' , self class name , ' was released, or belongs to an earlier VM session'].
	^address
!
addressAt: index
	^self address + (index - 1 * self elementSize)
! !

!CudaArray methodsFor: 'copying'!
fromArray: anArray
	"Copy anArray's numbers to the device; answer me."
	anArray size = count ifFalse: [^self error: 'I hold ' , count printString , ' values, not ' , anArray size printString].
	^self fromBytes: (self class bytesOf: anArray type: type)
!
fromBytes: aByteArray
	"Copy packed floats (or doubles) to the device; answer me."
	aByteArray size = self byteSize ifFalse: [^self error: 'I hold ' , self byteSize printString , ' bytes'].
	count > 0 ifTrue: [CudaRuntimeAPI cudaMemcpyHtoD: self address src: aByteArray count: aByteArray size]
!
asByteArray
	^self bytesFrom: 1 count: count
!
bytesFrom: index count: n
	| bytes |
	(index >= 1 and: [n >= 0 and: [index + n - 1 <= count]]) ifFalse: [^self error: 'out of bounds'].
	bytes := ByteArray new: n * self elementSize.
	n > 0 ifTrue: [CudaRuntimeAPI cudaMemcpyDtoH: bytes src: (self addressAt: index) count: bytes size].
	^bytes
!
asArray
	"My values, copied from the device."
	^self class valuesOf: self asByteArray type: type
!
copyFrom: index count: n
	^self class valuesOf: (self bytesFrom: index count: n) type: type
!
at: index
	^(self copyFrom: index count: 1) first
!
first: n
	^self copyFrom: 1 count: (n min: count)
!
emptyLike
	^self class new: count type: type
!
copyOnDevice
	"A new array with my values, copied on the device."
	| copy |
	copy := self emptyLike.
	count > 0 ifTrue: [CudaRuntimeAPI cudaMemcpyDtoD: copy address src: self address count: self byteSize].
	^copy
! !

!CudaArray methodsFor: 'computing'!
fillUniform
	"Fill me with random Floats in (0, 1] (cuRAND, this session's generator); answer me."
	count = 0 ifTrue: [^self].
	type == #float32
		ifTrue: [CurandAPI curandGenerateUniform: Cuda rng outputPtr: self address num: count]
		ifFalse: [CurandAPI curandGenerateUniformDouble: Cuda rng outputPtr: self address num: count]
!
zero
	CudaRuntimeAPI cudaMemset: self address value: 0 count: self byteSize
!
norm
	"My Euclidean norm (cuBLAS nrm2)."
	^type == #float32
		ifTrue: [CublasAPI cublasSnrm2: Cuda blas n: count x: self address incx: 1]
		ifFalse: [CublasAPI cublasDnrm2: Cuda blas n: count x: self address incx: 1]
!
add: other times: aNumber
	"A new array: me + aNumber * other (cuBLAS axpy)."
	| result |
	(other size = count and: [other type = type]) ifFalse: [^self error: 'sizes or types differ'].
	result := self copyOnDevice.
	type == #float32
		ifTrue: [CublasAPI cublasSaxpy: Cuda blas n: count alpha: aNumber asFloat x: other address incx: 1 y: result address incy: 1]
		ifFalse: [CublasAPI cublasDaxpy: Cuda blas n: count alpha: aNumber asFloat x: other address incx: 1 y: result address incy: 1].
	^result
!
+ other
	^self add: other times: 1
!
- other
	^self add: other times: -1
! !

!CudaArray methodsFor: 'releasing'!
release
	"Free my device memory now."
	self isAlive ifTrue: [CudaRuntimeAPI cudaFree: address].
	address := nil.
	WeakRegistry default remove: self
! !

!CudaArray methodsFor: 'printing'!
shapeString
	^'[' , count printString , ']'
!
sizeString
	| bytes |
	bytes := self byteSize.
	bytes < 1024 ifTrue: [^bytes printString , ' bytes'].
	bytes < (1024 * 1024) ifTrue: [^(bytes / 1024) rounded printString , ' KB'].
	^(bytes / (1024 * 1024)) rounded printString , ' MB'
!
printOn: aStream
	aStream nextPutAll: 'a '; nextPutAll: self class name; space; nextPutAll: type; nextPutAll: self shapeString.
	self isAlive ifFalse: [^aStream nextPutAll: ' (released)'].
	aStream nextPutAll: ' ('; nextPutAll: self sizeString; nextPutAll: ') '.
	[self printValuesOn: aStream] on: Error do: [:e | aStream nextPutAll: '(unreadable: '; nextPutAll: e messageText; nextPut: $)]
!
printValues: anArray more: aBoolean on: aStream
	aStream nextPut: $(.
	anArray do: [:v | aStream nextPutAll: (v printShowingDecimalPlaces: 4)] separatedBy: [aStream space].
	aBoolean ifTrue: [aStream nextPutAll: ' ...'].
	aStream nextPut: $)
!
printValuesOn: aStream
	self printValues: (self first: 6) more: count > 6 on: aStream
! !
