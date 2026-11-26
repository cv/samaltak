Object subclass: #SoftwareGPUTestDisplay
	instanceVariableNames: 'width height frames'
	classVariableNames: ''
	package: 'Tests-Graphics'!

SoftwareGPUTestDisplay comment: 'The display of a SoftwareGPU under test: window 1, width x height pixels; presentWindow:pixels:width:height: keeps the frames ({window. width. height. BGRA8 bytes}).'!

!SoftwareGPUTestDisplay methodsFor: 'accessing'!
initialize
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

!SoftwareGPUTestDisplay methodsFor: 'windows'!
openWindow: w height: h title: aString flags: flags
	^1
!
closeWindow: window
!
keepsWindowOpen: window
	"Like the firmware's screen: every window is window 1."
	^true
!
windowSize: window
	window = 1 ifFalse: [^self error: 'no such window'].
	^{width. height}
!
windowPixelSize: window
	^self windowSize: window
!
windowDisplayScale: window
	^1.0
!
window: window icon: aByteArray width: w
	^false
!
presentWindow: window pixels: address width: w height: h
	frames add: {window. w. h. Machine bytesAt: address count: w * h * 4}
!
presentWindow: window pixels: address width: w height: h rects: anArray
	"Damage-limited: the frame and the rectangles that changed."
	frames add: {window. w. h. Machine bytesAt: address count: w * h * 4. anArray}
! !

TestCase subclass: #SoftwareGPUTest
	instanceVariableNames: 'display gpu dev pipe nearest linear'
	classVariableNames: ''
	package: 'Tests-Graphics'!

SoftwareGPUTest comment: 'SoftwareGPU, the software GPU device (UEFI''s), on the raster primitives of this VM: coverage and the fill rule at fractional coordinates, scissor, glyph coverage, images 1:1 and scaled, the blend maths against exact fractions, triangles (bit 31 of mode) against the quads they split, the patterns against the shader''s formulas, antialiased lines, blits, downloads, the swapchain, the pipeline it refuses, handles; and real DisplayLists of a Canvas, through the Renderer too.

Colors are RGBA8 words, red in the low byte (premultiplied, as the vertex format and RGBA8 textures have them).'!

!SoftwareGPUTest methodsFor: 'running'!
setUp
	display := SoftwareGPUTestDisplay new.
	gpu := self gpuOn: display.
	dev := gpu createDevice: false.
	pipe := self pipelineBlend: 2.
	nearest := gpu createSampler: dev linear: false repeat: false.
	linear := gpu createSampler: dev linear: true repeat: false
!
tearDown
	(gpu liveObjects includes: #device) ifTrue: [gpu release: dev]
! !

!SoftwareGPUTest methodsFor: 'objects'!
gpuOn: aDisplay
	"The device under test (subclasses: another SoftwareGPU)."
	^SoftwareGPU on: aDisplay
!
shaderLanguage
	"What the device under test answers for shaderLanguage:."
	^'software'
!
isSynchronous
	"Whether the device under test has done the work when submit answers (a SoftwareGPU)."
	^true
!
pipelineBlend: blend
	| vs fs |
	vs := gpu createShader: dev source: 'vertex' entry: 'vmain' stage: 0 samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
	fs := gpu createShader: dev source: 'fragment' entry: 'fmain' stage: 1 samplers: 1 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
	^gpu createPipeline: dev vertex: vs fragment: fs stride: 40 attributes: #(4 0 7 16 7 20 5 24 7 28 2 32) primitive: 0 blend: blend format: 2
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
	gpu uploadTexture: t bytes: aByteArray x: 0 y: 0 width: w height: h bytesPerRow: aByteArray size // h.
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
floats: anArray
	| b |
	b := ByteArray new: anArray size * 4.
	anArray doWithIndex: [:f :i | b float32At: i * 4 - 3 put: f asFloat].
	^b
!
pixelsOf: tex
	"The texture's pixels as RGBA words (or bytes for R8)."
	| size n bytes |
	size := gpu textureSize: tex.
	n := size first * (size at: 2) * (size last = 1 ifTrue: [1] ifFalse: [4]).
	bytes := gpu download: tex x: 0 y: 0 width: size first height: (size at: 2) into: (ByteArray new: n).
	size last = 1 ifTrue: [^bytes].
	^(1 to: n by: 4) collect: [:i | bytes uint32At: i]
!
target: w height: h clear: aWordOrNil
	"An RGBA8 target of w x h pixels, all aWordOrNil (or zero)."
	^self textureWidth: w height: h words: (Array new: w * h withAll: (aWordOrNil ifNil: [0]))
!
failure: aBlock is: aString
	self should: aBlock raise: GPUError withExceptionDo: [:e | self assert: e platformLastError equals: aString]
! !

!SoftwareGPUTest methodsFor: 'vertices'!
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

!SoftwareGPUTest methodsFor: 'drawing'!
draw: vertexBytes on: tex
	^self draw: vertexBytes on: tex scissor: nil texture: nil sampler: nil translation: 0 @ 0 pipeline: pipe
!
draw: vertexBytes on: tex texture: t sampler: s
	^self draw: vertexBytes on: tex scissor: nil texture: t sampler: s translation: 0 @ 0 pipeline: pipe
!
draw: vertexBytes on: tex scissor: anArrayOrNil texture: t sampler: s translation: aPoint pipeline: aPipeline
	"One command buffer as the Renderer encodes it: the viewport uniform, a pass that loads, the scissor, the texture, one draw."
	| size cmd buf pass |
	size := gpu textureSize: tex.
	cmd := gpu acquireCommandBuffer: dev.
	buf := gpu createBuffer: dev usage: 1 size: vertexBytes size.
	gpu uploadBuffer: buf bytes: vertexBytes count: vertexBytes size offset: 0.
	gpu pushUniforms: cmd stage: 0 slot: 0 bytes: (self floats: {size first. size at: 2. aPoint x. aPoint y}).
	pass := gpu beginPass: cmd target: tex clear: nil.
	gpu bindPipeline: pass pipeline: aPipeline.
	gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0.
	anArrayOrNil isNil ifFalse: [
		gpu setScissor: pass x: anArrayOrNil first y: (anArrayOrNil at: 2) width: (anArrayOrNil at: 3) height: (anArrayOrNil at: 4)].
	t isNil ifFalse: [gpu bindTexture: pass slot: 0 texture: t sampler: s].
	gpu draw: pass count: vertexBytes size // 40 first: 0.
	gpu endPass: pass.
	self assert: (gpu submit: cmd fence: false) isNil.
	gpu release: buf
!
render: aDisplayList width: w height: h clear: aColor
	"Render aDisplayList as the Renderer does (one draw per batch, its texture, scissor and translation); answer the RGBA words."
	| target cmd buf pass textures white uniforms tx ty |
	target := self textureWidth: w height: h format: 2.
	white := self textureWidth: 1 height: 1 words: #(16rFFFFFFFF).
	textures := aDisplayList batches collect: [:b | self textureFor: b texture white: white].
	cmd := gpu acquireCommandBuffer: dev.
	buf := gpu createBuffer: dev usage: 1 size: (aDisplayList byteCount max: 40).
	gpu uploadBuffer: buf bytes: aDisplayList vertices count: aDisplayList byteCount offset: 0.
	uniforms := [:x :y | self floats: {w. h. x. y}].
	tx := ty := 0.
	gpu pushUniforms: cmd stage: 0 slot: 0 bytes: (uniforms value: 0 value: 0).
	pass := gpu beginPass: cmd target: target clear: aColor asArray.
	gpu bindPipeline: pass pipeline: pipe.
	gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0.
	aDisplayList batches doWithIndex: [:b :i |
		| s |
		s := b scissor ifNil: [{0. 0. w. h}].
		gpu setScissor: pass x: (s at: 1) y: (s at: 2) width: (s at: 3) height: (s at: 4).
		(b dx = tx and: [b dy = ty]) ifFalse: [
			tx := b dx.
			ty := b dy.
			gpu pushUniforms: pass stage: 0 slot: 0 bytes: (uniforms value: tx value: ty)].
		gpu bindTexture: pass slot: 0 texture: (textures at: i) sampler: ((b texture isNil or: [b texture isLinearFiltered]) ifTrue: [linear] ifFalse: [nearest]).
		gpu draw: pass count: b count first: b first].
	gpu endPass: pass.
	gpu submit: cmd fence: false.
	^self pixelsOf: target
!
textureFor: aTextureSource white: white
	aTextureSource isNil ifTrue: [^white].
	(aTextureSource isKindOf: GlyphAtlasPage) ifTrue: [
		^self textureWidth: aTextureSource size height: aTextureSource size format: 1 pixels: aTextureSource pixels].
	^self textureWidth: aTextureSource width height: aTextureSource height format: 2 pixels: aTextureSource asByteArray
!
blit: src rect: sr to: dst rect: dr linear: aBoolean
	| cmd |
	cmd := gpu acquireCommandBuffer: dev.
	gpu blit: cmd source: src rect: sr destination: dst rect: dr linear: aBoolean.
	gpu submit: cmd fence: false
! !

!SoftwareGPUTest methodsFor: 'references'!
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

!SoftwareGPUTest methodsFor: 'tests'!
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
	| t cmd buf pass px |
	t := self target: 8 height: 6 clear: 0.
	cmd := gpu acquireCommandBuffer: dev.
	buf := gpu createBuffer: dev usage: 1 size: 240.
	gpu uploadBuffer: buf bytes: (self quadX0: -4 y0: 0 x1: 8 y1: 6 color: 16rFF0000FF mode: 0) count: 240 offset: 0.
	gpu pushUniforms: cmd stage: 0 slot: 0 bytes: (self floats: #(8 6 0 0)).
	pass := gpu beginPass: cmd target: t clear: nil.
	gpu bindPipeline: pass pipeline: pipe.
	gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0.
	gpu setViewport: pass x: 2.0 y: 1.0 width: 4.0 height: 3.0.
	gpu draw: pass count: 6 first: 0.
	gpu endPass: pass.
	gpu submit: cmd fence: false.
	px := self pixelsOf: t.
	0 to: 5 do: [:y |
		0 to: 7 do: [:x |
			self assert: (px at: y * 8 + x + 1) equals: (((x between: 2 and: 5) and: [y between: 1 and: 3]) ifTrue: [16rFF0000FF] ifFalse: [0])]]
!
testGlyphCoverage
	"Mode 1: the color times the R8 coverage, over what is there."
	| cov atlas back t px |
	cov := #[0 64 128 255 255 0 10 200 1 2 3 4].
	atlas := self textureWidth: 4 height: 3 format: 1 pixels: cov.
	back := self word: 50 g: 100 b: 150 a: 255.
	#(16rFF000000 16r96143264) do: [:c |
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
	"Over many colors, coverages and destinations, the blend rounds the exact result once: a whole coverage (solid quads, two lanes at a time) and a partial one (glyph quads of one texel)."
	| random n ds cs ks solid glyph atlas quads |
	random := Random seed: 4711.
	n := 300.
	ds := (1 to: n) collect: [:i | random nextInt: 16rFFFFFFFF].
	cs := (1 to: n) collect: [:i | | a |
		a := (random nextInt: 256) - 1.
		self word: (random nextInt: a + 1) - 1 g: (random nextInt: a + 1) - 1 b: (random nextInt: a + 1) - 1 a: a].
	ks := (1 to: n) collect: [:i | (random nextInt: 256) - 1].
	atlas := self textureWidth: n height: 1 format: 1 pixels: ks asByteArray.
	solid := self textureWidth: n height: 1 words: ds.
	glyph := self textureWidth: n height: 1 words: ds.
	quads := ByteArray new: 0.
	1 to: n do: [:i | quads := quads , (self quadX0: i - 1 y0: 0 x1: i y1: 1 color: (cs at: i) mode: 0)].
	self draw: quads on: solid.
	quads := ByteArray new: 0.
	1 to: n do: [:i | quads := quads , (self quadX0: i - 1 y0: 0 x1: i y1: 1 uv0: (self uvX: i - 1 y: 0) uv1: (self uvX: i y: 1) color: (cs at: i) mode: 1)].
	self draw: quads on: glyph texture: atlas sampler: nearest.
	(self pixelsOf: solid) doWithIndex: [:p :i | self assert: p equals: (self over: (ds at: i) color: (cs at: i) k: 255)].
	(self pixelsOf: glyph) doWithIndex: [:p :i |
		self assert: p equals: ((ks at: i) = 0 ifTrue: [ds at: i] ifFalse: [self over: (ds at: i) color: (cs at: i) k: (ks at: i)])].
	solid := self target: 2 height: 1 clear: 16rFFFFFFFF.
	self draw: (self quadX0: 0 y0: 0 x1: 1 y1: 1 color: 16r80FFFFFF mode: 0) on: solid.
	self assert: (self pixelsOf: solid) first equals: 16rFFFFFFFF
!
testOtherBlends
	"none: the source itself (times the coverage); alpha: straight source alpha."
	| t |
	t := self target: 2 height: 1 clear: 16r12345678.
	self draw: (self quadX0: 0 y0: 0 x1: 1 y1: 1 color: 16r80402010 mode: 0) on: t scissor: nil texture: nil sampler: nil translation: 0 @ 0 pipeline: (self pipelineBlend: 0).
	self assert: (self pixelsOf: t) equals: {16r80402010. 16r12345678}.
	t := self target: 1 height: 1 clear: (self word: 0 g: 0 b: 255 a: 255).
	"s.rgb * s.a + d.rgb * (1 - s.a): (255, 0, 0) at 128/255 over (0, 0, 255, 255)"
	self draw: (self quadX0: 0 y0: 0 x1: 1 y1: 1 color: 16r800000FF mode: 0) on: t scissor: nil texture: nil sampler: nil translation: 0 @ 0 pipeline: (self pipelineBlend: 1).
	self assert: (self pixelsOf: t) equals: {self word: 128 g: 0 b: 127 a: 255}
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
	| canvas px |
	canvas := Canvas extent: 10 @ 8 scale: 1.
	canvas line: 0 @ 4 to: 10 @ 4.001 color: Color black width: 1.
	px := self render: canvas displayList width: 10 height: 8 clear: Color white.
	0 to: 7 do: [:y |
		1 to: 8 do: [:x |
			| v |
			v := (px at: y * 10 + x + 1) bitAnd: 255.
			(y = 3 or: [y = 4])
				ifTrue: [self assert: (v between: 126 and: 129)]
				ifFalse: [self assert: v equals: 255]]]
!
testBlitConvertsAndScales
	| texels src bgra r8 dst px |
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
	self failure: [gpu blit: (gpu acquireCommandBuffer: dev) source: 999 rect: #(0 0 1 1) destination: dst rect: #(0 0 1 1) linear: false]
		is: 'bad texture handle 999'
!
testUploadAndDownloadRegions
	| t b |
	t := self textureWidth: 4 height: 3 words: (1 to: 12) asArray.
	gpu uploadTexture: t bytes: (self wordBytes: #(100 101 0 102 103)) x: 1 y: 1 width: 2 height: 2 bytesPerRow: 12.
	self assert: (self pixelsOf: t) equals: #(1 2 3 4 5 100 101 8 9 102 103 12).
	b := ByteArray new: 8.
	gpu download: t x: 2 y: 1 width: 2 height: 1 into: b.
	self assert: b equals: (self wordBytes: #(101 8)).
	self failure: [gpu download: t x: 3 y: 1 width: 2 height: 1 into: b] is: 'bad download region'.
	self failure: [gpu download: t x: 0 y: 0 width: 2 height: 1 into: (ByteArray new: 7)] is: 'bad download region'.
	self failure: [gpu uploadTexture: t bytes: b x: 0 y: 0 width: 3 height: 1 bytesPerRow: 12] is: 'bad texture upload region'.
	"a Form's Bitmap uploads as it is"
	gpu uploadTexture: t bytes: (Bitmap new: 2 withAll: 7) x: 0 y: 2 width: 2 height: 1 bytesPerRow: 8.
	self assert: (self pixelsOf: t) equals: #(1 2 3 4 5 100 101 8 7 7 103 12)
!
testClearAndAFence
	| t cmd pass f |
	t := self textureWidth: 2 height: 2 format: 2.
	cmd := gpu acquireCommandBuffer: dev.
	pass := gpu beginPass: cmd target: t clear: #(1.0 0.5 0.0 1.0).
	gpu endPass: pass.
	f := gpu submit: cmd fence: true.
	self isSynchronous ifTrue: [self assert: (gpu fenceDone: f)].
	gpu waitFence: f.
	self assert: (gpu fenceDone: f).
	self assert: (gpu fenceElapsed: f) >= 0.
	self assert: (self pixelsOf: t) equals: (Array new: 4 withAll: (self word: 255 g: 128 b: 0 a: 255)).
	gpu release: f.
	self failure: [gpu fenceDone: f] is: 'bad fence handle ' , f printString
!
testFirmwareBltsMerge
	"FirmwareScreen merges a frame's damaged rectangles into at most four Blts: near ones always, far ones by least waste."
	| near far merged |
	near := FirmwareScreen mergeBlts: {10 @ 10 extent: 20 @ 16. 40 @ 10 extent: 20 @ 16}.
	self assert: near size equals: 1.
	self assert: near first equals: (10 @ 10 corner: 60 @ 26).
	far := (0 to: 5) collect: [:i | (i * 300) @ (i * 150) extent: 20 @ 20].
	merged := FirmwareScreen mergeBlts: far.
	self assert: merged size equals: 4.
	far do: [:r | self assert: (merged anySatisfy: [:m | m containsRect: r])].
	self assert: (FirmwareScreen mergeBlts: {0 @ 0 extent: 10 @ 10. 1000 @ 900 extent: 10 @ 10}) size equals: 2
!
testPresentDamageKeepsTheBackBuffer
	"The back buffer keeps the last frame: a frame that blits and presents only its damage hands the display those rectangles."
	| cmd sw tex |
	gpu claim: dev window: 1.
	self assert: (gpu swapchainKeepsContents: dev window: 1).
	tex := gpu createTexture: dev width: 6 height: 4 format: 2 usage: 3.
	gpu uploadTexture: tex bytes: (ByteArray new: 96 withAll: 200) x: 0 y: 0 width: 6 height: 4 bytesPerRow: 24.
	cmd := gpu acquireCommandBuffer: dev.
	sw := gpu acquireSwapchain: cmd window: 1.
	gpu blit: cmd source: tex rect: #(0 0 6 4) destination: sw first rect: #(0 0 6 4) linear: false.
	gpu submit: cmd fence: false.
	self assert: display frames last size equals: 4.
	gpu uploadTexture: tex bytes: (ByteArray new: 4 withAll: 9) x: 2 y: 1 width: 1 height: 1 bytesPerRow: 4.
	cmd := gpu acquireCommandBuffer: dev.
	sw := gpu acquireSwapchain: cmd window: 1.
	gpu blit: cmd source: tex rect: #(2 1 1 1) destination: sw first rect: #(2 1 1 1) linear: false.
	gpu presentDamage: cmd rects: #(#(2 1 1 1)).
	gpu submit: cmd fence: false.
	self assert: display frames size equals: 2.
	self assert: display frames last last equals: #(#(2 1 1 1)).
	"the pixel blitted, the rest kept from the first frame"
	self assert: ((display frames last at: 4) copyFrom: 1 * 24 + 9 to: 1 * 24 + 12) equals: #[9 9 9 9].
	self assert: ((display frames last at: 4) copyFrom: 1 to: 4) equals: #[200 200 200 200]
!
testPresentsOnAKmsScreen
	"The appliance's screen (KmsDisplay; its KmsScreen in memory here, where the dumb buffer would be): a whole frame, then only its damage, reach the buffer, and only the damaged rectangle is flushed (NvComputeGPUTest: the raster kernels' frames, as on the Spark)."
	| screen kms old cmd sw tex pixels |
	screen := (KmsScreen path: '/nonexistent/card0') setOffscreen: 6 @ 4; yourself.
	kms := KmsDisplay new setScreen: screen.
	kms instVarNamed: #open put: true.
	old := gpu instVarNamed: #display.
	gpu instVarNamed: #display put: kms.
	[gpu claim: dev window: 1.
	tex := gpu createTexture: dev width: 6 height: 4 format: 2 usage: 3.
	gpu uploadTexture: tex bytes: (ByteArray new: 96 withAll: 200) x: 0 y: 0 width: 6 height: 4 bytesPerRow: 24.
	cmd := gpu acquireCommandBuffer: dev.
	sw := gpu acquireSwapchain: cmd window: 1.
	gpu blit: cmd source: tex rect: #(0 0 6 4) destination: sw first rect: #(0 0 6 4) linear: false.
	gpu submit: cmd fence: false.
	gpu waitIdle: dev.
	self assert: (Machine bytesAt: screen frameBuffer count: 8) equals: (ByteArray new: 8 withAll: 200).
	pixels := screen counts at: #pixels.
	gpu uploadTexture: tex bytes: (ByteArray new: 4 withAll: 9) x: 2 y: 1 width: 1 height: 1 bytesPerRow: 4.
	cmd := gpu acquireCommandBuffer: dev.
	sw := gpu acquireSwapchain: cmd window: 1.
	gpu blit: cmd source: tex rect: #(2 1 1 1) destination: sw first rect: #(2 1 1 1) linear: false.
	gpu presentDamage: cmd rects: #(#(2 1 1 1)).
	gpu submit: cmd fence: false.
	gpu waitIdle: dev.
	self assert: (screen counts at: #presents) equals: 1.
	self assert: (screen counts at: #pixels) - pixels equals: 1.
	self assert: (Machine bytesAt: screen frameBuffer + (1 * 6 + 2 * 4) count: 4) equals: #[9 9 9 9].
	self assert: (Machine bytesAt: screen frameBuffer + (1 * 6 + 1 * 4) count: 4) equals: #[200 200 200 200]]
		ensure: [
			gpu instVarNamed: #display put: old.
			screen freeOffscreen]
!
testTheSwapchainIsPresentedOnSubmit
	| cmd sw pass buf frame |
	self should: [gpu claim: dev window: 2] raise: Error.
	gpu claim: dev window: 1.
	gpu claim: dev window: 1.
	self assert: (gpu swapchainFormat: dev window: 1) equals: 3.
	cmd := gpu acquireCommandBuffer: dev.
	sw := gpu acquireSwapchain: cmd window: 1.
	self assert: (sw copyFrom: 2 to: 3) equals: #(6 4).
	self assert: (gpu textureSize: sw first) equals: #(6 4 3).
	"a draw into the BGRA8 back buffer"
	buf := gpu createBuffer: dev usage: 1 size: 240.
	gpu uploadBuffer: buf bytes: (self quadX0: 1 y0: 1 x1: 3 y1: 2 color: (self word: 10 g: 20 b: 30 a: 255) mode: 0) count: 240 offset: 0.
	gpu pushUniforms: cmd stage: 0 slot: 0 bytes: (self floats: #(6 4 0 0)).
	pass := gpu beginPass: cmd target: sw first clear: #(0.0 0.0 1.0 1.0).
	gpu bindPipeline: pass pipeline: pipe.
	gpu bindVertexBuffer: pass slot: 0 buffer: buf offset: 0.
	gpu draw: pass count: 6 first: 0.
	gpu endPass: pass.
	self assert: display frames isEmpty.
	gpu submit: cmd fence: false.
	self assert: display frames size equals: 1.
	frame := display frames first.
	self assert: (frame copyFrom: 1 to: 3) equals: #(1 6 4).
	"BGRA8: blue, then the quad's (30, 20, 10)"
	self assert: ((frame at: 4) copyFrom: 1 to: 4) equals: #[255 0 0 255].
	self assert: ((frame at: 4) copyFrom: 6 * 4 + 5 to: 6 * 4 + 12) equals: #[30 20 10 255 30 20 10 255].
	"the swapchain texture ended with the command buffer; a minimized window has none (and no error)"
	self failure: [gpu release: sw first] is: 'bad GPU handle ' , sw first printString.
	display width: 0 height: 0.
	cmd := gpu acquireCommandBuffer: dev.
	self assert: (gpu acquireSwapchain: cmd window: 1) isNil.
	gpu windowClosed: 1.
	self failure: [gpu acquireSwapchain: cmd window: 1] is: 'the window is not claimed'
!
testClosingASharedWindowKeepsTheClaim
	"On the firmware's screen every window is window 1: one closing (a UI test's in a live World) leaves the World's claim."
	| old cmd |
	old := GPUPlatform display: display device: gpu.
	[gpu claim: dev window: 1.
	 GPUPlatform closeWindow: (GPUPlatform openWindow: 6 height: 4 title: 'test' flags: 0).
	 cmd := gpu acquireCommandBuffer: dev.
	 self assert: (gpu acquireSwapchain: cmd window: 1) notNil.
	 gpu submit: cmd fence: false]
		ensure: [GPUPlatform display: old first device: old last]
!
testOnlyTheRenderersPipeline
	| vs fs |
	self assert: pipe > 0.
	self assert: (gpu shaderLanguage: dev) equals: self shaderLanguage.
	vs := gpu createShader: dev source: 'v' entry: 'main' stage: 0 samplers: 0 uniformBuffers: 0 storageBuffers: 0 storageTextures: 0.
	fs := gpu createShader: dev source: 'f' entry: 'main' stage: 1 samplers: 0 uniformBuffers: 1 storageBuffers: 0 storageTextures: 0.
	self failure: [gpu createPipeline: dev vertex: vs fragment: fs stride: 0 attributes: #() primitive: 0 blend: 0 format: 2]
		is: 'the software GPU runs the Renderer''s shader only'.
	self failure: [gpu createPipeline: dev vertex: fs fragment: vs stride: 40 attributes: #(4 0 7 16 7 20 5 24 7 28 2 32) primitive: 0 blend: 2 format: 2]
		is: 'the software GPU runs the Renderer''s shader only'.
	self assert: (self pipelineBlend: 0) > 0
!
testHandles
	| t cmd pass |
	self assert: gpu liveObjects size equals: 6.
	self assert: (#(#device #shader #pipeline #sampler) collect: [:k | gpu liveObjects occurrencesOf: k]) equals: #(1 2 1 2).
	t := self textureWidth: 1 height: 1 format: 2.
	cmd := gpu acquireCommandBuffer: dev.
	pass := gpu beginPass: cmd target: t clear: nil.
	self assert: (gpu liveObjects occurrencesOf: #pass) equals: 1.
	self failure: [gpu release: pass] is: 'pass/swapchain handles end with their command buffer'.
	gpu release: cmd.
	self failure: [gpu endPass: pass] is: 'bad pass handle ' , pass printString.
	gpu release: dev.
	self assert: gpu liveObjects isEmpty.
	self failure: [gpu createTexture: dev width: 1 height: 1 format: 2 usage: 1] is: 'bad device handle ' , dev printString
!
testADisplayList
	"Text, a rectangle, an image, a line from a Canvas, rendered as the Renderer would."
	| canvas form px font dark |
	font := Font ui.
	form := Form width: 4 height: 4.
	form fill: Color red.
	canvas := Canvas extent: 60 @ 30 scale: 1.
	canvas fillRect: (2 @ 2 extent: 10 @ 6) color: Color blue.
	canvas image: form in: (40 @ 2 extent: 8 @ 8).
	canvas drawString: 'Hi' at: 2 @ 10 font: font color: Color black.
	canvas line: 20 @ 25 to: 58 @ 12 color: Color black width: 1.
	px := self render: canvas displayList width: 60 height: 30 clear: Color white.
	self assert: (px at: 3 * 60 + 5 + 1) equals: 16rFFFF0000.
	self assert: (px at: 1) equals: 16rFFFFFFFF.
	self assert: (px at: 5 * 60 + 44 + 1) equals: 16rFF0000FF.
	dark := ((10 to: 10 + font lineHeight - 1) inject: 0 into: [:n :y |
		n + ((2 to: 20) count: [:x | ((px at: y * 60 + x + 1) bitAnd: 255) < 128])]).
	self assert: dark > 10.
	self assert: ((20 to: 58) count: [:x | (0 to: 29) anySatisfy: [:y | ((px at: y * 60 + x + 1) bitAnd: 255) < 200]]) > 30
!
testTheGPULayerOnASoftwareDevice
	"GPUPlatform's backends: a Renderer on a GPUDevice of a SoftwareGPU draws what the same DisplayList does here, into a Surface and through a swapchain onto the display, as DisplayWindow does."
	| old device canvas form list renderer surface window swapchain cmd swap px frame |
	old := GPUPlatform display: display device: gpu.
	[device := GPUDevice new.
	self assert: device isSoftware equals: self shaderLanguage = 'software'.
	self deny: device buildsShaders.
	form := Form width: 4 height: 4.
	form fill: Color red.
	canvas := Canvas extent: 6 @ 4 scale: 1.
	canvas fillRect: (1 @ 1 extent: 3 @ 2) color: Color blue.
	canvas image: form in: (4 @ 0 extent: 2 @ 2).
	canvas line: 0 @ 3.5 to: 6 @ 3.5 color: Color black width: 1.
	list := canvas displayList.
	renderer := Renderer on: device.
	surface := Surface new setWidth: 6 height: 4 scale: 1 device: device.
	window := HostWindow width: 6 height: 4 title: 'test' flags: 1.
	swapchain := device swapchainFor: window.
	cmd := device commandBuffer.
	renderer render: list into: surface texture clear: Color white commandBuffer: cmd.
	swap := cmd acquireSwapchainTexture: swapchain.
	cmd blit: surface texture to: swap.
	cmd submit.
	px := surface texture download.
	self assert: ((1 to: px size by: 4) collect: [:i | px uint32At: i]) equals: (self render: list width: 6 height: 4 clear: Color white).
	self assert: display frames size equals: 1.
	frame := display frames first last.
	self assert: ((1 to: px size by: 4) collect: [:i | frame uint32At: i]) equals: ((1 to: px size by: 4) collect: [:i |
		((px uint32At: i) bitAnd: 16rFF00FF00) + (((px uint32At: i) bitAnd: 16rFF) bitShift: 16) + (((px uint32At: i) bitShift: -16) bitAnd: 16rFF)])]
		ensure: [GPUPlatform display: old first device: old last]
!
testTheRendererKeepsItsPipelineHere
	"A device that runs the Renderer's shader natively builds no shaders: changed shader source (Renderer shaderSourceChanged) rebuilds nothing, reports nothing and draws the same; a FragmentShader gets no pipeline and no error either (an NvComputeGPU's compiles its GLSL, without an error)."
	| old device canvas list renderer surface before pipeline errors handler image |
	old := GPUPlatform display: display device: gpu.
	handler := Renderer shaderErrorHandler.
	errors := OrderedCollection new.
	Renderer shaderErrorHandler: [:e | errors add: e].
	[device := GPUDevice new.
	self deny: device buildsShaders.
	canvas := Canvas extent: 6 @ 4 scale: 1.
	canvas fillRect: (1 @ 1 extent: 3 @ 2) color: Color blue.
	canvas line: 0 @ 3.5 to: 6 @ 3.5 color: Color black width: 1.
	list := canvas displayList.
	renderer := Renderer on: device.
	surface := Surface new setWidth: 6 height: 4 scale: 1 device: device.
	renderer render: list on: surface clear: Color white.
	before := surface texture download.
	pipeline := renderer pipeline.
	Renderer shaderSourceChanged.
	renderer render: list on: surface clear: Color white.
	self assert: surface texture download equals: before.
	self assert: renderer pipeline == pipeline.
	self assert: renderer pipelineVersion equals: 1.
	self deny: renderer updatePipeline.
	image := (FragmentShader on: device) imageExtent: 2 @ 2 source: 'void main() { fragColor = vec4(1.0); }' uniforms: (ByteArray new: 16).
	canvas := Canvas extent: 6 @ 4 scale: 1.
	canvas image: image in: (0 @ 0 extent: 2 @ 2).
	renderer render: canvas displayList on: surface clear: Color white.
	self assert: errors isEmpty description: 'a shader error was reported']
		ensure: [
			Renderer shaderErrorHandler: handler.
			GPUPlatform display: old first device: old last]
! !
