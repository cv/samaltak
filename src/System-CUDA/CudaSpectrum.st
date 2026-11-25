Object subclass: #CudaSpectrum
	instanceVariableNames: 'n cosine sine image re im pm qm t1 t2 t3 t4 reValues imValues times engine r2c c2r half halfIn'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaSpectrum comment: 'I am the two-dimensional discrete Fourier transform of an n x n picture on the GPU, as the Spectrum window shows it, by one of two engines (engine:): #cufft, cuFFT''s real-to-complex and complex-to-real plans of the half spectrum (made once), or #cublas, the transform as matrix products on cuBLAS (Y = F X F with F the DFT matrix C - iS, cosines and sines, so six real products forward and six back); the magnitude spectrum read back (log scaled, the zero frequency in the middle), a mask applied to it on the host, and the masked spectrum transformed back. The device''s times of each direction are measured by CUDA events. fftMilliseconds: is the same forward transform as a radix-2 FFT in Smalltalk, for comparison. Release me (release) to free my matrices.

	| s | s := CudaSpectrum size: 256.
	s image: ((1 to: 256 * 256) collect: [:i | (i \\ 256 // 16) odd ifTrue: [1.0] ifFalse: [0.0]]).
	s forward. s spectrum. s inverseMasked: (s lowPass: 20). s times. s release'!

!CudaSpectrum class methodsFor: 'instance creation'!
size: anInteger
	^self new setSize: anInteger
! !

!CudaSpectrum class methodsFor: 'engines'!
hasCufft
	^CufftAPI isAvailable
!
engines
	"The engines this VM has: #cufft where cuFFT loads, #cublas."
	^self hasCufft ifTrue: [#(#cufft #cublas)] ifFalse: [#(#cublas)]
! !

!CudaSpectrum class methodsFor: 'Smalltalk FFT'!
fft: re imaginary: im inverse: aBoolean
	"In place, radix 2 (re size a power of 2)."
	| n j m step angle wr wi |
	n := re size.
	j := 1.
	1 to: n do: [:i |
		i < j ifTrue: [| t |
			t := re at: i. re at: i put: (re at: j). re at: j put: t.
			t := im at: i. im at: i put: (im at: j). im at: j put: t].
		m := n // 2.
		[m >= 1 and: [j > m]] whileTrue: [j := j - m. m := m // 2].
		j := j + m].
	step := 1.
	[step < n] whileTrue: [
		angle := (aBoolean ifTrue: [Float pi] ifFalse: [Float pi negated]) / step.
		0 to: step - 1 do: [:k |
			wr := (angle * k) cos.
			wi := (angle * k) sin.
			k + 1 to: n by: step * 2 do: [:a | | b tr ti |
				b := a + step.
				tr := (wr * (re at: b)) - (wi * (im at: b)).
				ti := (wr * (im at: b)) + (wi * (re at: b)).
				re at: b put: (re at: a) - tr. im at: b put: (im at: a) - ti.
				re at: a put: (re at: a) + tr. im at: a put: (im at: a) + ti]].
		step := step * 2]
!
fft2D: values size: n
	"{re. im} of the 2-D transform of n x n real values, row-major, by rows then columns."
	| re im rowRe rowIm |
	re := Array new: n * n.
	im := Array new: n * n withAll: 0.0.
	1 to: n * n do: [:i | re at: i put: (values at: i) asFloat].
	rowRe := Array new: n. rowIm := Array new: n.
	1 to: n do: [:r |
		1 to: n do: [:c | rowRe at: c put: (re at: r - 1 * n + c). rowIm at: c put: (im at: r - 1 * n + c)].
		self fft: rowRe imaginary: rowIm inverse: false.
		1 to: n do: [:c | re at: r - 1 * n + c put: (rowRe at: c). im at: r - 1 * n + c put: (rowIm at: c)]].
	1 to: n do: [:c |
		1 to: n do: [:r | rowRe at: r put: (re at: r - 1 * n + c). rowIm at: r put: (im at: r - 1 * n + c)].
		self fft: rowRe imaginary: rowIm inverse: false.
		1 to: n do: [:r | re at: r - 1 * n + c put: (rowRe at: r). im at: r - 1 * n + c put: (rowIm at: r)]].
	^{re. im}
! !

!CudaSpectrum methodsFor: 'initialization'!
setSize: anInteger
	| c s |
	n := anInteger.
	c := Array new: n * n.
	s := Array new: n * n.
	0 to: n - 1 do: [:j | 0 to: n - 1 do: [:k | | a |
		a := 2 * Float pi * (j * k \\ n) / n.
		c at: j * n + k + 1 put: a cos.
		s at: j * n + k + 1 put: a sin]].
	cosine := CudaMatrix rows: n cols: n values: c.
	sine := CudaMatrix rows: n cols: n values: s.
	image := CudaMatrix rows: n cols: n.
	re := CudaMatrix rows: n cols: n.
	im := CudaMatrix rows: n cols: n.
	pm := CudaMatrix rows: n cols: n.
	qm := CudaMatrix rows: n cols: n.
	t1 := CudaMatrix rows: n cols: n.
	t2 := CudaMatrix rows: n cols: n.
	t3 := CudaMatrix rows: n cols: n.
	t4 := CudaMatrix rows: n cols: n.
	times := Dictionary new.
	engine := #cublas.
	"Once, so that the times shown are not cuBLAS's first call (its handle, its kernels' loading)."
	image zero.
	self forward
!
release
	{cosine. sine. image. re. im. pm. qm. t1. t2. t3. t4. half. halfIn. r2c. c2r} do: [:m | m isNil ifFalse: [m release]]
! !

!CudaSpectrum methodsFor: 'accessing'!
size
	^n
!
engine
	^engine
!
engine: aSymbol
	"#cufft or #cublas (the spectrum of the current image needs forward again)."
	(self class engines includes: aSymbol) ifFalse: [^self error: 'no ' , aSymbol , ' engine here'].
	engine := aSymbol
!
times
	"#forward, #inverse: the device's milliseconds; #read, #mask: the host's for copies and Smalltalk work."
	^times
! !

!CudaSpectrum methodsFor: 'transforming'!
image: values
	"The picture: n * n numbers, row by row."
	image fromArray: values
!
timed: aSymbol during: aBlock
	| start stop |
	start := CudaEvent new record.
	[aBlock value.
	stop := CudaEvent new record.
	stop wait.
	times at: aSymbol put: (stop millisecondsSince: start)]
		ensure: [start release. stop isNil ifFalse: [stop release]]
!
forward
	"The transform of the image, read back for spectrum and inverseMasked:."
	engine == #cufft ifTrue: [^self forwardFFT].
	self forwardDFT
!
forwardFFT
	"cuFFT's half spectrum (n x (n // 2 + 1)), read back and completed by its symmetry Y(r, c) = conj Y(-r, -c)."
	| t0 h bytes |
	h := n // 2 + 1.
	r2c isNil ifTrue: [r2c := CudaFFTPlan shape: {n. n} kind: #r2c type: #float32 batch: 1].
	half isNil ifTrue: [half := CudaArray new: n * h type: #complex64].
	self timed: #forward during: [r2c forward: image into: half].
	t0 := Time microsecondClockValue.
	bytes := half asByteArray.
	reValues := Array new: n * n.
	imValues := Array new: n * n.
	0 to: n - 1 do: [:r | 0 to: n - 1 do: [:c | | o sign |
		c < h
			ifTrue: [o := r * h + c * 8. sign := 1]
			ifFalse: [o := (n - r \\ n) * h + (n - c) * 8. sign := -1].
		reValues at: r * n + c + 1 put: (bytes float32At: o + 1).
		imValues at: r * n + c + 1 put: sign * (bytes float32At: o + 5)]].
	times at: #read put: Time microsecondClockValue - t0 / 1000.0
!
forwardDFT
	"Y = (C - iS) X (C - iS): re := C X C - S X S, im := -(C X S + S X C) negated, kept as C X S + S X C (the sign does not matter to magnitudes; inverse knows it). Then read both back."
	| t0 |
	self timed: #forward during: [
		cosine multiply: image into: t1.
		sine multiply: image into: t2.
		t1 multiply: cosine into: re.
		t2 multiply: sine into: t3.
		re accumulate: t3 times: -1.
		t1 multiply: sine into: im.
		t2 multiply: cosine into: t4.
		im accumulate: t4 times: 1].
	t0 := Time microsecondClockValue.
	reValues := re asArray.
	imValues := im asArray.
	times at: #read put: Time microsecondClockValue - t0 / 1000.0
!
spectrum
	"log(1 + |Y|) scaled to 0..1, the zero frequency in the middle (row-major, n * n)."
	| out top h |
	out := Array new: n * n.
	h := n // 2.
	top := 0.
	1 to: n * n do: [:i | | m |
		m := (((reValues at: i) squared + (imValues at: i) squared) sqrt + 1) ln.
		top := top max: m.
		out at: (self shifted: i) put: m].
	top = 0 ifTrue: [^out atAllPut: 0; yourself].
	1 to: out size do: [:i | out at: i put: (out at: i) / top].
	^out
!
shifted: i
	"The index of element i in the centered spectrum."
	| r c h |
	r := i - 1 // n.
	c := i - 1 \\ n.
	h := n // 2.
	^(r + h \\ n) * n + (c + h \\ n) + 1
!
frequencyOf: i
	"The distance of element i (unshifted) from the zero frequency, in cycles across the picture."
	| r c |
	r := i - 1 // n.
	c := i - 1 \\ n.
	r > (n // 2) ifTrue: [r := r - n].
	c > (n // 2) ifTrue: [c := c - n].
	^((r * r) + (c * c)) sqrt
!
lowPass: radius
	^(1 to: n * n) collect: [:i | (self frequencyOf: i) <= radius ifTrue: [1.0] ifFalse: [0.0]]
!
highPass: radius
	^(1 to: n * n) collect: [:i | (self frequencyOf: i) > radius ifTrue: [1.0] ifFalse: [0.0]]
!
bandPass: radius width: w
	^(1 to: n * n) collect: [:i | ((self frequencyOf: i) - radius) abs <= (w / 2) ifTrue: [1.0] ifFalse: [0.0]]
!
inverseMasked: mask
	"The picture back from the spectrum times mask (n * n, unshifted, symmetric as a filter is), values row by row."
	engine == #cufft ifTrue: [^self inverseFFTMasked: mask].
	^self inverseDFTMasked: mask
!
inverseFFTMasked: mask
	"cuFFT's complex-to-real transform of the masked half spectrum, normalized here."
	| t0 h bytes scale out |
	h := n // 2 + 1.
	t0 := Time microsecondClockValue.
	bytes := ByteArray new: n * h * 8.
	0 to: n - 1 do: [:r | 0 to: h - 1 do: [:c | | i o m |
		i := r * n + c + 1.
		o := r * h + c * 8.
		m := mask at: i.
		bytes float32At: o + 1 put: (reValues at: i) * m.
		bytes float32At: o + 5 put: (imValues at: i) * m]].
	halfIn isNil ifTrue: [halfIn := CudaArray new: n * h type: #complex64].
	halfIn fromBytes: bytes.
	times at: #mask put: Time microsecondClockValue - t0 / 1000.0.
	c2r isNil ifTrue: [c2r := CudaFFTPlan shape: {n. n} kind: #c2r type: #float32 batch: 1].
	self timed: #inverse during: [c2r inverse: halfIn into: t2].
	scale := 1.0 / (n * n).
	out := t2 asArray.
	1 to: out size do: [:i | out at: i put: (out at: i) * scale].
	^out
!
inverseDFTMasked: mask
	"Real part of X = (C + iS) Y (C + iS) / n^2 on cuBLAS."
	| t0 p q scale out |
	t0 := Time microsecondClockValue.
	p := Array new: n * n.
	q := Array new: n * n.
	1 to: n * n do: [:i | | m | m := mask at: i. p at: i put: (reValues at: i) * m. q at: i put: (imValues at: i) * m].
	pm fromArray: p.
	qm fromArray: q.
	times at: #mask put: Time microsecondClockValue - t0 / 1000.0.
	"with qm = -Im Y: U = C P + S Q', V = S P - C Q'; X = U C - V S"
	self timed: #inverse during: [
		cosine multiply: pm into: t1.
		sine multiply: qm into: t2.
		t1 accumulate: t2 times: 1.
		sine multiply: pm into: t3.
		cosine multiply: qm into: t4.
		t3 accumulate: t4 times: -1.
		t1 multiply: cosine into: t2.
		t3 multiply: sine into: t4.
		t2 accumulate: t4 times: -1].
	scale := 1.0 / (n * n).
	out := t2 asArray.
	1 to: out size do: [:i | out at: i put: (out at: i) * scale].
	^out
!
fftMilliseconds: values
	"The milliseconds of the forward transform as a Smalltalk FFT, for comparison."
	| t0 |
	t0 := Time microsecondClockValue.
	self class fft2D: values size: n.
	^Time microsecondClockValue - t0 / 1000.0
! !
