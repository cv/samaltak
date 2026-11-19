Object subclass: #UefiGpuTestWindows
	instanceVariableNames: 'memory width height frames'
	classVariableNames: ''
	package: 'Tests-VM'!

UefiGpuTestWindows comment: 'The windows of a UefiGpuSimulation: window 1, width x height pixels; present:pixels:width:height: keeps the frames (BGRA8 ByteArrays).'!

!UefiGpuTestWindows methodsFor: 'accessing'!
setMemory: aSimulatedMemory
	memory := aSimulatedMemory.
	width := 6.
	height := 4.
	frames := OrderedCollection new
!
width: w height: h
	width := w.
	height := h
!
frames
	^frames
! !

!UefiGpuTestWindows methodsFor: 'windows'!
pixelSize: win width: w height: h
	win = 1 ifFalse: [^false].
	w value: width.
	h value: height.
	^true
!
present: win pixels: p width: w height: h
	frames add: (Array with: win with: w with: h with: (memory bytesAt: (memory addressOf: p) count: w * h * 4))
! !

VMSimulation subclass: #UefiGpuSimulation
	instanceVariableNames: 'windows'
	classVariableNames: ''
	package: 'Tests-VM'!

UefiGpuSimulation comment: 'A simulation of UefiGpu with PlatformCommon (handle tables, the error string) and a UefiGpuTestWindows in place of the windows module; the modules connected to neither are nil.'!

!UefiGpuSimulation methodsFor: 'accessing'!
windows
	^windows ifNil: [windows := UefiGpuTestWindows new setMemory: memory]
!
moduleOrLibrary: aTypeName
	aTypeName asString = 'PlatformWindows' ifTrue: [^self windows].
	^[super moduleOrLibrary: aTypeName] on: Error do: [:e | e return: nil]
! !

TestCase subclass: #UefiGpuTest
	instanceVariableNames: 'sim gpu memory dev pipe nearest linear'
	classVariableNames: ''
	package: 'Tests-VM'!

UefiGpuTest comment: 'UefiGpu, the software GPU of the VM on UEFI, run as Smalltalk (UefiGpuSimulation): coverage and the fill rule at fractional coordinates, scissor, glyph coverage, images 1:1 and scaled, the blend maths against exact fractions, triangles (bit 31 of mode) against the quads they split, the patterns against the shader''s formulas, antialiased lines, blits, downloads, the swapchain, the pipeline it refuses, handles; and real DisplayLists of a Canvas.

Colors are RGBA8 words, red in the low byte (premultiplied, as the vertex format and RGBA8 textures have them).'!

!UefiGpuTest methodsFor: 'running'!
setUp
	sim := UefiGpuSimulation modules: {UefiGpu. PlatformCommon}.
	gpu := sim module: UefiGpu.
	memory := sim memory.
	dev := gpu createDevice: false.
	pipe := self pipelineBlend: 2.
	nearest := gpu createSampler: dev linear: false repeat: false.
	linear := gpu createSampler: dev linear: true repeat: false
!
timeLimitMilliseconds
	^300000
! !

!UefiGpuTest methodsFor: 'memory'!
pointer: aTypeName to: aByteArray
	"A pointer to a fresh copy of aByteArray in simulated memory."
	| a |
	a := memory allocate: (aByteArray size max: 1).
	memory bytesAt: a put: aByteArray.
	^memory pointerTo: (CTypeRegistry default parse: aTypeName) at: a
!
bytes: aByteArray
	^self pointer: 'uint8_t' to: aByteArray
!
floats: anArray
	| b |
	b := ByteArray new: anArray size * 4.
	anArray doWithIndex: [:f :i | b float32At: i * 4 - 3 put: f asFloat].
	^self pointer: 'float' to: b
!
ints: anArray
	| b |
	b := ByteArray new: anArray size * 4.
	anArray doWithIndex: [:v :i | b uint32At: i * 4 - 3 put: (v bitAnd: 16rFFFFFFFF)].
	^self pointer: 'int' to: b
!
attributes: anArray
	"pf_vattrs: format offset ..."
	| b |
	b := ByteArray new: (anArray size * 4 max: 8).
	anArray doWithIndex: [:v :i | b uint32At: i * 4 - 3 put: v].
	^self pointer: 'pf_vattr' to: b
!
graphics: aSymbol
	"A class of Graphics-Canvas (a higher layer: late-bound)."
	^Smalltalk at: aSymbol
!
lastError
	^memory stringAt: (sim module: PlatformCommon) lastErrorString
! !

!UefiGpuTest methodsFor: 'objects'!
pipelineBlend: blend
	| vs fs |
	vs := gpu createShader: dev source: 'vertex' entry: 'vmain' stage: 0 samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
	fs := gpu createShader: dev source: 'fragment' entry: 'fmain' stage: 1 samplers: 1 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
	^gpu createPipeline: dev vertexShader: vs fragmentShader: fs stride: 40 attributes: (self attributes: #(4 0 7 16 7 20 5 24 7 28 2 32)) count: 6
		primitive: 0 blend: blend targetFormat: 2
!
textureWidth: w height: h format: f
	| t |
	t := gpu createTexture: dev width: w height: h format: f usage: 3.
	self assert: t > 0.
	^t
!
textureWidth: w height: h format: f pixels: aByteArray
	| t |
	t := self textureWidth: w height: h format: f.
	self assert: (gpu uploadTexture: t data: (self bytes: aByteArray) length: aByteArray size x: 0 y: 0 width: w height: h bytesPerRow: aByteArray size // h).
	^t
!
textureWidth: w height: h words: anArray
	"An RGBA8 texture of the RGBA words."
	^self textureWidth: w height: h format: 2 pixels: (self wordBytes: anArray)
!
wordBytes: anArray
	| b |
	b := ByteArray new: anArray size * 4.
	anArray doWithIndex: [:v :i | b uint32At: i * 4 - 3 put: v].
	^b
!
pixelsOf: tex
	"The texture's pixels as RGBA words (or bytes for R8)."
	| w h f n p ok bytes |
	w := self pointer: 'int' to: (ByteArray new: 4).
	h := self pointer: 'int' to: (ByteArray new: 4).
	f := self pointer: 'int' to: (ByteArray new: 4).
	self assert: (gpu textureSize: tex width: w height: h format: f).
	n := w value * h value * (f value = 1 ifTrue: [1] ifFalse: [4]).
	p := self bytes: (ByteArray new: n).
	ok := gpu download: tex x: 0 y: 0 width: w value height: h value into: p length: n.
	self assert: ok.
	bytes := memory bytesAt: (memory addressOf: p) count: n.
	f value = 1 ifTrue: [^bytes].
	^(1 to: n by: 4) collect: [:i | bytes uint32At: i]
!
target: w height: h clear: aWordOrNil
	"An RGBA8 target of w x h pixels, all aWordOrNil (or zero)."
	^self textureWidth: w height: h words: (Array new: w * h withAll: (aWordOrNil ifNil: [0]))
! !

!UefiGpuTest methodsFor: 'vertices'!
quadX0: x0 y0: y0 x1: x1 y1: y1 color: rgba mode: mode
	^self quadX0: x0 y0: y0 x1: x1 y1: y1 uv0: 0 uv1: 0 color: rgba mode: mode
!
quadX0: x0 y0: y0 x1: x1 y1: y1 uv0: uv0 uv1: uv1 color: rgba mode: mode
	"A quad as Canvas records it: six equal vertices."
	| v |
	v := ByteArray new: 40.
	v float32At: 1 put: x0 asFloat.
	v float32At: 5 put: y0 asFloat.
	v float32At: 9 put: x1 asFloat.
	v float32At: 13 put: y1 asFloat.
	v uint32At: 17 put: uv0.
	v uint32At: 21 put: uv1.
	v uint32At: 25 put: rgba.
	v uint32At: 29 put: mode.
	^v , v , v , v , v , v
!
vertexX: x y: y u: u v: v color: rgba mode: mode
	"An explicitly positioned vertex (bit 31 of mode): uv as floats."
	| b |
	b := ByteArray new: 40.
	b float32At: 1 put: x asFloat.
	b float32At: 5 put: y asFloat.
	b float32At: 17 put: u asFloat.
	b float32At: 21 put: v asFloat.
	b uint32At: 25 put: rgba.
	b uint32At: 29 put: (mode bitOr: 16r80000000).
	^b
!
trianglesOfQuadX0: x0 y0: y0 x1: x1 y1: y1 u0: u0 v0: v0 u1: u1 v1: v1 color: rgba mode: mode
	"The quad as two explicitly positioned triangles, both from its first corner (the provoking vertex: the patterns' origin)."
	| corner |
	corner := [:kx :ky |
		self vertexX: x0 + (x1 - x0 * kx) y: y0 + (y1 - y0 * ky) u: u0 + (u1 - u0 * kx) v: v0 + (v1 - v0 * ky) color: rgba mode: mode].
	^(corner value: 0 value: 0) , (corner value: 1 value: 0) , (corner value: 1 value: 1)
		, (corner value: 0 value: 0) , (corner value: 1 value: 1) , (corner value: 0 value: 1)
!
uvX: x y: y
	^x + (y bitShift: 16)
! !

!UefiGpuTest methodsFor: 'drawing'!
draw: vertexBytes on: tex
	^self draw: vertexBytes on: tex scissor: nil texture: nil sampler: nil translation: 0 @ 0 pipeline: pipe
!
draw: vertexBytes on: tex texture: t sampler: s
	^self draw: vertexBytes on: tex scissor: nil texture: t sampler: s translation: 0 @ 0 pipeline: pipe
!
draw: vertexBytes on: tex scissor: anArrayOrNil texture: t sampler: s translation: aPoint pipeline: aPipeline
	"One command buffer as the Renderer encodes it: the viewport uniform, a pass that loads, the scissor, the texture, one draw."
	| w h f cmd buf pass ok |
	w := self pointer: 'int' to: (ByteArray new: 4).
	h := self pointer: 'int' to: (ByteArray new: 4).
	f := self pointer: 'int' to: (ByteArray new: 4).
	self assert: (gpu textureSize: tex width: w height: h format: f).
	cmd := gpu acquireCommandBuffer: dev.
	buf := gpu createBuffer: dev usage: 1 size: vertexBytes size.
	self assert: (gpu uploadBuffer: buf data: (self bytes: vertexBytes) count: vertexBytes size offset: 0).
	self assert: (gpu pushUniforms: cmd stage: 0 slot: 0 data: (self floats: {w value. h value. aPoint x. aPoint y}) count: 16).
	pass := gpu beginPass: cmd target: tex clear: CPointer null.
	self assert: pass > 0.
	self assert: (gpu bindPipeline: pass pipeline: aPipeline).
	self assert: (gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0).
	anArrayOrNil isNil ifFalse: [
		self assert: (gpu setScissor: pass x: anArrayOrNil first y: (anArrayOrNil at: 2) width: (anArrayOrNil at: 3) height: (anArrayOrNil at: 4))].
	t isNil ifFalse: [self assert: (gpu bindTexture: pass slot: 0 texture: t sampler: s)].
	self assert: (gpu draw: pass vertices: vertexBytes size // 40 first: 0).
	self assert: (gpu endPass: pass).
	ok := self pointer: 'bool' to: #[0].
	gpu submit: cmd fence: false ok: ok.
	self assert: ok value.
	self assert: (gpu releaseHandle: buf)
!
render: aDisplayList width: w height: h clear: aColor
	"Render aDisplayList as the Renderer does (one draw per batch, its texture, scissor and translation); answer the RGBA words."
	| target cmd buf pass ok textures white uniforms tx ty |
	target := self textureWidth: w height: h format: 2.
	white := self textureWidth: 1 height: 1 words: #(16rFFFFFFFF).
	textures := aDisplayList batches collect: [:b | self textureFor: b texture white: white].
	cmd := gpu acquireCommandBuffer: dev.
	buf := gpu createBuffer: dev usage: 1 size: (aDisplayList byteCount max: 40).
	self assert: (gpu uploadBuffer: buf data: (self bytes: (aDisplayList vertices copyFrom: 1 to: aDisplayList byteCount)) count: aDisplayList byteCount offset: 0).
	uniforms := [:x :y | self floats: {w. h. x. y}].
	tx := ty := 0.
	self assert: (gpu pushUniforms: cmd stage: 0 slot: 0 data: (uniforms value: 0 value: 0) count: 16).
	pass := gpu beginPass: cmd target: target clear: (self floats: aColor asArray).
	self assert: (gpu bindPipeline: pass pipeline: pipe).
	self assert: (gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0).
	aDisplayList batches doWithIndex: [:b :i |
		| s |
		s := b scissor ifNil: [{0. 0. w. h}].
		gpu setScissor: pass x: (s at: 1) y: (s at: 2) width: (s at: 3) height: (s at: 4).
		(b dx = tx and: [b dy = ty]) ifFalse: [
			tx := b dx.
			ty := b dy.
			gpu pushUniforms: pass stage: 0 slot: 0 data: (uniforms value: tx value: ty) count: 16].
		gpu bindTexture: pass slot: 0 texture: (textures at: i) sampler: ((b texture isNil or: [b texture isLinearFiltered]) ifTrue: [linear] ifFalse: [nearest]).
		self assert: (gpu draw: pass vertices: b count first: b first)].
	self assert: (gpu endPass: pass).
	ok := self pointer: 'bool' to: #[0].
	gpu submit: cmd fence: false ok: ok.
	self assert: ok value.
	^self pixelsOf: target
!
textureFor: aTextureSource white: white
	aTextureSource isNil ifTrue: [^white].
	(aTextureSource isKindOf: (self graphics: #GlyphAtlasPage)) ifTrue: [
		^self textureWidth: aTextureSource size height: aTextureSource size format: 1 pixels: aTextureSource pixels].
	^self textureWidth: aTextureSource width height: aTextureSource height format: 2 pixels: aTextureSource asByteArray
! !

!UefiGpuTest methodsFor: 'references'!
over: d color: c k: k
	"Premultiplied source-over of c * k / 255 on d, exactly, rounded once (the GPU's blend into unorm8)."
	| ca |
	ca := (c bitShift: -24) * k / 255.
	^(0 to: 3) inject: 0 into: [:acc :lane |
		| s dc |
		s := ((c bitShift: lane * -8) bitAnd: 255) * k / 255.
		dc := (d bitShift: lane * -8) bitAnd: 255.
		acc + (((s + (dc * (255 - ca) / 255)) rounded min: 255) bitShift: lane * 8)]
!
word: r g: g b: b a: a
	^((r + (g bitShift: 8)) + (b bitShift: 16)) + (a bitShift: 24)
!
patternOn: mode variant: variant cell: cell dx: dx dy: dy
	"The uber-shader's halftone (3) and stripes (4)."
	| ix iy |
	ix := (dx max: 0) // cell.
	iy := (dy max: 0) // cell.
	mode = 3 ifTrue: [^variant = 1 ifTrue: [(ix + iy) even] ifFalse: [ix odd and: [iy odd]]].
	variant = 1 ifTrue: [^ix even].
	variant = 2 ifTrue: [^((dx + dy max: 0) // cell) even].
	^iy even
!
bilinear: texels width: w height: h u: u v: v
	"textureLod with a linear sampler, clamped: texel centres at +0.5, 8-bit weights (as the hardware)."
	| uu vv x y fx fy at |
	uu := u - 0.5.
	vv := v - 0.5.
	x := uu floor.
	y := vv floor.
	fx := (uu - x * 256) rounded.
	fy := (vv - y * 256) rounded.
	at := [:i :j | texels at: ((j max: 0) min: h - 1) * w + ((i max: 0) min: w - 1) + 1].
	^(0 to: 3) inject: 0 into: [:acc :lane |
		| ch |
		ch := [:t | ((t bitShift: lane * -8) bitAnd: 255)].
		acc + ((((ch value: (at value: x value: y)) * (256 - fx) + ((ch value: (at value: x + 1 value: y)) * fx) * (256 - fy))
			+ ((ch value: (at value: x value: y + 1)) * (256 - fx) + ((ch value: (at value: x + 1 value: y + 1)) * fx) * fy) + 32768
			bitShift: -16) bitShift: lane * 8)]
! !

!UefiGpuTest methodsFor: 'tests'!
testAQuadCoversThePixelsWhoseCentresAreInside
	| t px |
	t := self target: 8 height: 6 clear: 0.
	self draw: (self quadX0: 1.5 y0: 1.25 x1: 4.5 y1: 3.75 color: 16rFF0000FF mode: 0) on: t.
	px := self pixelsOf: t.
	0 to: 5 do: [:y |
		0 to: 7 do: [:x |
			self assert: (px at: y * 8 + x + 1) equals: (((x between: 1 and: 3) and: [y between: 1 and: 3]) ifTrue: [16rFF0000FF] ifFalse: [0])]]
!
testAdjacentQuadsNeitherOverlapNorLeaveGaps
	"Translucent quads meeting at fractional coordinates on a transparent target: a pixel blended twice would not be the color."
	| t c px |
	t := self target: 7 height: 6 clear: 0.
	c := self word: 64 g: 32 b: 16 a: 128.
	self draw: (self quadX0: 0.3 y0: 0.3 x1: 2.6 y1: 2.6 color: c mode: 0) , (self quadX0: 2.6 y0: 0.3 x1: 5.1 y1: 2.6 color: c mode: 0)
		, (self quadX0: 0.3 y0: 2.6 x1: 2.6 y1: 4.9 color: c mode: 0) , (self quadX0: 5.1 y0: 4.9 x1: 2.6 y1: 2.6 color: c mode: 0) on: t.
	px := self pixelsOf: t.
	0 to: 5 do: [:y |
		0 to: 6 do: [:x |
			self assert: (px at: y * 7 + x + 1) equals: (((x between: 0 and: 4) and: [y between: 0 and: 4]) ifTrue: [c] ifFalse: [0])]]
!
testScissorAndTranslation
	| t px |
	t := self target: 8 height: 8 clear: 0.
	self draw: (self quadX0: -10 y0: -10 x1: 20 y1: 20 color: 16rFF00FF00 mode: 0) on: t scissor: #(2 3 3 2) texture: nil sampler: nil translation: 0 @ 0 pipeline: pipe.
	self draw: (self quadX0: 0 y0: 0 x1: 1 y1: 1 color: 16rFFFF0000 mode: 0) on: t scissor: #(6 6 10 10) texture: nil sampler: nil translation: 6 @ 7 pipeline: pipe.
	px := self pixelsOf: t.
	0 to: 7 do: [:y |
		0 to: 7 do: [:x |
			self assert: (px at: y * 8 + x + 1) equals: (((x between: 2 and: 4) and: [y between: 3 and: 4])
				ifTrue: [16rFF00FF00]
				ifFalse: [(x = 6 and: [y = 7]) ifTrue: [16rFFFF0000] ifFalse: [0]])]]
!
testViewport
	"The viewport maps the uniform's viewport (8 x 6 here) onto its rectangle, and clips."
	| t cmd buf pass ok px |
	t := self target: 8 height: 6 clear: 0.
	cmd := gpu acquireCommandBuffer: dev.
	buf := gpu createBuffer: dev usage: 1 size: 240.
	gpu uploadBuffer: buf data: (self bytes: (self quadX0: -4 y0: 0 x1: 8 y1: 6 color: 16rFF0000FF mode: 0)) count: 240 offset: 0.
	gpu pushUniforms: cmd stage: 0 slot: 0 data: (self floats: #(8 6 0 0)) count: 16.
	pass := gpu beginPass: cmd target: t clear: CPointer null.
	gpu bindPipeline: pass pipeline: pipe.
	gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0.
	self assert: (gpu setViewport: pass x: 2.0 y: 1.0 width: 4.0 height: 3.0).
	self assert: (gpu draw: pass vertices: 6 first: 0).
	gpu endPass: pass.
	ok := self pointer: 'bool' to: #[0].
	gpu submit: cmd fence: false ok: ok.
	px := self pixelsOf: t.
	0 to: 5 do: [:y |
		0 to: 7 do: [:x |
			self assert: (px at: y * 8 + x + 1) equals: (((x between: 2 and: 5) and: [y between: 1 and: 3]) ifTrue: [16rFF0000FF] ifFalse: [0])]]
!
testGlyphCoverage
	"Mode 1: the color times the R8 coverage, over what is there."
	| cov atlas back t px c |
	cov := #[0 64 128 255 255 0 10 200 1 2 3 4].
	atlas := self textureWidth: 4 height: 3 format: 1 pixels: cov.
	back := self word: 50 g: 100 b: 150 a: 255.
	#(16rFF000000 16r96143264) do: [:color |
		c := color.
		t := self target: 8 height: 5 clear: back.
		self draw: (self quadX0: 2 y0: 1 x1: 6 y1: 4 uv0: 0 uv1: (self uvX: 4 y: 3) color: c mode: 1) on: t texture: atlas sampler: nearest.
		px := self pixelsOf: t.
		0 to: 4 do: [:y |
			0 to: 7 do: [:x |
				self assert: (px at: y * 8 + x + 1) equals: (((x between: 2 and: 5) and: [y between: 1 and: 3])
					ifTrue: [self over: back color: c k: (cov at: y - 1 * 4 + x - 1)]
					ifFalse: [back])]]]
!
testImageOneToOne
	"Mode 2 at whole pixels: the texels (times the color's alpha) over what is there, with either sampler."
	| texels img back t px |
	texels := {self word: 255 g: 0 b: 0 a: 255. self word: 0 g: 100 b: 0 a: 100. 0. self word: 10 g: 20 b: 30 a: 40.
		self word: 1 g: 2 b: 3 a: 255. self word: 200 g: 200 b: 200 a: 200. self word: 0 g: 0 b: 0 a: 255. self word: 255 g: 255 b: 255 a: 255}.
	img := self textureWidth: 4 height: 2 words: texels.
	back := self word: 50 g: 100 b: 150 a: 255.
	{nearest. linear} do: [:sampler |
		#(16rFFFFFFFF 16r80FFFFFF) do: [:color |
			t := self target: 6 height: 4 clear: back.
			self draw: (self quadX0: 1 y0: 1 x1: 5 y1: 3 uv0: 0 uv1: (self uvX: 4 y: 2) color: color mode: 2) on: t texture: img sampler: sampler.
			px := self pixelsOf: t.
			0 to: 3 do: [:y |
				0 to: 5 do: [:x |
					self assert: (px at: y * 6 + x + 1) equals: (((x between: 1 and: 4) and: [y between: 1 and: 2])
						ifTrue: [self over: back color: (texels at: y - 1 * 4 + x) k: (color bitShift: -24)]
						ifFalse: [back])]]]]
!
testImageScaled
	"A 2 x 2 image into 4 x 4 pixels: nearest repeats each texel 2 x 2, linear is bilinear between texel centres (clamped)."
	| texels img t px |
	texels := {self word: 255 g: 0 b: 0 a: 255. self word: 0 g: 255 b: 0 a: 255. self word: 0 g: 0 b: 255 a: 255. self word: 100 g: 100 b: 100 a: 100}.
	img := self textureWidth: 2 height: 2 words: texels.
	t := self target: 4 height: 4 clear: 0.
	self draw: (self quadX0: 0 y0: 0 x1: 4 y1: 4 uv0: 0 uv1: (self uvX: 2 y: 2) color: 16rFFFFFFFF mode: 2) on: t texture: img sampler: nearest.
	px := self pixelsOf: t.
	0 to: 3 do: [:y | 0 to: 3 do: [:x | self assert: (px at: y * 4 + x + 1) equals: (texels at: y // 2 * 2 + (x // 2) + 1)]].
	t := self target: 4 height: 4 clear: 0.
	self draw: (self quadX0: 0 y0: 0 x1: 4 y1: 4 uv0: 0 uv1: (self uvX: 2 y: 2) color: 16rFFFFFFFF mode: 2) on: t texture: img sampler: linear.
	px := self pixelsOf: t.
	0 to: 3 do: [:y |
		0 to: 3 do: [:x |
			self assert: (px at: y * 4 + x + 1) equals: (self bilinear: texels width: 2 height: 2 u: x + 0.5 / 2 v: y + 0.5 / 2)]].
	"clamped at the edge: the corner pixel is its texel"
	self assert: (px at: 1) equals: (texels at: 1)
!
testPremultipliedBlendIsExact
	"Over many colors, coverages and destinations, the blend rounds the exact result once (the SWAR path of a whole coverage too)."
	| random c d k |
	random := Random seed: 4711.
	500 timesRepeat: [
		| a |
		a := (random nextInt: 256) - 1.
		c := self word: (random nextInt: a + 1) - 1 g: (random nextInt: a + 1) - 1 b: (random nextInt: a + 1) - 1 a: a.
		d := random nextInt: 16rFFFFFFFF.
		k := (random nextInt: 256) - 1.
		self assert: (gpu over: d color: c k: k) equals: (self over: d color: c k: k).
		self assert: (gpu over: d color: c) equals: (self over: d color: c k: 255)].
	self assert: (gpu over: 16rFFFFFFFF color: 16r80FFFFFF) equals: 16rFFFFFFFF.
	self assert: (gpu over: 16r12345678 color: 16rFF000000) equals: 16rFF000000
!
testOtherBlends
	"none: the source itself; alpha: straight source alpha."
	gpu instVarNamed: 'rsBlend' put: 0.
	self assert: (gpu blend: 16r12345678 source: 16r80402010 k: 255) equals: 16r80402010.
	self assert: (gpu blend: 16r12345678 source: 16r80402010 k: 0) equals: 0.
	gpu instVarNamed: 'rsBlend' put: 1.
	"s.rgb * s.a + d.rgb * (1 - s.a): (255, 0, 0) at 128/255 over (0, 0, 255, 255)"
	self assert: (gpu blend: 16rFFFF0000 source: 16r800000FF k: 255) equals: (self word: 128 g: 0 b: 127 a: 255)
!
testTrianglesSplitTheirQuadExactly
	"Explicitly positioned triangles (bit 31 of mode) cover what the quad covers, the shared diagonal once."
	| c t px quad |
	c := self word: 64 g: 32 b: 16 a: 128.
	t := self target: 8 height: 6 clear: 0.
	self draw: (self trianglesOfQuadX0: 0.7 y0: 0.7 x1: 5.3 y1: 4.2 u0: 0 v0: 0 u1: 0 v1: 0 color: c mode: 0) on: t.
	px := self pixelsOf: t.
	quad := self target: 8 height: 6 clear: 0.
	self draw: (self quadX0: 0.7 y0: 0.7 x1: 5.3 y1: 4.2 color: c mode: 0) on: quad.
	self assert: px equals: (self pixelsOf: quad).
	self assert: (px select: [:p | p ~= 0]) size equals: 12.
	self assert: (px reject: [:p | p = 0 or: [p = c]]) isEmpty
!
testATriangleFanCoversEachPixelOnce
	"Eight triangles around a point, their edges at every angle: a translucent color blended twice anywhere would show."
	| c t px bytes center corners covered |
	c := self word: 40 g: 30 b: 20 a: 100.
	center := 6.3 @ 5.6.
	corners := (0 to: 8) collect: [:i | center + ((i * Float pi / 4 + 0.3) cos * 5.2 @ ((i * Float pi / 4 + 0.3) sin * 4.7))].
	bytes := ByteArray new: 0.
	1 to: 8 do: [:i |
		bytes := bytes , (self vertexX: center x y: center y u: 0 v: 0 color: c mode: 0)
			, (self vertexX: (corners at: i) x y: (corners at: i) y u: 0 v: 0 color: c mode: 0)
			, (self vertexX: (corners at: i + 1) x y: (corners at: i + 1) y u: 0 v: 0 color: c mode: 0)].
	t := self target: 13 height: 12 clear: 0.
	self draw: bytes on: t.
	px := self pixelsOf: t.
	covered := (px select: [:p | p = c]) size.
	self assert: (px allSatisfy: [:p | p = 0 or: [p = c]]).
	"the octagon's area, about 69 pixels"
	self assert: (covered between: 60 and: 78)
!
testFastPathsDrawLikeTriangles
	"Quads take the row paths; split into explicitly positioned triangles they go pixel by pixel through the general rasterizer and shader: the same pixels."
	| texels img atlas back cases |
	texels := (1 to: 16) collect: [:i | self word: i * 15 g: 255 - (i * 13) b: i * 7 a: 255].
	img := self textureWidth: 4 height: 4 words: texels.
	atlas := self textureWidth: 4 height: 4 format: 1 pixels: ((1 to: 16) collect: [:i | i * 37 \\ 256]) asByteArray.
	back := self word: 50 g: 100 b: 150 a: 255.
	cases := {
		{0. 16r80402010. nil. nil. 0.6. 0.3. 5.7. 4.4. 0. 0. 0. 0}.
		{1. 16rC0603010. atlas. nearest. 1. 1. 5. 5. 0. 0. 4. 4}.
		{2. 16rFFFFFFFF. img. linear. 1. 0. 5. 4. 0. 0. 4. 4}.
		{2. 16rFFFFFFFF. img. linear. 0. 0. 7. 6. 0. 0. 4. 4}.
		{2. 16rFFFFFFFF. img. nearest. 0.5. 0.5. 6.5. 5.5. 0. 0. 4. 4}.
		{3 + (2 bitShift: 8). 16rFF000000. nil. nil. 0.5. 0.25. 7. 6. 0. 0. 0. 0}.
		{4 + (1 bitShift: 8) + (2 bitShift: 16). 16rFF0000FF. nil. nil. 0.5. 0.5. 7. 6. 0. 0. 0. 0}}.
	cases do: [:k |
		| quad tris |
		quad := self target: 8 height: 7 clear: back.
		self draw: (self quadX0: (k at: 5) y0: (k at: 6) x1: (k at: 7) y1: (k at: 8)
			uv0: (self uvX: (k at: 9) y: (k at: 10)) uv1: (self uvX: (k at: 11) y: (k at: 12)) color: (k at: 2) mode: (k at: 1))
			on: quad texture: (k at: 3) sampler: (k at: 4).
		tris := self target: 8 height: 7 clear: back.
		self draw: (self trianglesOfQuadX0: (k at: 5) y0: (k at: 6) x1: (k at: 7) y1: (k at: 8) u0: (k at: 9) v0: (k at: 10) u1: (k at: 11) v1: (k at: 12) color: (k at: 2) mode: (k at: 1))
			on: tris texture: (k at: 3) sampler: (k at: 4).
		self assert: (self pixelsOf: quad) equals: (self pixelsOf: tris)]
!
testPatterns
	"Halftone, checkerboard and the stripes, from the quad's top-left, per the shader."
	#(#(3 0 1) #(3 1 1) #(3 0 2) #(4 0 1) #(4 1 2) #(4 2 2) #(4 2 1)) do: [:p |
		| t px |
		t := self target: 9 height: 8 clear: 0.
		self draw: (self quadX0: 1 y0: 2 x1: 9 y1: 8 color: 16rFF000000 mode: (p first + ((p at: 3) bitShift: 8) + ((p at: 2) bitShift: 16))) on: t.
		px := self pixelsOf: t.
		0 to: 7 do: [:y |
			0 to: 8 do: [:x |
				self assert: (px at: y * 9 + x + 1)
					equals: ((x >= 1 and: [y >= 2 and: [self patternOn: p first variant: (p at: 2) cell: (p at: 3) dx: x - 1 dy: y - 2]]) ifTrue: [16rFF000000] ifFalse: [0])]]]
!
testAntialiasedLineCoverage
	"Mode 5, a horizontal line at y = 4 one pixel wide as Canvas records it: half covers the rows above and below."
	| canvas list px |
	canvas := (self graphics: #Canvas) extent: 10 @ 8 scale: 1.
	canvas line: 0 @ 4 to: 10 @ 4.001 color: (self graphics: #Color) black width: 1.
	list := canvas displayList.
	px := self render: list width: 10 height: 8 clear: (self graphics: #Color) white.
	0 to: 7 do: [:y |
		1 to: 8 do: [:x |
			| v |
			v := (px at: y * 10 + x + 1) bitAnd: 255.
			(y = 3 or: [y = 4])
				ifTrue: [self assert: (v between: 126 and: 129)]
				ifFalse: [self assert: v equals: 255]]]
!
testBlitConvertsAndScales
	| texels src bgra r8 dst px ok |
	texels := {self word: 1 g: 2 b: 3 a: 4. self word: 5 g: 6 b: 7 a: 8. self word: 9 g: 10 b: 11 a: 12. self word: 13 g: 14 b: 15 a: 16}.
	src := self textureWidth: 2 height: 2 words: texels.
	bgra := self textureWidth: 2 height: 2 format: 3.
	self blit: src rect: #(0 0 2 2) to: bgra rect: #(0 0 2 2) linear: false.
	"downloads are RGBA8"
	self assert: (self pixelsOf: bgra) equals: texels.
	r8 := self textureWidth: 2 height: 1 format: 1 pixels: #[7 200].
	dst := self target: 2 height: 1 clear: 0.
	self blit: r8 rect: #(0 0 2 1) to: dst rect: #(0 0 2 1) linear: true.
	self assert: (self pixelsOf: dst) equals: {self word: 7 g: 0 b: 0 a: 255. self word: 200 g: 0 b: 0 a: 255}.
	dst := self target: 4 height: 4 clear: 0.
	self blit: src rect: #(0 0 2 2) to: dst rect: #(0 0 4 4) linear: false.
	px := self pixelsOf: dst.
	0 to: 3 do: [:y | 0 to: 3 do: [:x | self assert: (px at: y * 4 + x + 1) equals: (texels at: y // 2 * 2 + (x // 2) + 1)]].
	dst := self target: 4 height: 4 clear: 0.
	self blit: src rect: #(0 0 2 2) to: dst rect: #(0 0 4 4) linear: true.
	px := self pixelsOf: dst.
	0 to: 3 do: [:y | 0 to: 3 do: [:x | self assert: (px at: y * 4 + x + 1) equals: (self bilinear: texels width: 2 height: 2 u: x + 0.5 / 2 v: y + 0.5 / 2)]].
	"a part, into a part"
	dst := self target: 3 height: 3 clear: 0.
	self blit: src rect: #(1 0 1 2) to: dst rect: #(2 1 1 2) linear: false.
	px := self pixelsOf: dst.
	self assert: px equals: {0. 0. 0. 0. 0. texels at: 2. 0. 0. texels at: 4}.
	ok := gpu blit: (gpu acquireCommandBuffer: dev) source: 999 rect: (self ints: #(0 0 1 1)) destination: dst rect: (self ints: #(0 0 1 1)) linear: false.
	self deny: ok.
	self assert: self lastError equals: 'bad texture handle 999'
!
blit: src rect: sr to: dst rect: dr linear: aBoolean
	| cmd ok |
	cmd := gpu acquireCommandBuffer: dev.
	self assert: (gpu blit: cmd source: src rect: (self ints: sr) destination: dst rect: (self ints: dr) linear: aBoolean).
	ok := self pointer: 'bool' to: #[0].
	gpu submit: cmd fence: false ok: ok.
	self assert: ok value
!
testUploadAndDownloadRegions
	| t p |
	t := self textureWidth: 4 height: 3 words: (1 to: 12) asArray.
	self assert: (gpu uploadTexture: t data: (self bytes: (self wordBytes: #(100 101 0 102 103))) length: 20 x: 1 y: 1 width: 2 height: 2 bytesPerRow: 12).
	self assert: (self pixelsOf: t) equals: #(1 2 3 4 5 100 101 8 9 102 103 12).
	p := self bytes: (ByteArray new: 8).
	self assert: (gpu download: t x: 2 y: 1 width: 2 height: 1 into: p length: 8).
	self assert: (memory bytesAt: (memory addressOf: p) count: 8) equals: (self wordBytes: #(101 8)).
	self deny: (gpu download: t x: 3 y: 1 width: 2 height: 1 into: p length: 8).
	self assert: self lastError equals: 'bad download region'.
	self deny: (gpu download: t x: 0 y: 0 width: 2 height: 1 into: p length: 7).
	self deny: (gpu uploadTexture: t data: p length: 8 x: 0 y: 0 width: 3 height: 1 bytesPerRow: 12).
	self assert: self lastError equals: 'bad texture upload region'
!
testClearAndAFence
	| t cmd pass ok f |
	t := self textureWidth: 2 height: 2 format: 2.
	cmd := gpu acquireCommandBuffer: dev.
	pass := gpu beginPass: cmd target: t clear: (self floats: #(1.0 0.5 0.0 1.0)).
	self assert: (gpu endPass: pass).
	ok := self pointer: 'bool' to: #[0].
	f := gpu submit: cmd fence: true ok: ok.
	self assert: ok value.
	self assert: (gpu fenceDone: f) equals: 1.
	self assert: (gpu waitFence: f).
	self assert: (gpu fenceElapsed: f) >= 0.
	self assert: (self pixelsOf: t) equals: (Array new: 4 withAll: (self word: 255 g: 128 b: 0 a: 255)).
	self assert: (gpu releaseHandle: f).
	self assert: (gpu fenceDone: f) equals: -1.
	self assert: (gpu fenceElapsed: f) equals: -2
!
testTheSwapchainIsPresentedOnSubmit
	| win cmd w h sw f pass buf ok frame |
	win := sim windows.
	self deny: (gpu claimWindow: dev window: 2).
	self assert: (gpu claimWindow: dev window: 1).
	self assert: (gpu claimWindow: dev window: 1).
	self assert: (gpu swapchainFormat: dev window: 1) equals: 3.
	cmd := gpu acquireCommandBuffer: dev.
	w := self pointer: 'int' to: (ByteArray new: 4).
	h := self pointer: 'int' to: (ByteArray new: 4).
	sw := gpu acquireSwapchain: cmd window: 1 width: w height: h.
	self assert: sw > 0.
	self assert: w value equals: 6.
	self assert: h value equals: 4.
	f := self pointer: 'int' to: (ByteArray new: 4).
	self assert: (gpu textureSize: sw width: w height: h format: f).
	self assert: f value equals: 3.
	"a draw into the BGRA8 back buffer"
	buf := gpu createBuffer: dev usage: 1 size: 240.
	gpu uploadBuffer: buf data: (self bytes: (self quadX0: 1 y0: 1 x1: 3 y1: 2 color: (self word: 10 g: 20 b: 30 a: 255) mode: 0)) count: 240 offset: 0.
	gpu pushUniforms: cmd stage: 0 slot: 0 data: (self floats: #(6 4 0 0)) count: 16.
	pass := gpu beginPass: cmd target: sw clear: (self floats: #(0.0 0.0 1.0 1.0)).
	gpu bindPipeline: pass pipeline: pipe.
	gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0.
	self assert: (gpu draw: pass vertices: 6 first: 0).
	gpu endPass: pass.
	self assert: win frames isEmpty.
	ok := self pointer: 'bool' to: #[0].
	gpu submit: cmd fence: false ok: ok.
	self assert: ok value.
	self assert: win frames size equals: 1.
	frame := win frames first.
	self assert: (frame copyFrom: 1 to: 3) equals: #(1 6 4).
	"BGRA8: blue, then the quad's (30, 20, 10)"
	self assert: ((frame at: 4) copyFrom: 1 to: 4) equals: #[255 0 0 255].
	self assert: ((frame at: 4) copyFrom: 6 * 4 + 5 to: 6 * 4 + 12) equals: #[30 20 10 255 30 20 10 255].
	"the swapchain texture ended with the command buffer; a minimized window has none (and no error)"
	self deny: (gpu releaseHandle: sw).
	win width: 0 height: 0.
	cmd := gpu acquireCommandBuffer: dev.
	self assert: (gpu acquireSwapchain: cmd window: 1 width: w height: h) equals: 0.
	self assert: self lastError equals: ''.
	gpu windowClosing: 1.
	self assert: (gpu acquireSwapchain: cmd window: 1 width: w height: h) equals: 0.
	self assert: self lastError equals: 'the window is not claimed'
!
testOnlyTheRenderersPipeline
	| vs fs |
	self assert: pipe > 0.
	self assert: (memory stringAt: (gpu shaderLanguage: dev)) equals: 'software'.
	vs := gpu createShader: dev source: 'v' entry: 'main' stage: 0 samplers: 0 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
	fs := gpu createShader: dev source: 'f' entry: 'main' stage: 1 samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
	self assert: (gpu createPipeline: dev vertexShader: vs fragmentShader: fs stride: 0 attributes: (self attributes: #()) count: 0 primitive: 0 blend: 0 targetFormat: 2) equals: 0.
	self assert: self lastError equals: 'the software GPU runs the Renderer''s shader only'.
	self assert: (gpu createPipeline: dev vertexShader: fs fragmentShader: vs stride: 40 attributes: (self attributes: #(4 0 7 16 7 20 5 24 7 28 2 32)) count: 6 primitive: 0 blend: 2 targetFormat: 2) equals: 0.
	self assert: (self pipelineBlend: 0) > 0
!
testHandles
	| counts t cmd pass |
	counts := [| out | out := self pointer: 'int64_t' to: (ByteArray new: 56). gpu handleCounts: out. (0 to: 6) collect: [:i | out at: i]].
	self assert: counts value equals: #(1 2 1 0 2 0 0).
	t := self textureWidth: 1 height: 1 format: 2.
	cmd := gpu acquireCommandBuffer: dev.
	pass := gpu beginPass: cmd target: t clear: CPointer null.
	self assert: counts value equals: #(1 2 1 1 2 0 0).
	self deny: (gpu releaseHandle: pass).
	self assert: self lastError equals: 'pass/swapchain handles end with their command buffer'.
	self assert: (gpu releaseHandle: cmd).
	self deny: (gpu endPass: pass).
	self assert: self lastError equals: 'bad render pass handle ' , pass printString.
	self assert: (gpu releaseHandle: dev).
	self assert: counts value equals: #(0 0 0 0 0 0 0).
	self assert: (gpu createTexture: dev width: 1 height: 1 format: 2 usage: 1) equals: 0.
	self assert: self lastError equals: 'bad device handle ' , dev printString
!
testADisplayList
	"Text, a rectangle, an image, a line from a Canvas, rendered as the Renderer would."
	| canvas form px font dark |
	font := (self graphics: #Font) ui.
	form := (self graphics: #Form) width: 4 height: 4.
	form fill: (self graphics: #Color) red.
	canvas := (self graphics: #Canvas) extent: 60 @ 30 scale: 1.
	canvas fillRect: (2 @ 2 extent: 10 @ 6) color: (self graphics: #Color) blue.
	canvas image: form in: (40 @ 2 extent: 8 @ 8).
	canvas drawString: 'Hi' at: 2 @ 10 font: font color: (self graphics: #Color) black.
	canvas line: 20 @ 25 to: 58 @ 12 color: (self graphics: #Color) black width: 1.
	px := self render: canvas displayList width: 60 height: 30 clear: (self graphics: #Color) white.
	self assert: (px at: 3 * 60 + 5 + 1) equals: 16rFFFF0000.
	self assert: (px at: 1) equals: 16rFFFFFFFF.
	self assert: (px at: 5 * 60 + 44 + 1) equals: 16rFF0000FF.
	dark := ((10 to: 10 + font lineHeight - 1) inject: 0 into: [:n :y |
		n + ((2 to: 20) count: [:x | ((px at: y * 60 + x + 1) bitAnd: 255) < 128])]).
	self assert: dark > 10.
	self assert: ((20 to: 58) count: [:x | (0 to: 29) anySatisfy: [:y | ((px at: y * 60 + x + 1) bitAnd: 255) < 200]]) > 30
! !
