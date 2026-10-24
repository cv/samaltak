Form subclass: #GlyphForm
	instanceVariableNames: 'font character glyph'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

GlyphForm comment: 'I am one glyph of a Font as Canvas draws it: the 8-bit coverage GlyphRasterizer produced from the TrueType outline at the font''s device size (subpixel phase 0), read back from the GlyphAtlas page that holds it (my glyph, a GlyphInfo). Each pixel is the ink (black) at that coverage, so my alpha byte is the coverage. left and top place my top-left relative to the pen on the baseline, in device pixels.

	(Font code glyphFor: $g) inspect'!

!GlyphForm methodsFor: 'initialization'!
setFont: aFont character: aCharacter glyph: aGlyphInfo
	| w |
	font := aFont.
	character := aCharacter.
	glyph := aGlyphInfo.
	w := aGlyphInfo width.
	self setWidth: w height: aGlyphInfo height bits: (Bitmap new: w * aGlyphInfo height).
	0 to: height - 1 do: [:y |
		0 to: w - 1 do: [:x |
			bits at: y * w + x + 1 put: ((aGlyphInfo coverageAtX: x y: y) bitShift: 24)]]
! !

!GlyphForm methodsFor: 'accessing'!
font
	^font
!
character
	^character
!
glyph
	^glyph
!
left
	^glyph left
!
top
	^glyph top
!
coverageAt: aPoint
	"0..255 at aPoint (0-based)."
	^(self pixelValueAt: aPoint) bitShift: -24
!
coverage
	"Answer my coverage as a ByteArray, rows top to bottom (GlyphRasterizer>>coverage's layout)."
	| out |
	out := ByteArray new: width * height.
	1 to: out size do: [:i | out at: i put: ((bits at: i) bitShift: -24)].
	^out
! !

!GlyphForm methodsFor: 'pixels'!
pixelComponentNames
	^#('coverage')
!
pixelComponentsAt: aPoint
	^Array with: (self coverageAt: aPoint)
! !

!GlyphForm methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a GlyphForm('; print: character; space; print: font; nextPutAll: ', '; print: width; nextPut: $x; print: height; nextPut: $)
! !

!GlyphForm class methodsFor: 'instance creation'!
font: aFont character: aCharacter
	| ch |
	ch := aFont isUppercase ifTrue: [aCharacter asUppercase] ifFalse: [aCharacter].
	^self new setFont: aFont character: ch glyph: (aFont glyphForCodePoint: ch value phase: 0)
! !
