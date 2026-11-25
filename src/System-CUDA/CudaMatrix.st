CudaArray subclass: #CudaMatrix
	instanceVariableNames: 'rows cols'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaMatrix comment: 'I am a rows x cols matrix in the CUDA device''s memory, stored row-major as Smalltalk reads a matrix (element i, j at (i - 1) * cols + j), of type #float32 or #float64 (or #complex64 / #complex128 for Fourier transforms). a * b multiplies on the device with cuBLAS (Sgemm or Dgemm) into a new matrix; multiply:into: reuses one. cuBLAS and cuSOLVER are column-major, where a row-major matrix reads as its transpose, so C = A B is computed as the column-major C^T = B^T A^T: the same gemm with the operands swapped, no transposes or copies (docs/cuda.md). The factorizations run on the device with cuSOLVER: lu (a CudaLU: solve:, inverse, determinant), qr, svd, cholesky, symmetricEigen (CudaDecomposition); solve:, inverse and determinant use lu. A failure the library reports in devInfo (a singular matrix, one not positive definite, no convergence) is a CudaSolverError with the library''s meaning. fft is my 2-D Fourier transform (cuFFT; of a real matrix the half spectrum, rows x (cols // 2 + 1)), fftRows the 1-D one of each row (batched).

	| a b | a := CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6). b := CudaMatrix rows: 3 cols: 2 values: #(1 0 0 1 1 1).
	(a * b) asRows      "#(#(4.0 5.0) #(10.0 11.0))"
	(CudaMatrix uniformRows: 4096 cols: 4096) * (CudaMatrix uniformRows: 4096 cols: 4096)
	((CudaMatrix fromRows: #(#(2 1) #(1 3)) type: #float64) solve: (CudaArray withAll: #(3 5) type: #float64)) asArray   "#(0.8 1.4)"
	(CudaMatrix fromRows: #(#(2 1) #(1 3)) type: #float64) determinant   "5.0"'!

!CudaMatrix class methodsFor: 'instance creation'!
rows: r cols: c type: aSymbol
	^(self new: r * c type: aSymbol) setRows: r cols: c
!
rows: r cols: c
	^self rows: r cols: c type: #float32
!
rows: r cols: c values: anArray type: aSymbol
	"anArray: the values row by row."
	^(self rows: r cols: c type: aSymbol) fromArray: anArray
!
rows: r cols: c values: anArray
	^self rows: r cols: c values: anArray type: #float32
!
fromRows: anArray type: aSymbol
	"anArray: an Array of rows, each an Array of numbers."
	| c values |
	c := anArray isEmpty ifTrue: [0] ifFalse: [anArray first size].
	values := OrderedCollection new.
	anArray do: [:row |
		row size = c ifFalse: [^self error: 'rows of different lengths'].
		values addAll: row].
	^self rows: anArray size cols: c values: values asArray type: aSymbol
!
fromRows: anArray
	^self fromRows: anArray type: #float32
!
uniformRows: r cols: c type: aSymbol
	^(self rows: r cols: c type: aSymbol) fillUniform
!
uniformRows: r cols: c
	^self uniformRows: r cols: c type: #float32
!
identity: n type: aSymbol
	"The n x n identity matrix: zeros, and ones copied onto the diagonal (cuBLAS copy, stride n + 1)."
	| id ones |
	id := self rows: n cols: n type: aSymbol.
	id zero.
	n = 0 ifTrue: [^id].
	ones := CudaArray withAll: (Array new: n withAll: 1.0) type: aSymbol.
	[id stridedCopy: n from: ones inc: 1 offset: 0 to: id inc: n + 1 offset: 0] ensure: [ones release].
	^id
! !

!CudaMatrix methodsFor: 'accessing'!
setRows: r cols: c
	rows := r.
	cols := c
!
rows
	^rows
!
cols
	^cols
!
isSquare
	^rows = cols
!
at: i at: j
	^self at: i - 1 * cols + j
!
asRows
	| values |
	values := self asArray.
	^(1 to: rows) collect: [:i | values copyFrom: i - 1 * cols + 1 to: i * cols]
!
emptyLike
	^self class rows: rows cols: cols type: type
!
like: aType
	^self class rows: rows cols: cols type: aType
! !

!CudaMatrix methodsFor: 'arithmetic'!
* aMatrix
	"A new matrix: me times aMatrix, on the device."
	^self multiply: aMatrix into: (self class rows: rows cols: aMatrix cols type: type)
!
multiply: b into: c
	"c := me * b, all row-major; answer c. cuBLAS is column-major, where a row-major m x k matrix reads as its k x m transpose, so c^T = b^T me^T: the gemm of b and me, swapped (m := b cols, n := my rows), each leading dimension its own row length."
	(cols = b rows and: [c rows = rows and: [c cols = b cols]]) ifFalse: [
		^self error: 'shapes do not fit: ' , self shapeString , ' * ' , b shapeString , ' into ' , c shapeString].
	(type = b type and: [type = c type]) ifFalse: [^self error: 'types differ'].
	self isReal ifFalse: [^self error: 'products of ' , type , ' matrices are not bound'].
	(rows = 0 or: [b cols = 0]) ifTrue: [^c].
	type == #float32
		ifTrue: [CublasAPI cublasSgemm: Cuda blas transa: 0 transb: 0 m: b cols n: rows k: cols
			alpha: 1.0 a: b address lda: (b cols max: 1) b: self address ldb: (cols max: 1) beta: 0.0 c: c address ldc: (c cols max: 1)]
		ifFalse: [CublasAPI cublasDgemm: Cuda blas transa: 0 transb: 0 m: b cols n: rows k: cols
			alpha: 1.0 a: b address lda: (b cols max: 1) b: self address ldb: (cols max: 1) beta: 0.0 c: c address ldc: (c cols max: 1)].
	^c
!
transposed
	"A new matrix, my transpose (cuBLAS geam). Its memory, read column-major, is me: what cuSOLVER takes."
	| t |
	self isReal ifFalse: [^self error: 'transposes of ' , type , ' matrices are not bound'].
	t := self class rows: cols cols: rows type: type.
	(rows = 0 or: [cols = 0]) ifTrue: [^t].
	"Column-major I am the cols x rows matrix (ld cols); t is me rows x cols (ld rows): op(A) = A^T."
	type == #float32
		ifTrue: [CublasAPI cublasSgeam: Cuda blas transa: 1 transb: 0 m: rows n: cols alpha: 1.0 a: self address lda: cols beta: 0.0 b: t address ldb: rows c: t address ldc: rows]
		ifFalse: [CublasAPI cublasDgeam: Cuda blas transa: 1 transb: 0 m: rows n: cols alpha: 1.0 a: self address lda: cols beta: 0.0 b: t address ldb: rows c: t address ldc: rows].
	^t
!
triangle: upper unit: unit of: factors size: n ld: ld
	"A new n x n matrix: the lower (or upper) triangle of the column-major n x n matrix at factors (leading dimension ld), as Smalltalk reads it, with ones on the diagonal if unit: cuBLAS trmm of the triangle, transposed, by the identity (a column-major C = tri(A)^T is tri(A) row-major)."
	| id result fill diag |
	id := self class identity: n type: type.
	result := self class rows: n cols: n type: type.
	fill := CublasAPI constant: (upper ifTrue: ['CUBLAS_FILL_MODE_UPPER'] ifFalse: ['CUBLAS_FILL_MODE_LOWER']).
	diag := CublasAPI constant: (unit ifTrue: ['CUBLAS_DIAG_UNIT'] ifFalse: ['CUBLAS_DIAG_NON_UNIT']).
	[n > 0 ifTrue: [
		type == #float32
			ifTrue: [CublasAPI cublasStrmm: Cuda blas side: (CublasAPI constant: 'CUBLAS_SIDE_LEFT') uplo: fill trans: 1 diag: diag m: n n: n
				alpha: 1.0 a: factors address lda: ld b: id address ldb: n c: result address ldc: n]
			ifFalse: [CublasAPI cublasDtrmm: Cuda blas side: (CublasAPI constant: 'CUBLAS_SIDE_LEFT') uplo: fill trans: 1 diag: diag m: n n: n
				alpha: 1.0 a: factors address lda: ld b: id address ldb: n c: result address ldc: n]]]
		ensure: [id release].
	^result
! !

!CudaMatrix methodsFor: 'solving'!
checkReal: aString
	self isReal ifFalse: [^self error: aString , ' factors #float32 or #float64 matrices'].
	(rows = 0 or: [cols = 0]) ifTrue: [^self error: aString , ' of an empty matrix']
!
checkSquare: aString
	self checkReal: aString.
	self isSquare ifFalse: [^self error: aString , ' needs a square matrix, not ' , self shapeString]
!
lu
	"My LU factorization with partial pivoting, P A = L U (cuSOLVER getrf): a CudaLU, which solves, inverts and has the determinant. A singular matrix has one too (isSingular); solving with it signals CudaSingularMatrix."
	self checkSquare: 'lu'.
	^CudaLU of: self
!
solve: b
	"x with me x = b (LU, then getrs): b a CudaArray of my rows (answers a CudaArray) or a CudaMatrix of my rows (answers a matrix of its shape). Signals CudaSingularMatrix for a singular me."
	| lu |
	lu := self lu.
	^[lu solve: b] ensure: [lu release]
!
inverse
	"My inverse (LU, then getrs on the identity). Signals CudaSingularMatrix for a singular me."
	| lu |
	lu := self lu.
	^[lu inverse] ensure: [lu release]
!
determinant
	"From LU: the product of U's diagonal, signed by the row exchanges (0.0 for a singular me)."
	| lu |
	lu := self lu.
	^[lu determinant] ensure: [lu release]
!
cholesky
	"The lower triangular L with me = L L^T (cuSOLVER potrf), me symmetric positive definite (my upper triangle is the one read). Signals CudaNotPositiveDefinite otherwise."
	| n c sizes work host info result |
	self checkSquare: 'cholesky'.
	n := rows.
	c := self copyOnDevice.
	info := CudaArray new: 1 type: #int32.
	[sizes := CusolverAPI cusolverDnXpotrfBufferSize: Cuda solver params: Cuda solverParams uplo: (CusolverAPI constant: 'CUBLAS_FILL_MODE_LOWER') n: n
		dataTypeA: self dataType a: c address lda: n computeType: self dataType.
	work := CudaArray workspace: sizes first.
	host := ByteArray new: (sizes last max: 1).
	CusolverAPI cusolverDnXpotrf: Cuda solver params: Cuda solverParams uplo: (CusolverAPI constant: 'CUBLAS_FILL_MODE_LOWER') n: n
		dataTypeA: self dataType a: c address lda: n computeType: self dataType
		bufferOnDevice: work address workspaceInBytesOnDevice: sizes first bufferOnHost: host workspaceInBytesOnHost: sizes last info: info address.
	CudaSolverError check: info in: 'cusolverDnXpotrf'.
	result := self triangle: false unit: false of: c size: n ld: n]
		ensure: [c release. info release. work ifNotNil: [work release]].
	^result
!
qr
	"My thin QR factorization, me = Q R with Q rows x cols with orthonormal columns and R cols x cols upper triangular (cuSOLVER geqrf, then orgqr for Q), for rows >= cols: a CudaDecomposition (q, r)."
	| m n f tau info sizes work host lwork r q |
	self checkReal: 'qr'.
	rows >= cols ifFalse: [^self error: 'qr needs rows >= cols, not ' , self shapeString].
	m := rows. n := cols.
	f := self transposed.
	tau := CudaArray new: n type: type.
	info := CudaArray new: 1 type: #int32.
	[[sizes := CusolverAPI cusolverDnXgeqrfBufferSize: Cuda solver params: Cuda solverParams m: m n: n dataTypeA: self dataType a: f address lda: m
		dataTypeTau: self dataType tau: tau address computeType: self dataType.
	work := CudaArray workspace: sizes first.
	host := ByteArray new: (sizes last max: 1).
	CusolverAPI cusolverDnXgeqrf: Cuda solver params: Cuda solverParams m: m n: n dataTypeA: self dataType a: f address lda: m
		dataTypeTau: self dataType tau: tau address computeType: self dataType
		bufferOnDevice: work address workspaceInBytesOnDevice: sizes first bufferOnHost: host workspaceInBytesOnHost: sizes last info: info address.
	CudaSolverError check: info in: 'cusolverDnXgeqrf'.
	work release.
	r := self triangle: true unit: false of: f size: n ld: m.
	lwork := self isDouble
		ifTrue: [CusolverAPI cusolverDnDorgqrBufferSize: Cuda solver m: m n: n k: n a: f address lda: m tau: tau address]
		ifFalse: [CusolverAPI cusolverDnSorgqrBufferSize: Cuda solver m: m n: n k: n a: f address lda: m tau: tau address].
	work := CudaArray new: (lwork max: 1) type: type.
	self isDouble
		ifTrue: [CusolverAPI cusolverDnDorgqr: Cuda solver m: m n: n k: n a: f address lda: m tau: tau address work: work address lwork: lwork info: info address]
		ifFalse: [CusolverAPI cusolverDnSorgqr: Cuda solver m: m n: n k: n a: f address lda: m tau: tau address work: work address lwork: lwork info: info address].
	CudaSolverError check: info in: (self isDouble ifTrue: ['cusolverDnDorgqr'] ifFalse: ['cusolverDnSorgqr']).
	"f, n x m, is Q column-major: Q^T as Smalltalk reads it."
	q := f transposed]
		ifCurtailed: [r ifNotNil: [r release]]]
		ensure: [f release. tau release. info release. work ifNotNil: [work release]].
	^CudaDecomposition kind: #qr parts: {#q -> q. #r -> r}
!
svd
	"My thin singular value decomposition, me = U diag(S) Vt with k := rows min: cols: U rows x k and Vt k x cols with orthonormal columns and rows, S the k singular values, decreasing (cuSOLVER gesvd): a CudaDecomposition (u, s, vt)."
	^self svdVectors: true
!
singularValues
	"My singular values, decreasing (a CudaArray; cuSOLVER gesvd without vectors)."
	| d s |
	d := self svdVectors: false.
	s := d s.
	^s
!
svdVectors: aBoolean
	| wide m n a s u vt lwork work rwork info job |
	self checkReal: 'svd'.
	"gesvd wants m >= n of its column-major matrix: a wide me read column-major is my transpose, cols x rows, as it is; a tall me is transposed first."
	wide := cols >= rows.
	wide ifTrue: [a := self copyOnDevice. m := cols. n := rows] ifFalse: [a := self transposed. m := rows. n := cols].
	s := CudaArray new: n type: type.
	job := aBoolean ifTrue: [83 "S: the thin vectors"] ifFalse: [78 "N: none"].
	aBoolean ifTrue: [
		u := self class rows: n cols: m type: type.
		vt := self class rows: n cols: n type: type].
	info := CudaArray new: 1 type: #int32.
	[[lwork := self isDouble
		ifTrue: [CusolverAPI cusolverDnDgesvdBufferSize: Cuda solver m: m n: n]
		ifFalse: [CusolverAPI cusolverDnSgesvdBufferSize: Cuda solver m: m n: n].
	work := CudaArray new: (lwork max: 1) type: type.
	rwork := CudaArray new: (n - 1 max: 1) type: type.
	self isDouble
		ifTrue: [CusolverAPI cusolverDnDgesvd: Cuda solver jobu: job jobvt: job m: m n: n a: a address lda: m s: s address
			u: (u ifNil: [s] ifNotNil: [u]) address ldu: m vT: (vt ifNil: [s] ifNotNil: [vt]) address ldvt: n
			work: work address lwork: lwork rwork: rwork address info: info address]
		ifFalse: [CusolverAPI cusolverDnSgesvd: Cuda solver jobu: job jobvt: job m: m n: n a: a address lda: m s: s address
			u: (u ifNil: [s] ifNotNil: [u]) address ldu: m vT: (vt ifNil: [s] ifNotNil: [vt]) address ldvt: n
			work: work address lwork: lwork rwork: rwork address info: info address].
	CudaSolverError check: info in: (self isDouble ifTrue: ['cusolverDnDgesvd'] ifFalse: ['cusolverDnSgesvd'])]
		ifCurtailed: [s release. u ifNotNil: [u release]. vt ifNotNil: [vt release]]]
		ensure: [a release. info release. work ifNotNil: [work release]. rwork ifNotNil: [rwork release]].
	aBoolean ifFalse: [^CudaDecomposition kind: #svd parts: {#s -> s}].
	"Column-major a = Uc S Vtc; u holds Uc (read: Uc^T, n x m), vt holds Vtc (read: Vtc^T).
	Wide: a is my transpose, so I am Vtc^T S Uc^T: U is vt as read, Vt is u as read. Tall: a is me, U = Uc, Vt = Vtc."
	wide ifTrue: [^CudaDecomposition kind: #svd parts: {#u -> vt. #s -> s. #vt -> u}].
	^CudaDecomposition kind: #svd parts: {#u -> ([u transposed] ensure: [u release]). #s -> s. #vt -> ([vt transposed] ensure: [vt release])}
!
symmetricEigen
	"The eigenvalues (increasing) and eigenvectors (the columns of vectors, orthonormal) of me, symmetric (cuSOLVER syevd; my upper triangle is the one read): a CudaDecomposition (values, vectors) with me = vectors diag(values) vectors^T."
	| n a w lwork work info vectors jobz uplo |
	self checkSquare: 'symmetricEigen'.
	n := rows.
	a := self copyOnDevice.
	w := CudaArray new: n type: type.
	info := CudaArray new: 1 type: #int32.
	jobz := CusolverAPI constant: 'CUSOLVER_EIG_MODE_VECTOR'.
	uplo := CusolverAPI constant: 'CUBLAS_FILL_MODE_LOWER'.
	[lwork := self isDouble
		ifTrue: [CusolverAPI cusolverDnDsyevdBufferSize: Cuda solver jobz: jobz uplo: uplo n: n a: a address lda: n w: w address]
		ifFalse: [CusolverAPI cusolverDnSsyevdBufferSize: Cuda solver jobz: jobz uplo: uplo n: n a: a address lda: n w: w address].
	work := CudaArray new: (lwork max: 1) type: type.
	self isDouble
		ifTrue: [CusolverAPI cusolverDnDsyevd: Cuda solver jobz: jobz uplo: uplo n: n a: a address lda: n w: w address work: work address lwork: lwork info: info address]
		ifFalse: [CusolverAPI cusolverDnSsyevd: Cuda solver jobz: jobz uplo: uplo n: n a: a address lda: n w: w address work: work address lwork: lwork info: info address].
	CudaSolverError check: info in: (self isDouble ifTrue: ['cusolverDnDsyevd'] ifFalse: ['cusolverDnSsyevd']).
	"a holds the eigenvectors as columns, column-major: as rows, read; transposed for columns."
	vectors := a transposed]
		ensure: [a release. info release. work ifNotNil: [work release]].
	^CudaDecomposition kind: #eigen parts: {#values -> w. #vectors -> vectors}
! !

!CudaMatrix methodsFor: 'fourier'!
fftShape
	^{rows. cols}
!
fftResultLike: dims batch: batch type: aType
	dims size = 2 ifTrue: [^self class rows: dims first * batch cols: dims last type: aType].
	^self class rows: batch cols: (dims inject: 1 into: [:a :b | a * b]) type: aType
!
ifftReal: c
	"The real rows x c matrix whose 2-D half spectrum (fft) I am, normalized."
	^self ifftReal: {rows. c} batch: 1
!
fftRows
	"The 1-D transform of each row (cuFFT, batched): of a real matrix each row's half spectrum."
	^self fft: {cols} batch: rows
!
ifftRows
	^self ifft: {cols} batch: rows
!
ifftRealRows: c
	^self ifftReal: {c} batch: rows
! !

!CudaMatrix methodsFor: 'printing'!
shapeString
	^'[' , rows printString , 'x' , cols printString , ']'
!
printValuesOn: aStream
	"The top left corner: up to 3 rows of up to 4 values."
	aStream nextPut: $(.
	1 to: (rows min: 3) do: [:i |
		i > 1 ifTrue: [aStream space].
		self printValues: (self copyFrom: i - 1 * cols + 1 count: (cols min: 4)) more: cols > 4 on: aStream].
	rows > 3 ifTrue: [aStream nextPutAll: ' ...'].
	aStream nextPut: $)
! !
