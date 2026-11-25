Object subclass: #CudaBenchmark
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CudaBenchmark comment: 'I measure the CUDA bindings for docs/cuda.md: single precision matrix products on the GPU (cuBLAS through CudaMatrix: device time by CUDA events, wall time, the cost of a call), the same product as a naive Smalltalk loop on the CPU (extrapolated by n cubed), and the GPU''s result against the Smalltalk one. tools/cuda/sgemm_sample.c is the same in C, for the binding''s overhead.

	CudaBenchmark report      "a few seconds; run it from a Workspace with print it"
	CudaBenchmark sgemm: 4096 repeat: 20
	CudaBenchmark solverReport     "LU, SVD and FFT (cuSOLVER, cuFFT) against Smalltalk loops; half a minute"'!

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

!CudaBenchmark class methodsFor: 'solvers and transforms'!
timeGpu: aBlock
	"{GPU ms. wall ms} of aBlock's work: CUDA events around it, after a synchronize, and the wall clock until the device is done."
	| start stop t0 wall gpu |
	Cuda synchronize.
	start := CudaEvent new record.
	t0 := Time microsecondClockValue.
	[aBlock value.
	stop := CudaEvent new record.
	Cuda synchronize.
	wall := Time microsecondClockValue - t0.
	gpu := stop millisecondsSince: start]
		ensure: [start release. stop ifNotNil: [stop release]].
	^{gpu. wall / 1000.0}
!
luSolve: n type: aSymbol
	"Factor a random n x n matrix (uniform, plus n / 8 on the diagonal) with CudaMatrix lu and solve one right-hand side with it, after a warm-up: {lu GPU ms. lu wall ms. solve GPU ms. solve wall ms. the relative residual |A x - b| / |b|}."
	| u id a b lu x lut st ax r residual |
	u := CudaMatrix uniformRows: n cols: n type: aSymbol.
	id := CudaMatrix identity: n type: aSymbol.
	a := u add: id times: n / 8.
	u release. id release.
	b := CudaMatrix uniformRows: n cols: 1 type: aSymbol.
	[a lu release.
	lut := self timeGpu: [lu := a lu].
	st := self timeGpu: [x := lu solve: b].
	ax := a * x.
	r := ax - b.
	residual := r norm / b norm]
		ensure: [a release. b release. lu ifNotNil: [lu release]. x ifNotNil: [x release]. ax ifNotNil: [ax release]. r ifNotNil: [r release]].
	^{lut first. lut last. st first. st last. residual}
!
svd: m by: n type: aSymbol
	"The thin SVD of a random m x n matrix with CudaMatrix svd, and its singular values alone, after a warm-up: {svd GPU ms. svd wall ms. values GPU ms. values wall ms. |sum of s^2 - |A|^2| / |A|^2 (the Frobenius norm)}."
	| a d s vt st sum fro |
	a := CudaMatrix uniformRows: m cols: n type: aSymbol.
	[a singularValues release.
	vt := self timeGpu: [d := a svd].
	st := self timeGpu: [s := a singularValues].
	sum := s asArray inject: 0.0 into: [:acc :v | acc + v squared].
	fro := a norm squared]
		ensure: [a release. d ifNotNil: [d release]. s ifNotNil: [s release]].
	^{vt first. vt last. st first. st last. (sum - fro) abs / fro}
!
fft2d: n repeat: count
	"The real-to-complex 2-D FFT of a random n x n float32 matrix: with a CudaFFTPlan made once, count times; and CudaMatrix fft, which plans each call: {GPU ms a transform. GFLOPS (2.5 N log2 N). wall ms a transform. plan wall ms. fft wall ms. |ifftReal(fft a) - a| / |a|}."
	| a c plan pt t ft f back r err |
	a := CudaMatrix uniformRows: n cols: n.
	c := CudaMatrix rows: n cols: n // 2 + 1 type: #complex64.
	[pt := self timeGpu: [plan := CudaFFTPlan shape: {n. n} kind: #r2c type: #float32 batch: 1].
	plan forward: a into: c.
	t := self timeGpu: [count timesRepeat: [plan forward: a into: c]].
	a fft release.
	ft := self timeGpu: [f := a fft].
	back := f ifftReal: n.
	r := back - a.
	err := r norm / a norm]
		ensure: [a release. c release. plan ifNotNil: [plan release]. f ifNotNil: [f release]. back ifNotNil: [back release]. r ifNotNil: [r release]].
	^{t first / count. 2.5 * n * n * ((n * n) ln / 2 ln) / (t first / count / 1000.0) / 1.0e9. t last / count. pt last. ft last. err}
!
cpuLU: n
	"Seconds a Smalltalk loop takes to solve a random n x n system by Gaussian elimination with partial pivoting (Floats in an Array, row-major)."
	| a b t0 |
	a := (1 to: n * n) collect: [:i | (i * 7919 \\ 1009) / 1009.0].
	1 to: n do: [:i | a at: i - 1 * n + i put: (a at: i - 1 * n + i) + (n / 8)].
	b := (1 to: n) collect: [:i | i / n asFloat].
	t0 := Time microsecondClockValue.
	1 to: n do: [:k | | p pivot kk |
		p := k.
		k + 1 to: n do: [:i | (a at: i - 1 * n + k) abs > (a at: p - 1 * n + k) abs ifTrue: [p := i]].
		p = k ifFalse: [
			1 to: n do: [:j | | v | v := a at: k - 1 * n + j. a at: k - 1 * n + j put: (a at: p - 1 * n + j). a at: p - 1 * n + j put: v].
			b swap: k with: p].
		kk := k - 1 * n.
		pivot := a at: kk + k.
		k + 1 to: n do: [:i | | f ii |
			ii := i - 1 * n.
			f := (a at: ii + k) / pivot.
			k to: n do: [:j | a at: ii + j put: (a at: ii + j) - (f * (a at: kk + j))].
			b at: i put: (b at: i) - (f * (b at: k))]].
	n to: 1 by: -1 do: [:i | | s |
		s := b at: i.
		i + 1 to: n do: [:j | s := s - ((a at: i - 1 * n + j) * (b at: j))].
		b at: i put: s / (a at: i - 1 * n + i)].
	^(Time microsecondClockValue - t0) / 1.0e6
!
fft: re im: im offset: o stride: s n: n cos: wr sin: wi
	"In place, radix 2 (n a power of 2), the elements o + (k * s), k = 0 .. n - 1, of re and im; wr and wi: the n / 2 twiddles."
	| j len |
	j := 0.
	0 to: n - 1 do: [:i | | m |
		i < j ifTrue: [| a b v |
			a := o + (i * s). b := o + (j * s).
			v := re at: a. re at: a put: (re at: b). re at: b put: v.
			v := im at: a. im at: a put: (im at: b). im at: b put: v].
		m := n // 2.
		[m >= 1 and: [j >= m]] whileTrue: [j := j - m. m := m // 2].
		j := j + m].
	len := 2.
	[len <= n] whileTrue: [| half step |
		half := len // 2.
		step := n // len.
		0 to: n - 1 by: len do: [:start |
			0 to: half - 1 do: [:k | | a b cr ci tr ti |
				cr := wr at: k * step + 1. ci := wi at: k * step + 1.
				a := o + (start + k * s). b := a + (half * s).
				tr := ((re at: b) * cr) - ((im at: b) * ci).
				ti := ((re at: b) * ci) + ((im at: b) * cr).
				re at: b put: (re at: a) - tr. im at: b put: (im at: a) - ti.
				re at: a put: (re at: a) + tr. im at: a put: (im at: a) + ti]].
		len := len * 2]
!
fft2dRe: re im: im n: n
	"The 2-D FFT of the n x n complex matrix in re and im (row-major), in place: each row, then each column."
	| wr wi |
	wr := (0 to: n // 2 - 1) collect: [:k | (-2.0 * Float pi * k / n) cos].
	wi := (0 to: n // 2 - 1) collect: [:k | (-2.0 * Float pi * k / n) sin].
	0 to: n - 1 do: [:i | self fft: re im: im offset: i * n + 1 stride: 1 n: n cos: wr sin: wi].
	1 to: n do: [:j | self fft: re im: im offset: j stride: n n: n cos: wr sin: wi]
!
cpuFFT2d: n
	"Seconds the Smalltalk radix-2 loop takes for the 2-D FFT of a real n x n matrix (as complex values)."
	| re im t0 |
	re := (1 to: n * n) collect: [:i | (i * 7919 \\ 1009) / 1009.0].
	im := Array new: n * n withAll: 0.0.
	t0 := Time microsecondClockValue.
	self fft2dRe: re im: im n: n.
	^(Time microsecondClockValue - t0) / 1.0e6
!
checkFFT2d: n
	"The largest difference between cuFFT's half spectrum of a random n x n float32 matrix and the Smalltalk loop's, relative to the largest magnitude."
	| a f values half re im worst scale |
	a := CudaMatrix uniformRows: n cols: n.
	[values := a asArray. f := a fft. half := f asArray] ensure: [a release. f ifNotNil: [f release]].
	re := values copy. im := Array new: n * n withAll: 0.0.
	self fft2dRe: re im: im n: n.
	worst := 0.0. scale := 0.0.
	1 to: n do: [:i | 1 to: n // 2 + 1 do: [:j | | z k |
		z := half at: i - 1 * (n // 2 + 1) + j.
		k := i - 1 * n + j.
		scale := scale max: ((re at: k) squared + (im at: k) squared) sqrt.
		worst := worst max: ((z real - (re at: k)) squared + (z imaginary - (im at: k)) squared) sqrt]].
	^worst / scale
!
jacobiSingularValues: rows m: m n: n
	"The singular values (decreasing) of the m x n matrix rows (a flat row-major Array), by one-sided Jacobi rotations of its columns in Smalltalk."
	| cols |
	cols := (1 to: n) collect: [:j | (1 to: m) collect: [:i | rows at: i - 1 * n + j]].
	1 to: 40 do: [:sweep | | rotated |
		rotated := false.
		1 to: n - 1 do: [:p | p + 1 to: n do: [:q | | cp cq alpha beta gamma |
			cp := cols at: p. cq := cols at: q.
			alpha := 0.0. beta := 0.0. gamma := 0.0.
			1 to: m do: [:i | | x y | x := cp at: i. y := cq at: i. alpha := alpha + (x * x). beta := beta + (y * y). gamma := gamma + (x * y)].
			gamma abs > (1.0e-12 * (alpha * beta) sqrt) ifTrue: [| zeta t c s |
				rotated := true.
				zeta := beta - alpha / (2.0 * gamma).
				t := zeta sign asFloat / (zeta abs + (zeta squared + 1.0) sqrt).
				zeta = 0.0 ifTrue: [t := 1.0].
				c := 1.0 / (t squared + 1.0) sqrt. s := c * t.
				1 to: m do: [:i | | x y | x := cp at: i. y := cq at: i. cp at: i put: (c * x) - (s * y). cq at: i put: (s * x) + (c * y)]]]].
		rotated ifFalse: [^((cols collect: [:col | (col inject: 0.0 into: [:a :v | a + (v * v)]) sqrt]) asSortedCollection: [:x :y | x >= y]) asArray]].
	^((cols collect: [:col | (col inject: 0.0 into: [:a :v | a + (v * v)]) sqrt]) asSortedCollection: [:x :y | x >= y]) asArray
!
cpuSVD: m by: n
	"{seconds the Smalltalk one-sided Jacobi takes for the singular values of a random m x n float64 matrix. the largest difference from cuSOLVER's, relative to the largest}."
	| a values gpu t0 cpu |
	a := CudaMatrix uniformRows: m cols: n type: #float64.
	[| sv | values := a asArray. sv := a singularValues. gpu := sv asArray. sv release] ensure: [a release].
	t0 := Time microsecondClockValue.
	cpu := self jacobiSingularValues: values m: m n: n.
	t0 := (Time microsecondClockValue - t0) / 1.0e6.
	^{t0. ((1 to: gpu size) inject: 0.0 into: [:w :i | w max: ((gpu at: i) - (cpu at: i)) abs]) / gpu first}
!
solverReport
	"The cuSOLVER and cuFFT numbers of docs/cuda.md, as text (half a minute: the Smalltalk loops are most of it). tools/cuda/solver_fft_sample.c is the same in C, with LAPACK and FFTW on the CPU."
	^String streamContents: [:s | | r cpu |
		s nextPutAll: Cuda summary; cr.
		#(#float32 #float64) do: [:type |
			r := self luSolve: 4096 type: type.
			s nextPutAll: 'LU 4096 '; nextPutAll: type; nextPutAll: ': lu GPU '; nextPutAll: (r first printShowingDecimalPlaces: 2);
				nextPutAll: ' ms, wall '; nextPutAll: ((r at: 2) printShowingDecimalPlaces: 2);
				nextPutAll: ' ms; solve GPU '; nextPutAll: ((r at: 3) printShowingDecimalPlaces: 3);
				nextPutAll: ' ms, wall '; nextPutAll: ((r at: 4) printShowingDecimalPlaces: 3);
				nextPutAll: ' ms; residual '; print: (r at: 5); cr].
		cpu := self cpuLU: 1024.
		s nextPutAll: 'Smalltalk Gaussian elimination 1024: '; nextPutAll: (cpu printShowingDecimalPlaces: 2);
			nextPutAll: ' s; 4096 would take '; nextPutAll: (cpu * 64 / 60 printShowingDecimalPlaces: 1); nextPutAll: ' minutes'; cr.
		#(#float32 #float64) do: [:type |
			r := self svd: 2048 by: 1024 type: type.
			s nextPutAll: 'SVD 2048 x 1024 '; nextPutAll: type; nextPutAll: ': svd GPU '; nextPutAll: (r first printShowingDecimalPlaces: 1);
				nextPutAll: ' ms, wall '; nextPutAll: ((r at: 2) printShowingDecimalPlaces: 1);
				nextPutAll: ' ms; values only GPU '; nextPutAll: ((r at: 3) printShowingDecimalPlaces: 1);
				nextPutAll: ' ms; |sum s^2 - |A|^2| / |A|^2 '; print: (r at: 5); cr].
		r := self cpuSVD: 256 by: 128.
		s nextPutAll: 'Smalltalk one-sided Jacobi 256 x 128 (float64): '; nextPutAll: (r first printShowingDecimalPlaces: 2);
			nextPutAll: ' s, singular values within '; print: r last; nextPutAll: ' of cuSOLVER''s; 2048 x 1024 would take ~';
			nextPutAll: (r first * 512 / 60 printShowingDecimalPlaces: 1); nextPutAll: ' minutes (by m n^2)'; cr.
		r := self fft2d: 4096 repeat: 20.
		s nextPutAll: 'FFT 4096 x 4096 real to complex: GPU '; nextPutAll: (r first printShowingDecimalPlaces: 3);
			nextPutAll: ' ms ('; nextPutAll: ((r at: 2) printShowingDecimalPlaces: 0); nextPutAll: ' GFLOPS), wall ';
			nextPutAll: ((r at: 3) printShowingDecimalPlaces: 3); nextPutAll: ' ms; plan '; nextPutAll: ((r at: 4) printShowingDecimalPlaces: 1);
			nextPutAll: ' ms; CudaMatrix fft (plans too) '; nextPutAll: ((r at: 5) printShowingDecimalPlaces: 1);
			nextPutAll: ' ms; round trip within '; print: (r at: 6); cr.
		s nextPutAll: 'cuFFT 256 x 256 against the Smalltalk FFT: within '; print: (self checkFFT2d: 256); cr.
		cpu := self cpuFFT2d: 4096.
		s nextPutAll: 'Smalltalk radix-2 FFT 4096 x 4096 (complex, float64): '; nextPutAll: (cpu printShowingDecimalPlaces: 2); nextPutAll: ' s'; cr]
! !
