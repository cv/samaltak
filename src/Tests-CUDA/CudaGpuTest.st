TestCase subclass: #CudaGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaGpuTest comment: 'Tests System-CUDA on the GPU through NVIDIA''s CUDA libraries (libcudart, cuBLAS, cuRAND; cuOpt where SAMALTAK_CUDA_LIBS finds it): device memory, copies, gemm against a Smalltalk product, the VM''s checks of device extents and host buffers, error names, events. Needs a GPU and the CUDA toolkit''s libraries, so it does not run by default (runsByDefault): make test-nv runs it. Each test releases what it allocates.'!

!CudaGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!CudaGpuTest methodsFor: 'running'!
setUp
	Cuda isAvailable ifFalse: [^self error: 'no CUDA here (libcudart from the CUDA toolkit, and a GPU): CudaGpuTest needs them']
! !

!CudaGpuTest methodsFor: 'tests'!
testSummary
	| s |
	s := Cuda summary.
	self assert: ('*compute*CUDA runtime*' match: s)
!
testRoundTrip
	| a b |
	a := CudaArray withAll: #(1.5 -2.25 3.0 0.0) type: #float32.
	b := CudaArray withAll: #(1.0e300 -7.0 3.141592653589793) type: #float64.
	[self assert: a asArray equals: #(1.5 -2.25 3.0 0.0).
	self assert: b asArray equals: #(1.0e300 -7.0 3.141592653589793).
	self assert: (a at: 2) equals: -2.25.
	self assert: (b copyFrom: 2 count: 2) equals: #(-7.0 3.141592653589793)]
		ensure: [a release. b release]
!
testSmallGemm
	#(#float32 #float64) do: [:type | | a b c |
		a := CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6) type: type.
		b := CudaMatrix rows: 3 cols: 2 values: #(1 0 0 1 1 1) type: type.
		c := a * b.
		[self assert: c rows equals: 2.
		self assert: c cols equals: 2.
		self assert: c asRows equals: #(#(4.0 5.0) #(10.0 11.0))]
			ensure: [a release. b release. c release]]
!
testRandomGemmMatchesSmalltalk
	"A 33 x 17 times 17 x 29 product of random matrices against the naive Smalltalk loop."
	#(#float32 #float64) do: [:type | | a b c x y z worst |
		a := CudaMatrix uniformRows: 33 cols: 17 type: type.
		b := CudaMatrix uniformRows: 17 cols: 29 type: type.
		c := a * b.
		[x := a asArray. y := b asArray. z := c asArray.
		worst := 0.
		1 to: 33 do: [:i | 1 to: 29 do: [:j | | sum |
			sum := 0.0.
			1 to: 17 do: [:k | sum := sum + ((x at: i - 1 * 17 + k) * (y at: k - 1 * 29 + j))].
			worst := worst max: (sum - (z at: i - 1 * 29 + j)) abs]].
		self assert: worst < (type == #float32 ifTrue: [1.0e-4] ifFalse: [1.0e-12])]
			ensure: [a release. b release. c release]]
!
testShapesMustFit
	| a b |
	a := CudaMatrix rows: 2 cols: 3.
	b := CudaMatrix rows: 2 cols: 2.
	[self should: [a * b] raise: Error] ensure: [a release. b release]
!
testExtentPastAllocationRefused
	"A gemm whose operands would reach past their allocations never reaches cuBLAS."
	| a e |
	a := CudaArray new: 16.
	[e := [CublasAPI cublasSgemm: Cuda blas transa: 0 transb: 0 m: 8 n: 8 k: 8 alpha: 1.0 a: a address lda: 8 b: a address ldb: 8 beta: 0.0 c: a address ldc: 8. nil]
		on: CudaArgumentError do: [:err | err].
	self assert: e notNil.
	self assert: e code equals: -4.
	e := [CublasAPI cublasSgemm: Cuda blas transa: 0 transb: 0 m: 4 n: 4 k: 1 alpha: 1.0 a: a address lda: 2 b: a address ldb: 1 beta: 0.0 c: a address ldc: 4. nil]
		on: CudaArgumentError do: [:err | err].
	self assert: e notNil]
		ensure: [a release]
!
testShortHostBufferRefused
	| a e |
	a := CudaArray new: 4.
	[e := [CudaRuntimeAPI cudaMemcpyDtoH: (ByteArray new: 4) src: a address count: 16. nil] on: CudaArgumentError do: [:err | err].
	self assert: e code equals: -5]
		ensure: [a release]
!
testLibraryErrorNames
	| e |
	e := [CudaRuntimeAPI cudaMalloc: (1 bitShift: 52). nil] on: CudaError do: [:err | err].
	self assert: e notNil.
	self assert: e statusName equals: 'cudaErrorMemoryAllocation'.
	self assert: ('cudaMalloc: cudaErrorMemoryAllocation (*' match: e messageText)
!
testReleaseFreesMemory
	| before a |
	before := CudaLibraryAPI liveAllocations.
	a := CudaArray new: 1000.
	self assert: CudaLibraryAPI liveAllocations equals: before + 1.
	self assert: a isAlive.
	a release.
	a release.
	self deny: a isAlive.
	self assert: CudaLibraryAPI liveAllocations equals: before.
	self assert: ('*released*' match: a printString).
	self should: [a asArray] raise: Error
!
testPrintString
	| a m |
	a := CudaArray withAll: #(1.5 2 3) type: #float32.
	m := CudaMatrix rows: 2 cols: 2 values: #(1 2 3 4) type: #float64.
	[self assert: ('a CudaArray float32[3] (12 bytes) (1.5000 2.0000 3.0000)' = a printString).
	self assert: ('a CudaMatrix float64[2x2] (32 bytes) ((1.0000 2.0000) (3.0000 4.0000))' = m printString)]
		ensure: [a release. m release]
!
testUniformNormAndDifference
	| a b d |
	a := CudaArray uniform: 1000 type: #float32.
	[self assert: (a asArray allSatisfy: [:v | v > 0 and: [v <= 1]]).
	b := a copyOnDevice.
	d := a - b.
	self assert: d norm equals: 0.0.
	self assert: ((a + b) norm - (2 * a norm)) abs < 1.0e-3]
		ensure: [a release. b ifNotNil: [b release]. d ifNotNil: [d release]]
!
testEventTiming
	| a b c start stop ms |
	a := CudaMatrix uniformRows: 256 cols: 256.
	b := CudaMatrix uniformRows: 256 cols: 256.
	c := CudaMatrix rows: 256 cols: 256.
	[start := CudaEvent new record.
	a multiply: b into: c.
	stop := CudaEvent new record wait.
	ms := stop millisecondsSince: start.
	self assert: ms >= 0.
	self assert: ms < 10000]
		ensure: [a release. b release. c release. start ifNotNil: [start release]. stop ifNotNil: [stop release]]
!
testLinearProgram
	| r |
	CuOpt isAvailable ifFalse: [^self skip: 'no cuOpt here (SAMALTAK_CUDA_LIBS: the libcuopt wheel''s lib64)'].
	r := CuOpt maximize: #(3 5) subjectTo: #(#(1 0) #(0 2) #(3 2)) atMost: #(4 12 18).
	self assert: r isOptimal.
	self assert: (r objective - 36) abs < 1.0e-6.
	self assert: ((r values first - 2) abs < 1.0e-6 and: [(r values last - 6) abs < 1.0e-6])
! !
