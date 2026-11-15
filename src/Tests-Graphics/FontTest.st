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

!FontTest methodsFor: 'tests - coverage'!
testStandardFacesCoverGreekCyrillicAndBoxDrawing
	#(16r3B1 16r3A9 16r416 16r44F 16r2500 16r2510 16r2588) do: [:cp |
		self assert: (Font ui face includesCodePoint: cp).
		self assert: (Font code face includesCodePoint: cp)].
	"Greek Extended: Iosevka only"
	self assert: (Font ui face includesCodePoint: 16r1F00)
!
testFallbackFaces
	"Code points the face lacks come from the first fallback face that has them."
	self assert: (Font code faceFor: $a value) == Font code face.
	self assert: (Font code faceFor: 16r1F00) name equals: 'IosevkaEtoile-Regular.ttf'.
	self assert: (Font code faceFor: 16r65E5) name equals: 'NotoSansSC-Regular.ttf'.
	self assert: (Font ui faceFor: 16r3042) name equals: 'NotoSansSC-Regular.ttf'.
	self assert: (Font ui faceFor: 16rD55C) name equals: 'NotoSansKR-Hangul.ttf'.
	self assert: (Font ui faceFor: 16r1F600) name equals: 'NotoEmoji-Regular.ttf'.
	self assert: (Font codeBold faceFor: 16r1F389) name equals: 'NotoEmoji-Regular.ttf'.
	self assert: (Font ui faceFor: 16r2654) name equals: 'NotoSansSymbols2-Regular.ttf'.
	self assert: (Font ui faceFor: 16rE000) isNil
!
testFallbackGlyphMetrics
	"Fallback glyphs at the font's em size on its baseline, with their own advances: a Han ideograph is 1 em wide, an emoji 1.27 em. Glyphs are in device pixels, at the font's scale."
	| f s han emoji |
	f := Font code.
	s := f scale.
	self assert: (f advanceOf: (Character value: 16r65E5)) closeTo: 13.
	self assert: (f advanceOf: (Character value: 16r1F600)) closeTo: 2600 * 13 / 2048.
	self assert: (f widthOf: (String with: $a with: (Character value: 16r65E5))) closeTo: 7.8 + 13.
	han := f glyphForCodePoint: 16r65E5 phase: 0.
	self assert: han inkSum > 0.
	self assert: (han top between: f ascent * s negated and: f capHeight * s negated).
	self assert: (han top + han height between: 0 and: f descent * s).
	emoji := f glyphForCodePoint: 16r1F600 phase: 0.
	self assert: emoji inkSum > 0.
	"rounded out to whole pixels: up to one more at each edge"
	self assert: (emoji height between: 13 * s * 0.9 and: 13 * s * 1.1 + 2).
	self assert: (emoji top + emoji height between: 0 and: f descent * s)
!
testMissingGlyphIsABox
	"A code point no face has (unassigned, private use) draws as a hollow box as tall as a capital, with its hex digits inside when that is 15 device pixels or more (at 2×, not at 1×)."
	| f box wide |
	f := Font code.
	#(16r378 16rE000) do: [:cp |
		box := f glyphForCodePoint: cp phase: 0.
		self deny: box isBlank.
		self assert: box height equals: (f capHeight * f scale) rounded.
		self assert: box top equals: box height negated.
		self assert: (box coverageAtX: 0 y: 0) equals: 255.
		self assert: (box coverageAtX: box width - 1 y: box height - 1) equals: 255.
		self assert: (box coverageAtX: box width // 2 y: 1) equals: 0.
		self assert: (f deviceAdvanceOf: cp) > box width].
	"the digits, at 2× whatever the display's scale"
	f := Font face: f face size: f size scale: 2.
	box := f glyphForCodePoint: 16rE000 phase: 0.
	self deny: (f glyphForCodePoint: 16r378 phase: 0) inkSum = box inkSum.
	wide := f glyphForCodePoint: 16r10FFFD phase: 0.
	self assert: wide width > box width
!
testInvisibleCharactersHaveNoWidth
	"Controls, zero-width characters, variation selectors and the BOM draw nothing and do not advance."
	| f smiley |
	f := Font ui.
	#(0 9 16r7F 16r85 16r200B 16r200D 16r2060 16rFE0E 16rFE0F 16rFEFF 16rE0001) do: [:cp |
		self assert: (f deviceAdvanceOf: cp) equals: 0.
		self assert: (f glyphForCodePoint: cp phase: 0) isBlank].
	smiley := String with: (Character value: 16r263A).
	self assert: (f widthOf: smiley , (String with: (Character value: 16rFE0F))) equals: (f widthOf: smiley).
	"combining marks have glyphs"
	self deny: (f glyphForCodePoint: 16r301 phase: 0) isBlank
! !

!FontTest methodsFor: 'tests - color emoji'!
testColorEmojiClusters
	"Which clusters are drawn as color emoji, with how many glyphs (0: text). A ZWJ sequence Twemoji has no ligature for shows its parts; U+FE0E, a bare digit or ©, and a single code point without Emoji_Presentation stay text."
	| f s end |
	f := Font code.
	#(#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466) 1 #(16r1F1E9 16r1F1EA) 1 #(16r31 16rFE0F 16r20E3) 1
	  #(16r1F44D 16r1F3FD) 1 #(16r261D 16r1F3FD) 1 #(16r1F3F3 16rFE0F 16r200D 16r1F308) 1 #(16r1F600) 1 #(16rA9 16rFE0F) 1 #(16r1F3F4 16rE0067 16rE0062 16rE0073 16rE0063 16rE0074 16rE007F) 1
	  #(16r1F468 16r200D 16r1F9B0 16r200D 16r1F9B0) 2
	  #(16r1F600 16rFE0E) 0 #(16r31) 0 #(16r31 16rFE0F) 0 #(16rA9) 0 #(16r263A) 0 #(16r1FAE8) 0) pairsDo: [:cps :n |
		s := self stringOf: cps.
		end := f colorClusterEndAt: 1 in: s to: s size.
		self assert: end equals: (n = 0 ifTrue: [0] ifFalse: [s size]).
		n > 0 ifTrue: [self assert: (f colorGlyphsFrom: 1 to: end in: s) size equals: n]].
	"Emoji 15 (shaking face): Twemoji lacks it, the monochrome fallback has it"
	self assert: (f faceFor: 16r1FAE8) name equals: 'NotoEmoji-Regular.ttf'.
	"a cluster cut by the end of the range is text"
	s := self stringOf: #(16r1F44D 16r1F3FD).
	self assert: (f colorClusterEndAt: 1 in: s to: 1) equals: 0
!
testSymbolsDoNotLookForEmojiClusters
	"Box drawing, blocks, shapes and dingbats are measured and drawn without looking up their clusters, but for the few with an emoji presentation (U+25FD ...)."
	| f s cache before |
	f := Font code.
	s := String withAll: ((16r2500 to: 16r27BF) collect: [:cp | Character value: cp]).
	cache := Font emoji instVarNamed: 'clusters'.
	before := cache size.
	f widthOf: s.
	(Canvas extent: 20000 @ 20 scale: f scale) drawString: s at: 0 @ 0 font: f color: Color black.
	self assert: cache size - before <= ((s select: [:c | Unicode isEmojiPresentationCode: c value]) size).
	s := String withAll: ((16r2500 to: 16r25FC) collect: [:cp | Character value: cp]).
	before := cache size.
	f widthOf: s.
	(Canvas extent: 20000 @ 20 scale: f scale) drawString: s at: 0 @ 0 font: f color: Color black.
	self assert: cache size equals: before
!
testColorEmojiWidthAndIndexAt
	"An emoji cluster advances by its glyphs (one em here), its other characters nothing; positions at an x are never inside it."
	| f family s w |
	f := Font code.
	family := self stringOf: #(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466).
	s := 'a' , family , 'b' , (self stringOf: #(16r1F1E9 16r1F1EA 16r31 16rFE0F 16r20E3)).
	self assert: (f widthOf: family) equals: f size.
	w := f widthOf: s.
	self assert: w closeTo: (f advanceOf: $a) + (f advanceOf: $b) + (3 * f size).
	self assert: (f widthOf: s from: 2 to: 8) equals: f size.
	0 to: w + 2 by: 0.25 do: [:x | self assert: (#(0 1 8 9 11 14) includes: (f indexAt: x in: s))].
	self assert: (f indexAt: (f advanceOf: $a) + (f size * 0.4) in: s) equals: 1.
	self assert: (f indexAt: (f advanceOf: $a) + (f size * 0.6) in: s) equals: 8
!
testColorEmojiLayersSitOnTheLine
	"Layers are rasterized at the em size from Twemoji, centred on the ascent and descent: inside the line box."
	| f layers info |
	#(#ui #code #small) do: [:name |
		f := Font named: name.
		layers := f colorLayersOf: (f colorGlyphsFrom: 1 to: 1 in: (self stringOf: #(16r1F600))) first.
		self assert: layers size equals: 6.
		self assert: (layers select: [:each | each isKindOf: Color]) size equals: 3.
		info := f colorLayerGlyph: layers first.
		self assert: (info height between: f size * f scale - 1 and: f size * f scale + 2).
		self assert: info top >= (f baselineOffset * f scale) floor negated.
		self assert: info top + info height <= ((f lineHeight - f baselineOffset) * f scale) ceiling.
		self assert: ((info top + (info height / 2)) - ((f descent - f ascent) * f scale / 2)) abs <= 1.5]
! !

!FontTest methodsFor: 'support'!
stringOf: codePoints
	^String withAll: (codePoints collect: [:cp | Character value: cp])
!
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
