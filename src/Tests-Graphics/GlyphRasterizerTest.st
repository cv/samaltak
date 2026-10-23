TestCase subclass: #GlyphRasterizerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GlyphRasterizerTest comment: 'I check the glyph rasterizer: exact coverage of simple shapes, total coverage against the outline area (fontTools AreaPen), and whole glyph bitmaps against references made by a 16x16 supersampling non-zero-winding rasterizer in Python (fontTools outlines, quadratics flattened to 64 segments) at the same placement.'!

!GlyphRasterizerTest methodsFor: 'support'!
bytesFromHex: aString
	| bytes |
	bytes := ByteArray new: aString size // 2.
	1 to: bytes size do: [:i |
		bytes at: i put: ((aString at: i * 2 - 1) digitValue * 16) + (aString at: i * 2) digitValue].
	^bytes
!
coverageOf: aGlyphInfo
	| bytes |
	bytes := ByteArray new: aGlyphInfo width * aGlyphInfo height.
	0 to: aGlyphInfo height - 1 do: [:y |
		0 to: aGlyphInfo width - 1 do: [:x |
			bytes at: y * aGlyphInfo width + x + 1 put: (aGlyphInfo coverageAtX: x y: y)]].
	^bytes
!
assertGlyph: codePoint face: faceName size: size phase: phase matches: hex width: w height: h left: left top: top
	"Compare the rasterized glyph with the supersampled reference: same box, every pixel within 12/255, mean error below 1.5/255."
	| font info mine ref maxDiff total |
	font := Font face: (Font faceNamed: faceName) size: size scale: 2.
	info := font glyphForCodePoint: codePoint phase: phase.
	self assert: info width equals: w.
	self assert: info height equals: h.
	self assert: info left equals: left.
	self assert: info top equals: top.
	mine := self coverageOf: info.
	ref := self bytesFromHex: hex.
	maxDiff := 0.
	total := 0.
	1 to: ref size do: [:i |
		| d |
		d := ((mine at: i) - (ref at: i)) abs.
		maxDiff := maxDiff max: d.
		total := total + d].
	self assert: maxDiff <= 12 description: 'max pixel difference ', maxDiff printString.
	self assert: total / ref size < 1.5 description: 'mean difference ', (total / ref size) asFloat printString
! !

!GlyphRasterizerTest methodsFor: 'tests'!
testPixelAlignedSquareIsSolid
	| r cov |
	r := GlyphRasterizer width: 6 height: 5.
	r addContour: #(1 1 true 4 1 true 4 4 true 1 4 true) scale: 1.0 offsetX: 0.0 offsetY: 5.0.
	cov := r coverage.
	"y up: rows 1..3 from the bottom, columns 1..3"
	1 to: 5 do: [:y | 1 to: 6 do: [:x |
		| inside |
		inside := (x between: 2 and: 4) and: [y between: 2 and: 4].
		self assert: (cov at: (y - 1) * 6 + x) equals: (inside ifTrue: [255] ifFalse: [0])]]
!
testFractionalEdgesGiveExactArea
	"A square from 0.25 to 2.75 (x) and 0.5 to 2.5 (y): edge pixels are covered by the exact fractions."
	| r cov |
	r := GlyphRasterizer width: 3 height: 3.
	r addContour: #(0.25 0.5 true 2.75 0.5 true 2.75 2.5 true 0.25 2.5 true) scale: 1.0 offsetX: 0.0 offsetY: 3.0.
	cov := r coverage.
	"row 1 (top) is y 2..3 in font space: covered 0.5 vertically"
	self assert: (cov at: 1) equals: (0.75 * 0.5 * 255 + 0.5) truncated.
	self assert: (cov at: 2) equals: (0.5 * 255 + 0.5) truncated.
	self assert: (cov at: 3) equals: (0.75 * 0.5 * 255 + 0.5) truncated.
	self assert: (cov at: 4) equals: (0.75 * 255 + 0.5) truncated.
	self assert: (cov at: 5) equals: 255.
	self assert: (cov at: 6) equals: (0.75 * 255 + 0.5) truncated
!
testWindingDirectionDoesNotMatter
	| a b |
	a := GlyphRasterizer width: 8 height: 8.
	a addContour: #(1 1 true 7 2 true 5 7 true) scale: 1.0 offsetX: 0.0 offsetY: 8.0.
	b := GlyphRasterizer width: 8 height: 8.
	b addContour: #(5 7 true 7 2 true 1 1 true) scale: 1.0 offsetX: 0.0 offsetY: 8.0.
	self assert: a coverage equals: b coverage
!
testOverlappingContoursClampToFull
	"Two same-direction squares on top of each other (non-zero winding 2) stay fully covered, not doubled."
	| r cov |
	r := GlyphRasterizer width: 4 height: 4.
	r addContour: #(0 0 true 4 0 true 4 4 true 0 4 true) scale: 1.0 offsetX: 0.0 offsetY: 4.0.
	r addContour: #(1 1 true 3 1 true 3 3 true 1 3 true) scale: 1.0 offsetX: 0.0 offsetY: 4.0.
	cov := r coverage.
	self assert: (cov allSatisfy: [:v | v = 255])
!
testCircleIsSymmetric
	"An off-curve-only contour (a circle of quadratics) rasterizes mirror-symmetrically."
	| r cov w |
	w := 12.
	r := GlyphRasterizer width: w height: w.
	r addContour: #(10 6 false 10 10 false 6 10 false 2 10 false 2 6 false 2 2 false 6 2 false 10 2 false) scale: 1.0 offsetX: 0.0 offsetY: w asFloat.
	cov := r coverage.
	0 to: w - 1 do: [:y | 0 to: w - 1 do: [:x |
		self assert: ((cov at: y * w + x + 1) - (cov at: y * w + (w - 1 - x) + 1)) abs <= 1.
		self assert: ((cov at: y * w + x + 1) - (cov at: (w - 1 - y) * w + x + 1)) abs <= 1]]
!
testCoverageMatchesOutlineArea
	"Total coverage equals the glyph area (fontTools AreaPen, font units) times the scale squared, within 0.5%."
	#(#('IosevkaEtoile-Regular' 103 158699.0) #('IosevkaEtoile-Regular' 16r2318 210949.8) #('IosevkaEtoile-Bold' 87 264461.0) #('JetBrainsMono-Regular' 8364 155723.3) #('IosevkaEtoile-Regular' 16rE9 134138.1))
		do: [:spec |
			| face glyph box s left top r expected |
			face := Font faceNamed: spec first.
			glyph := face glyphIndexFor: (spec at: 2).
			box := face boundsOf: glyph.
			s := 27.0 / face unitsPerEm.
			left := (box left * s) floor.
			top := (box bottom * s) negated floor.
			r := GlyphRasterizer width: (box right * s) ceiling - left height: (box top * s) negated ceiling - top.
			(face contoursOf: glyph) do: [:c | r addContour: c scale: s offsetX: left negated offsetY: top negated].
			expected := (spec at: 3) * s * s.
			self assert: (r coverageSum - expected) abs / expected < 0.005
				description: spec printString, ': ', r coverageSum printString, ' vs ', expected printString]
! !

!GlyphRasterizerTest methodsFor: 'tests - references'!
testIosevkaG
	self assertGlyph: 103 face: 'IosevkaEtoile-Regular' size: 13.5 phase: 0
		matches: '0000000c383c1400000a10101002000387f7fffffda70f9fffffff20008afffff4c5c5f4bea0fff9ef1e20fbffb510000011b8e9ff9f000070fff1110000000011f3ff9f000098ffb0000000000000b4ff9f00009fff950000000000009fff9f00009fff8f0000000000009fff9f00009fff8f0000000000009fff9f00009fff960000000000009fff9f000097ffb2000000000000b6ff9f00006dfff3130000000016f4ff9f00001cf9ffbd15000016bfe5ff9f00000082fffff8d2d3f8b4a0ff9f000000017cf2fffffa9b0a9fff9f0000000000062b2f0c00009fff9f0000000000000000000000c1ff8800005ccfb1010000000028fcff4f000027fdffa027010545dcffd80400000075feffffffffffffed31000000000040afe8fffedf941c000000000000000000000000000000000000'
		width: 14 height: 22 left: 2 top: -15
!
testItalicAmpersandAtSubpixelPhase
	self assertGlyph: 38 face: 'IosevkaEtoile-Italic' size: 13.5 phase: 2
		matches: '0000000000000210020000000000000000002cb7f8fff7ab1900000000000037f4fff9e0fcffd3040000000000d0ffba140031f8ff480000000029fffd1c000000c4ff6f0000000049ffe300000000caff680000000035fff102000023fcff2d0000000006f0ff430006bcffbe00000000000093ffba14b8fff0280000000000001ef9ffedffeb370000000000000029e3ffffb91c0000000000000056f4ffffff4e0000000000000052fcffa5a0ffc700000f60601314efff90001ef9ff43008cffc9027cffd60400009dffbf29fafe3700c3ff7300000024fbffd5ff9e0000dfff5000000000a2fffff1170000d0ff74000000003dffff7e00000097ffe220000022d2ffffab00000027f5fff7c0bef9ffa9fffd2a0000003fd7ffffffde5900b7ffa700000000001e30230100000000000000'
		width: 14 height: 22 left: 2 top: -21
!
testMonoAtSignAtSubpixelPhase
	self assertGlyph: 64 face: 'JetBrainsMono-Regular' size: 13 phase: 1
		matches: '00000000000c30402c07000000000000003ab7fbfffffff6a31e000000006cfcffe5a891aceeffed33000049fefd75040000000ca4ffde0901d5ff8000000000000004d5ff6235ffee090000000000000077ffa870ffad00000000000000004cffc98cff87000000015494924c40ffcf8fff800000009dffffffffafffcf8fff80000034fffc5e0c33deffcf8fff80000072ffb100000064ffcf8fff80000080ff8f00000041ffcf8fff80000080ff8f00000040ffcf8fff80000080ff8f00000040ffcf8fff80000080ff9100000044ffcc8fff80000065ffbf00000072ffa98fff80000016f2ff83325aedff4e8fff810000004ef5ffffffff8c007eff9c000000001b708f803500004cffdd010000000000000000000009eeff59000000000000000000000077fff03e0000000000000000000003b1fffdac614540402400000000000687f9ffffffffff8f00000000000000186999afafaf63000000'
		width: 14 height: 25 left: 1 top: -20
!
testCompositeEAcute
	self assertGlyph: 233 face: 'IosevkaEtoile-Regular' size: 13.5 phase: 0
		matches: '00000000000000334700000000000000000024eaf94d000000000000001adeffbd0b0000000000000fd1ffb108000000000000003df3a40600000000000000000023030000000000000000001c3c3f2401000000000043ceffffffffe26400000051fcfff6c3bcedffff80000eedffb91500000792fffd3061fff1110000000002cfff9292ffad0000000000007bffc69fff8f00000000000060ffdb9fffffffffffffffffffffdf9fffffffffffffffffffffdf9fff9000000000000000000092ffb00000000000000000005cfff41500000000007eefb30ce9ffc01a0000004ef3ff790048f9fffaccc3e4ffffc80a000037c2feffffffeb860b0000000000112f302302000000'
		width: 12 height: 22 left: 2 top: -21
! !
