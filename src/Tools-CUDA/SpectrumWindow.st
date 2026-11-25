ToolPane subclass: #SpectrumWindow
	instanceVariableNames: 'spectrum size source filter radius values filtered engine engineToggle sourceToggle sizeToggle filterToggle picture spectrumImage filteredImage status cpuMs pictureForm'
	classVariableNames: ''
	package: 'Tools-CUDA'!

SpectrumWindow comment: 'I am the Spectrum (World menu › Apps › GPU): a picture''s two-dimensional Fourier transform on the GPU (CudaSpectrum: cuFFT, or the DFT as matrix products on cuBLAS, as chosen), its magnitude spectrum, and the picture again from the spectrum filtered: low-pass (only the frequencies inside the circle: blurred), high-pass (only those outside: the edges) or a band. Drag on the spectrum to set the circle; the filtered picture follows as one drags. The status bar has the device''s times of the two transforms and, for comparison, a radix-2 FFT in Smalltalk of the same picture.

	SpectrumWindow open'!

!SpectrumWindow methodsFor: 'initialization'!
initialize
	super initialize.
	size := 256.
	engine := (GpuTools isAvailable and: [CudaSpectrum hasCufft]) ifTrue: [#cufft] ifFalse: [#cublas].
	source := #letters.
	filter := #low.
	radius := 24.
	self build
!
build
	| toolbar |
	sourceToggle := ToggleGroup options: {#letters -> 'Letters'. #zone -> 'Zone plate'. #checks -> 'Checks'. #bars -> 'Bars'}.
	sourceToggle name: 'source'; selection: source; onChange: [:k | self source: k].
	sizeToggle := ToggleGroup options: {128 -> '128'. 256 -> '256'. 512 -> '512'}.
	sizeToggle name: 'size'; selection: size; onChange: [:k | self size: k].
	filterToggle := ToggleGroup options: {#low -> 'Low-pass'. #high -> 'High-pass'. #band -> 'Band'. #none -> 'None'}.
	filterToggle name: 'filter'; selection: filter; onChange: [:k | self filter: k].
	engineToggle := ToggleGroup options: {#cufft -> 'cuFFT'. #cublas -> 'cuBLAS DFT'}.
	engineToggle name: 'engine'; selection: engine; onChange: [:k | self engine: k].
	toolbar := Row with: {sourceToggle fixed: 330; yourself. sizeToggle fixed: 150; yourself. engineToggle fixed: 190; yourself. Widget new flex: 1; yourself. filterToggle fixed: 330; yourself}.
	toolbar spacing: 10; padding: (8 @ 5 corner: 8 @ 5); fixed: 30.
	picture := SpectrumImage new name: 'picture'; yourself.
	picture tool: self role: #picture.
	spectrumImage := SpectrumImage new name: 'spectrum'; yourself.
	spectrumImage tool: self role: #spectrum.
	filteredImage := SpectrumImage new name: 'filtered'; yourself.
	filteredImage tool: self role: #filtered.
	status := StatusBar new name: 'status'; yourself.
	self addAll: {
		toolbar.
		ProfilerRule new.
		((Row with: {
			(self pane: picture title: 'Picture' right: [size printString , ' x ' , size printString]) flex: 1; yourself.
			(self pane: spectrumImage title: 'Spectrum' right: 'log |F|, drag: the filter') flex: 1; yourself.
			(self pane: filteredImage title: 'Filtered' right: [self filterText]) flex: 1; yourself}) separators: true; flex: 1; yourself).
		status}
!
minimumWindowExtent
	^640 @ 300
! !

!SpectrumWindow methodsFor: 'accessing'!
size
	^size
!
radius
	^radius
!
radii
	"The circles on the spectrum."
	filter == #none ifTrue: [^#()].
	filter == #band ifTrue: [^{radius - self bandWidth / 2 max: 0. radius + self bandWidth / 2}].
	^{radius}
!
bandWidth
	^size / 16
!
spectrum
	^spectrum
!
pictureImage
	^picture
!
spectrumImage
	^spectrumImage
!
filteredImage
	^filteredImage
!
statusBar
	^status
!
filterText
	filter == #low ifTrue: [^'frequencies up to ' , radius rounded printString].
	filter == #high ifTrue: [^'frequencies above ' , radius rounded printString].
	filter == #band ifTrue: [^'frequencies near ' , radius rounded printString].
	^'all frequencies'
! !

!SpectrumWindow methodsFor: 'changing'!
source: aSymbol
	source := aSymbol.
	sourceToggle selection: aSymbol.
	self transform
!
size: anInteger
	size = anInteger ifTrue: [^self].
	spectrum isNil ifFalse: [spectrum release. spectrum := nil].
	radius := radius * anInteger / size.
	size := anInteger.
	sizeToggle selection: anInteger.
	cpuMs := nil.
	self transform
!
engine: aSymbol
	"cuFFT or the DFT as cuBLAS products."
	(aSymbol == #cufft and: [GpuTools isAvailable and: [CudaSpectrum hasCufft not]]) ifTrue: [engineToggle selection: engine. ^self].
	engine := aSymbol.
	engineToggle selection: aSymbol.
	spectrum isNil ifTrue: [^self transform].
	spectrum engine: aSymbol.
	self transform
!
engine
	^engine
!
filter: aSymbol
	filter := aSymbol.
	filterToggle selection: aSymbol.
	self refilter
!
radius: aNumber
	radius := (aNumber max: 1) min: size * 0.71.
	self refilter
! !

!SpectrumWindow methodsFor: 'computing'!
start
	self transform
!
windowClosed
	spectrum isNil ifFalse: [spectrum release. spectrum := nil]
!
transform
	"A new picture: show it, transform it forward on the GPU, show its spectrum, then filter."
	values := self class picture: source size: size.
	picture form: (self class grayForm: values size: size).
	GpuTools isAvailable ifFalse: [^self showUnavailable].
	spectrum isNil ifTrue: [spectrum := CudaSpectrum size: size].
	spectrum engine: engine.
	spectrum image: values.
	spectrum forward.
	spectrum forward.
	spectrumImage form: (self class heatForm: spectrum spectrum size: size).
	cpuMs := spectrum fftMilliseconds: values.
	self refilter
!
refilter
	| mask |
	spectrum isNil ifTrue: [^self invalidate].
	mask := filter == #low ifTrue: [spectrum lowPass: radius] ifFalse: [
		filter == #high ifTrue: [spectrum highPass: radius] ifFalse: [
			filter == #band ifTrue: [spectrum bandPass: radius width: self bandWidth] ifFalse: [Array new: size * size withAll: 1.0]]].
	filtered := spectrum inverseMasked: mask.
	filteredImage form: (self class grayForm: filtered size: size).
	spectrumImage invalidate.
	self invalidate.
	self showTimes
!
showTimes
	| t |
	t := spectrum times.
	status clear.
	status add: (engine == #cufft ifTrue: ['cuFFT '] ifFalse: ['cuBLAS DFT ']) , size printString , '²' style: #mono.
	status add: 'forward ' , (CudaComparison milliseconds: (t at: #forward)) , ' · inverse ' , (CudaComparison milliseconds: (t at: #inverse ifAbsent: [0])) , ' on the device' style: #text.
	status add: 'copies and mask ' , (CudaComparison milliseconds: (t at: #read) + (t at: #mask ifAbsent: [0])) , ' here' style: #text.
	cpuMs isNil ifFalse: [status addRight: 'Smalltalk FFT ' , (CudaComparison milliseconds: cpuMs) style: #mono]
!
showUnavailable
	status clear.
	status add: 'no CUDA' style: #pillSuspended.
	status add: GpuTools unavailableText style: #text.
	self invalidate
! !

!SpectrumWindow class methodsFor: 'pictures'!
picture: aSymbol size: n
	"n * n values in 0..1, row by row."
	aSymbol == #letters ifTrue: [^[self letters: 'GPU' size: n] on: Error do: [:e | e return: (self picture: #checks size: n)]].
	aSymbol == #zone ifTrue: [^(1 to: n * n) collect: [:i | | x y |
		x := (i - 1 \\ n) - (n / 2). y := (i - 1 // n) - (n / 2).
		0.5 + (0.5 * (Float pi * ((x * x) + (y * y)) / n) cos)]].
	aSymbol == #bars ifTrue: [^(1 to: n * n) collect: [:i | | x y |
		x := i - 1 \\ n. y := i - 1 // n.
		(0.5 + (0.25 * (2 * Float pi * x * 6 / n) sin) + (0.25 * (2 * Float pi * (x + y) * 17 / n) sin))]].
	^(1 to: n * n) collect: [:i | | x y c |
		x := i - 1 \\ n. y := i - 1 // n. c := n // 8.
		((x // c) + (y // c)) odd ifTrue: [1.0] ifFalse: [0.0]]
!
letters: aString size: n
	"aString in the bold UI face, as large as fits, ink 1 on paper 0."
	| font glyphs width height x0 y0 out x |
	font := Font faceNamed: 'IosevkaEtoile-Bold' size: (n * 0.55) rounded.
	glyphs := aString asArray collect: [:c | font glyphFor: c].
	width := glyphs inject: 0 into: [:s :g | s + g width + (n // 32)].
	height := glyphs inject: 0 into: [:m :g | m max: g height].
	out := Array new: n * n withAll: 0.0.
	x0 := (n - width) // 2 max: 0.
	y0 := (n - height) // 2 max: 0.
	x := x0.
	glyphs do: [:g |
		0 to: g height - 1 do: [:gy | 0 to: g width - 1 do: [:gx | | px py |
			px := x + gx. py := y0 + gy + (height - g height).
			(px < n and: [py < n]) ifTrue: [out at: py * n + px + 1 put: (g coverageAt: gx @ gy) / 255.0]]].
		x := x + g width + (n // 32)].
	^out
!
grayForm: values size: n
	"paper for 0, ink for 1 (clamped)."
	| form t lut bits |
	t := Theme current.
	lut := (0 to: 255) collect: [:k | | c | c := t paper mixed: k / 255.0 with: t ink.
		(c red * 255) rounded + ((c green * 255) rounded bitShift: 8) + ((c blue * 255) rounded bitShift: 16) + 16rFF000000].
	form := Form width: n height: n.
	bits := form bits.
	1 to: n * n do: [:i | bits at: i put: (lut at: ((((values at: i) max: 0) min: 1) * 255) rounded + 1)].
	form changed.
	^form
!
heatForm: values size: n
	^CudaHeatMap formFrom: values width: n height: n
! !

!SpectrumWindow class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	^self openIn: (Tools placeAt: aPointOrNil extent: 1140 @ 470)
!
openIn: aRectangle
	| tool window |
	tool := self new.
	window := tool openIn: aRectangle title: 'Spectrum'.
	window do: [tool start].
	^window
!
initialize
	ToolsMenu register: 'Spectrum' description: '2-D Fourier transform · filters' group: #gpu order: 40 action: [:point | self openAt: point].
	Tools registerOpener: #spectrum with: [:arg | self open]
! !
