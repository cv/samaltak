Object subclass: #CudaComparison
	instanceVariableNames: 'title gpuMs cpuMs cpuNote work unit check'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaComparison comment: 'I am one operation timed on the GPU and on the CPU, as the GPU Workspace shows it: the GPU''s milliseconds by CUDA events (the median of a few runs after a warm-up), the CPU''s by the clock, running the same operation in Smalltalk (a naive loop: what the image does without the GPU). Past a size the CPU would take minutes, so it runs a smaller one and is extrapolated (cpuNote says from which size). Then the speedup, the rate of each (FLOPS, numbers a second), and a check that the GPU computed the right thing (check: the largest difference from the Smalltalk result, or what was compared).

	CudaComparison sgemm: 1024.        "cuBLAS against the Smalltalk loop"
	CudaComparison gemm: 512 type: #float64.
	CudaComparison uniform: 10000000.  "cuRAND against Random"
	CudaComparison norm: 10000000.     "cuBLAS nrm2 against a Smalltalk loop"
	CudaComparison report'!

!CudaComparison class methodsFor: 'measuring'!
gpuMillisecondsOf: aBlock
	"The device's milliseconds for aBlock's work: one run to warm up, then the median of 3 to 7 (fewer when they take long)."
	| times total |
	aBlock value.
	Cuda synchronize.
	times := OrderedCollection new.
	total := 0.
	[times size < 3 or: [times size < 7 and: [total < 300]]] whileTrue: [| start stop |
		[start := CudaEvent new record.
		aBlock value.
		stop := CudaEvent new record.
		stop wait.
		times add: (stop millisecondsSince: start)]
			ensure: [start ifNotNil: [start release]. stop ifNotNil: [stop release]].
		total := total + times last].
	^times asSortedCollection asArray at: times size + 1 // 2
!
cpuMillisecondsOf: aBlock
	| t0 |
	t0 := Time microsecondClockValue.
	aBlock value.
	^Time microsecondClockValue - t0 / 1000.0
!
cpuGemm: m type: aSymbol
	"The CPU's milliseconds for the naive Smalltalk product of two m x m matrices (row-major Arrays of Floats)."
	| x y z |
	x := (1 to: m * m) collect: [:i | (i \\ 7) / 7.0].
	y := (1 to: m * m) collect: [:i | (i \\ 5) / 5.0].
	z := Array new: m * m.
	^self cpuMillisecondsOf: [
		1 to: m do: [:i | | row |
			row := i - 1 * m.
			1 to: m do: [:j | | sum |
				sum := 0.0.
				1 to: m do: [:k | sum := sum + ((x at: row + k) * (y at: k - 1 * m + j))].
				z at: row + j put: sum]]]
!
cornerError: k of: c product: a times: b
	"The largest difference between the k x k top-left corner of c (= a * b, on the device) and the same corner computed here from a's first rows and b's first columns (a few small copies, at any size), relative to the largest value there."
	| n rows cols worst kk largest |
	n := a cols.
	kk := (k min: a rows) min: b cols.
	rows := a copyFrom: 1 count: kk * n.
	cols := (1 to: n) collect: [:i | b copyFrom: i - 1 * b cols + 1 count: kk].
	worst := 0.
	largest := 0.
	1 to: kk do: [:i | | got |
		got := c copyFrom: i - 1 * c cols + 1 count: kk.
		1 to: kk do: [:j | | sum |
			sum := 0.0.
			1 to: n do: [:l | sum := sum + ((rows at: i - 1 * n + l) * ((cols at: l) at: j))].
			largest := largest max: sum abs.
			worst := worst max: (sum - (got at: j)) abs]].
	^largest = 0 ifTrue: [worst] ifFalse: [worst / largest]
! !

!CudaComparison class methodsFor: 'comparing'!
sgemm: n
	"An n x n float32 product: cuBLAS against the Smalltalk loop."
	^self gemm: n type: #float32
!
gemm: n type: aSymbol
	"An n x n product of random matrices: cuBLAS (Sgemm or Dgemm) on the GPU, the naive Smalltalk loop on the CPU (up to 256 x 256, beyond that extrapolated by n cubed)."
	| a b c gpu m cpu err |
	a := CudaMatrix uniformRows: n cols: n type: aSymbol.
	b := CudaMatrix uniformRows: n cols: n type: aSymbol.
	c := CudaMatrix rows: n cols: n type: aSymbol.
	[gpu := self gpuMillisecondsOf: [a multiply: b into: c].
	err := self cornerError: 8 of: c product: a times: b]
		ensure: [a release. b release. c release].
	m := n min: 256.
	cpu := (self cpuGemm: m type: aSymbol) * ((n / m) raisedTo: 3).
	^self new
		title: (aSymbol == #float32 ifTrue: ['SGEMM '] ifFalse: ['DGEMM ']) , n printString , 'x' , n printString
		gpu: gpu cpu: cpu
		cpuNote: (m = n ifTrue: ['Smalltalk loop'] ifFalse: ['Smalltalk loop at ' , m printString , ', x' , ((n / m) raisedTo: 3) rounded printString])
		work: 2.0 * n * n * n unit: 'FLOPS'
		check: 'corner within ' , (self format: err) , ' relative'
!
uniform: n
	"n random float32 numbers in (0, 1]: cuRAND on the GPU, Random into an Array on the CPU (up to a million, beyond that extrapolated)."
	| a gpu m cpu mean |
	a := CudaArray new: n type: #float32.
	[gpu := self gpuMillisecondsOf: [a fillUniform].
	mean := ((a first: 10000) inject: 0 into: [:s :v | s + v]) / (n min: 10000)]
		ensure: [a release].
	m := n min: 1000000.
	cpu := (self cpuMillisecondsOf: [| r array |
		r := Random seed: 42.
		array := Array new: m.
		1 to: m do: [:i | array at: i put: r next]]) * (n / m).
	^self new
		title: 'cuRAND uniform x' , n asStringWithCommas
		gpu: gpu cpu: cpu
		cpuNote: (m = n ifTrue: ['Random'] ifFalse: ['Random for ' , m asStringWithCommas , ', x' , (n / m) rounded printString])
		work: n unit: ' numbers/s'
		check: 'mean ' , (mean printShowingDecimalPlaces: 4)
!
norm: n
	"The Euclidean norm of n random float32 numbers: cuBLAS nrm2 on the GPU, a Smalltalk loop over the same numbers on the CPU (up to a million, beyond that extrapolated)."
	| a gpu m values cpu here there |
	a := CudaArray uniform: n type: #float32.
	m := n min: 1000000.
	[gpu := self gpuMillisecondsOf: [a norm].
	values := a first: m.
	there := CublasAPI cublasSnrm2: Cuda blas n: m x: a address incx: 1]
		ensure: [a release].
	cpu := (self cpuMillisecondsOf: [| sum |
		sum := 0.0.
		values do: [:v | sum := sum + (v * v)].
		here := sum sqrt]) * (n / m).
	^self new
		title: 'cuBLAS nrm2 x' , n asStringWithCommas
		gpu: gpu cpu: cpu
		cpuNote: (m = n ifTrue: ['Smalltalk loop'] ifFalse: ['Smalltalk loop for ' , m asStringWithCommas , ', x' , (n / m) rounded printString])
		work: 2.0 * n unit: 'FLOPS'
		check: 'relative difference ' , (self format: (here - there) abs / here)
! !

!CudaComparison class methodsFor: 'reporting'!
report
	"Each comparison on a line."
	^String streamContents: [:s |
		s nextPutAll: Cuda summary; cr.
		{[self sgemm: 1024]. [self sgemm: 4096]. [self gemm: 1024 type: #float64]. [self uniform: 10000000]. [self norm: 10000000]}
			do: [:each | s print: each value; cr]]
!
format: aNumber
	"A small Float in short scientific notation: 2.3e-6."
	| e m |
	aNumber = 0 ifTrue: [^'0'].
	e := aNumber abs log: 10.
	e := e floor.
	m := aNumber / (10 raisedTo: e).
	^(m printShowingDecimalPlaces: 1) , 'e' , e printString
!
milliseconds: ms
	"0.137 ms, 12.3 ms, 2.95 s, 3.1 min"
	ms < 1 ifTrue: [^(ms printShowingDecimalPlaces: 3) , ' ms'].
	ms < 100 ifTrue: [^(ms printShowingDecimalPlaces: 1) , ' ms'].
	ms < 1000 ifTrue: [^ms rounded printString , ' ms'].
	ms < 120000 ifTrue: [^(ms / 1000.0 printShowingDecimalPlaces: 2) , ' s'].
	^(ms / 60000.0 printShowingDecimalPlaces: 1) , ' min'
!
rate: perSecond unit: aString
	"15.7 TFLOPS, 41.2 G numbers/s"
	| prefixes v i |
	prefixes := #('' 'K' 'M' 'G' 'T' 'P').
	v := perSecond.
	i := 1.
	[v >= 1000 and: [i < prefixes size]] whileTrue: [v := v / 1000.0. i := i + 1].
	^(v printShowingDecimalPlaces: 1) , ' ' , (prefixes at: i) , aString
! !

!CudaComparison methodsFor: 'accessing'!
title: aString gpu: gpuMilliseconds cpu: cpuMilliseconds cpuNote: noteString work: aNumber unit: unitString check: checkString
	title := aString.
	gpuMs := gpuMilliseconds.
	cpuMs := cpuMilliseconds.
	cpuNote := noteString.
	work := aNumber.
	unit := unitString.
	check := checkString
!
title
	^title
!
gpuMilliseconds
	^gpuMs
!
cpuMilliseconds
	^cpuMs
!
cpuNote
	^cpuNote
!
check
	^check
!
speedup
	"How many times faster the GPU is."
	^cpuMs / (gpuMs max: 1.0e-6)
!
gpuRate
	^work / (gpuMs max: 1.0e-6) * 1000
!
cpuRate
	^work / (cpuMs max: 1.0e-6) * 1000
! !

!CudaComparison methodsFor: 'printing'!
speedupString
	| s |
	s := self speedup.
	s >= 10 ifTrue: [^s rounded asStringWithCommas , 'x'].
	^(s printShowingDecimalPlaces: 1) , 'x'
!
printOn: aStream
	"SGEMM 1024x1024: GPU 0.137 ms (15.7 TFLOPS) · CPU 2.95 s (Smalltalk loop at 256, x64; 0.73 GFLOPS) · 21,500x faster · corner within 2.3e-6"
	aStream nextPutAll: title; nextPutAll: ': GPU '; nextPutAll: (self class milliseconds: gpuMs);
		nextPutAll: ' ('; nextPutAll: (self class rate: self gpuRate unit: unit); nextPutAll: ') · CPU ';
		nextPutAll: (self class milliseconds: cpuMs); nextPutAll: ' ('; nextPutAll: cpuNote; nextPutAll: '; ';
		nextPutAll: (self class rate: self cpuRate unit: unit); nextPutAll: ') · ';
		nextPutAll: self speedupString; nextPutAll: ' faster'.
	check isNil ifFalse: [aStream nextPutAll: ' · '; nextPutAll: check]
! !
