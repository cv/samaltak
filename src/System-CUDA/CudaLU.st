Object subclass: #CudaLU
	instanceVariableNames: 'n type factors pivots info status'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaLU comment: 'I am the LU factorization with partial pivoting of an n x n CudaMatrix A, P A = L U (cuSOLVER Xgetrf), kept on the device: factors (L below the diagonal, its unit diagonal implied, and U, column-major, as cuSOLVER leaves them) and pivots (LAPACK''s ipiv: row i was exchanged with row (pivots at: i)). solve: and inverse run getrs on them; determinant is the product of U''s diagonal, signed by the exchanges; l, u and permutation give the factors as Smalltalk reads them. A singular A has an LU too (isSingular: getrf''s devInfo, U(i, i) exactly zero); solve: and inverse then signal CudaSingularMatrix. Release me when done (or my arrays are freed when collected).

	| lu | lu := (CudaMatrix fromRows: #(#(4 3) #(6 3)) type: #float64) lu.
	lu determinant.     "-6.0"
	(lu solve: (CudaArray withAll: #(10 12) type: #float64)) asArray.   "#(1.0 2.0)"
	lu release'!

!CudaLU class methodsFor: 'instance creation'!
of: aMatrix
	^self basicNew factor: aMatrix
! !

!CudaLU methodsFor: 'factoring'!
factor: aMatrix
	| sizes work host dt |
	n := aMatrix rows.
	type := aMatrix type.
	dt := aMatrix dataType.
	factors := aMatrix transposed.
	pivots := CudaArray new: n type: #int64.
	info := CudaArray new: 1 type: #int32.
	[sizes := Cuda bufferSize: {#getrf. n. type} ifAbsent: [CusolverAPI cusolverDnXgetrfBufferSize: Cuda solver params: Cuda solverParams m: n n: n dataTypeA: dt a: factors address lda: n computeType: dt].
	work := Cuda workspace: sizes first.
	host := ByteArray new: (sizes last max: 1).
	CusolverAPI cusolverDnXgetrf: Cuda solver params: Cuda solverParams m: n n: n dataTypeA: dt a: factors address lda: n ipiv: pivots address computeType: dt
		bufferOnDevice: work address workspaceInBytesOnDevice: sizes first bufferOnHost: host workspaceInBytesOnHost: sizes last info: info address.
	status := info at: 1]
		ensure: [Cuda releaseWorkspace: work].
	status < 0 ifTrue: [self release. CudaSolverError signalInfo: status in: 'cusolverDnXgetrf']
! !

!CudaLU methodsFor: 'accessing'!
size
	^n
!
type
	^type
!
factors
	"L and U in one column-major n x n array, as getrf leaves them."
	^factors
!
pivots
	"LAPACK's ipiv, 1-based: row i was exchanged with row (pivots at: i), i = 1, 2, ..."
	^pivots asArray
!
isSingular
	"Whether getrf found U(i, i) exactly zero (its devInfo i > 0)."
	^status > 0
!
devInfo
	^status
!
permutation
	"p with (P A) row i = A row (p at: i)."
	| p |
	p := (1 to: n) asArray.
	self pivots doWithIndex: [:k :i | p swap: i with: k].
	^p
!
l
	"L, unit lower triangular, a new CudaMatrix."
	^(CudaMatrix rows: 0 cols: 0 type: type) triangle: false unit: true of: factors size: n ld: n
!
u
	"U, upper triangular, a new CudaMatrix."
	^(CudaMatrix rows: 0 cols: 0 type: type) triangle: true unit: false of: factors size: n ld: n
!
diagonal
	"U's diagonal, from the device."
	| d |
	d := CudaArray new: n type: type.
	^[factors stridedCopy: n from: factors inc: n + 1 offset: 0 to: d inc: 1 offset: 0.
	d asArray] ensure: [d release]
! !

!CudaLU methodsFor: 'solving'!
checkSingular: functionName
	self isSingular ifTrue: [^CudaSingularMatrix signalInfo: status in: functionName]
!
solve: b
	"x with A x = b: b a CudaArray of n values (answers a CudaArray) or a CudaMatrix n x k (answers one, n x k). Signals CudaSingularMatrix if A is singular."
	| nrhs x result |
	self checkSingular: 'cusolverDnXgetrf'.
	b type = type ifFalse: [^self error: 'the right-hand side is ' , b type , ', the matrix ' , type].
	nrhs := (b isKindOf: CudaMatrix)
		ifTrue: [b rows = n ifFalse: [^self error: 'the right-hand side has ' , b rows printString , ' rows, not ' , n printString]. b cols]
		ifFalse: [b size = n ifFalse: [^self error: 'the right-hand side has ' , b size printString , ' values, not ' , n printString]. 1].
	nrhs = 0 ifTrue: [^b copyOnDevice].
	"One column is the same in either order; several are transposed to column-major and back."
	x := nrhs = 1 ifTrue: [b copyOnDevice] ifFalse: [b transposed].
	[self getrs: x nrhs: nrhs] ifCurtailed: [x release].
	nrhs = 1 ifTrue: [^x].
	result := x transposed.
	x release.
	^result
!
getrs: x nrhs: nrhs
	"Solve A X = B in place: x holds B column-major (n x nrhs)."
	| dt |
	dt := factors dataType.
	CusolverAPI cusolverDnXgetrs: Cuda solver params: Cuda solverParams trans: (CusolverAPI constant: 'CUBLAS_OP_N') n: n nrhs: nrhs
		dataTypeA: dt a: factors address lda: n ipiv: pivots address dataTypeB: dt b: x address ldb: n info: info address.
	CudaSolverError check: info in: 'cusolverDnXgetrs'
!
inverse
	"A's inverse, a new CudaMatrix (getrs on the identity). Signals CudaSingularMatrix if A is singular."
	| x result |
	self checkSingular: 'cusolverDnXgetrf'.
	x := CudaMatrix identity: n type: type.
	[self getrs: x nrhs: n] ifCurtailed: [x release].
	"x holds A^-1 column-major: its transpose as read."
	result := x transposed.
	x release.
	^result
!
determinantSign
	"-1 or 1: the parity of the row exchanges (and of U's diagonal's signs: see determinant)."
	| sign |
	sign := 1.
	self pivots doWithIndex: [:k :i | k = i ifFalse: [sign := sign negated]].
	^sign
!
determinant
	"det A: the product of U's diagonal, signed by the row exchanges; 0.0 if singular. Can overflow a Float for a large matrix: logAbsDeterminant does not."
	| product |
	self isSingular ifTrue: [^0.0].
	product := self diagonal inject: 1.0 into: [:a :d | a * d].
	^product * self determinantSign
!
logAbsDeterminant
	"ln |det A| (Float infinity negated if singular)."
	self isSingular ifTrue: [^Float infinity negated].
	^self diagonal inject: 0.0 into: [:a :d | a + d abs ln]
! !

!CudaLU methodsFor: 'releasing'!
release
	factors ifNotNil: [factors release].
	pivots ifNotNil: [pivots release].
	info ifNotNil: [info release]
! !

!CudaLU methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a CudaLU of a '; nextPutAll: type; nextPutAll: '['; print: n; nextPut: $x; print: n; nextPutAll: '] matrix'.
	(factors notNil and: [factors isAlive]) ifFalse: [^aStream nextPutAll: ' (released)'].
	self isSingular ifTrue: [aStream nextPutAll: ', singular (U('; print: status; nextPut: $,; print: status; nextPutAll: ') = 0)']
! !
