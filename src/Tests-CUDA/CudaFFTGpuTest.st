TestCase subclass: #CudaFFTGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaFFTGpuTest comment: 'Tests cuFFT through CudaArray and CudaMatrix on the GPU against discrete Fourier transforms summed in Smalltalk: 1-D and 2-D, complex and real (half spectra), batched rows, float32 and float64, the inverses, complex arrays'' printString, and that the VM refuses a plan run on arrays too short or of the other kind. Needs a GPU and the CUDA toolkit''s libraries: make test-nv runs it. Each test releases what it allocates.'!

!CudaFFTGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!CudaFFTGpuTest class methodsFor: 'references'!
dft: values
	"The unnormalized forward DFT of a sequence of Complex (or real) numbers, summed in Smalltalk."
	| n |
	n := values size.
	^(0 to: n - 1) collect: [:k | | re im |
		re := 0.0. im := 0.0.
		values doWithIndex: [:v :j | | angle x y |
			angle := -2.0 * Float pi * k * (j - 1) / n.
			x := v isNumber ifTrue: [v asFloat] ifFalse: [v real].
			y := v isNumber ifTrue: [0.0] ifFalse: [v imaginary].
			re := re + (x * angle cos) - (y * angle sin).
			im := im + (x * angle sin) + (y * angle cos)].
		Complex real: re imaginary: im]
!
dft2: rows
	"The 2-D DFT: of each row, then of each column."
	| r cols |
	r := rows collect: [:row | self dft: row].
	cols := (1 to: r first size) collect: [:j | self dft: (r collect: [:row | row at: j])].
	^(1 to: r size) collect: [:i | cols collect: [:col | col at: i]]
! !

!CudaFFTGpuTest methodsFor: 'running'!
setUp
	Cuda isAvailable ifFalse: [^self error: 'no CUDA here (libcudart from the CUDA toolkit, and a GPU): CudaFFTGpuTest needs them'].
	CufftAPI isAvailable ifFalse: [^self error: 'no cuFFT here (libcufft from the CUDA toolkit)']
! !

!CudaFFTGpuTest methodsFor: 'helpers'!
tolerance: type
	^(CudaArray realTypeOf: type) == #float64 ifTrue: [1.0e-10] ifFalse: [1.0e-4]
!
flat: a
	^(a notEmpty and: [a first isKindOf: Array]) ifTrue: [a inject: #() into: [:all :row | all , row]] ifFalse: [a]
!
assert: a closeTo: b tolerance: eps
	"Complex or real numbers (or rows of them), relative to the largest magnitude."
	| x y scale |
	x := self flat: a. y := self flat: b.
	self assert: x size equals: y size.
	scale := y inject: 1.0 into: [:m :v | m max: v abs].
	x with: y do: [:u :v | | d |
		d := (u isNumber and: [v isNumber])
			ifTrue: [(u - v) abs]
			ifFalse: [((u isNumber ifTrue: [Complex real: u imaginary: 0.0] ifFalse: [u]) - (v isNumber ifTrue: [Complex real: v imaginary: 0.0] ifFalse: [v])) abs].
		self assert: d <= (eps * scale) description: u printString , ' is not ' , v printString]
!
random: n type: type
	| a |
	a := CudaArray uniform: n type: type.
	^[a asArray collect: [:v | v isNumber ifTrue: [v - 0.5] ifFalse: [Complex real: v real - 0.5 imaginary: v imaginary - 0.5]]] ensure: [a release]
! !

!CudaFFTGpuTest methodsFor: 'tests'!
testComplex1D
	#(#complex64 #complex128) do: [:type | | values a f back eps |
		eps := self tolerance: type.
		values := self random: 12 type: type.
		a := CudaArray withAll: values type: type.
		[f := a fft.
		self assert: f type equals: type.
		self assert: f asArray closeTo: (self class dft: values) tolerance: eps.
		back := f ifft.
		self assert: back asArray closeTo: values tolerance: eps.
		f release. back release]
			ensure: [a release]]
!
testReal1D
	#(#float32 #float64) do: [:type | | values a f back eps |
		eps := self tolerance: type.
		values := self random: 10 type: type.
		a := CudaArray withAll: values type: type.
		[f := a fft.
		self assert: f size equals: 6.
		self assert: f type equals: (CudaArray complexTypeOf: type).
		self assert: f asArray closeTo: ((self class dft: values) first: 6) tolerance: eps.
		back := f ifftReal: 10.
		self assert: back type equals: type.
		self assert: back asArray closeTo: values tolerance: eps.
		f release. back release]
			ensure: [a release]]
!
testReal2D
	#(#float32 #float64) do: [:type | | rows a f back ref eps |
		eps := self tolerance: type.
		rows := (1 to: 6) collect: [:i | self random: 8 type: type].
		a := CudaMatrix fromRows: rows type: type.
		[f := a fft.
		self assert: f rows equals: 6.
		self assert: f cols equals: 5.
		ref := (self class dft2: rows) collect: [:row | row first: 5].
		self assert: f asRows closeTo: ref tolerance: eps.
		back := f ifftReal: 8.
		self assert: back asRows closeTo: rows tolerance: eps.
		f release. back release]
			ensure: [a release]]
!
testComplex2D
	#(#complex64 #complex128) do: [:type | | rows a f back eps |
		eps := self tolerance: type.
		rows := (1 to: 5) collect: [:i | self random: 6 type: type].
		a := CudaMatrix fromRows: rows type: type.
		[f := a fft.
		self assert: f asRows closeTo: (self class dft2: rows) tolerance: eps.
		back := f ifft.
		self assert: back asRows closeTo: rows tolerance: eps.
		f release. back release]
			ensure: [a release]]
!
testBatchedRows
	#(#float32 #complex128) do: [:type | | rows a f back eps half |
		eps := self tolerance: type.
		rows := (1 to: 4) collect: [:i | self random: 16 type: type].
		a := CudaMatrix fromRows: rows type: type.
		half := (CudaArray isComplex: type) ifTrue: [16] ifFalse: [9].
		[f := a fftRows.
		self assert: f rows equals: 4.
		self assert: f cols equals: half.
		self assert: f asRows closeTo: (rows collect: [:row | (self class dft: row) first: half]) tolerance: eps.
		back := (CudaArray isComplex: type) ifTrue: [f ifftRows] ifFalse: [f ifftRealRows: 16].
		self assert: back asRows closeTo: rows tolerance: eps.
		f release. back release]
			ensure: [a release]]
!
testComplexValuesAndPrinting
	| a re |
	a := CudaArray withAll: {Complex real: 1.5 imaginary: -2.0. 3. Complex real: 0.0 imaginary: 0.25} type: #complex64.
	[self assert: a asArray equals: {Complex real: 1.5 imaginary: -2.0. Complex real: 3.0 imaginary: 0.0. Complex real: 0.0 imaginary: 0.25}.
	self assert: a printString equals: 'a CudaArray complex64[3] (24 bytes) (1.5000-2.0000i 3.0000+0.0000i 0.0000+0.2500i)'.
	re := a real.
	self assert: re asArray equals: #(1.5 3.0 0.0).
	re release.
	re := a imaginary.
	self assert: re asArray equals: #(-2.0 0.0 0.25).
	re release.
	self assert: (a norm - (1.5 squared + 4 + 9 + 0.0625) sqrt) abs < 1.0e-5]
		ensure: [a release]
!
testPlanChecks
	"A plan runs only on arrays as long as its transform and of its kind: CudaFFTPlan checks, and the VM checks the raw calls (the plan's type and sizes are its handle's tag)."
	| plan small real complex e |
	plan := CudaFFTPlan shape: #(64) kind: #r2c type: #float32 batch: 2.
	real := CudaArray new: 128 type: #float32.
	complex := CudaArray new: 66 type: #complex64.
	small := CudaArray new: 65 type: #complex64.
	[self assert: plan realCount equals: 128.
	self assert: plan halfCount equals: 66.
	real zero.
	plan forward: real into: complex.
	self should: [plan forward: real into: small] raise: Error.
	e := [CufftAPI cufftExecR2C: plan handle idata: real address odata: small address. nil] on: CudaArgumentError do: [:x | x].
	self assert: e notNil.
	self assert: e code equals: -4.
	e := [CufftAPI cufftExecC2C: plan handle idata: complex address odata: complex address direction: -1. nil] on: CudaArgumentError do: [:x | x].
	self assert: e notNil.
	e := [CufftAPI cufftExecR2C: plan handle idata: real address + 8 odata: complex address. nil] on: CudaArgumentError do: [:x | x].
	self assert: e notNil]
		ensure: [plan release. real release. complex release. small release].
	self should: [CudaFFTPlan shape: #(0) kind: #c2c type: #float32 batch: 1] raise: CudaError
! !
