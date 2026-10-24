Object subclass: #Font
	instanceVariableNames: 'face size scale letterSpacing lineHeight baselineOffset uppercase pixelsPerUnit phases glyphTable wideGlyphs deviceAdvances wideAdvances atlas'
	classVariableNames: 'DeviceScale Faces FontsDirectory Standard SubpixelPhases'
	package: 'Graphics-Canvas'!

Font comment: 'I am a TrueTypeFont at a pixel size (CSS px = points) for a device scale (2 on Retina), with optional letter spacing and capitals (for tracked-caps headers). I answer metrics in points (ascent, descent, lineHeight, widthOf:) and supply Canvas with rasterized glyphs: each glyph is rasterized lazily at device resolution for one of SubpixelPhases horizontal subpixel offsets and kept in the shared GlyphAtlas.

The standard fonts (Font ui, uiBold, uiItalic, code, codeBold, codeItalic, header, title, small, smallItalic) follow docs/ui.md and the prototype''s blue-book/pi-orb styles. Stage 2 parses the faces from fonts/ and pre-rasterizes ASCII and the UI symbols, so the atlas lives in the image.'!

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
	^(face advanceWidthOfCodePoint: codePoint) * pixelsPerUnit + (letterSpacing * scale)
!
advanceOf: aCharacter
	"Points the pen moves after aCharacter."
	^(self deviceAdvanceOf: aCharacter value) / scale
!
widthOf: aString
	"Answer the width of aString in points (with letter spacing after each character, as CSS)."
	^self widthOf: aString from: 1 to: aString size
!
widthOf: aString from: start to: stop
	| sum string cp |
	string := uppercase ifTrue: [aString asUppercase] ifFalse: [aString].
	sum := 0.0.
	start to: stop do: [:i |
		cp := (string at: i) value.
		sum := sum + (cp < 256 ifTrue: [deviceAdvances at: cp + 1] ifFalse: [self deviceAdvanceOf: cp])].
	^sum / scale
!
indexAt: x in: aString
	"Answer the index of the character boundary nearest to x points from the start of aString (0 = before the first character)."
	| pen advance |
	pen := 0.0.
	1 to: aString size do: [:i |
		advance := self advanceOf: (aString at: i).
		x < (pen + (advance / 2)) ifTrue: [^i - 1].
		pen := pen + advance].
	^aString size
! !

!Font methodsFor: 'glyphs'!
glyphForCodePoint: codePoint phase: phase
	"Answer the GlyphInfo, rasterizing it on first use."
	| key |
	codePoint < 256 ifTrue: [
		key := codePoint * phases + phase + 1.
		^(glyphTable at: key) ifNil: [glyphTable at: key put: (self rasterizeCodePoint: codePoint phase: phase)]].
	key := codePoint * phases + phase.
	^wideGlyphs at: key ifAbsent: [wideGlyphs at: key put: (self rasterizeCodePoint: codePoint phase: phase)]
!
rasterizeCodePoint: codePoint phase: phase
	"Rasterize the glyph with its origin phase / phases device pixels right of a pixel boundary; answer a GlyphInfo."
	| glyph box contours dx left top right bottom w h rasterizer coverage slot template |
	glyph := face glyphIndexFor: codePoint.
	box := face boundsOf: glyph.
	box isNil ifTrue: [^GlyphInfo blank].
	contours := face contoursOf: glyph.
	contours isEmpty ifTrue: [^GlyphInfo blank].
	dx := phase / phases asFloat.
	left := (box left * pixelsPerUnit + dx) floor.
	right := (box right * pixelsPerUnit + dx) ceiling.
	top := (box bottom * pixelsPerUnit) negated floor.
	bottom := (box top * pixelsPerUnit) negated ceiling.
	w := right - left max: 1.
	h := bottom - top max: 1.
	rasterizer := GlyphRasterizer width: w height: h.
	contours do: [:each |
		rasterizer addContour: each scale: pixelsPerUnit offsetX: dx - left offsetY: top negated].
	coverage := rasterizer coverage.
	slot := atlas add: coverage width: w height: h.
	template := DisplayList glyphTemplateLeft: left top: top width: w height: h atlasX: (slot at: 2) atlasY: (slot at: 3).
	^GlyphInfo template: template page: (slot at: 1) width: w height: h
!
prerasterize: aString
	"Rasterize the characters of aString at every subpixel phase."
	| string |
	string := uppercase ifTrue: [aString asUppercase] ifFalse: [aString].
	string do: [:ch |
		0 to: phases - 1 do: [:phase | self glyphForCodePoint: ch value phase: phase]]
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
fontsDirectory
	"Answer the directory with the .ttf files: fonts/ in the current directory, else next to the image's build directory."
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
	"Answer the TrueTypeFont of fonts/<aString>.ttf, loading it once."
	Faces isNil ifTrue: [Faces := Dictionary new].
	^Faces at: aString ifAbsent: [
		Faces at: aString put: (TrueTypeFont fromFile: self fontsDirectory , '/' , aString , '.ttf')]
!
faces
	^Faces ifNil: [Dictionary new]
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
rasterizingClasses
	"Changing one of these may change how glyphs look."
	^Array with: Font with: GlyphRasterizer with: TrueTypeFont
!
regenerateGlyphs
	"The rasterizer or the outlines changed: forget every rasterized glyph of every Font (atlas included). Glyphs are rasterized again on first use; DisplayLists made before keep the old atlas pages."
	GlyphAtlas reset.
	self allInstances do: [:each | each resetGlyphs]
!
resetGlyphs
	"Drop all rasterized glyphs (atlas included)."
	GlyphAtlas reset.
	Standard isNil ifFalse: [Standard do: [:each | each resetGlyphs]]
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
buildStandardFonts
	"Stage 2: load the faces and pre-rasterize the standard fonts into the shared atlas."
	| chars |
	Faces := nil.
	Standard := nil.
	GlyphAtlas reset.
	chars := self prerasterizedCharacters.
	self standardFonts do: [:font | font prerasterize: chars].
	Transcript show: ' '; show: (GlyphAtlas default pages size) printString; show: ' atlas page(s)'
! !

!Font class methodsFor: 'class initialization'!
initialize
	Smalltalk addStage2Step: [self buildStandardFonts] named: 'Font atlases'.
	SystemChanges subscribe: #Font do: [:change |
		(change affectsAnyOf: self rasterizingClasses) ifTrue: [self regenerateGlyphs]]
! !
