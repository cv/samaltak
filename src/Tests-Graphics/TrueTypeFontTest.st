TestCase subclass: #TrueTypeFontTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

TrueTypeFontTest comment: 'I check the TrueType parser against values read with fontTools from the files in fonts/.'!

!TrueTypeFontTest methodsFor: 'tests'!
testTwemojiColorLayers
	"COLR v0 and CPAL of the bundled Twemoji: a base glyph's layers bottom first, each a glyph and a palette color."
	| f layers |
	f := Font faceNamed: 'Twemoji'.
	self assert: f unitsPerEm equals: 512.
	self assert: f colorBaseGlyphCount equals: 3689.
	self assert: (f glyphIndexFor: 16r1F600) equals: 884.
	self assert: (f colorLayersOf: 884) equals: #(3150 195 8287 823 8288 11).
	self assert: (f colorLayersOf: 3150) isNil.
	self assert: (f boundsOf: 884) isNil.
	self assert: (f boundsOf: 3150) equals: (Rectangle left: 0 right: 512 top: -64 bottom: 448).
	self assert: f palette size equals: 1063.
	self assert: ((f palette first) hex) equals: 16rE6E7E8.
	self assert: (f palette count: [:each | each alpha < 1]) equals: 15.
	layers := f colorLayersOf: (f glyphIndexFor: 16r1F468).
	self assert: layers size equals: 10.
	self assert: (layers at: 1) equals: 5616
!
testTwemojiLigatures
	"GSUB ccmp ligatures, longest first: the family ZWJ sequence, a flag, a keycap, a skin tone."
	| f ligs glyphs find |
	f := Font faceNamed: 'Twemoji'.
	ligs := f ligatures.
	self assert: (ligs inject: 0 into: [:sum :each | sum + each size]) equals: 2298.
	self assert: (ligs inject: 0 into: [:max :each | max max: each first first size]) equals: 9.
	ligs do: [:list | 1 to: list size - 1 do: [:i | self assert: (list at: i) first size >= (list at: i + 1) first size]].
	glyphs := [:cps | cps collect: [:cp | f glyphIndexFor: cp]].
	find := [:cps | | g | g := glyphs value: cps.
		((ligs at: g first ifAbsent: [#()]) detect: [:each | each first = g allButFirst] ifNone: [nil]) ifNotNil: [:each | each last]].
	self assert: (find value: #(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466)) equals: 6000.
	self assert: (find value: #(16r1F1E9 16r1F1EA)) equals: 1900.
	self assert: (f colorLayersOf: 1900) size equals: 6.
	self assert: (find value: #(16r31 16rFE0F 16r20E3)) equals: 13695.
	self assert: (find value: #(16r31 16r20E3)) isNil.
	self assert: (find value: #(16r1F44D 16r1F3FD)) equals: 5137
!
testCompactKeepsMappedGlyphs
	"A compacted face keeps the tables it reads and the outlines the cmap reaches (composites with their components); GSUB-only alternates go."
	| f before contours |
	f := TrueTypeFont fromFile: Font fontsDirectory , '/IosevkaEtoile-Regular.ttf'.
	before := f data size.
	contours := f contoursOf: 172.
	self assert: (f boundsOf: 9000) notNil.
	f compact.
	self assert: f data size < (before // 4).
	self assert: f tableTags size equals: 8.
	self deny: (f tableTags includes: 'GSUB').
	self assert: f numGlyphs equals: 50732.
	self assert: (f glyphIndexFor: 16rE9) equals: 172.
	self assert: (f contoursOf: 172) equals: contours.
	self assert: (f boundsOf: 172) bottom equals: 766.
	self assert: (f advanceWidthOf: 6630) equals: 1000.
	self assert: (f boundsOf: 9000) isNil
!
testIosevkaHeaderMetrics
	| f |
	f := Font faceNamed: 'IosevkaEtoile-Regular'.
	self assert: f unitsPerEm equals: 1000.
	self assert: f ascender equals: 965.
	self assert: f descender equals: -215.
	self assert: f lineGap equals: 70.
	self assert: f numGlyphs equals: 50732.
	self assert: f xHeight equals: 520.
	self assert: f capHeight equals: 735.
	self assert: f weightClass equals: 400.
	self assert: f usesTypoMetrics.
	self deny: f isBold.
	self assert: (Font faceNamed: 'IosevkaEtoile-Bold') weightClass equals: 700.
	self assert: (Font faceNamed: 'IosevkaEtoile-Italic') isItalic
!
testJetBrainsHeaderMetrics
	| f |
	f := Font faceNamed: 'JetBrainsMono-Regular'.
	self assert: f unitsPerEm equals: 1000.
	self assert: f ascender equals: 1020.
	self assert: f descender equals: -300.
	self assert: f lineGap equals: 0.
	self assert: f numGlyphs equals: 1743.
	self assert: f xHeight equals: 550.
	self assert: f capHeight equals: 730
!
testCharacterMapping
	| f j |
	f := Font faceNamed: 'IosevkaEtoile-Regular'.
	j := Font faceNamed: 'JetBrainsMono-Regular'.
	self assert: (f glyphIndexFor: $a value) equals: 68.
	self assert: (f glyphIndexFor: $W value) equals: 58.
	self assert: (f glyphIndexFor: 16rE9) equals: 172.
	self assert: (f glyphIndexFor: 16r2318) equals: 6630.
	self assert: (f glyphIndexFor: 16r2192) equals: 6491.
	self assert: (f glyphIndexFor: 16r20AC) equals: 26989.
	self assert: (j glyphIndexFor: $a value) equals: 189.
	self assert: (j glyphIndexFor: 16r2318) equals: 1513.
	self assert: (j glyphIndexFor: 16r10FFFF) equals: 0
!
testAdvancesAndBearings
	| f j |
	f := Font faceNamed: 'IosevkaEtoile-Regular'.
	j := Font faceNamed: 'JetBrainsMono-Regular'.
	self assert: (f advanceWidthOf: 68) equals: 600.
	self assert: (f leftSideBearingOf: 68) equals: 87.
	self assert: (f advanceWidthOf: 58) equals: 900.
	self assert: (f advanceWidthOf: 6630) equals: 1000.
	self assert: (f leftSideBearingOf: 6491) equals: 24.
	self assert: (j advanceWidthOfCodePoint: $W value) equals: 600.
	self assert: (j leftSideBearingOf: 245) equals: 88
!
testGlyphBounds
	| f b |
	f := Font faceNamed: 'IosevkaEtoile-Regular'.
	b := f boundsOf: 74.
	self assert: b left equals: 87.
	self assert: b top equals: -223.
	self assert: b right equals: 561.
	self assert: b bottom equals: 528.
	self assert: (f boundsOf: (f glyphIndexFor: 32)) isNil
!
testSimpleGlyphOutline
	"'a' of Iosevka Etoile has two contours; every point lies in the glyph box."
	| f contours box |
	f := Font faceNamed: 'IosevkaEtoile-Regular'.
	contours := f contoursOf: 68.
	self assert: contours size equals: 2.
	self assert: (contours collect: [:c | c size // 3]) asArray equals: #(53 23).
	box := f boundsOf: 68.
	contours do: [:c |
		1 to: c size by: 3 do: [:i |
			self assert: ((c at: i) between: box left and: box right).
			self assert: ((c at: i + 1) between: box top and: box bottom)]]
!
testCompositeGlyphOutline
	"'é' is a composite (base 'e' plus an accent); its contours are the components', transformed into its box."
	| f contours box ys |
	f := Font faceNamed: 'IosevkaEtoile-Regular'.
	contours := f contoursOf: 172.
	self assert: contours size >= 3.
	box := f boundsOf: 172.
	self assert: box bottom equals: 766.
	ys := OrderedCollection new.
	contours do: [:c | 2 to: c size by: 3 do: [:i | ys add: (c at: i)]].
	self assert: ys max equals: 766.
	self assert: ys min equals: -8
! !
