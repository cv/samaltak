Object subclass: #TrueTypeFont
	instanceVariableNames: 'name data tables unitsPerEm bounds indexToLocFormat numGlyphs numberOfHMetrics ascender descender lineGap typoAscender typoDescender typoLineGap winAscent winDescent xHeight capHeight weightClass fsSelection cmapOffset cmapFormat cmapCache palette ligatures'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

TrueTypeFont comment: 'I am a TrueType typeface parsed from the bytes of a .ttf file: the tables head, hhea, maxp, OS/2, hmtx, cmap (formats 4 and 12), loca and glyf (simple and composite glyphs), and for color glyphs COLR (version 0), CPAL and the ligatures of GSUB''s ccmp feature. Everything is in font units (unitsPerEm per em, y up); Font scales me to a pixel size. Kerning and hinting are ignored. Stage 2 compacts the faces it keeps in the image to the tables I read and the outlines the cmap reaches (compact), but for a face with color glyphs: its layers and ligatures are glyphs the cmap does not reach.'!

!TrueTypeFont methodsFor: 'initialization'!
setName: aString data: aByteArray
	name := aString.
	data := aByteArray.
	cmapCache := Dictionary new.
	self readTableDirectory.
	self readHead.
	self readHhea.
	self readMaxp.
	self readOS2.
	self readCmap
!
readTableDirectory
	| count offset |
	count := self u16: 5.
	tables := Dictionary new.
	offset := 13.
	count timesRepeat: [
		tables at: (data copyFrom: offset to: offset + 3) asString
			put: (Array with: (self u32: offset + 8) with: (self u32: offset + 12)).
		offset := offset + 16]
!
readHead
	| h |
	h := self tableOffset: 'head'.
	unitsPerEm := self u16: h + 18.
	bounds := Rectangle
		left: (self s16: h + 36) right: (self s16: h + 40)
		top: (self s16: h + 38) bottom: (self s16: h + 42).
	indexToLocFormat := self s16: h + 50
!
readHhea
	| h |
	h := self tableOffset: 'hhea'.
	ascender := self s16: h + 4.
	descender := self s16: h + 6.
	lineGap := self s16: h + 8.
	numberOfHMetrics := self u16: h + 34
!
readMaxp
	numGlyphs := self u16: (self tableOffset: 'maxp') + 4
!
readOS2
	| o version |
	(tables includesKey: 'OS/2') ifFalse: [
		typoAscender := ascender. typoDescender := descender. typoLineGap := lineGap.
		winAscent := ascender. winDescent := descender negated. weightClass := 400. fsSelection := 0.
		^self].
	o := self tableOffset: 'OS/2'.
	version := self u16: o.
	weightClass := self u16: o + 4.
	fsSelection := self u16: o + 62.
	typoAscender := self s16: o + 68.
	typoDescender := self s16: o + 70.
	typoLineGap := self s16: o + 72.
	winAscent := self u16: o + 74.
	winDescent := self u16: o + 76.
	version >= 2 ifTrue: [
		xHeight := self s16: o + 86.
		capHeight := self s16: o + 88]
!
readCmap
	"Pick the best Unicode subtable: format 12 (full repertoire) over format 4 (BMP)."
	| c count best bestFormat rec platform encoding offset format |
	c := self tableOffset: 'cmap'.
	count := self u16: c + 2.
	bestFormat := 0.
	0 to: count - 1 do: [:i |
		rec := c + 4 + (i * 8).
		platform := self u16: rec.
		encoding := self u16: rec + 2.
		offset := c + (self u32: rec + 4).
		format := self u16: offset.
		((platform = 0 or: [platform = 3 and: [encoding = 1 or: [encoding = 10]]])
			and: [(format = 4 or: [format = 12]) and: [format > bestFormat]])
				ifTrue: [best := offset. bestFormat := format]].
	best isNil ifTrue: [^self error: name, ': no Unicode cmap'].
	cmapOffset := best.
	cmapFormat := bestFormat
! !

!TrueTypeFont methodsFor: 'reading'!
u16: offset
	"Big-endian unsigned 16 bits at the 1-based byte offset."
	^data uint16BigEndianAt: offset
!
s16: offset
	^data int16BigEndianAt: offset
!
u32: offset
	^data uint32BigEndianAt: offset
!
tableOffset: tag
	"Answer the 1-based byte offset of the table tag."
	^((tables at: tag ifAbsent: [^self error: name, ': missing table ', tag]) at: 1) + 1
! !

!TrueTypeFont methodsFor: 'accessing'!
name
	^name
!
data
	^data
!
tableTags
	^tables keys asSortedCollection asArray
!
unitsPerEm
	^unitsPerEm
!
bounds
	"The union of all glyph boxes, font units, y up (top < bottom numerically)."
	^bounds
!
numGlyphs
	^numGlyphs
!
ascender
	"hhea ascender (font units, positive)."
	^ascender
!
descender
	"hhea descender (font units, negative)."
	^descender
!
lineGap
	^lineGap
!
typoAscender
	^typoAscender
!
typoDescender
	^typoDescender
!
typoLineGap
	^typoLineGap
!
winAscent
	^winAscent
!
winDescent
	^winDescent
!
xHeight
	^xHeight
!
capHeight
	^capHeight
!
weightClass
	^weightClass
!
isBold
	^(fsSelection bitAnd: 32) ~= 0 or: [weightClass >= 700]
!
isItalic
	^(fsSelection bitAnd: 1) ~= 0
!
usesTypoMetrics
	^(fsSelection bitAnd: 128) ~= 0
!
cmapFormat
	^cmapFormat
! !

!TrueTypeFont methodsFor: 'character mapping'!
glyphIndexFor: codePoint
	"Answer the glyph index of the Unicode code point (0, the .notdef glyph, if unmapped)."
	^cmapCache at: codePoint ifAbsent: [
		cmapCache at: codePoint put: (cmapFormat = 4
			ifTrue: [self format4GlyphIndexFor: codePoint]
			ifFalse: [self format12GlyphIndexFor: codePoint])]
!
format4GlyphIndexFor: codePoint
	| segX2 endCodes startCodes idDeltas idRangeOffsets lo hi mid end start rangeOffset glyphOffset glyph |
	codePoint > 16rFFFF ifTrue: [^0].
	segX2 := self u16: cmapOffset + 6.
	endCodes := cmapOffset + 14.
	startCodes := endCodes + segX2 + 2.
	idDeltas := startCodes + segX2.
	idRangeOffsets := idDeltas + segX2.
	lo := 0.
	hi := segX2 // 2 - 1.
	[lo <= hi] whileTrue: [
		mid := (lo + hi) // 2.
		end := self u16: endCodes + (mid * 2).
		end < codePoint
			ifTrue: [lo := mid + 1]
			ifFalse: [
				start := self u16: startCodes + (mid * 2).
				start > codePoint
					ifTrue: [hi := mid - 1]
					ifFalse: [
						rangeOffset := self u16: idRangeOffsets + (mid * 2).
						rangeOffset = 0 ifTrue: [^(codePoint + (self s16: idDeltas + (mid * 2))) bitAnd: 16rFFFF].
						glyphOffset := idRangeOffsets + (mid * 2) + rangeOffset + ((codePoint - start) * 2).
						glyph := self u16: glyphOffset.
						glyph = 0 ifTrue: [^0].
						^(glyph + (self s16: idDeltas + (mid * 2))) bitAnd: 16rFFFF]]].
	^0
!
format12GlyphIndexFor: codePoint
	| groups lo hi mid rec start end |
	groups := self u32: cmapOffset + 12.
	lo := 0.
	hi := groups - 1.
	[lo <= hi] whileTrue: [
		mid := (lo + hi) // 2.
		rec := cmapOffset + 16 + (mid * 12).
		start := self u32: rec.
		end := self u32: rec + 4.
		codePoint < start
			ifTrue: [hi := mid - 1]
			ifFalse: [
				codePoint > end
					ifTrue: [lo := mid + 1]
					ifFalse: [^(self u32: rec + 8) + (codePoint - start)]]].
	^0
!
includesCodePoint: codePoint
	^(self glyphIndexFor: codePoint) ~= 0
! !

!TrueTypeFont methodsFor: 'metrics'!
advanceWidthOf: glyphIndex
	"Answer the horizontal advance of the glyph in font units."
	^self u16: (self tableOffset: 'hmtx') + ((glyphIndex min: numberOfHMetrics - 1) * 4)
!
leftSideBearingOf: glyphIndex
	| h |
	h := self tableOffset: 'hmtx'.
	glyphIndex < numberOfHMetrics ifTrue: [^self s16: h + (glyphIndex * 4) + 2].
	^self s16: h + (numberOfHMetrics * 4) + ((glyphIndex - numberOfHMetrics) * 2)
!
advanceWidthOfCodePoint: codePoint
	^self advanceWidthOf: (self glyphIndexFor: codePoint)
! !

!TrueTypeFont methodsFor: 'outlines'!
glyphDataOffset: glyphIndex
	"Answer the 1-based offset of the glyph's glyf record, or nil for an empty glyph."
	| loca start end |
	(glyphIndex < 0 or: [glyphIndex >= numGlyphs]) ifTrue: [^nil].
	loca := self tableOffset: 'loca'.
	indexToLocFormat = 0
		ifTrue: [
			start := (self u16: loca + (glyphIndex * 2)) * 2.
			end := (self u16: loca + (glyphIndex * 2) + 2) * 2]
		ifFalse: [
			start := self u32: loca + (glyphIndex * 4).
			end := self u32: loca + (glyphIndex * 4) + 4].
	start = end ifTrue: [^nil].
	^(self tableOffset: 'glyf') + start
!
glyphDataSize: glyphIndex
	"Answer the byte size of the glyph's glyf record (0 for an empty glyph)."
	| loca |
	loca := self tableOffset: 'loca'.
	indexToLocFormat = 0 ifTrue: [^((self u16: loca + (glyphIndex * 2) + 2) - (self u16: loca + (glyphIndex * 2))) * 2].
	^(self u32: loca + (glyphIndex * 4) + 4) - (self u32: loca + (glyphIndex * 4))
!
componentsOf: glyphIndex
	"Answer the glyph indices a composite glyph is made of (none for a simple or empty glyph)."
	| g p flags result |
	result := OrderedCollection new.
	g := self glyphDataOffset: glyphIndex.
	(g isNil or: [(self s16: g) >= 0]) ifTrue: [^result].
	p := g + 10.
	[flags := self u16: p.
	 result add: (self u16: p + 2).
	 p := p + 4 + ((flags bitAnd: 1) ~= 0 ifTrue: [4] ifFalse: [2]).
	 (flags bitAnd: 8) ~= 0 ifTrue: [p := p + 2].
	 (flags bitAnd: 16r40) ~= 0 ifTrue: [p := p + 4].
	 (flags bitAnd: 16r80) ~= 0 ifTrue: [p := p + 8].
	 (flags bitAnd: 16r20) ~= 0] whileTrue.
	^result
!
boundsOf: glyphIndex
	"Answer the glyph's box in font units as a Rectangle (left/right = xMin/xMax, top/bottom = yMin/yMax), or nil if it has no outline."
	| g |
	g := self glyphDataOffset: glyphIndex.
	g isNil ifTrue: [^nil].
	^Rectangle left: (self s16: g + 2) right: (self s16: g + 6) top: (self s16: g + 4) bottom: (self s16: g + 8)
!
contoursOf: glyphIndex
	"Answer the glyph outline: an Array of contours, each a flat Array x1 y1 on1 x2 y2 on2 ... (font units, y up; on = true for on-curve points). Composite glyphs are flattened."
	| result |
	result := OrderedCollection new.
	self addContoursOf: glyphIndex to: result transform: nil depth: 0.
	^result asArray
!
addContoursOf: glyphIndex to: aCollection transform: anArrayOrNil depth: depth
	| g count |
	depth > 8 ifTrue: [^self].
	g := self glyphDataOffset: glyphIndex.
	g isNil ifTrue: [^self].
	count := self s16: g.
	count >= 0
		ifTrue: [self addSimpleContoursAt: g count: count to: aCollection transform: anArrayOrNil]
		ifFalse: [self addCompositeAt: g to: aCollection transform: anArrayOrNil depth: depth]
!
addSimpleContoursAt: g count: contourCount to: aCollection transform: anArrayOrNil
	| endPts p numPoints flags xs ys flag repeat x y start contour |
	contourCount = 0 ifTrue: [^self].
	endPts := Array new: contourCount.
	1 to: contourCount do: [:i | endPts at: i put: (self u16: g + 10 + ((i - 1) * 2))].
	numPoints := (endPts at: contourCount) + 1.
	p := g + 10 + (contourCount * 2).
	p := p + 2 + (self u16: p).
	flags := ByteArray new: numPoints.
	x := 1.
	[x <= numPoints] whileTrue: [
		flag := data at: p.
		p := p + 1.
		flags at: x put: flag.
		x := x + 1.
		(flag bitAnd: 8) ~= 0 ifTrue: [
			repeat := data at: p.
			p := p + 1.
			repeat timesRepeat: [x <= numPoints ifTrue: [flags at: x put: flag. x := x + 1]]]].
	xs := Array new: numPoints.
	x := 0.
	1 to: numPoints do: [:i |
		flag := flags at: i.
		(flag bitAnd: 2) ~= 0
			ifTrue: [
				(flag bitAnd: 16) ~= 0 ifTrue: [x := x + (data at: p)] ifFalse: [x := x - (data at: p)].
				p := p + 1]
			ifFalse: [
				(flag bitAnd: 16) = 0 ifTrue: [x := x + (self s16: p). p := p + 2]].
		xs at: i put: x].
	ys := Array new: numPoints.
	y := 0.
	1 to: numPoints do: [:i |
		flag := flags at: i.
		(flag bitAnd: 4) ~= 0
			ifTrue: [
				(flag bitAnd: 32) ~= 0 ifTrue: [y := y + (data at: p)] ifFalse: [y := y - (data at: p)].
				p := p + 1]
			ifFalse: [
				(flag bitAnd: 32) = 0 ifTrue: [y := y + (self s16: p). p := p + 2]].
		ys at: i put: y].
	start := 1.
	endPts do: [:last |
		contour := Array new: (last + 2 - start) * 3.
		start to: last + 1 do: [:i |
			| k px py |
			k := (i - start) * 3.
			px := xs at: i.
			py := ys at: i.
			anArrayOrNil isNil ifFalse: [
				| tx |
				tx := ((anArrayOrNil at: 1) * px) + ((anArrayOrNil at: 3) * py) + (anArrayOrNil at: 5).
				py := ((anArrayOrNil at: 2) * px) + ((anArrayOrNil at: 4) * py) + (anArrayOrNil at: 6).
				px := tx].
			contour at: k + 1 put: px.
			contour at: k + 2 put: py.
			contour at: k + 3 put: ((flags at: i) bitAnd: 1) ~= 0].
		contour isEmpty ifFalse: [aCollection add: contour].
		start := last + 2]
!
addCompositeAt: g to: aCollection transform: anArrayOrNil depth: depth
	"Components: flags, glyph index, offsets (or point numbers, unsupported: treated as 0) and an optional scale or 2x2 matrix (F2Dot14)."
	| p flags glyph dx dy a b c d m more |
	p := g + 10.
	more := true.
	[more] whileTrue: [
		flags := self u16: p.
		glyph := self u16: p + 2.
		p := p + 4.
		(flags bitAnd: 1) ~= 0
			ifTrue: [dx := self s16: p. dy := self s16: p + 2. p := p + 4]
			ifFalse: [
				dx := data at: p. dy := data at: p + 1.
				dx > 127 ifTrue: [dx := dx - 256].
				dy > 127 ifTrue: [dy := dy - 256].
				p := p + 2].
		(flags bitAnd: 2) = 0 ifTrue: [dx := 0. dy := 0].
		a := 1. b := 0. c := 0. d := 1.
		(flags bitAnd: 8) ~= 0
			ifTrue: [a := d := (self s16: p) / 16384.0. p := p + 2]
			ifFalse: [
				(flags bitAnd: 16r40) ~= 0
					ifTrue: [a := (self s16: p) / 16384.0. d := (self s16: p + 2) / 16384.0. p := p + 4]
					ifFalse: [
						(flags bitAnd: 16r80) ~= 0 ifTrue: [
							a := (self s16: p) / 16384.0. b := (self s16: p + 2) / 16384.0.
							c := (self s16: p + 4) / 16384.0. d := (self s16: p + 6) / 16384.0.
							p := p + 8]]].
		m := Array with: a with: b with: c with: d with: dx with: dy.
		anArrayOrNil isNil ifFalse: [m := self compose: m with: anArrayOrNil].
		self addContoursOf: glyph to: aCollection transform: m depth: depth + 1.
		more := (flags bitAnd: 16r20) ~= 0]
!
compose: inner with: outer
	"Answer the affine transform that applies inner, then outer (both {a. b. c. d. e. f}: x' = a x + c y + e, y' = b x + d y + f)."
	| a b c d e f |
	a := (outer at: 1) * (inner at: 1) + ((outer at: 3) * (inner at: 2)).
	b := (outer at: 2) * (inner at: 1) + ((outer at: 4) * (inner at: 2)).
	c := (outer at: 1) * (inner at: 3) + ((outer at: 3) * (inner at: 4)).
	d := (outer at: 2) * (inner at: 3) + ((outer at: 4) * (inner at: 4)).
	e := (outer at: 1) * (inner at: 5) + ((outer at: 3) * (inner at: 6)) + (outer at: 5).
	f := (outer at: 2) * (inner at: 5) + ((outer at: 4) * (inner at: 6)) + (outer at: 6).
	^Array with: a with: b with: c with: d with: e with: f
! !

!TrueTypeFont methodsFor: 'color glyphs'!
colorBaseGlyphCount
	"The number of COLR base glyphs (0 without COLR)."
	(tables includesKey: 'COLR') ifFalse: [^0].
	^self u16: (self tableOffset: 'COLR') + 2
!
colorLayersOf: glyphIndex
	"Answer the layers of a COLR base glyph, bottom first, as a flat Array: layer glyph index, CPAL palette index (16rFFFF: the text color), ...; nil if glyphIndex is not a base glyph."
	| c records lo hi mid rec g n layers result |
	(tables includesKey: 'COLR') ifFalse: [^nil].
	c := self tableOffset: 'COLR'.
	records := c + (self u32: c + 4).
	lo := 0.
	hi := (self u16: c + 2) - 1.
	[lo <= hi] whileTrue: [
		mid := lo + hi // 2.
		rec := records + (mid * 6).
		g := self u16: rec.
		g = glyphIndex ifTrue: [
			n := self u16: rec + 4.
			layers := c + (self u32: c + 8) + ((self u16: rec + 2) * 4).
			result := Array new: n * 2.
			0 to: n - 1 do: [:i |
				result at: i * 2 + 1 put: (self u16: layers + (i * 4)).
				result at: i * 2 + 2 put: (self u16: layers + (i * 4) + 2)].
			^result].
		g < glyphIndex ifTrue: [lo := mid + 1] ifFalse: [hi := mid - 1]].
	^nil
!
palette
	"CPAL palette 0: an Array of Colors (empty without CPAL)."
	| c n records |
	palette isNil ifFalse: [^palette].
	(tables includesKey: 'CPAL') ifFalse: [^palette := #()].
	c := self tableOffset: 'CPAL'.
	n := self u16: c + 2.
	records := c + (self u32: c + 8) + ((self u16: c + 12) * 4).
	^palette := (0 to: n - 1) collect: [:i | | p |
		p := records + (i * 4).
		Color r: (data at: p + 2) / 255.0 g: (data at: p + 1) / 255.0 b: (data at: p) / 255.0 a: (data at: p + 3) / 255.0]
!
ligatures
	"The ligatures of the lookups of GSUB's ccmp feature (type 4, also inside extension lookups, type 7): a Dictionary first glyph index -> Array of {the other components (an Array of glyph indices). the ligature glyph index}, longest first."
	| g features lookups indices lookup type subtable result |
	ligatures isNil ifFalse: [^ligatures].
	result := Dictionary new.
	(tables includesKey: 'GSUB') ifFalse: [^ligatures := result].
	g := self tableOffset: 'GSUB'.
	features := g + (self u16: g + 6).
	lookups := g + (self u16: g + 8).
	indices := Set new.
	0 to: (self u16: features) - 1 do: [:i | | rec feature |
		rec := features + 2 + (i * 6).
		(data copyFrom: rec to: rec + 3) asString = 'ccmp' ifTrue: [
			feature := features + (self u16: rec + 4).
			0 to: (self u16: feature + 2) - 1 do: [:k | indices add: (self u16: feature + 4 + (k * 2))]]].
	indices asSortedCollection do: [:index |
		lookup := lookups + (self u16: lookups + 2 + (index * 2)).
		0 to: (self u16: lookup + 4) - 1 do: [:k |
			type := self u16: lookup.
			subtable := lookup + (self u16: lookup + 6 + (k * 2)).
			type = 7 ifTrue: [
				type := self u16: subtable + 2.
				subtable := subtable + (self u32: subtable + 4)].
			type = 4 ifTrue: [self addLigaturesAt: subtable to: result]]].
	result keysAndValuesDo: [:first :list |
		result at: first put: (list asSortedCollection: [:a :b | a first size >= b first size]) asArray].
	^ligatures := result
!
addLigaturesAt: subtable to: aDictionary
	"A ligature substitution subtable (format 1): for each glyph of its coverage a set of ligatures."
	| firsts set |
	firsts := self coverageGlyphsAt: subtable + (self u16: subtable + 2).
	1 to: (self u16: subtable + 4) do: [:i |
		set := subtable + (self u16: subtable + 6 + (i - 1 * 2)).
		0 to: (self u16: set) - 1 do: [:k | | lig components |
			lig := set + (self u16: set + 2 + (k * 2)).
			components := (1 to: (self u16: lig + 2) - 1) collect: [:c | self u16: lig + 2 + (c * 2)].
			(aDictionary at: (firsts at: i) ifAbsentPut: [OrderedCollection new])
				add: (Array with: components with: (self u16: lig))]]
!
coverageGlyphsAt: coverage
	"The glyph indices of a coverage table (format 1: a list, 2: ranges), in coverage index order."
	| result |
	(self u16: coverage) = 1 ifTrue: [
		^(1 to: (self u16: coverage + 2)) collect: [:i | self u16: coverage + 2 + (i * 2)]].
	result := OrderedCollection new.
	0 to: (self u16: coverage + 2) - 1 do: [:r | | rec |
		rec := coverage + 4 + (r * 6).
		(self u16: rec) to: (self u16: rec + 2) do: [:each | result add: each]].
	^result asArray
! !

!TrueTypeFont methodsFor: 'compacting'!
compact
	"Keep only the tables I read and the outlines of the glyphs the cmap reaches (the bytes of a face kept in the image: alternates that only GSUB reaches go). Glyph indices, metrics and mapped outlines stay."
	| marks loca glyf pos size kept cmapStart |
	marks := self mappedGlyphs.
	loca := ByteArray new: numGlyphs + 1 * 4.
	pos := 0.
	0 to: numGlyphs do: [:i |
		self bytes: loca at: i * 4 + 1 putU32: pos.
		(i < numGlyphs and: [(marks at: i + 1) = 1]) ifTrue: [pos := pos + (self glyphDataSize: i)]].
	glyf := ByteArray new: pos.
	pos := 1.
	0 to: numGlyphs - 1 do: [:i |
		((marks at: i + 1) = 1 and: [(size := self glyphDataSize: i) > 0]) ifTrue: [
			glyf replaceFrom: pos to: pos + size - 1 with: data startingAt: (self glyphDataOffset: i).
			pos := pos + size]].
	kept := OrderedCollection new.
	#('head' 'hhea' 'maxp' 'OS/2' 'hmtx' 'cmap') do: [:tag |
		(tables includesKey: tag) ifTrue: [
			kept add: tag -> (data copyFrom: (self tableOffset: tag) to: (self tableOffset: tag) + ((tables at: tag) at: 2) - 1)]].
	kept add: 'loca' -> loca; add: 'glyf' -> glyf.
	cmapStart := self tableOffset: 'cmap'.
	data := ByteArray new: (kept inject: 0 into: [:sum :each | sum + each value size]).
	tables := Dictionary new.
	pos := 0.
	kept do: [:each |
		data replaceFrom: pos + 1 to: pos + each value size with: each value startingAt: 1.
		tables at: each key put: (Array with: pos with: each value size).
		pos := pos + each value size].
	cmapOffset := cmapOffset - cmapStart + (self tableOffset: 'cmap').
	indexToLocFormat := 1
!
mappedGlyphs
	"Answer a ByteArray with 1 at g + 1 for .notdef, every glyph g the cmap maps and their components."
	| marks todo groups rec first segX2 end g |
	marks := ByteArray new: numGlyphs.
	todo := OrderedCollection with: 0.
	cmapFormat = 12
		ifTrue: [
			groups := self u32: cmapOffset + 12.
			0 to: groups - 1 do: [:i |
				rec := cmapOffset + 16 + (i * 12).
				first := self u32: rec + 8.
				first to: first + (self u32: rec + 4) - (self u32: rec) do: [:each | todo add: each]]]
		ifFalse: [
			segX2 := self u16: cmapOffset + 6.
			0 to: segX2 // 2 - 1 do: [:i |
				end := (self u16: cmapOffset + 14 + (i * 2)) min: 16rFFFE.
				(self u16: cmapOffset + 16 + segX2 + (i * 2)) to: end do: [:cp | todo add: (self format4GlyphIndexFor: cp)]]].
	[todo isEmpty] whileFalse: [
		g := todo removeLast.
		(g < numGlyphs and: [(marks at: g + 1) = 0]) ifTrue: [
			marks at: g + 1 put: 1.
			todo addAll: (self componentsOf: g)]].
	^marks
!
bytes: aByteArray at: offset putU32: anInteger
	"Store anInteger big-endian at the 1-based offset."
	0 to: 3 do: [:i | aByteArray at: offset + i put: ((anInteger bitShift: (3 - i) * -8) bitAnd: 255)]
! !

!TrueTypeFont methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a TrueTypeFont('; nextPutAll: (name ifNil: ['?']); nextPut: $)
! !

!TrueTypeFont class methodsFor: 'instance creation'!
named: aString bytes: aByteArray
	^self new setName: aString data: aByteArray
!
fromFile: aPath
	^self named: (aPath copyAfterLast: $/) bytes: (File readBytes: aPath)
! !
