Object subclass: #CudaDecomposition
	instanceVariableNames: 'kind parts'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaDecomposition comment: 'I am a matrix factorization cuSOLVER computed, its parts on the device as CudaMatrix and CudaArray: kind #qr (q, r), #svd (u, s, vt: A = U diag(S) Vt) or #eigen (values, vectors: A = V diag(values) V^T). CudaLU is the LU one, which also solves. Release me to free all my parts.

	| d | d := (CudaMatrix uniformRows: 6 cols: 4 type: #float64) svd.
	d s asArray. d u. d vt. d release'!

!CudaDecomposition class methodsFor: 'instance creation'!
kind: aSymbol parts: associations
	^self new setKind: aSymbol parts: associations
! !

!CudaDecomposition methodsFor: 'accessing'!
setKind: aSymbol parts: associations
	kind := aSymbol.
	parts := associations
!
kind
	^kind
!
part: aSymbol
	parts do: [:a | a key == aSymbol ifTrue: [^a value]].
	^self error: 'a ' , kind , ' decomposition has no ' , aSymbol
!
partNames
	^parts collect: [:a | a key]
!
q
	^self part: #q
!
r
	^self part: #r
!
u
	^self part: #u
!
s
	"The singular values, decreasing."
	^self part: #s
!
vt
	^self part: #vt
!
values
	"The eigenvalues, increasing."
	^self part: #values
!
vectors
	"The eigenvectors, as columns."
	^self part: #vectors
! !

!CudaDecomposition methodsFor: 'releasing'!
release
	parts do: [:a | a value release]
! !

!CudaDecomposition methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a CudaDecomposition '; nextPutAll: kind.
	parts do: [:a | aStream nextPutAll: (a == parts first ifTrue: [': '] ifFalse: ['; ']); nextPutAll: a key; nextPutAll: ' '; nextPutAll: a value type; nextPutAll: a value shapeString]
! !
