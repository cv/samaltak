TestCase subclass: #CudaShowcaseModelTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaShowcaseModelTest comment: 'Tests the models behind the GPU demos without a GPU: CuOptProgram''s reading of a program''s text, CuOptRouting''s mixed-integer program and how it reads routes from a solution, CudaSpectrum''s Smalltalk FFT against the definition and its masks, CudaComparison''s formats, and CudaTrace recording host operations and counting calls. CudaShowcaseGpuTest runs them on the GPU.'!

!CudaShowcaseModelTest methodsFor: 'running'!
tearDown
	CudaTrace stop; reset
! !

!CudaShowcaseModelTest methodsFor: 'tests'!
testProgramText
	| p |
	p := CuOptProgram fromText: '# a comment
maximize 3x + 5 y
wood: x <= 4
2*y <= 12   # labor
3 x + 2 y - 1 <= 17
integer y'.
	self assert: p sense equals: #maximize.
	self assert: p variables equals: #('x' 'y').
	self assert: p objective equals: #(3 5).
	self assert: p rows size equals: 3.
	self assert: (p rows at: 2) equals: #(0 2).
	self assert: (p rows at: 3) equals: #(3 2).
	self assert: p rhs equals: #(4 12 18).
	self assert: p senses equals: 'LLL'.
	self assert: p rowNames equals: #('wood' 'c2' 'c3').
	self assert: (p isInteger: 'y').
	self deny: (p isInteger: 'x').
	self assert: p summary equals: 'MILP 2 variables x 3 constraints'
!
testProgramSensesAndSides
	| p |
	p := CuOptProgram fromText: 'minimize a - b
a + b >= 2
4 = a - 2 b
3 a <= b + 9
binary b'.
	self assert: p senses equals: 'GEL'.
	self assert: (p rows at: 2) equals: #(-1 2).
	self assert: p rhs equals: #(2 -4 9).
	self assert: (p rows at: 3) equals: #(3 -1).
	self assert: (p isInteger: 'b')
!
testProgramErrorsSayTheLine
	| e |
	e := [CuOptProgram fromText: 'maximize x
x <= 1
x + 4'. nil] on: CuOptSyntaxError do: [:err | err].
	self assert: e line equals: 3.
	self assert: ('line 3:*' match: e messageText).
	e := [CuOptProgram fromText: 'x <= 1'. nil] on: CuOptSyntaxError do: [:err | err].
	self assert: e line equals: 1.
	self assert: (CuOptProgram examples allSatisfy: [:each | (CuOptProgram fromText: each value) variables notEmpty])
!
testRoutingProgramShape
	| r p n |
	r := CuOptRouting example.
	n := r stops size.
	p := r program.
	self assert: (p at: 1) size equals: n + 1 * n + n.
	self assert: (p at: 2) size equals: 2 * n + 3 + (n * (n - 1)).
	self assert: (p at: 3) size equals: (p at: 2) size.
	self assert: ((p at: 7) occurrencesOf: $I) equals: n + 1 * n.
	self assert: r capacity equals: n // 2 + 1.
	"every leg's cost is its length"
	self assert: ((p at: 1) at: 1) equals: (r distanceFrom: 0 to: 1)
!
testRoutesFromASolution
	"Two tours, 0-1-2-0 and 0-3-0, read back in order."
	| r values legs |
	r := CuOptRouting new.
	r addStop: 0.1 @ 0.1; addStop: 0.2 @ 0.1; addStop: 0.9 @ 0.9.
	legs := r legs.
	values := legs collect: [:leg | (#(#(0 1) #(1 2) #(2 0) #(0 3) #(3 0)) includes: {leg key. leg value}) ifTrue: [1.0] ifFalse: [0.0]].
	self assert: (r routesFrom: values) equals: #(#(1 2) #(3)).
	r instVarNamed: 'routes' put: (r routesFrom: values).
	self assert: r visitsEveryStop.
	self assert: (r totalDistance - ((r distanceOf: #(1 2)) + (r distanceOf: #(3)))) abs < 1.0e-12
!
testSmalltalkFFTMatchesTheDefinition
	| n v f worst |
	n := 8.
	v := (1 to: n * n) collect: [:i | (i * 37 \\ 11) / 11.0].
	f := CudaSpectrum fft2D: v size: n.
	worst := 0.
	0 to: n - 1 do: [:u | 0 to: n - 1 do: [:w | | re im |
		re := 0. im := 0.
		0 to: n - 1 do: [:y | 0 to: n - 1 do: [:x | | a |
			a := -2 * Float pi * ((u * y) + (w * x)) / n.
			re := re + ((v at: y * n + x + 1) * a cos).
			im := im + ((v at: y * n + x + 1) * a sin)]].
		worst := worst max: ((f first at: u * n + w + 1) - re) abs.
		worst := worst max: ((f last at: u * n + w + 1) - im) abs]].
	self assert: worst < 1.0e-9
!
testSpectrumMasks
	| s |
	s := CudaSpectrum basicNew instVarNamed: 'n' put: 16; yourself.
	self assert: (s frequencyOf: 1) equals: 0.
	self assert: (s frequencyOf: 2) equals: 1.
	self assert: (s frequencyOf: 16) equals: 1.
	self assert: (s shifted: 1) equals: 8 * 16 + 8 + 1.
	self assert: ((s lowPass: 3) occurrencesOf: 1.0) equals: 29.
	self assert: ((s lowPass: 3) with: (s highPass: 3) collect: [:a :b | a + b]) asSet asArray equals: #(1.0)
!
testComparisonFormats
	self assert: (CudaComparison milliseconds: 0.1372) equals: '0.137 ms'.
	self assert: (CudaComparison milliseconds: 12.34) equals: '12.3 ms'.
	self assert: (CudaComparison milliseconds: 2950) equals: '2.95 s'.
	self assert: (CudaComparison milliseconds: 186000) equals: '3.1 min'.
	self assert: (CudaComparison rate: 1.57e13 unit: 'FLOPS') equals: '15.7 TFLOPS'.
	self assert: (CudaComparison rate: 4.8e10 unit: ' numbers/s') equals: '48.0 G numbers/s'.
	self assert: (CudaComparison format: 2.3e-6) equals: '2.3e-6'
!
testSolveJobsAreChecked
	"A job the VM did not start is refused (or the export is missing)."
	| r |
	r := [CuOpt ffiSolvePoll: 5 outs: (ByteArray new: 16)] on: Error do: [:e | e return: false].
	CudaLibraryAPI session = 0 ifTrue: [^self assert: r == false].
	self assert: r equals: -7.
	r := CuOpt ffiSolvePoll: 99 outs: (ByteArray new: 16).
	self assert: r equals: -7.
	r := CuOpt ffiSolvePoll: 1 outs: (ByteArray new: 8).
	self assert: r equals: -5
!
testTraceRecordsWhileOn
	| t e |
	CudaTrace reset.
	CudaTrace hostOperation: 'off' detail: [self error: 'not evaluated while off'] during: [3].
	self assert: CudaTrace default entries isEmpty.
	CudaTrace start.
	self assert: (CudaTrace hostOperation: 'cuOptSolve' detail: ['LP 2 x 3'] during: [(Delay forMilliseconds: 2) wait. 42]) equals: 42.
	CudaTrace call: 'cudaMalloc'; call: 'cudaMalloc'; call: 'cudaFree'.
	CudaTrace quietly: [CudaTrace call: 'cudaFree'. CudaTrace hostOperation: 'quiet' detail: [''] during: [nil]].
	t := CudaTrace default.
	self assert: t entries size equals: 1.
	e := t entries first.
	self assert: e name equals: 'cuOptSolve'.
	self assert: e detail equals: 'LP 2 x 3'.
	self assert: e hostMicros >= 1000.
	self assert: e deviceMilliseconds isNil.
	self assert: (t calls at: 'cudaMalloc') equals: 2.
	self assert: (t calls at: 'cudaFree') equals: 1.
	self assert: t callsByCount first first equals: 'cudaMalloc'.
	self assert: t callCount equals: 3
! !
