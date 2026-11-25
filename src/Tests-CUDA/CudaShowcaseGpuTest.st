TestCase subclass: #CudaShowcaseGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaShowcaseGpuTest comment: 'Tests what the GPU demos compute, on the GPU: CudaComparison''s timings and checks, CudaTrace''s device times and the allocation table, CudaSpectrum''s transform against the Smalltalk FFT and back, and (where cuOpt is installed) CuOptRouting and CuOptProgram solved. Needs a GPU, so it does not run by default (runsByDefault): make test-nv runs it. Each test releases what it allocates.'!

!CudaShowcaseGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!CudaShowcaseGpuTest methodsFor: 'running'!
setUp
	Cuda isAvailable ifFalse: [^self error: 'no CUDA device here']
!
tearDown
	CudaTrace stop; reset
! !

!CudaShowcaseGpuTest methodsFor: 'tests'!
testComparison
	| c |
	c := CudaComparison sgemm: 256.
	self assert: c gpuMilliseconds > 0.
	self assert: c cpuMilliseconds > c gpuMilliseconds.
	self assert: c speedup > 1.
	self assert: ('SGEMM 256x256: GPU * faster · corner within *' match: c printString).
	self assert: ((c check copyFrom: 15 to: c check size - 9) asNumber) < 1.0e-4.
	c := CudaComparison uniform: 100000.
	self assert: c cpuNote equals: 'Random'.
	c := CudaComparison solve: 64.
	self assert: ('cuSOLVER solve 64x64: GPU * residual *' match: c printString).
	c := CudaComparison fft2d: 64.
	self assert: ('cuFFT 2-D 64x64: GPU * of the DC term' match: c printString)
!
testAllocationTableAndTrace
	| a b c before entry |
	before := CudaLibraryAPI allocations size.
	CudaTrace start.
	a := CudaMatrix uniformRows: 64 cols: 64.
	b := CudaMatrix uniformRows: 64 cols: 64.
	[c := a * b.
	self assert: CudaLibraryAPI allocations size equals: before + 3.
	self assert: (CudaLibraryAPI allocations includes: c address -> (64 * 64 * 4)).
	self assert: (CudaArray liveArrays includes: c).
	Cuda synchronize.
	entry := CudaTrace default entries detect: [:e | e name = 'cublasSgemm'] ifNone: [nil].
	self assert: entry notNil.
	self assert: entry detail equals: '[64x64] * [64x64] float32'.
	self assert: (self waitFor: [entry resolve. entry deviceMilliseconds notNil]).
	self assert: ((CudaTrace default calls at: 'cublasSgemm') >= 1)]
		ensure: [a release. b release. c isNil ifFalse: [c release]].
	self assert: CudaLibraryAPI allocations size equals: before.
	self deny: (CudaArray liveArrays includes: c)
!
testSpectrumRoundTrip
	| s n v back f worst |
	n := 64.
	v := (1 to: n * n) collect: [:i | ((i - 1 \\ n) // 8 + ((i - 1 // n) // 8)) odd ifTrue: [1.0] ifFalse: [0.0]].
	s := CudaSpectrum size: n.
	[s image: v.
	s forward.
	back := s inverseMasked: (Array new: n * n withAll: 1.0).
	self assert: ((1 to: v size) inject: 0 into: [:m :i | m max: ((back at: i) - (v at: i)) abs]) < 1.0e-4.
	f := CudaSpectrum fft2D: v size: n.
	worst := 0.
	(s spectrum) size = (n * n) ifFalse: [self fail].
	1 to: v size do: [:i | | g |
		g := (((s instVarNamed: 'reValues') at: i) squared + ((s instVarNamed: 'imValues') at: i) squared) sqrt.
		worst := worst max: (g - ((f first at: i) squared + (f last at: i) squared) sqrt) abs].
	self assert: worst < 1.0e-2.
	back := s inverseMasked: (s lowPass: 4).
	self assert: ((back inject: 0 into: [:m :x | m max: x]) < 1.0).
	self assert: ((s times at: #forward) > 0 and: [(s times at: #inverse) > 0]).
	CudaSpectrum hasCufft ifTrue: [| a c |
		a := s spectrum.
		s engine: #cufft; forward.
		c := s spectrum.
		self assert: ((1 to: a size) inject: 0 into: [:mx :i | mx max: ((c at: i) - (a at: i)) abs]) < 1.0e-3.
		back := s inverseMasked: (Array new: n * n withAll: 1.0).
		self assert: ((1 to: v size) inject: 0 into: [:mx :i | mx max: ((back at: i) - (v at: i)) abs]) < 1.0e-4]]
		ensure: [s release]
!
testRoutingSolved
	| r |
	CuOpt isAvailable ifFalse: [^self skip: 'no cuOpt here'].
	r := CuOptRouting example.
	r vehicles: 2; timeLimit: 5.
	r solve.
	self assert: r result hasSolution.
	self assert: r visitsEveryStop.
	self assert: r routes size <= 2.
	self assert: (r routes allSatisfy: [:route | route size <= r capacity]).
	self assert: (r totalDistance - r result objective) abs < 1.0e-6
!
testProgramSolved
	| p |
	CuOpt isAvailable ifFalse: [^self skip: 'no cuOpt here'].
	p := CuOptProgram fromText: (CuOptProgram examples at: 1) value.
	p solve.
	self assert: p result isOptimal.
	self assert: (p result objective - 36) abs < 1.0e-6.
	self assert: ((p valueOf: 'chairs') - 2) abs < 1.0e-6.
	self assert: ((p activityOf: 3) - 18) abs < 1.0e-6.
	p := CuOptProgram fromText: (CuOptProgram examples at: 3) value.
	p solve.
	self assert: p result hasSolution.
	self assert: (p result objective - 27) abs < 1.0e-6
! !
