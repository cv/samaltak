Object subclass: #Font
	instanceVariableNames: 'face size scale letterSpacing lineHeight baselineOffset uppercase pixelsPerUnit phases glyphTable wideGlyphs deviceAdvances wideAdvances atlas'
	classVariableNames: 'DeviceScale Emoji Faces Fallbacks FontsDirectory RasterizeLock Standard SubpixelPhases'
	package: 'Graphics-Canvas'!

Font comment: 'I am a TrueTypeFont at a pixel size (CSS px = points) for a device scale (2 on Retina), with optional letter spacing and capitals (for tracked-caps headers). I answer metrics in points (ascent, descent, lineHeight, widthOf:) and supply Canvas with rasterized glyphs: each glyph is rasterized lazily at device resolution for one of SubpixelPhases horizontal subpixel offsets and kept in the shared GlyphAtlas.

The standard fonts (Font ui, uiBold, uiItalic, code, codeBold, codeItalic, header, title, small, smallItalic) follow docs/ui.md and the prototype''s blue-book/pi-orb styles. Stage 2 loads every face the system uses from fonts/ into the image (imageFaceNames: the standard faces, the fallback faces and Twemoji) and pre-rasterizes ASCII and the UI symbols, so faces and atlas live in the image and survive snapshots: the system never reads a font file at run time.

A code point my face lacks is drawn from the first fallback face that has it (fallbackFaceNames), at the same em size on the same baseline, with that glyph''s advance. Controls and invisible format characters (isInvisible:) draw nothing and advance 0; a code point no face has draws as a box with its hex digits.

A grapheme cluster that ColorEmoji (Font class>>emoji, the Twemoji face) takes for an emoji is drawn as its color glyphs instead: each glyph''s layers rasterized at my em size (subpixel phase 0) and centred on my ascent and descent, drawn in their palette colors; it advances by the glyphs'' advances. Width, hit-testing (widthOf:from:to:, indexAt:in:) and Canvas>>drawString: agree on it; colorClusterEndAt:in:to: finds such a cluster.'!

!Font methodsFor: 'initialization'!
setFace: aTrueTypeFont size: pixelSize scale: deviceScale
	face := aTrueTypeFont.
	size := pixelSize.
	scale := deviceScale.
	letterSpacing := 0.
	uppercase := false.
	lineHeight := nil.
	baselineOffset := nil.
	self resetGlyphs
!
resetGlyphs
	"Forget rasterized glyphs and cached advances (after the atlas was reset or the parameters changed)."
	pixelsPerUnit := (size * scale / face unitsPerEm) asFloat.
	phases := self class subpixelPhases.
	glyphTable := Array new: 256 * phases.
	wideGlyphs := Dictionary new.
	deviceAdvances := Array new: 256.
	0 to: 255 do: [:cp | deviceAdvances at: cp + 1 put: (self computeDeviceAdvanceOf: cp)].
	wideAdvances := Dictionary new.
	atlas := GlyphAtlas default
!
letterSpacing: points
	letterSpacing := points.
	self resetGlyphs
!
lineHeight: points
	lineHeight := points.
	baselineOffset := nil
!
beUppercase
	uppercase := true
! !

!Font methodsFor: 'accessing'!
face
	^face
!
size
	"The pixel size (CSS px, = points)."
	^size
!
scale
	"Device pixels per point."
	^scale
!
letterSpacing
	^letterSpacing
!
isUppercase
	^uppercase
!
phases
	^phases
!
glyphTable
	"Array: index codePoint * phases + phase + 1 (code points < 256) -> GlyphInfo or nil (not yet rasterized)."
	^glyphTable
!
deviceAdvances
	"Array: index codePoint + 1 (code points < 256) -> advance in device pixels, letter spacing included."
	^deviceAdvances
!
pixelsPerUnit
	"Device pixels per font unit."
	^pixelsPerUnit
!
atScale: aNumber
	"Keep logical typography while matching the destination display density."
	scale = aNumber ifTrue: [^self].
	^self copy rescaleTo: aNumber
! !

!Font methodsFor: 'metrics'!
ascent
	"Points above the baseline (hhea, as browsers on macOS use)."
	^face ascender * size / face unitsPerEm
!
descent
	"Points below the baseline (positive)."
	^face descender negated * size / face unitsPerEm
!
height
	^self ascent + self descent
!
lineHeight
	"Height of a line box in points (the CSS line-height)."
	^lineHeight ifNil: [(face ascender - face descender + face lineGap) * size / face unitsPerEm]
!
baselineOffset
	"Points from the top of a line box to the baseline: half the leading, then the ascent (CSS inline layout; like Chrome on macOS, the ascent is rounded and the descent rounded up to whole points)."
	^baselineOffset ifNil: [
		| a d |
		a := self ascent rounded.
		d := self descent ceiling.
		baselineOffset := (self lineHeight - (a + d)) / 2 + a]
!
xHeight
	^(face xHeight ifNil: [face ascender // 2]) * size / face unitsPerEm
!
capHeight
	^(face capHeight ifNil: [face ascender]) * size / face unitsPerEm
!
deviceAdvanceOf: codePoint
	codePoint < 256 ifTrue: [^deviceAdvances at: codePoint + 1].
	^wideAdvances at: codePoint ifAbsent: [wideAdvances at: codePoint put: (self computeDeviceAdvanceOf: codePoint)]
!
computeDeviceAdvanceOf: codePoint
	| f |
	(self class isInvisible: codePoint) ifTrue: [^0].
	f := self faceFor: codePoint.
	f isNil ifTrue: [^(self missingBoxExtentOf: codePoint) x + (2 * self missingBoxMargin) + (letterSpacing * scale)].
	^(f advanceWidthOfCodePoint: codePoint) * (self pixelsPerUnitOf: f) + (letterSpacing * scale)
!
faceFor: codePoint
	"Answer the face that draws codePoint: mine, else the first fallback face that has it; nil if none has it."
	(face includesCodePoint: codePoint) ifTrue: [^face].
	^self class fallbackFaceFor: codePoint
!
pixelsPerUnitOf: aFace
	aFace == face ifTrue: [^pixelsPerUnit].
	^(size * scale / aFace unitsPerEm) asFloat
!
advanceOf: aCharacter
	"Points the pen moves after aCharacter."
	^(self deviceAdvanceOf: aCharacter value) / scale
!
widthOf: aString
	"Answer the width of aString in points (with letter spacing after each character, as CSS)."
	^self widthOf: aString from: 1 to: aString size
!
naturalWidthOf: aString
	"The width of aString as a layout engine such as Qt's sizes a line of text: its advances (widthOf:), and, if the last glyph's ink reaches past its advance (an icon of a Nerd Font, an italic f), as far as that ink."
	| cp f glyph bounds overhang |
	aString isEmpty ifTrue: [^0].
	cp := (uppercase ifTrue: [aString last asUppercase] ifFalse: [aString last]) value.
	f := self faceFor: cp.
	f isNil ifTrue: [^self widthOf: aString].
	glyph := f glyphIndexFor: cp.
	bounds := f boundsOf: glyph.
	bounds isNil ifTrue: [^self widthOf: aString].
	overhang := bounds right - (f advanceWidthOf: glyph).
	^(self widthOf: aString) + ((overhang max: 0) * size / f unitsPerEm)
!
widthOf: aString from: start to: stop
	"Below U+203C character by character; from the character before the first one beyond, cluster by cluster (color emoji)."
	| sum last string cp |
	string := uppercase ifTrue: [aString asUppercase] ifFalse: [aString].
	sum := last := 0.0.
	start to: stop do: [:i |
		cp := (string at: i) value.
		cp >= 16r203C ifTrue: [
			^(i > start ifTrue: [last] ifFalse: [sum]) + (self deviceWidthOf: string from: (i - 1 max: start) to: stop) / scale].
		last := sum.
		sum := sum + (cp < 256 ifTrue: [deviceAdvances at: cp + 1] ifFalse: [self deviceAdvanceOf: cp])].
	^sum / scale
!
deviceWidthOf: string from: start to: stop
	"Device pixels, as Canvas>>drawString: advances: a color emoji cluster by its glyphs, other characters by theirs."
	| sum cp i j |
	sum := 0.0.
	i := start.
	[i <= stop] whileTrue: [
		cp := (string at: i) value.
		((cp >= 16r203C or: [i < stop and: [(string at: i + 1) value >= 16r203C]])
				and: [(j := self colorClusterEndAt: i in: string to: stop) > 0])
			ifTrue: [
				sum := sum + (self deviceAdvanceOfColorCluster: string from: i to: j).
				i := j + 1]
			ifFalse: [
				sum := sum + (cp < 256 ifTrue: [deviceAdvances at: cp + 1] ifFalse: [self deviceAdvanceOf: cp]).
				i := i + 1]].
	^sum
!
indexAt: x in: aString
	"Answer the grapheme cluster boundary nearest to x points from the start of aString (0 = before the first character)."
	| pen advance i j |
	pen := 0.0.
	i := 0.
	[i < aString size] whileTrue: [
		j := aString graphemeClusterEndAfter: i.
		advance := self widthOf: aString from: i + 1 to: j.
		x < (pen + (advance / 2)) ifTrue: [^i].
		pen := pen + advance.
		i := j].
	^aString size
! !

!Font methodsFor: 'glyphs'!
glyphForCodePoint: codePoint phase: phase
	"Answer the GlyphInfo, rasterizing it on first use. Window Processes draw concurrently: one at a time rasterizes, and a glyph another one rasterized meanwhile is used, so every drawing of a glyph refers to the same atlas entry (retained drawing compares them)."
	| key table |
	codePoint < 256
		ifTrue: [key := codePoint * phases + phase + 1. table := glyphTable]
		ifFalse: [key := codePoint * phases + phase. table := wideGlyphs].
	(table at: key ifAbsent: [nil]) ifNotNil: [:info | ^info].
	^self class rasterizing: [
		(table at: key ifAbsent: [nil]) ifNil: [table at: key put: (self rasterizeCodePoint: codePoint phase: phase)]]
!
rasterizeCodePoint: codePoint phase: phase
	"Rasterize the glyph with its origin phase / phases device pixels right of a pixel boundary; answer a GlyphInfo."
	| f |
	(self class isInvisible: codePoint) ifTrue: [^GlyphInfo blank].
	f := self faceFor: codePoint.
	f isNil ifTrue: [^self rasterizeMissing: codePoint].
	^self rasterizeGlyph: (f glyphIndexFor: codePoint) of: f phase: phase raisedBy: 0
!
rasterizeGlyph: glyph of: f phase: phase raisedBy: raise
	"Rasterize glyph of the face f, its origin phase / phases device pixels right of a pixel boundary and raise device pixels above the baseline; answer a GlyphInfo."
	| ppu box contours dx left top right bottom w h rasterizer |
	ppu := self pixelsPerUnitOf: f.
	box := f boundsOf: glyph.
	box isNil ifTrue: [^GlyphInfo blank].
	contours := f contoursOf: glyph.
	contours isEmpty ifTrue: [^GlyphInfo blank].
	dx := phase / phases asFloat.
	left := (box left * ppu + dx) floor.
	right := (box right * ppu + dx) ceiling.
	top := (box bottom * ppu) negated floor.
	bottom := (box top * ppu) negated ceiling.
	w := right - left max: 1.
	h := bottom - top max: 1.
	rasterizer := GlyphRasterizer width: w height: h.
	contours do: [:each |
		rasterizer addContour: each scale: ppu offsetX: dx - left offsetY: top negated].
	^self glyphInfo: rasterizer coverage left: left top: top - raise width: w height: h
!
glyphInfo: coverage left: left top: top width: w height: h
	"Store a w×h coverage in the atlas; answer its GlyphInfo (left, top: device pixels from the pen on the baseline)."
	| slot |
	slot := atlas add: coverage width: w height: h.
	^GlyphInfo
		template: (DisplayList glyphTemplateLeft: left top: top width: w height: h atlasX: (slot at: 2) atlasY: (slot at: 3))
		page: (slot at: 1) width: w height: h
!
rasterizeMissing: codePoint
	"A code point no face has: a hollow box as tall as a capital with the code point in hex inside (two rows of 3×5 dots) when that fits."
	| extent w h u b coverage n cols top bits x y |
	extent := self missingBoxExtentOf: codePoint.
	w := extent x.
	h := extent y.
	u := h // 15.
	b := u max: 1.
	coverage := ByteArray new: w * h.
	0 to: h - 1 do: [:row | 0 to: w - 1 do: [:col |
		(col < b or: [row < b or: [col >= (w - b) or: [row >= (h - b)]]]) ifTrue: [coverage at: row * w + col + 1 put: 255]]].
	u > 0 ifTrue: [
		n := codePoint > 16rFFFF ifTrue: [6] ifFalse: [4].
		cols := n // 2.
		top := h - (11 * u) // 2.
		0 to: n - 1 do: [:i |
			bits := self class hexDigitDots at: ((codePoint bitShift: (n - 1 - i) * -4) bitAnd: 15) + 1.
			0 to: 14 do: [:k |
				((bits bitShift: k - 14) bitAnd: 1) = 1 ifTrue: [
					x := (i \\ cols * 4 + 2 + (k \\ 3)) * u.
					y := top + ((i // cols * 6 + (k // 3)) * u).
					y to: y + u - 1 do: [:row |
						coverage replaceFrom: row * w + x + 1 to: row * w + x + u with: (ByteArray new: u withAll: 255) startingAt: 1]]]]].
	^self glyphInfo: coverage left: self missingBoxMargin top: h negated width: w height: h
!
missingBoxExtentOf: codePoint
	"Device pixels: as tall as a capital; wide enough for a frame around two rows of two (BMP) or three hex digits, or 0.6 of the height when too small for digits."
	| h u |
	h := (self capHeight * scale) rounded max: 3.
	u := h // 15.
	u = 0 ifTrue: [^((h * 0.6) rounded max: 3) @ h].
	^((codePoint > 16rFFFF ifTrue: [3] ifFalse: [2]) * 4 + 3 * u) @ h
!
missingBoxMargin
	"Device pixels left and right of a missing-glyph box."
	^(self capHeight * scale / 10) rounded max: 1
!
prerasterize: aString
	"Rasterize the characters of aString at every subpixel phase."
	| string |
	string := uppercase ifTrue: [aString asUppercase] ifFalse: [aString].
	string do: [:ch |
		0 to: phases - 1 do: [:phase | self glyphForCodePoint: ch value phase: phase]]
! !

!Font methodsFor: 'color emoji'!
colorClusterEndAt: i in: aString to: stop
	"Answer the end of the grapheme cluster at i if it ends by stop and is drawn as color emoji, else 0. Every emoji cluster has a code point from U+203C on, so callers ask only when the character at i or the next one has; here the cluster is looked for only when the next code point asks for emoji (FE0F, ZWJ, a keycap, a modifier, a tag) or the one at i is Emoji_Presentation."
	| cp next j emoji |
	cp := (aString at: i) value.
	next := i < stop ifTrue: [(aString at: i + 1) value] ifFalse: [0].
	(next = 16rFE0F or: [next = 16r200D or: [next = 16r20E3
		or: [(next between: 16r1F3FB and: 16r1F3FF) or: [next between: 16rE0020 and: 16rE007F]]]]) ifFalse: [
			(((cp between: 16r231A and: 16r2B55) or: [cp between: 16r1F004 and: 16r1FAFF])
				and: [Unicode isEmojiPresentationCode: cp]) ifFalse: [^0]].
	(emoji := self class emoji) isNil ifTrue: [^0].
	j := aString graphemeClusterEndAfter: i - 1.
	(j > stop or: [(emoji glyphsOf: aString from: i to: j) isNil]) ifTrue: [^0].
	^j
!
colorGlyphsFrom: start to: stop in: aString
	"The color glyphs of the emoji cluster start .. stop (see colorClusterEndAt:in:to:)."
	^self class emoji glyphsOf: aString from: start to: stop
!
colorLayersOf: glyph
	"A color glyph's layers: layer glyph, Color (nil: the text color), ..."
	^self class emoji layersOf: glyph
!
deviceAdvanceOfColorGlyph: glyph
	| f |
	f := self class emoji face.
	^(f advanceWidthOf: glyph) * (self pixelsPerUnitOf: f) + (letterSpacing * scale)
!
deviceAdvanceOfColorCluster: aString from: start to: stop
	^(self colorGlyphsFrom: start to: stop in: aString) inject: 0 into: [:sum :each | sum + (self deviceAdvanceOfColorGlyph: each)]
!
colorLayerGlyph: layerGlyph
	"Answer the GlyphInfo of a layer of a color glyph (subpixel phase 0), rasterizing it on first use; kept with my glyphs under a negative key."
	| key |
	key := (layerGlyph + 1) negated.
	(wideGlyphs at: key ifAbsent: [nil]) ifNotNil: [:info | ^info].
	^self class rasterizing: [
		(wideGlyphs at: key ifAbsent: [nil]) ifNil: [wideGlyphs at: key put: (self rasterizeColorLayer: layerGlyph)]]
!
rasterizeColorLayer: layerGlyph
	"At my em size, the middle of the emoji face's typographic box raised to the middle of my ascent and descent."
	| f raise |
	f := self class emoji face.
	raise := ((face ascender + face descender) * pixelsPerUnit - ((f typoAscender + f typoDescender) * (self pixelsPerUnitOf: f))) / 2.
	^self rasterizeGlyph: layerGlyph of: f phase: 0 raisedBy: raise rounded
! !

!Font methodsFor: 'inspecting'!
glyphFor: aCharacter
	"Answer aCharacter's glyph as Canvas draws it: a GlyphForm of its coverage."
	^GlyphForm font: self character: aCharacter
! !

!Font methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Font('; nextPutAll: face name; space; print: size; nextPutAll: 'px @'; print: scale; nextPut: $)
! !

!Font class methodsFor: 'instance creation'!
face: aTrueTypeFont size: pixelSize
	^self face: aTrueTypeFont size: pixelSize scale: self deviceScale
!
face: aTrueTypeFont size: pixelSize scale: deviceScale
	^self new setFace: aTrueTypeFont size: pixelSize scale: deviceScale
!
faceNamed: aString size: pixelSize
	^self face: (self faceNamed: aString) size: pixelSize
! !

!Font class methodsFor: 'settings'!
deviceScale
	"Device pixels per point the standard fonts are rasterized for."
	^DeviceScale ifNil: [2]
!
deviceScale: aNumber
	"Switch the standard fonts to another display scale (glyphs are rasterized again lazily)."
	DeviceScale := aNumber.
	Standard := nil
!
subpixelPhases
	"Horizontal subpixel positions each glyph is rasterized at."
	^SubpixelPhases ifNil: [4]
!
subpixelPhases: anInteger
	SubpixelPhases := anInteger.
	self resetGlyphs
! !

!Font class methodsFor: 'faces'!
emoji
	"Answer the ColorEmoji of the Twemoji face in the image, or nil without it. Not a fallback face: it maps digits, joiners and tags to empty glyphs."
	Emoji isNil ifTrue: [
		self rasterizing: [
			Emoji isNil ifTrue: [Emoji := (self fallbackFaceNamed: self emojiFaceName) ifNil: [false] ifNotNil: [:f | ColorEmoji face: f]]]].
	^Emoji == false ifTrue: [nil] ifFalse: [Emoji]
!
fontsDirectory
	"Answer the directory with the .ttf files (read at stage 2): fonts/ in the current directory, else next to the image's build directory."
	| image |
	FontsDirectory isNil ifFalse: [^FontsDirectory].
	(File exists: 'fonts/IosevkaEtoile-Regular.ttf') ifTrue: [^'fonts'].
	image := Smalltalk vm imagePath.
	^(image copyUpToLast: $/) , '/../fonts'
!
fontsDirectory: aPath
	FontsDirectory := aPath
!
faceNamed: aString
	"Answer the TrueTypeFont of fonts/<aString>.ttf: the one in the image, else the file's, read as it is needed (the faces of imageFaceNames are in the image; the runtime image has none)."
	Faces isNil ifTrue: [Faces := Dictionary new].
	^Faces at: aString ifAbsent: [
		Faces at: aString put: (TrueTypeFont fromFile: self fontsDirectory , '/' , aString , '.ttf')]
!
faces
	^Faces ifNil: [Dictionary new]
!
faceFromFile: aPath
	"A face from a .ttf file outside fonts/, e.g. a system font fontconfig names, read as it is needed (not kept in faces)."
	^TrueTypeFont fromFile: aPath
!
fallbackFaceNames
	"Faces tried in order for a code point a font's face lacks: Iosevka Etoile (symbols, math, Greek and Cyrillic for the code font), monochrome emoji, symbols, CJK (Simplified Chinese glyph forms, kana), Hangul."
	^#('IosevkaEtoile-Regular' 'NotoEmoji-Regular' 'NotoSansSymbols2-Regular' 'NotoSansSC-Regular' 'NotoSansKR-Hangul')
!
fallbackFaceFor: codePoint
	"Answer the first fallback face that has codePoint, or nil; cached per code point."
	Fallbacks isNil ifTrue: [Fallbacks := Dictionary new].
	^Fallbacks at: codePoint ifAbsent: [
		self rasterizing: [
			Fallbacks at: codePoint put: (self fallbackFaceNames inject: nil into: [:found :each |
				found ifNil: [(self fallbackFaceNamed: each) ifNotNil: [:f | (f includesCodePoint: codePoint) ifTrue: [f]]]])]]
!
fallbackFaceNamed: aString
	"The fallback face aString: the image's; in the runtime image, which has none, read from fonts/ when first needed (nil without the file)."
	(self imageFaceNamed: aString) ifNotNil: [:face | ^face].
	(Smalltalk isRuntimeImage and: [File exists: self fontsDirectory , '/' , aString , '.ttf']) ifFalse: [^nil].
	^[self faceNamed: aString] on: Error do: [:e | e return: nil]
!
emojiFaceName
	^'Twemoji'
!
imageFaceNames
	"The faces stage 2 loads into the image: the standard faces, the fallback faces and the color emoji face. The runtime image keeps none: its applications read the faces they draw from their files, as they need them."
	| names |
	Smalltalk isRuntimeImage ifTrue: [^#()].
	names := OrderedCollection new.
	self standardSpecs do: [:spec | (names includes: (spec at: 2)) ifFalse: [names add: (spec at: 2)]].
	self fallbackFaceNames do: [:each | (names includes: each) ifFalse: [names add: each]].
	names add: self emojiFaceName.
	^names asArray
!
isOptionalFace: aString
	"Not a standard face: stage 2 leaves it out when fonts/ lacks it."
	^(self standardSpecs anySatisfy: [:spec | (spec at: 2) = aString]) not
!
imageFaceNamed: aString
	"Answer the face as loaded into the image, or nil (it was missing from fonts/ at stage 2). Never reads a file."
	^self faces at: aString ifAbsent: [nil]
!
isInvisible: codePoint
	"Controls and default-ignorable format characters (zero-width space and joiners, bidi controls, word joiner, variation selectors, BOM, tags): drawn as nothing, no advance."
	codePoint < 16r20 ifTrue: [^true].
	codePoint < 16r7F ifTrue: [^false].
	codePoint < 16rA0 ifTrue: [^true].
	codePoint < 16r34F ifTrue: [^false].
	^codePoint = 16r34F or: [codePoint = 16r61C or: [(codePoint between: 16r180B and: 16r180F)
		or: [(codePoint between: 16r200B and: 16r200F) or: [(codePoint between: 16r202A and: 16r202E)
		or: [(codePoint between: 16r2060 and: 16r206F) or: [(codePoint between: 16rFE00 and: 16rFE0F)
		or: [codePoint = 16rFEFF or: [codePoint between: 16rE0000 and: 16rE0FFF]]]]]]]]
!
hexDigitDots
	"3×5 dot patterns of the hex digits 0-F (rows top to bottom, most significant bit first), for missing-glyph boxes."
	^#(16r7B6F 16r2C97 16r73E7 16r73CF 16r5BC9 16r79CF 16r79EF 16r7249 16r7BEF 16r7BCF 16r7BED 16r6BAE 16r7927 16r6B6E 16r79E7 16r79E4)
! !

!Font class methodsFor: 'standard fonts'!
standardSpecs
	"name, face, pixel size, line height, letter spacing (em), capitals"
	^#(
		#(#ui 'IosevkaEtoile-Regular' 13.5 18 0 false)
		#(#uiBold 'IosevkaEtoile-Bold' 13.5 18 0 false)
		#(#uiItalic 'IosevkaEtoile-Italic' 13.5 18 0 false)
		#(#code 'JetBrainsMono-Regular' 13 20 0 false)
		#(#codeBold 'JetBrainsMono-Bold' 13 20 0 false)
		#(#codeItalic 'JetBrainsMono-Italic' 13 20 0 false)
		#(#header 'IosevkaEtoile-Bold' 10.5 14 0.08 true)
		#(#title 'IosevkaEtoile-Bold' 13 15 0.01 false)
		#(#small 'IosevkaEtoile-Regular' 12 16 0 false)
		#(#smallItalic 'IosevkaEtoile-Italic' 12 16 0 false))
!
named: aSymbol
	"Answer a standard font (see standardSpecs)."
	Standard isNil ifTrue: [Standard := IdentityDictionary new].
	^Standard at: aSymbol ifAbsent: [
		| spec font |
		spec := self standardSpecs detect: [:each | each first == aSymbol] ifNone: [^self error: 'No standard font ', aSymbol printString].
		font := self faceNamed: (spec at: 2) size: (spec at: 3).
		font lineHeight: (spec at: 4).
		(spec at: 5) = 0 ifFalse: [font letterSpacing: (spec at: 5) * (spec at: 3)].
		(spec at: 6) ifTrue: [font beUppercase].
		Standard at: aSymbol put: font]
!
standardFonts
	^self standardSpecs collect: [:spec | self named: spec first]
!
ui
	^self named: #ui
!
uiBold
	^self named: #uiBold
!
uiItalic
	^self named: #uiItalic
!
code
	^self named: #code
!
codeBold
	^self named: #codeBold
!
codeItalic
	^self named: #codeItalic
!
header
	"Tracked capitals, 10.5px bold (pane headers)."
	^self named: #header
!
title
	"Window titles, 13px bold."
	^self named: #title
!
small
	^self named: #small
!
smallItalic
	^self named: #smallItalic
! !

!Font class methodsFor: 'glyph cache'!
rasterizing: aBlock
	"Evaluate aBlock alone among the Processes rasterizing glyphs."
	^RasterizeLock critical: aBlock
!
rasterizingClasses
	"Changing one of these may change how glyphs look."
	^Array with: Font with: GlyphRasterizer with: TrueTypeFont
!
regenerateGlyphs
	"The rasterizer or the outlines changed: forget every rasterized glyph of every Font (atlas included). Glyphs are rasterized again on first use; DisplayLists made before keep the old atlas pages."
	self rasterizing: [
		GlyphAtlas reset.
		self allInstances do: [:each | each resetGlyphs].
		Canvas glyphsChanged]
!
resetGlyphs
	"Drop all rasterized glyphs (atlas included)."
	GlyphAtlas reset.
	Standard isNil ifFalse: [Standard do: [:each | each resetGlyphs]].
	Canvas glyphsChanged
!
prerasterizedCharacters
	"ASCII and the symbols the UI uses."
	| s |
	s := WriteStream on: (String new: 128).
	32 to: 126 do: [:cp | s nextPut: (Character value: cp)].
	#(16rB7 16r2014 16r2013 16r2192 16r2190 16r2318 16r21E7 16r2026 16r2713 16r2022 16r25B8 16r25BE 16r25CF 16r25CB 16r25A1 16r25A0 16r2265 16r2264 16rD7 16rB6 16r2325 16r2191 16r2193 16r21A9 16r232B)
		do: [:cp | s nextPut: (Character value: cp)].
	^s contents
!
buildFonts
	"Stage 2: load the faces of imageFaceNames into the image (a fallback or emoji face missing from fonts/ is left out) and compact them, but for a face with color glyphs (its layers and ligatures are glyphs the cmap does not reach); pre-rasterize the standard fonts into the shared atlas."
	| chars fonts |
	Faces := nil.
	Fallbacks := nil.
	Emoji := nil.
	Standard := nil.
	GlyphAtlas reset.
	Faces := Dictionary new.
	self imageFaceNames do: [:each |
		((self isOptionalFace: each) not or: [File exists: self fontsDirectory , '/' , each , '.ttf'])
			ifTrue: [Faces at: each put: (TrueTypeFont readFile: self fontsDirectory , '/' , each , '.ttf')]].
	Faces do: [:each | each colorBaseGlyphCount = 0 ifTrue: [each compact]].
	Smalltalk isRuntimeImage ifFalse: [
		chars := self prerasterizedCharacters.
		fonts := self standardFonts.
		fonts do: [:font | font prerasterize: chars]].
	Transcript show: ' '; show: Faces size printString; show: ' faces, '; show: (GlyphAtlas default pages size) printString; show: ' atlas page(s)'
! !

!Font class methodsFor: 'class initialization'!
initialize
	RasterizeLock := Mutex new.
	Smalltalk addStage2Step: [self buildFonts] named: 'Fonts'.
	SystemChanges subscribe: #Font do: [:change |
		(change affectsAnyOf: self rasterizingClasses) ifTrue: [self regenerateGlyphs]]
! !

!Font methodsFor: 'private'!
rescaleTo: aNumber
	scale := aNumber.
	self resetGlyphs
! !
