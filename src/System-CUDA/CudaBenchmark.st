Object subclass: #CudaBenchmark
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaBenchmark comment: 'I measure the CUDA bindings for docs/cuda.md: single precision matrix products on the GPU (cuBLAS through CudaMatrix: device time by CUDA events, wall time, the cost of a call), the same product as a naive Smalltalk loop on the CPU (extrapolated by n cubed), and the GPU''s result against the Smalltalk one. tools/cuda/sgemm_sample.c is the same in C, for the binding''s overhead.

	CudaBenchmark report      "a few seconds; run it from a Workspace with print it"
	CudaBenchmark sgemm: 4096 repeat: 20'!

!CudaBenchmark class methodsFor: 'measuring'!
sgemm: n repeat: count
	"Multiply two random n x n float32 matrices count times on the GPU, after one product to warm up: {GPU ms a product. TFLOPS. wall ms a product. microseconds a call takes to queue}."
	| a b c start stop t0 queued wall gpu |
	a := CudaMatrix uniformRows: n cols: n.
	b := CudaMatrix uniformRows: n cols: n.
	c := CudaMatrix rows: n cols: n.
	[a multiply: b into: c.
	Cuda synchronize.
	start := CudaEvent new record.
	t0 := Time microsecondClockValue.
	count timesRepeat: [a multiply: b into: c].
	queued := Time microsecondClockValue - t0.
	stop := CudaEvent new record.
	Cuda synchronize.
	wall := Time microsecondClockValue - t0.
	gpu := (stop millisecondsSince: start) / count]
		ensure: [a release. b release. c release. start ifNotNil: [start release]. stop ifNotNil: [stop release]].
	^{gpu. 2.0 * n * n * n / (gpu / 1000.0) / 1.0e12. wall / 1000.0 / count. queued / count}
!
cpuSgemm: n
	"Seconds the naive Smalltalk triple loop takes for an n x n product of Floats."
	| x y z t0 |
	x := (1 to: n * n) collect: [:i | (i \\ 7) / 7.0].
	y := (1 to: n * n) collect: [:i | (i \\ 5) / 5.0].
	z := Array new: n * n.
	t0 := Time microsecondClockValue.
	1 to: n do: [:i | | row |
		row := i - 1 * n.
		1 to: n do: [:j | | sum |
			sum := 0.0.
			1 to: n do: [:k | sum := sum + ((x at: row + k) * (y at: k - 1 * n + j))].
			z at: row + j put: sum]].
	^(Time microsecondClockValue - t0) / 1.0e6
!
check: n type: aSymbol
	"The largest difference between the GPU's product of two random n x n matrices and the Smalltalk loop's."
	| a b c x y z worst |
	a := CudaMatrix uniformRows: n cols: n type: aSymbol.
	b := CudaMatrix uniformRows: n cols: n type: aSymbol.
	[c := a * b.
	x := a asArray. y := b asArray. z := c asArray]
		ensure: [a release. b release. c ifNotNil: [c release]].
	worst := 0.
	1 to: n do: [:i | 1 to: n do: [:j | | sum |
		sum := 0.0.
		1 to: n do: [:k | sum := sum + ((x at: i - 1 * n + k) * (y at: k - 1 * n + j))].
		worst := worst max: (sum - (z at: i - 1 * n + j)) abs]].
	^worst
!
microsecondsPerCall: count
	"The microseconds a trivial CUDA call (cudaGetDevice) takes through the bindings, averaged over count calls."
	| t0 |
	CudaRuntimeAPI cudaGetDevice.
	t0 := Time microsecondClockValue.
	count timesRepeat: [CudaRuntimeAPI cudaGetDevice].
	^(Time microsecondClockValue - t0) / count asFloat
! !

!CudaBenchmark class methodsFor: 'reporting'!
report
	"The numbers of docs/cuda.md, as text."
	^String streamContents: [:s | | r cpu |
		s nextPutAll: Cuda summary; cr.
		s nextPutAll: 'correct: 96 x 96 float32 within '; print: (self check: 96 type: #float32);
			nextPutAll: ', float64 within '; print: (self check: 96 type: #float64); cr.
		#(#(4096 20) #(1024 50) #(8 1000)) do: [:p |
			r := self sgemm: p first repeat: p last.
			s nextPutAll: 'SGEMM '; print: p first; nextPutAll: ' x '; print: p last; nextPutAll: ': GPU ';
				nextPutAll: (r first printShowingDecimalPlaces: 3); nextPutAll: ' ms a product, ';
				nextPutAll: ((r at: 2) printShowingDecimalPlaces: 2); nextPutAll: ' TFLOPS; wall ';
				nextPutAll: ((r at: 3) printShowingDecimalPlaces: 3); nextPutAll: ' ms; a call queues in ';
				nextPutAll: ((r at: 4) printShowingDecimalPlaces: 1); nextPutAll: ' us'; cr].
		cpu := self cpuSgemm: 128.
		s nextPutAll: 'Smalltalk loop 128 x 128: '; nextPutAll: (cpu * 1000 printShowingDecimalPlaces: 1); nextPutAll: ' ms, ';
			nextPutAll: (2.0 * 128 * 128 * 128 / cpu / 1.0e9 printShowingDecimalPlaces: 3); nextPutAll: ' GFLOPS; 4096 x 4096 would take ';
			nextPutAll: (cpu * 32768 / 60 printShowingDecimalPlaces: 1); nextPutAll: ' minutes'; cr.
		s nextPutAll: 'a call of cudaGetDevice takes '; nextPutAll: ((self microsecondsPerCall: 100000) printShowingDecimalPlaces: 3); nextPutAll: ' us'; cr]
! !
