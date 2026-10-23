TestCase subclass: #FontTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

FontTest comment: 'I check Font metrics (in points) and the standard fonts. Expected baselines were measured on Chrome (macOS, deviceScaleFactor 2) rendering the same fonts with the same CSS line heights.'!

!FontTest methodsFor: 'tests'!
testStandardFonts
	self assert: Font ui face name equals: 'IosevkaEtoile-Regular.ttf'.
	self assert: Font ui size equals: 13.5.
	self assert: Font uiBold face isBold.
	self assert: Font uiItalic face isItalic.
	self assert: Font code face name equals: 'JetBrainsMono-Regular.ttf'.
	self assert: Font code size equals: 13.
	self assert: Font code lineHeight equals: 20.
	self assert: Font codeBold face isBold.
	self assert: Font codeItalic face isItalic.
	self assert: Font header size equals: 10.5.
	self assert: Font header face isBold.
	self assert: Font header isUppercase.
	self assert: Font ui scale equals: 2
!
testMetrics
	| f |
	f := Font ui.
	self assert: f ascent closeTo: 965 * 13.5 / 1000.
	self assert: f descent closeTo: 215 * 13.5 / 1000.
	self assert: (Font code advanceOf: $m) closeTo: 7.8.
	self assert: (Font ui widthOf: 'Hello') closeTo: ('Hello' inject: 0 into: [:sum :ch | sum + (f face advanceWidthOfCodePoint: ch value)]) * 13.5 / 1000.
	self assert: (Font ui widthOf: 'Hello') closeTo: 2600 * 13.5 / 1000.
	self assert: (Font ui advanceOf: $W) closeTo: 900 * 13.5 / 1000.
	self assert: (Font code widthOf: '') equals: 0
!
testBaselinesMatchChrome
	self assert: Font ui baselineOffset equals: 14.
	self assert: Font code baselineOffset equals: 14.5.
	self assert: Font header baselineOffset equals: 10.5
!
testHeaderTracking
	"Tracked capitals: 0.08em letter spacing after every character, lowercase drawn as capitals."
	| h a |
	h := Font header.
	a := (h face advanceWidthOfCodePoint: $A value) * 10.5 / 1000.
	self assert: (h widthOf: 'A') closeTo: a + 0.84.
	self assert: (h widthOf: 'aa') closeTo: (h widthOf: 'AA').
	self assert: (h widthOf: 'AA') closeTo: 2 * (a + 0.84)
!
testWideCharacters
	"Symbols outside Latin-1 have advances and glyphs."
	| arrow info |
	arrow := String with: (Character value: 16r2192).
	self assert: (Font ui widthOf: arrow) closeTo: 13.5.
	info := Font ui glyphForCodePoint: 16r2318 phase: 0.
	self deny: info isBlank.
	self assert: info inkSum > 0
!
testIndexAt
	| s |
	s := 'abc'.
	self assert: (Font code indexAt: 0 in: s) equals: 0.
	self assert: (Font code indexAt: 7.9 in: s) equals: 1.
	self assert: (Font code indexAt: 100 in: s) equals: 3
!
testPrerasterizedInImage
	"Stage 2 put ASCII and the UI symbols of the standard fonts into the atlas."
	| f |
	f := Font ui.
	0 to: f phases - 1 do: [:phase |
		self assert: (f glyphTable at: $a value * f phases + phase + 1) notNil].
	self assert: (f glyphTable at: $Z value * f phases + 1) notNil.
	self assert: GlyphAtlas default pages notEmpty
!
testSubpixelPhasesShiftInk
	"A glyph rasterized a half pixel to the right has its ink centroid half a pixel to the right."
	| f c0 c2 |
	f := Font code.
	c0 := self centroidX: (f glyphForCodePoint: $l value phase: 0).
	c2 := self centroidX: (f glyphForCodePoint: $l value phase: 2).
	self assert: c2 - c0 closeTo: 0.5 precision: 0.05
! !

!FontTest methodsFor: 'support'!
centroidX: info
	| sum weighted |
	sum := 0.
	weighted := 0.
	0 to: info height - 1 do: [:y |
		0 to: info width - 1 do: [:x |
			| v |
			v := info coverageAtX: x y: y.
			sum := sum + v.
			weighted := weighted + (v * (x + info left + 0.5))]].
	^weighted / sum
! !
