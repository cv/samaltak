GraphicsTestCase subclass: #RendererTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

RendererTest comment: 'I render small scenes with the GPU into an offscreen Surface and check pixels: rectangle colors and edges, hairlines, text ink, the halftone and stripe patterns, clipping, alpha blending, images and antialiased lines.'!

!RendererTest methodsFor: 'tests'!
testClearAndRectColors
	| form |
	form := self render: [:c | c fillRect: (10 @ 10 corner: 60 @ 40) color: Color ultramarine] extent: 100 @ 50.
	self assert: form extent equals: 200 @ 100.
	self assertPixel: 0 @ 0 in: form is: #(255 255 255 255).
	self assertPixel: 20 @ 20 in: form is: #(27 58 140 255).
	self assertPixel: 119 @ 79 in: form is: #(27 58 140 255).
	self assertPixel: 19 @ 20 in: form is: #(255 255 255 255).
	self assertPixel: 120 @ 20 in: form is: #(255 255 255 255).
	self assertPixel: 20 @ 80 in: form is: #(255 255 255 255)
!
testHairlinesAreTwoDevicePixels
	| form |
	form := self render: [:c |
		c line: 0 @ 20 to: 100 @ 20 color: Color black width: 1.
		c line: 30 @ 0 to: 30 @ 50 color: Color black width: 1] extent: 100 @ 50.
	self assert: (self grayAt: 10 @ 39 in: form) equals: 255.
	self assert: (self grayAt: 10 @ 40 in: form) equals: 0.
	self assert: (self grayAt: 10 @ 41 in: form) equals: 0.
	self assert: (self grayAt: 10 @ 42 in: form) equals: 255.
	self assert: (self grayAt: 59 @ 10 in: form) equals: 255.
	self assert: (self grayAt: 60 @ 10 in: form) equals: 0.
	self assert: (self grayAt: 61 @ 10 in: form) equals: 0.
	self assert: (self grayAt: 62 @ 10 in: form) equals: 255
!
testHalftonePeriod
	"The desk pattern: in every 4×4 device-pixel cell (2×2 points) the bottom-right 2×2 pixels are black."
	| form |
	form := self render: [:c | c pattern: #halftone in: (10 @ 10 extent: 20 @ 20)] extent: 50 @ 50.
	0 to: 39 do: [:dy | 0 to: 39 do: [:dx |
		| expected |
		expected := ((dx // 2) odd and: [(dy // 2) odd]) ifTrue: [0] ifFalse: [255].
		self assert: (self grayAt: 20 + dx @ (20 + dy) in: form) equals: expected]].
	self assert: (self grayAt: 19 @ 23 in: form) equals: 255.
	self assert: (self grayAt: 60 @ 23 in: form) equals: 255
!
testStripes
	| form |
	form := self render: [:c | c pattern: #stripes in: (0 @ 0 extent: 10 @ 11)] extent: 20 @ 20.
	#(0 1 4 5 20 21) do: [:y | self assert: (self grayAt: 5 @ y in: form) equals: 0].
	#(2 3 6 7 19 23) do: [:y | self assert: (self grayAt: 5 @ y in: form) equals: 255].
	self assert: (self grayAt: 25 @ 0 in: form) equals: 255
!
testClipping
	| form |
	form := self render: [:c |
		c clip: (10 @ 10 extent: 10 @ 5) during: [
			c fillRect: (0 @ 0 extent: 50 @ 50) color: Color red]] extent: 50 @ 50.
	self assertPixel: 20 @ 20 in: form is: #(255 0 0 255).
	self assertPixel: 39 @ 29 in: form is: #(255 0 0 255).
	self assertPixel: 40 @ 20 in: form is: #(255 255 255 255).
	self assertPixel: 20 @ 30 in: form is: #(255 255 255 255).
	self assertPixel: 19 @ 20 in: form is: #(255 255 255 255)
!
testAlphaBlending
	| form |
	form := self render: [:c |
		c fillRect: (0 @ 0 extent: 10 @ 10) color: (Color black alpha: 0.5).
		c alpha: 0.5 during: [c fillRect: (10 @ 0 extent: 10 @ 10) color: Color ultramarine].
		c fillRect: (20 @ 0 extent: 10 @ 10) color: Color ultramarine.
		c fillRect: (20 @ 0 extent: 10 @ 10) color: (Color white alpha: 0.25)] extent: 30 @ 10.
	self assertPixel: 5 @ 5 in: form is: #(127 127 127 255) tolerance: 2.
	self assertPixel: 25 @ 5 in: form is: #(141 156 197 255) tolerance: 2.
	self assertPixel: 45 @ 5 in: form is: #(84 107 169 255) tolerance: 2
!
testGlyphInk
	"A 'W' leaves ink inside its glyph box and none outside; the total ink matches the atlas coverage."
	| form info penX baseline ink outside |
	form := self render: [:c | c drawString: 'W' at: 10 @ 10 font: Font code color: Color black] extent: 50 @ 50.
	info := Font code glyphForCodePoint: $W value phase: 0.
	penX := 20.
	baseline := (10 + Font code baselineOffset) * 2.
	ink := 0.
	outside := 0.
	0 to: 99 do: [:y | 0 to: 99 do: [:x |
		| dark |
		dark := 255 - (self grayAt: x @ y in: form).
		((x between: penX + info left and: penX + info left + info width - 1)
			and: [y between: baseline + info top and: baseline + info top + info height - 1])
				ifTrue: [ink := ink + dark]
				ifFalse: [outside := outside + dark]]].
	self assert: outside equals: 0.
	self assert: (ink - info inkSum) abs <= (info width * info height).
	self assert: ink > (255 * 20)
!
testColoredText
	| form darkest |
	form := self render: [:c | c drawString: 'l' at: 0 @ 0 font: Font codeBold color: Color ultramarine] extent: 20 @ 20.
	darkest := nil.
	0 to: 39 do: [:y | 0 to: 39 do: [:x |
		| v |
		v := self rgbaAt: x @ y in: form.
		(darkest isNil or: [(v at: 1) < (darkest at: 1)]) ifTrue: [darkest := v]]].
	self assert: darkest equals: #(27 58 140 255)
!
testImageAtDeviceResolution
	| image form |
	image := Form width: 4 height: 2.
	image fill: Color white.
	image at: 0 @ 0 put: Color red.
	image at: 3 @ 1 put: Color blue.
	form := self render: [:c | c image: image in: (5 @ 5 extent: 2 @ 1)] extent: 20 @ 20.
	self assertPixel: 10 @ 10 in: form is: #(255 0 0 255).
	self assertPixel: 13 @ 11 in: form is: #(0 0 255 255).
	self assertPixel: 11 @ 10 in: form is: #(255 255 255 255)
!
testSurfaceAsImage
	"A rendered Surface can be drawn as an image (layer compositing)."
	| layer list form canvas |
	layer := Surface width: 20 height: 20 scale: 2.
	canvas := Canvas extent: 10 @ 10 scale: 2.
	canvas fillRect: (0 @ 0 extent: 10 @ 10) color: Color green.
	layer render: canvas displayList clear: Color white.
	form := self render: [:c | c image: layer in: (10 @ 10 extent: 10 @ 10)] extent: 30 @ 30.
	self assertPixel: 25 @ 25 in: form is: #(0 255 0 255).
	self assertPixel: 15 @ 25 in: form is: #(255 255 255 255).
	layer release
!
testAntialiasedDiagonal
	| form partial |
	form := self render: [:c | c line: 0 @ 0 to: 20 @ 10 color: Color black width: 1] extent: 20 @ 20.
	self assert: (self grayAt: 20 @ 10 in: form) < 64.
	self assert: (self grayAt: 20 @ 30 in: form) equals: 255.
	partial := (0 to: 39) count: [:y | ((self grayAt: 20 @ y in: form) between: 20 and: 235)].
	self assert: partial >= 1
!
testSeveralListsInOneCommandBuffer
	"Each DisplayList gets its own range of the vertex buffer, so all of them survive until the submit."
	| a b sa sb cmd canvas |
	canvas := Canvas extent: 5 @ 5 scale: 2.
	canvas fillRect: (0 @ 0 extent: 5 @ 5) color: Color red.
	a := canvas displayList.
	canvas := Canvas extent: 5 @ 5 scale: 2.
	canvas fillRect: (0 @ 0 extent: 5 @ 5) color: Color blue.
	b := canvas displayList.
	sa := Surface width: 10 height: 10 scale: 2.
	sb := Surface width: 10 height: 10 scale: 2.
	cmd := GPUDevice default commandBuffer.
	Renderer default render: a into: sa texture clear: Color white commandBuffer: cmd.
	Renderer default render: b into: sb texture clear: Color white commandBuffer: cmd.
	cmd submitWithFence wait.
	self assertPixel: 5 @ 5 in: sa readback is: #(255 0 0 255).
	self assertPixel: 5 @ 5 in: sb readback is: #(0 0 255 255).
	sa release.
	sb release
! !
