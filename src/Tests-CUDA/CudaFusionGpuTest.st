TestCase subclass: #CudaFusionGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaFusionGpuTest comment: 'Tests element-wise expressions on CudaArrays on the GPU (CudaExpression): their values against Smalltalk''s, one launch an expression with its kernel kept per shape, broadcasting, masks and where:else:, the reductions, values computed when asked for (and before an operand changes or goes), one kernel an operation when not fusing and cuBLAS where there is no kernel; and the caches: cuFFT plans kept per shape (bounded, released by Cuda releaseCaches), one work area for cuSOLVER. Needs a GPU and NVRTC: make test-nv runs it. Each test releases what it allocates.'!

!CudaFusionGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!CudaFusionGpuTest methodsFor: 'running'!
setUp
	Cuda isAvailable ifFalse: [^self error: 'no CUDA here (libcudart from the CUDA toolkit, and a GPU): CudaFusionGpuTest needs them'].
	NvRtc isAvailable ifFalse: [^self error: 'no NVRTC here (the CUDA toolkit''s libnvrtc): CudaFusionGpuTest needs it']
! !

!CudaFusionGpuTest methodsFor: 'helpers'!
assert: values closeTo: expected
	self assert: values size equals: expected size.
	values with: expected do: [:v :e | self assert: (v - e) abs <= (1.0e-5 * (e abs max: 1.0)) description: v printString , ' is not ' , e printString]
!
with: arrays do: aBlock
	[aBlock valueWithArguments: arrays] ensure: [arrays do: [:each | each release]]
! !

!CudaFusionGpuTest methodsFor: 'tests'!
testChainIsOneKernel
	| xs ys a b c l0 kernels |
	xs := (1 to: 1000) collect: [:i | i / 1000.0].
	ys := (1 to: 1000) collect: [:i | (i \\ 7) / 7.0].
	a := CudaArray withAll: xs type: #float32.
	b := CudaArray withAll: ys type: #float32.
	self with: {a. b} do: [:x :y |
		c := ((x * 2 + y) sqrt - 1) max: 0.25.
		self assert: c isPending.
		self assert: c type equals: #float32.
		l0 := CudaExpression launches.
		self assert: c asArray closeTo: (xs with: ys collect: [:u :v | ((u * 2 + v) sqrt - 1) max: 0.25]).
		self assert: CudaExpression launches - l0 equals: 1.
		self deny: c isPending.
		c release.
		kernels := Cuda default fusedKernelCount.
		c := ((x * 3 + y) sqrt - 2) max: 0.5.
		self assert: c asArray closeTo: (xs with: ys collect: [:u :v | ((u * 3 + v) sqrt - 2) max: 0.5]).
		self assert: Cuda default fusedKernelCount equals: kernels.
		c release]
!
testUnaryOperationsAndTypes
	| xs a b |
	xs := (1 to: 64) collect: [:i | i / 10.0].
	a := CudaArray withAll: xs type: #float64.
	b := CudaArray withAll: xs type: #float32.
	self with: {a. b} do: [:x :y | | r |
		#(#negated #abs #sqrt #squared #reciprocal #exp #ln #log #sin #cos) do: [:op |
			r := x perform: op.
			self assert: r asArray closeTo: (xs collect: [:v | v perform: op]).
			r release].
		r := x tanh.
		self assert: r asArray closeTo: (xs collect: [:v | ((2 * v) exp - 1) / ((2 * v) exp + 1)]).
		r release.
		r := x + y.
		self assert: r type equals: #float64.
		self assert: r asArray closeTo: (xs collect: [:v | v * 2]).
		r release.
		r := (y raisedTo: 2) - (y / 2) + (2 * y) - (1 - y).
		self assert: r asArray closeTo: (xs collect: [:v | v * v - (v / 2) + (2 * v) - (1 - v)]).
		r release]
!
testMasksAndWhere
	| xs a r |
	xs := #(-2 -1 0 1 2).
	a := CudaArray withAll: xs type: #float32.
	self with: {a} do: [:x |
		self assert: (x > 0) asArray equals: #(0.0 0.0 0.0 1.0 1.0).
		self assert: (x <= 0) asArray equals: #(1.0 1.0 1.0 0.0 0.0).
		self assert: (x eq: 1) asArray equals: #(0.0 0.0 0.0 1.0 0.0).
		self assert: (x ne: 1) asArray equals: #(1.0 1.0 1.0 0.0 1.0).
		self assert: (x >= x) asArray equals: #(1.0 1.0 1.0 1.0 1.0).
		r := (x < 0) where: x negated else: x * 10.
		self assert: r asArray equals: #(2.0 1.0 0.0 10.0 20.0).
		self assert: ((x > 0) where: 1 else: -1) sum equals: -1.0.
		r release]
!
testBroadcasting
	| m row col r |
	m := CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6).
	row := CudaArray withAll: #(10 20 30).
	col := CudaMatrix rows: 2 cols: 1 values: #(100 200).
	self with: {m. row. col} do: [:a :b :c |
		r := a + b mul: c.
		self assert: (r isKindOf: CudaMatrix).
		self assert: r asRows equals: #(#(1100.0 2200.0 3300.0) #(2800.0 5000.0 7200.0)).
		r release.
		r := (a mul: a) - (a * 2).
		self assert: r asRows equals: #(#(-1.0 0.0 3.0) #(8.0 15.0 24.0)).
		r release.
		self should: [a + (CudaArray withAll: #(1 2))] raise: Error]
!
testReductions
	| xs a |
	xs := (1 to: 100000) collect: [:i | ((i * 7919) \\ 1009) / 1009.0 - 0.5].
	a := CudaArray withAll: xs type: #float32.
	self with: {a} do: [:x | | l0 sum vs |
		vs := x asArray.
		sum := vs inject: 0.0 into: [:s :v | s + (v * 2) abs].
		l0 := CudaExpression launches.
		self assert: ((x * 2) abs sum - sum) abs < (1.0e-9 * sum).
		self assert: CudaExpression launches - l0 equals: 1.
		self assert: ((x * 2) abs mean - (sum / vs size)) abs < 1.0e-9.
		self assert: x max equals: (vs inject: -1 into: [:m :v | m max: v]).
		self assert: x min equals: (vs inject: 1 into: [:m :v | m min: v]).
		self assert: (x > 0) sum equals: (xs select: [:v | v > 0]) size asFloat]
!
testPendingUntilNeeded
	"Printing, copying to the host or a cuBLAS product compute a pending array; so does changing or releasing one of its operands, first."
	| a b c d p |
	a := CudaArray withAll: #(1 2 3) type: #float32.
	b := CudaMatrix rows: 2 cols: 2 values: #(1 2 3 4).
	self with: {a. b} do: [:x :m |
		c := x * 2.
		x fromArray: #(10 20 30).
		self deny: c isPending.
		self assert: c asArray equals: #(2.0 4.0 6.0).
		d := x + 1.
		self assert: d isPending.
		self assert: d printString equals: 'a CudaArray float32[3] (12 bytes) (11.0000 21.0000 31.0000)'.
		p := (m * 2) * m.
		self assert: p asRows equals: #(#(14.0 20.0) #(30.0 44.0)).
		p release.
		c release.
		c := x - 5.
		x release.
		self deny: c isPending.
		self assert: c asArray equals: #(5.0 15.0 25.0).
		c release. d release.
		self should: [x * 2] raise: Error]
!
testStoreIntoInPlace
	| a |
	a := CudaArray withAll: #(1 2 3) type: #float64.
	self with: {a} do: [:x | | c |
		c := x * 2 + 1.
		self assert: (c storeInto: x) == x.
		self deny: c isAlive.
		self assert: x asArray equals: #(3.0 5.0 7.0).
		self should: [(x * 2) storeInto: (CudaArray new: 3 type: #float32)] raise: Error]
!
testOneKernelAnOperationWithoutFusion
	| a l0 c |
	a := CudaArray withAll: #(1 4 9) type: #float32.
	self with: {a} do: [:x |
		CudaExpression fusing: false during: [
			l0 := CudaExpression launches.
			c := (x sqrt * 2 + 1) negated.
			self deny: c isPending.
			self assert: CudaExpression launches - l0 equals: 4].
		self assert: c asArray equals: #(-3.0 -5.0 -7.0).
		c release]
!
testCublasWithoutAKernel
	| a b t e |
	a := CudaArray withAll: #(1 2 3) type: #float32.
	b := CudaArray withAll: #(10 20 30) type: #float32.
	t := CudaArray new: 3 type: #float32.
	self with: {a. b. t} do: [:x :y :out |
		e := CudaExpression op: #- args: {CudaExpression array: y. CudaExpression array: x}.
		e evaluateWithCublasInto: out.
		self assert: out asArray equals: #(9.0 18.0 27.0).
		e := CudaExpression op: #/ args: {CudaExpression array: y. CudaExpression scalar: 10}.
		e evaluateWithCublasInto: out.
		self assert: out asArray equals: #(1.0 2.0 3.0).
		e := CudaExpression op: #sqrt args: {CudaExpression array: y}.
		self should: [e evaluateWithCublasInto: out] raise: Error]
!
testComplexStillAdds
	| a b c |
	a := CudaArray withAll: {Complex real: 1 imaginary: 2} type: #complex64.
	b := CudaArray withAll: {Complex real: 3 imaginary: 4} type: #complex64.
	self with: {a. b} do: [:x :y |
		c := x + y.
		self deny: c isPending.
		self assert: c asArray first real equals: 4.0.
		c release.
		self should: [x * 2] raise: Error]
!
testFftPlansKept
	| a b f plans |
	Cuda releaseCaches.
	a := CudaMatrix uniformRows: 64 cols: 64.
	b := CudaMatrix uniformRows: 32 cols: 64.
	self with: {a. b} do: [:x :y |
		x fft release.
		plans := Cuda default fftPlans copy.
		self assert: plans size equals: 1.
		f := x fft.
		self assert: Cuda default fftPlans first == plans first.
		f release.
		y fft release.
		self assert: Cuda default fftPlans size equals: 2.
		self assert: Cuda default fftPlans last == plans first.
		1 to: Cuda fftPlanLimit + 2 do: [:n | | z | z := CudaArray uniform: n * 2 type: #float32. [z fft release] ensure: [z release]].
		self assert: Cuda default fftPlans size equals: Cuda fftPlanLimit.
		self deny: plans first isAlive.
		plans := Cuda default fftPlans copy.
		Cuda releaseCaches.
		self assert: Cuda default fftPlans isEmpty.
		self assert: (plans allSatisfy: [:p | p isAlive not]).
		f := x fft.
		self assert: ((f ifftReal: 64) - x) abs max < 1.0e-4.
		f release]
!
testSolverWorkspaceKept
	| a w lu |
	a := (CudaMatrix uniformRows: 64 cols: 64 type: #float64) add: (CudaMatrix identity: 64 type: #float64) times: 8.
	self with: {a} do: [:m | | d0 |
		d0 := m determinant.
		lu := m lu. lu release.
		w := Cuda workspace: 16.
		self assert: (Cuda workspace: 16) == w.
		lu := m lu.
		self assert: (Cuda workspace: 16) == w.
		self assert: (lu determinant - d0) abs < (1.0e-9 * d0 abs).
		lu release.
		Cuda releaseCaches.
		self deny: w isAlive]
! !
