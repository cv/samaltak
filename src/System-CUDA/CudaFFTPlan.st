Object subclass: #CudaFFTPlan
	instanceVariableNames: 'handle session shape kind type batch'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaFFTPlan comment: 'I am a cuFFT plan: batch transforms of the shape shape (1 to 3 dimensions, the last varying fastest, as a row-major CudaMatrix lays out its rows), of kind #r2c (real to the half spectrum: the last dimension // 2 + 1 complex values), #c2r (back) or #c2c, in type #float32 or #float64 (#complex64 / #complex128 for #c2c). The VM remembers my type and array sizes with my handle, so it refuses to run me on arrays too short or of the other kind. CudaArray>>fft and ifft use the session''s, kept by shape (Cuda fftPlan:kind:type:batch:: planning a 4096 x 4096 transform costs more than the transform); one made here is the caller''s, to release. Release me, or I am destroyed when collected.

	| plan a b | plan := CudaFFTPlan shape: #(4096 4096) kind: #r2c type: #float32 batch: 1.
	a := CudaMatrix uniformRows: 4096 cols: 4096. b := CudaMatrix rows: 4096 cols: 2049 type: #complex64.
	plan forward: a into: b. plan release'!

!CudaFFTPlan class methodsFor: 'instance creation'!
shape: dims kind: aSymbol type: aType batch: anInteger
	^self basicNew setShape: dims kind: aSymbol type: aType batch: anInteger
! !

!CudaFFTPlan class methodsFor: 'constants'!
cufftType: aSymbol for: aType
	"cuFFT's transform type: R2C, C2R, C2C in single precision, D2Z, Z2D, Z2Z in double."
	| double name |
	double := (CudaArray realTypeOf: aType) == #float64.
	name := aSymbol == #r2c
		ifTrue: [double ifTrue: ['CUFFT_D2Z'] ifFalse: ['CUFFT_R2C']]
		ifFalse: [aSymbol == #c2r
			ifTrue: [double ifTrue: ['CUFFT_Z2D'] ifFalse: ['CUFFT_C2R']]
			ifFalse: [double ifTrue: ['CUFFT_Z2Z'] ifFalse: ['CUFFT_C2C']]].
	^CufftAPI constant: name
! !

!CudaFFTPlan methodsFor: 'initializing'!
setShape: dims kind: aSymbol type: aType batch: anInteger
	| n |
	(#(#r2c #c2r #c2c) includes: aSymbol) ifFalse: [^self error: 'a CudaFFTPlan is #r2c, #c2r or #c2c'].
	(dims size between: 1 and: 3) ifFalse: [^self error: 'cuFFT transforms 1 to 3 dimensions'].
	shape := dims asArray.
	kind := aSymbol.
	type := CudaArray realTypeOf: aType.
	batch := anInteger.
	n := ByteArray new: dims size * 4.
	dims doWithIndex: [:d :i | n uint32At: i - 1 * 4 + 1 put: d].
	handle := CufftAPI cufftPlanMany: dims size n: n type: (self class cufftType: aSymbol for: type) batch: anInteger.
	session := CudaLibraryAPI session.
	WeakRegistry default add: self executor: (CudaReleaser kind: #fftPlan value: handle session: session)
! !

!CudaFFTPlan methodsFor: 'accessing'!
shape
	^shape
!
kind
	^kind
!
type
	^type
!
batch
	^batch
!
isAlive
	^handle notNil and: [session = CudaLibraryAPI session]
!
handle
	self isAlive ifFalse: [^self error: 'a CudaFFTPlan released or of an earlier VM session'].
	^handle
!
realCount
	"The elements of my full arrays (reals for #r2c input and #c2r output, complex values for #c2c)."
	^shape inject: batch into: [:a :b | a * b]
!
halfCount
	"The complex values of my half-spectrum arrays."
	^(shape allButLast inject: shape last // 2 + 1 into: [:a :b | a * b]) * batch
! !

!CudaFFTPlan methodsFor: 'transforming'!
check: anArray type: aType count: n
	anArray type == aType ifFalse: [^self error: 'this plan transforms ' , aType , ', not ' , anArray type].
	anArray size >= n ifFalse: [^self error: 'this plan needs ' , n printString , ' values, not ' , anArray size printString]
!
forward: source into: target
	"Queue the forward transform of source into target (both CudaArrays; source unchanged except for #c2r); answer target."
	^self run: source into: target direction: (CufftAPI constant: 'CUFFT_FORWARD')
!
inverse: source into: target
	"The unnormalized inverse (cuFFT's): the forward one's result times the elements of a transform."
	^self run: source into: target direction: (CufftAPI constant: 'CUFFT_INVERSE')
!
run: source into: target direction: direction
	| complex double |
	complex := CudaArray complexTypeOf: type.
	double := type == #float64.
	kind == #c2c ifTrue: [
		self check: source type: complex count: self realCount; check: target type: complex count: self realCount.
		double
			ifTrue: [CufftAPI cufftExecZ2Z: self handle idata: source readAddress odata: target address direction: direction]
			ifFalse: [CufftAPI cufftExecC2C: self handle idata: source readAddress odata: target address direction: direction].
		^target].
	kind == #r2c ifTrue: [
		self check: source type: type count: self realCount; check: target type: complex count: self halfCount.
		double
			ifTrue: [CufftAPI cufftExecD2Z: self handle idata: source readAddress odata: target address]
			ifFalse: [CufftAPI cufftExecR2C: self handle idata: source readAddress odata: target address].
		^target].
	self check: source type: complex count: self halfCount; check: target type: type count: self realCount.
	double
		ifTrue: [CufftAPI cufftExecZ2D: self handle idata: source address odata: target address]
		ifFalse: [CufftAPI cufftExecC2R: self handle idata: source address odata: target address].
	^target
! !

!CudaFFTPlan methodsFor: 'releasing'!
release
	self isAlive ifTrue: [CufftAPI cufftDestroy: handle].
	handle := nil.
	WeakRegistry default remove: self
! !

!CudaFFTPlan methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a CudaFFTPlan '; nextPutAll: kind; space; nextPutAll: type; space; print: shape.
	batch = 1 ifFalse: [aStream nextPutAll: ' x '; print: batch].
	self isAlive ifFalse: [aStream nextPutAll: ' (released)']
! !
