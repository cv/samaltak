TestCase subclass: #GlyphFormTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GlyphFormTest comment: 'I check Font>>glyphFor: (a GlyphForm: the coverage Canvas draws a glyph with) against GlyphRasterizer run afresh on the outline from the .ttf on disk, and the pixel components Forms answer.'!

!GlyphFormTest methodsFor: 'tests'!
testGlyphForIsTheRasterizersCoverage
	| font form face glyph box ppu left right top bottom r expected |
	font := Font code.
	form := font glyphFor: $g.
	self assert: form character equals: $g.
	self assert: form font == font.
	self assert: form extent equals: form glyph width @ form glyph height.
	face := TrueTypeFont fromFile: Font fontsDirectory , '/JetBrainsMono-Regular.ttf'.
	glyph := face glyphIndexFor: $g value.
	box := face boundsOf: glyph.
	ppu := font pixelsPerUnit.
	left := (box left * ppu) floor.
	right := (box right * ppu) ceiling.
	top := (box bottom * ppu) negated floor.
	bottom := (box top * ppu) negated ceiling.
	self assert: form left equals: left.
	self assert: form top equals: top.
	self assert: form extent equals: (right - left) @ (bottom - top).
	r := GlyphRasterizer width: right - left height: bottom - top.
	(face contoursOf: glyph) do: [:each | r addContour: each scale: ppu offsetX: left negated offsetY: top negated].
	expected := r coverage.
	self assert: form coverage equals: expected.
	self assert: (expected includes: 255).
	self assert: (expected detect: [:c | c > 0 and: [c < 255]] ifNone: [nil]) notNil.
	self assert: (form coverageAt: 0 @ 0) equals: expected first.
	self assert: (form pixelComponentsAt: 0 @ 0) equals: (Array with: expected first).
	self assert: form pixelComponentNames equals: #('coverage')
!
testBlankAndUppercaseGlyphs
	self assert: (Font code glyphFor: $ ) extent equals: 0 @ 0.
	self assert: (Font header glyphFor: $a) character equals: $A.
	self assert: ((Font ui glyphFor: $W) printString beginsWith: 'a GlyphForm($W a Font(IosevkaEtoile-Regular')
!
testFormPixelComponents
	| f |
	f := Form width: 2 height: 1.
	f at: 1 @ 0 put: (Color r: 1 g: 0 b: 0 a: 1).
	self assert: f pixelComponentNames equals: #('r' 'g' 'b' 'a').
	self assert: (f pixelComponentsAt: 1 @ 0) asArray equals: #(255 0 0 255).
	self assert: (f pixelComponentsAt: 0 @ 0) asArray equals: #(0 0 0 0)
! !
