Object subclass: #CudaHeatMap
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools-CUDA'!

CudaHeatMap comment: 'I paint a CudaMatrix as a heat map, as the Inspector shows one: at most side x side samples, evenly spaced rows and columns (a copy from the device a sampled row), scaled from the smallest to the largest value through the theme''s colors (paper, the accent, ink: the Blue Book''s ramp, Haiku''s in Haiku).

	CudaHeatMap formOf: (CudaMatrix uniformRows: 1000 cols: 1000)'!

!CudaHeatMap class methodsFor: 'painting'!
formOf: aMatrix
	^self formOf: aMatrix side: 256
!
formOf: aMatrix side: side
	| s |
	s := self samplesOf: aMatrix side: side.
	^self formFrom: s last width: (s at: 2) height: s first
!
samplesOf: aMatrix side: side
	"{rows. cols. values row by row} of aMatrix at up to side x side evenly spaced places."
	| r c values |
	r := aMatrix rows min: side.
	c := aMatrix cols min: side.
	values := Array new: r * c.
	(r = 0 or: [c = 0]) ifTrue: [^{r. c. values}].
	1 to: r do: [:i | | row |
		row := aMatrix rows: (self index: i of: r in: aMatrix rows) to: (self index: i of: r in: aMatrix rows).
		row := row first.
		1 to: c do: [:j | values at: i - 1 * c + j put: (row at: (self index: j of: c in: aMatrix cols))]].
	^{r. c. values}
!
index: i of: n in: size
	"The i-th of n evenly spaced indices in 1..size."
	n = size ifTrue: [^i].
	^((i - 0.5) * size / n) floor + 1 min: size
!
formFrom: values width: w height: h
	| form lut lo hi scale bits |
	form := Form width: (w max: 1) height: (h max: 1).
	values isEmpty ifTrue: [^form fill: Theme current paper; yourself].
	lut := self palette.
	lo := values inject: values first into: [:m :v | m min: v].
	hi := values inject: values first into: [:m :v | m max: v].
	scale := hi = lo ifTrue: [0] ifFalse: [255.0 / (hi - lo)].
	bits := form bits.
	1 to: values size do: [:k | bits at: k put: (lut at: ((values at: k) - lo * scale) rounded + 1)].
	form changed.
	^form
!
palette
	"256 opaque RGBA8 words from paper through the accent to ink."
	| t stops |
	t := Theme current.
	stops := {t paper. t paper mixed: 0.35 with: t ultramarine. t ultramarine. t ultramarine mixed: 0.6 with: t ink. t ink}.
	^(0 to: 255) collect: [:k | | x i c |
		x := k / 255.0 * (stops size - 1).
		i := x floor min: stops size - 2.
		c := (stops at: i + 1) mixed: x - i with: (stops at: i + 2).
		(c red * 255) rounded + ((c green * 255) rounded bitShift: 8) + ((c blue * 255) rounded bitShift: 16) + 16rFF000000]
! !
