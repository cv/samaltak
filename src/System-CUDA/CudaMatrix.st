CudaArray subclass: #CudaMatrix
	instanceVariableNames: 'rows cols'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaMatrix comment: 'I am a rows x cols matrix of Floats in the CUDA device''s memory, stored row-major as Smalltalk reads a matrix (element i, j at (i - 1) * cols + j), of type #float32 or #float64. a * b multiplies on the device with cuBLAS (Sgemm or Dgemm) into a new matrix; multiply:into: reuses one. cuBLAS is column-major, where a row-major matrix reads as its transpose, so C = A B is computed as the column-major C^T = B^T A^T: the same gemm with the operands swapped, no transposes or copies (docs/cuda.md).

	| a b | a := CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6). b := CudaMatrix rows: 3 cols: 2 values: #(1 0 0 1 1 1).
	(a * b) asRows      "#(#(4.0 5.0) #(10.0 11.0))"
	(CudaMatrix uniformRows: 4096 cols: 4096) * (CudaMatrix uniformRows: 4096 cols: 4096)'!

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
uniformRows: r cols: c type: aSymbol
	^(self rows: r cols: c type: aSymbol) fillUniform
!
uniformRows: r cols: c
	^self uniformRows: r cols: c type: #float32
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
	(rows = 0 or: [b cols = 0]) ifTrue: [^c].
	type == #float32
		ifTrue: [CublasAPI cublasSgemm: Cuda blas transa: 0 transb: 0 m: b cols n: rows k: cols
			alpha: 1.0 a: b address lda: (b cols max: 1) b: self address ldb: (cols max: 1) beta: 0.0 c: c address ldc: (c cols max: 1)]
		ifFalse: [CublasAPI cublasDgemm: Cuda blas transa: 0 transb: 0 m: b cols n: rows k: cols
			alpha: 1.0 a: b address lda: (b cols max: 1) b: self address ldb: (cols max: 1) beta: 0.0 c: c address ldc: (c cols max: 1)].
	^c
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
