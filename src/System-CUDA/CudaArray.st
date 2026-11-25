Object subclass: #CudaArray
	instanceVariableNames: 'address count type session pending readers'
	classVariableNames: 'Arrays'
	package: 'System-CUDA'!

CudaArray comment: 'I am an array of count numbers in the CUDA device''s memory (cudaMalloc), of type #float32 or #float64, #complex64 or #complex128 (interleaved pairs of float32 or float64, as cuFFT and cuBLAS keep complex numbers: my values are Complex), or #int32 / #int64 (pivots and devInfo for cuSOLVER). withAll: copies Smalltalk numbers to the device, asArray copies them back; fillUniform fills me on the device (cuRAND); norm runs there (cuBLAS); element-wise arithmetic (+ - * / with numbers and arrays, min: max:, abs sqrt exp ln sin cos ..., comparisons into masks, where:else:) answers a pending array whose values one kernel computes for the whole expression when they are needed (realize, value, or asking for them: printString, asArray, a library''s operand), and sum, max, min and mean reduce in the same kernel (CudaExpression); complex arrays add and subtract with cuBLAS; fft and ifft transform me there (cuFFT, a plan kept per shape: Cuda fftPlan:kind:type:batch:; a real array''s fft is its half spectrum, n // 2 + 1 Complex values; ifftReal: n is the inverse). My printString says my type, size and first values, as the Inspector shows. release frees my memory at once; otherwise it is freed when I am collected (CudaReleaser). A CudaArray of an earlier VM session (a restored snapshot) holds nothing: isAlive is false.

	(CudaArray withAll: #(1.5 2.5 3.5)) asArray
	(CudaArray new: 1000000) fillUniform; yourself
	(CudaArray withAll: #(1 2 3 4)) fft asArray       "{10.0 + 0.0i. -2.0 + 2.0i. -2.0 + 0.0i}"
	((CudaArray withAll: #(1 4 9)) sqrt * 2 + 1) asArray   "#(3.0 5.0 7.0), one kernel"'!

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
	"anInteger random Floats in (0, 1] (real and imaginary parts, for a complex type), made on the device."
	^(self new: anInteger type: aSymbol) fillUniform
!
pending: anExpression
	"A new array (a CudaMatrix for a matrix's shape) whose values anExpression computes when they are first needed (realize)."
	| shape |
	shape := anExpression shape.
	^(shape size = 2 ifTrue: [CudaMatrix basicNew setRows: shape first cols: shape last] ifFalse: [CudaArray basicNew]) setPending: anExpression
!
workspace: bytes
	"Device memory of at least bytes bytes (a library's workspace)."
	^CudaArray new: (bytes + 7 // 8 max: 1) type: #int64
! !

!CudaArray class methodsFor: 'types'!
types
	^#(#float32 #float64 #complex64 #complex128 #int32 #int64)
!
elementSize: aSymbol
	^#(4 8 8 16 4 8) at: (self types indexOf: aSymbol)
!
isComplex: aSymbol
	^aSymbol == #complex64 or: [aSymbol == #complex128]
!
realTypeOf: aSymbol
	"The type of a complex type's parts; a real type itself."
	aSymbol == #complex64 ifTrue: [^#float32].
	aSymbol == #complex128 ifTrue: [^#float64].
	^aSymbol
!
complexTypeOf: aSymbol
	aSymbol == #float32 ifTrue: [^#complex64].
	aSymbol == #float64 ifTrue: [^#complex128].
	^aSymbol
! !

!CudaArray class methodsFor: 'live arrays'!
remember: anArray
	"Keep anArray, weakly, for liveArrays."
	| slot |
	Arrays isNil ifTrue: [Arrays := WeakArray new: 64].
	slot := (1 to: Arrays size) detect: [:i | | each | each := Arrays at: i. each isNil or: [each isAlive not]] ifNone: [nil].
	slot isNil ifTrue: [
		slot := Arrays size + 1.
		Arrays := (WeakArray new: Arrays size * 2) replaceFrom: 1 to: Arrays size with: Arrays startingAt: 1; yourself].
	Arrays at: slot put: anArray
!
liveArrays
	"The CudaArrays (and CudaMatrices) of this VM session that hold device memory, as the GPU Monitor lists them."
	Arrays isNil ifTrue: [^#()].
	^(Arrays select: [:each | each notNil and: [each isAlive]]) asArray
! !

!CudaArray class methodsFor: 'converting'!
describe: n type: aSymbol
	^aSymbol , '[' , n printString , '] (' , (self sizeString: n * (self elementSize: aSymbol)) , ')'
!
sizeString: bytes
	bytes < 1024 ifTrue: [^bytes printString , ' bytes'].
	bytes < (1024 * 1024) ifTrue: [^(bytes / 1024) rounded printString , ' KB'].
	^(bytes / (1024 * 1024)) rounded printString , ' MB'
!
bytesOf: anArray type: aSymbol
	"anArray's numbers as packed floats, doubles, (float, float) or (double, double) pairs for Complex numbers, or integers."
	| size bytes put |
	size := self elementSize: aSymbol.
	bytes := ByteArray new: anArray size * size.
	put := (self realTypeOf: aSymbol) == #float32
		ifTrue: [[:offset :v | bytes float32At: offset put: v asFloat]]
		ifFalse: [[:offset :v | bytes float64At: offset put: v asFloat]].
	aSymbol == #int64 ifTrue: [
		anArray doWithIndex: [:v :i | CudaLibraryAPI put64: (v bitAnd: 16rFFFFFFFFFFFFFFFF) at: i - 1 * 8 + 1 in: bytes].
		^bytes].
	aSymbol == #int32 ifTrue: [
		anArray doWithIndex: [:v :i | bytes uint32At: i - 1 * 4 + 1 put: (v bitAnd: 16rFFFFFFFF)].
		^bytes].
	(self isComplex: aSymbol)
		ifTrue: [anArray doWithIndex: [:v :i | | offset |
			offset := i - 1 * size + 1.
			put value: offset value: (v isNumber ifTrue: [v] ifFalse: [v real]).
			put value: offset + (size // 2) value: (v isNumber ifTrue: [0] ifFalse: [v imaginary])]]
		ifFalse: [anArray doWithIndex: [:v :i | put value: i - 1 * size + 1 value: v]].
	^bytes
!
valuesOf: bytes type: aSymbol
	| size get |
	size := self elementSize: aSymbol.
	aSymbol == #int32 ifTrue: [^(1 to: bytes size // 4) collect: [:i | | v |
		v := bytes uint32At: i - 1 * 4 + 1.
		v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]]].
	aSymbol == #int64 ifTrue: [^(1 to: bytes size // 8) collect: [:i | CudaLibraryAPI outs: bytes at: i kind: #int]].
	get := (self realTypeOf: aSymbol) == #float32
		ifTrue: [[:offset | bytes float32At: offset]]
		ifFalse: [[:offset | bytes float64At: offset]].
	(self isComplex: aSymbol) ifTrue: [^(1 to: bytes size // size) collect: [:i | | offset |
		offset := i - 1 * size + 1.
		Complex real: (get value: offset) imaginary: (get value: offset + (size // 2))]].
	^(1 to: bytes size // size) collect: [:i | get value: i - 1 * size + 1]
! !

!CudaArray methodsFor: 'initializing'!
setCount: anInteger type: aSymbol
	(self class types includes: aSymbol) ifFalse: [^self error: 'a CudaArray holds one of ' , self class types printString].
	(anInteger isInteger and: [anInteger >= 0]) ifFalse: [^self error: 'a CudaArray''s size is an Integer >= 0'].
	count := anInteger.
	type := aSymbol.
	self allocate
!
allocate
	address := CudaTrace hostOperation: 'cudaMalloc' detail: [self describe] during: [CudaRuntimeAPI cudaMalloc: (self byteSize max: 8)].
	session := CudaLibraryAPI session.
	WeakRegistry default add: self executor: (CudaReleaser kind: #memory value: address session: session).
	self class remember: self
!
setPending: anExpression
	count := anExpression count.
	type := anExpression type.
	session := CudaLibraryAPI session.
	pending := anExpression.
	anExpression arrays do: [:each | each addReader: self]
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
isComplex
	^self class isComplex: type
!
isReal
	^type == #float32 or: [type == #float64]
!
realType
	"#float32 or #float64: my type, or that of my real and imaginary parts."
	^self class realTypeOf: type
!
realCount
	"The Floats I hold: two a complex value."
	^self isComplex ifTrue: [count * 2] ifFalse: [count]
!
isDouble
	^self realType == #float64
!
dataType
	"My cudaDataType (CUDA_R_32F, ...), as cuSOLVER takes it."
	^CusolverAPI constant: (#('CUDA_R_32F' 'CUDA_R_64F' 'CUDA_C_32F' 'CUDA_C_64F') at: (#(#float32 #float64 #complex64 #complex128) indexOf: type))
!
isAlive
	"Whether I hold device memory of this VM session, or values to compute (isPending)."
	^(address notNil or: [pending notNil]) and: [session = CudaLibraryAPI session]
!
isPending
	"Whether my values are an expression not computed yet (CudaExpression): realize computes them."
	^pending notNil and: [session = CudaLibraryAPI session]
!
expression
	"My pending CudaExpression, or nil."
	^pending
!
address
	"My device address (an Integer the VM checks against its live allocations). Pending, I compute my values first; arrays pending on mine compute theirs (who asks may change me)."
	pending notNil ifTrue: [self realize].
	readers notNil ifTrue: [self realizeReaders].
	self isAlive ifFalse: [^self error: 'this ' , self class name , ' was released, or belongs to an earlier VM session'].
	^address
!
readAddress
	"My address for work that only reads me (a kernel's operand, a copy to the host): arrays pending on my values stay pending."
	pending notNil ifTrue: [self realize].
	self isAlive ifFalse: [^self error: 'this ' , self class name , ' was released, or belongs to an earlier VM session'].
	^address
!
addressAt: index
	^self address + (index - 1 * self elementSize)
!
elementShape
	"My shape for element-wise operations: {count} (a CudaMatrix: {rows. cols})."
	^Array with: count
! !

!CudaArray methodsFor: 'pending'!
realize
	"Compute my values now if they are pending (one kernel for the whole expression, CudaExpression); answer me."
	| e |
	pending isNil ifTrue: [^self].
	e := pending.
	pending := nil.
	session = CudaLibraryAPI session ifFalse: [^self].
	[self allocate.
	e evaluateInto: self]
		ifCurtailed: [self release. pending := e].
	e arrays do: [:each | each removeReader: self].
	^self
!
value
	"Me, my values computed (realize)."
	^self realize
!
storeInto: anArray
	"Compute my values into anArray (of my size and type; one of my operands too) instead of new memory, and answer it. A pending me is then spent (released); a computed one is copied."
	| e |
	(anArray size = count and: [anArray type = type]) ifFalse: [^self error: 'storeInto: wants a ' , self describe , ', not a ' , anArray describe].
	anArray == self ifTrue: [^self realize].
	self isPending ifFalse: [
		count > 0 ifTrue: [CudaRuntimeAPI cudaMemcpyDtoD: anArray address src: self readAddress count: self byteSize].
		^anArray].
	e := pending.
	pending := nil.
	e arrays do: [:each | each removeReader: self].
	anArray address.
	e evaluateInto: anArray.
	^anArray
!
asExpression
	"The CudaExpression of my values: my pending one, or me as an operand."
	self isPending ifTrue: [^pending].
	self isReal ifFalse: [^self error: 'element-wise operations take #float32 or #float64 arrays, not ' , type].
	self isAlive ifFalse: [^self error: 'this ' , self class name , ' was released, or belongs to an earlier VM session'].
	^CudaExpression array: self
!
addReader: anArray
	"anArray's pending values read mine (realizeReaders)."
	| slot |
	readers isNil ifTrue: [readers := WeakArray new: 4].
	slot := (1 to: readers size) detect: [:i | (readers at: i) isNil] ifNone: [0].
	slot = 0 ifTrue: [
		slot := readers size + 1.
		readers := (WeakArray new: readers size * 2) replaceFrom: 1 to: readers size with: readers startingAt: 1; yourself].
	readers at: slot put: anArray
!
removeReader: anArray
	readers isNil ifTrue: [^self].
	1 to: readers size do: [:i | (readers at: i) == anArray ifTrue: [readers at: i put: nil]]
!
realizeReaders
	"The arrays pending on my values compute them now: I may change, or go."
	| r |
	r := readers.
	readers := nil.
	r isNil ifTrue: [^self].
	r do: [:each | (each notNil and: [each isPending]) ifTrue: [each realize]]
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
	count > 0 ifTrue: [
		CudaTrace hostOperation: 'cudaMemcpy' detail: ['host to device, ' , self describe] during: [
			CudaRuntimeAPI cudaMemcpyHtoD: self address src: aByteArray count: aByteArray size]]
!
asByteArray
	^self bytesFrom: 1 count: count
!
bytesFrom: index count: n
	| bytes |
	(index >= 1 and: [n >= 0 and: [index + n - 1 <= count]]) ifFalse: [^self error: 'out of bounds'].
	bytes := ByteArray new: n * self elementSize.
	n > 0 ifTrue: [
		CudaTrace hostOperation: 'cudaMemcpy' detail: ['device to host, ' , (self class describe: n type: type)] during: [
			CudaRuntimeAPI cudaMemcpyDtoH: bytes src: self readAddress + (index - 1 * self elementSize) count: bytes size]].
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
	count > 0 ifTrue: [
		CudaTrace operation: 'cudaMemcpy' detail: ['device to device, ' , self describe] during: [
			CudaRuntimeAPI cudaMemcpyDtoD: copy address src: self readAddress count: self byteSize]].
	^copy
!
newVector: n type: aSymbol
	"A new CudaArray (a CudaMatrix answers a column)."
	^CudaArray new: n type: aSymbol
! !

!CudaArray methodsFor: 'complex'!
stridedCopy: n from: source inc: sourceInc offset: sourceOffset to: target inc: targetInc offset: targetOffset
	"Copy n reals between real views (cuBLAS copy): element sourceOffset + k * sourceInc of source to targetOffset + k * targetInc of target (0-based, in reals)."
	| size |
	n = 0 ifTrue: [^self].
	size := self realType == #float32 ifTrue: [4] ifFalse: [8].
	self isDouble
		ifTrue: [CublasAPI cublasDcopy: Cuda blas n: n x: source address + (sourceOffset * size) incx: sourceInc y: target address + (targetOffset * size) incy: targetInc]
		ifFalse: [CublasAPI cublasScopy: Cuda blas n: n x: source address + (sourceOffset * size) incx: sourceInc y: target address + (targetOffset * size) incy: targetInc]
!
asComplex
	"A new complex array of my values (a real array's with imaginary parts 0), copied on the device."
	| result |
	self isComplex ifTrue: [^self copyOnDevice].
	self isReal ifFalse: [^self error: 'not a real array'].
	result := self like: (self class complexTypeOf: type).
	result zero.
	self stridedCopy: count from: self inc: 1 offset: 0 to: result inc: 2 offset: 0.
	^result
!
real
	"A new real array of my real parts (my values, if I am real)."
	^self part: 0
!
imaginary
	"A new real array of my imaginary parts."
	self isComplex ifFalse: [^(self like: type) zero; yourself].
	^self part: 1
!
part: offset
	| result |
	self isComplex ifFalse: [^self copyOnDevice].
	result := self like: self realType.
	self stridedCopy: count from: self inc: 2 offset: offset to: result inc: 1 offset: 0.
	^result
!
like: aType
	"A new array of my shape and aType."
	^self class new: count type: aType
! !

!CudaArray methodsFor: 'computing'!
fillUniform
	"Fill me with random Floats in (0, 1] (cuRAND, this session's generator); answer me."
	count = 0 ifTrue: [^self].
	self isReal | self isComplex ifFalse: [^self error: 'fillUniform fills Floats'].
	CudaTrace operation: (self isDouble ifTrue: ['curandGenerateUniformDouble'] ifFalse: ['curandGenerateUniform']) detail: [self describe] during: [
		self isDouble
			ifTrue: [CurandAPI curandGenerateUniformDouble: Cuda rng outputPtr: self address num: self realCount]
			ifFalse: [CurandAPI curandGenerateUniform: Cuda rng outputPtr: self address num: self realCount]]
!
zero
	CudaTrace operation: 'cudaMemset' detail: [self describe] during: [CudaRuntimeAPI cudaMemset: self address value: 0 count: self byteSize]
!
norm
	"My Euclidean norm (cuBLAS nrm2; a complex array's as its interleaved parts)."
	^CudaTrace operation: (self isDouble ifTrue: ['cublasDnrm2'] ifFalse: ['cublasSnrm2']) detail: [self describe] during: [
		self isDouble
			ifTrue: [CublasAPI cublasDnrm2: Cuda blas n: self realCount x: self readAddress incx: 1]
			ifFalse: [CublasAPI cublasSnrm2: Cuda blas n: self realCount x: self readAddress incx: 1]]
!
scale: aNumber
	"Multiply me by the real aNumber in place (cuBLAS scal); answer me."
	count = 0 ifTrue: [^self].
	type == #float32 ifTrue: [CublasAPI cublasSscal: Cuda blas n: count alpha: aNumber asFloat x: self address incx: 1].
	type == #float64 ifTrue: [CublasAPI cublasDscal: Cuda blas n: count alpha: aNumber asFloat x: self address incx: 1].
	type == #complex64 ifTrue: [CublasAPI cublasCsscal: Cuda blas n: count alpha: aNumber asFloat x: self address incx: 1].
	type == #complex128 ifTrue: [CublasAPI cublasZdscal: Cuda blas n: count alpha: aNumber asFloat x: self address incx: 1]
!
add: other times: aNumber
	"A new array: me + aNumber * other (cuBLAS axpy; aNumber real)."
	| result |
	(other size = count and: [other type = type]) ifFalse: [^self error: 'sizes or types differ'].
	result := self copyOnDevice.
	CudaTrace operation: (self isDouble ifTrue: ['cublasDaxpy'] ifFalse: ['cublasSaxpy']) detail: [self describe] during: [
		self isDouble
			ifTrue: [CublasAPI cublasDaxpy: Cuda blas n: self realCount alpha: aNumber asFloat x: other address incx: 1 y: result address incy: 1]
			ifFalse: [CublasAPI cublasSaxpy: Cuda blas n: self realCount alpha: aNumber asFloat x: other address incx: 1 y: result address incy: 1]].
	^result
!
accumulate: other times: aNumber
	"Me := me + aNumber * other, in place (cuBLAS axpy); answer me."
	(other size = count and: [other type = type]) ifFalse: [^self error: 'sizes or types differ'].
	CudaTrace operation: (type == #float32 ifTrue: ['cublasSaxpy'] ifFalse: ['cublasDaxpy']) detail: [self describe] during: [
		type == #float32
			ifTrue: [CublasAPI cublasSaxpy: Cuda blas n: count alpha: aNumber asFloat x: other address incx: 1 y: self address incy: 1]
			ifFalse: [CublasAPI cublasDaxpy: Cuda blas n: count alpha: aNumber asFloat x: other address incx: 1 y: self address incy: 1]]
! !

!CudaArray methodsFor: 'element-wise'!
isComplexOperand: other
	^self isComplex or: [(other isKindOf: CudaArray) and: [other isComplex]]
!
elementwise: aSymbol
	^CudaExpression apply: aSymbol to: (Array with: self)
!
elementwise: aSymbol with: other
	^CudaExpression apply: aSymbol to: (Array with: self with: other)
!
+ other
	"Element-wise, pending (CudaExpression); complex arrays at once (cuBLAS axpy)."
	(self isComplexOperand: other) ifTrue: [^self add: other times: 1].
	^self elementwise: #+ with: other
!
- other
	(self isComplexOperand: other) ifTrue: [^self add: other times: -1].
	^self elementwise: #- with: other
!
* other
	"Element by element (a CudaMatrix's * of a matrix is the matrix product: mul: is the element-wise one)."
	^self elementwise: #* with: other
!
mul: other
	"The element-wise product, for matrices too."
	^self elementwise: #* with: other
!
/ other
	^self elementwise: #/ with: other
!
min: other
	^self elementwise: #min with: other
!
max: other
	^self elementwise: #max with: other
!
raisedTo: other
	^self elementwise: #pow with: other
!
< other
	"A mask: 1.0 where I am less than other, else 0.0 (pending)."
	^self elementwise: #lt with: other
!
<= other
	^self elementwise: #le with: other
!
> other
	^self elementwise: #gt with: other
!
>= other
	^self elementwise: #ge with: other
!
eq: other
	"A mask: 1.0 where I equal other (= stays identity's: a CudaArray is a key in collections)."
	^self elementwise: #eq with: other
!
ne: other
	^self elementwise: #ne with: other
!
where: whenTrue else: whenFalse
	"I am a mask: whenTrue's value where I am not 0, else whenFalse's (arrays or numbers; pending)."
	^CudaExpression apply: #where to: (Array with: self with: whenTrue with: whenFalse)
!
negated
	^self elementwise: #negated
!
abs
	^self elementwise: #abs
!
sqrt
	^self elementwise: #sqrt
!
squared
	^self elementwise: #squared
!
reciprocal
	^self elementwise: #reciprocal
!
exp
	^self elementwise: #exp
!
ln
	^self elementwise: #ln
!
log
	"Base 10, as Number's."
	^self elementwise: #log
!
sin
	^self elementwise: #sin
!
cos
	^self elementwise: #cos
!
tanh
	^self elementwise: #tanh
!
adaptToNumber: aNumber andSend: aSelector
	"aNumber + me and the like (Number's arithmetic retries with me)."
	(#(#+ #- #* #/) includes: aSelector) ifFalse: [^self error: 'a number cannot ' , aSelector , ' a ' , self class name].
	^CudaExpression apply: aSelector to: (Array with: aNumber with: self)
!
sum
	"The sum of my values, a Float: one kernel (a pending array's expression computed and summed in it, never stored)."
	^CudaExpression reduce: #sum of: self
!
max
	^CudaExpression reduce: #max of: self
!
min
	^CudaExpression reduce: #min of: self
!
mean
	^CudaExpression reduce: #mean of: self
! !

!CudaArray methodsFor: 'fourier'!
fftShape
	"The dimensions of my transforms (cuFFT's n: the last varies fastest)."
	^{count}
!
fftBatch
	^1
!
fftResultLike: dims batch: batch type: aType
	"A new array (a CudaMatrix answers a matrix) for batch transforms of the shape dims."
	^CudaArray new: (dims inject: batch into: [:a :b | a * b]) type: aType
!
fft
	"My discrete Fourier transform, unnormalized, on the device (cuFFT): of a complex array the full one; of a real one the half spectrum, count // 2 + 1 Complex values (the rest are their conjugates)."
	^self fft: self fftShape batch: self fftBatch
!
ifft
	"The inverse transform of my complex values, normalized (1/n): me fft ifft is me."
	^self ifft: self fftShape batch: self fftBatch
!
ifftReal: n
	"The real array of n values whose half spectrum (fft) I am, normalized: (a fft ifftReal: a size) is a."
	^self ifftReal: {n} batch: 1
!
fft: dims batch: batch
	| plan result source halfDims |
	self isComplex
		ifTrue: [
			result := self fftResultLike: dims batch: batch type: type.
			plan := Cuda fftPlan: dims kind: #c2c type: type batch: batch.
			plan forward: self into: result.
			^result].
	self isReal ifFalse: [^self error: 'fft transforms Floats or Complex numbers'].
	halfDims := dims copy.
	halfDims at: dims size put: dims last // 2 + 1.
	result := self fftResultLike: halfDims batch: batch type: (self class complexTypeOf: type).
	source := self.
	plan := Cuda fftPlan: dims kind: #r2c type: type batch: batch.
	plan forward: source into: result.
	^result
!
ifft: dims batch: batch
	| plan result |
	self isComplex ifFalse: [^self asComplex ifft: dims batch: batch].
	result := self fftResultLike: dims batch: batch type: type.
	plan := Cuda fftPlan: dims kind: #c2c type: type batch: batch.
	plan inverse: self into: result.
	^result scale: 1.0 / (dims inject: 1 into: [:a :b | a * b])
!
ifftReal: dims batch: batch
	"dims: the real result's dimensions; I hold the half spectrum (the last dimension // 2 + 1)."
	| plan result source |
	self isComplex ifFalse: [^self error: 'ifftReal: transforms a complex half spectrum'].
	(dims allButLast inject: dims last // 2 + 1 into: [:a :b | a * b]) * batch = count
		ifFalse: [^self error: 'a half spectrum of ' , dims printString , ' has ' , ((dims allButLast inject: dims last // 2 + 1 into: [:a :b | a * b]) * batch) printString , ' values, not ' , count printString].
	result := self fftResultLike: dims batch: batch type: self realType.
	source := self copyOnDevice.
	plan := Cuda fftPlan: dims kind: #c2r type: self realType batch: batch.
	[plan inverse: source into: result] ensure: [source release].
	^result scale: 1.0 / (dims inject: 1 into: [:a :b | a * b])
! !

!CudaArray methodsFor: 'releasing'!
release
	"Free my device memory now (arrays pending on my values compute them first); pending, forget my expression."
	pending notNil ifTrue: [
		pending arrays do: [:each | each removeReader: self].
		pending := nil].
	readers notNil ifTrue: [self realizeReaders].
	self isAlive ifTrue: [CudaTrace hostOperation: 'cudaFree' detail: [self describe] during: [CudaRuntimeAPI cudaFree: address]].
	address := nil.
	WeakRegistry default remove: self
! !

!CudaArray methodsFor: 'inspecting'!
inspectorExtraFields
	"What an Inspector shows of me besides my variables: name -> a block of me (evaluated at each refresh: copies from the device)."
	^{'device' -> [:a | a isAlive ifTrue: [a describe , ' at 16r' , (a address printString: 16)] ifFalse: ['released']].
		'first values' -> [:a | a isAlive ifTrue: [CudaTrace quietly: [a first: 64]] ifFalse: [#()]]}
! !

!CudaArray methodsFor: 'printing'!
describe
	"float32[1000] (4 KB), as the GPU Monitor lists me."
	^type , self shapeString , ' (' , self sizeString , ')'
!
shapeString
	^'[' , count printString , ']'
!
sizeString
	^self class sizeString: self byteSize
!
printOn: aStream
	aStream nextPutAll: 'a '; nextPutAll: self class name; space; nextPutAll: type; nextPutAll: self shapeString.
	self isAlive ifFalse: [^aStream nextPutAll: ' (released)'].
	aStream nextPutAll: ' ('; nextPutAll: self sizeString; nextPutAll: ') '.
	[CudaTrace quietly: [self printValuesOn: aStream]] on: Error do: [:e | aStream nextPutAll: '(unreadable: '; nextPutAll: e messageText; nextPut: $)]
!
printValue: v on: aStream
	"4 decimals; a Complex as 1.0000+2.0000i."
	v isInteger ifTrue: [^aStream print: v].
	(v isKindOf: Complex) ifFalse: [^aStream nextPutAll: (v printShowingDecimalPlaces: 4)].
	aStream nextPutAll: (v real printShowingDecimalPlaces: 4).
	v imaginary negative ifFalse: [aStream nextPut: $+].
	aStream nextPutAll: (v imaginary printShowingDecimalPlaces: 4); nextPut: $i
!
printValues: anArray more: aBoolean on: aStream
	aStream nextPut: $(.
	anArray do: [:v | self printValue: v on: aStream] separatedBy: [aStream space].
	aBoolean ifTrue: [aStream nextPutAll: ' ...'].
	aStream nextPut: $)
!
printValuesOn: aStream
	self printValues: (self first: 6) more: count > 6 on: aStream
! !
