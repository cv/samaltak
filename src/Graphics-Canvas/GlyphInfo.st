Object subclass: #GlyphInfo
	instanceVariableNames: 'template page width height'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

GlyphInfo comment: 'I am a glyph rasterized for one Font at one subpixel phase: the atlas page holding its coverage and a ready-made vertex (DisplayList format) whose rectangle is relative to the pen position (whole device pixels, on the baseline). Canvas copies my template and patches in the pen position and color. Blank glyphs (spaces) have no template.'!

!GlyphInfo methodsFor: 'private'!
setTemplate: aByteArray page: aPage width: w height: h
	template := aByteArray.
	page := aPage.
	width := w.
	height := h
! !

!GlyphInfo methodsFor: 'accessing'!
template
	^template
!
page
	^page
!
width
	^width
!
height
	^height
!
isBlank
	^template isNil
!
left
	"Offset of the bitmap's left edge from the pen, in device pixels."
	^template isNil ifTrue: [0] ifFalse: [(template float32At: 1) truncated]
!
top
	"Offset of the bitmap's top edge from the baseline (negative above), in device pixels."
	^template isNil ifTrue: [0] ifFalse: [(template float32At: 5) truncated]
!
atlasX
	^(template uint32At: 17) bitAnd: 16rFFFF
!
atlasY
	^(template uint32At: 17) bitShift: -16
!
coverageAtX: x y: y
	"Coverage (0..255) of my bitmap pixel x@y (0-based)."
	(x < 0 or: [y < 0 or: [x >= width or: [y >= height]]]) ifTrue: [^0].
	^page coverageAtX: self atlasX + x y: self atlasY + y
!
inkSum
	"Answer the sum of my coverage values (255 = one fully covered pixel)."
	| sum |
	sum := 0.
	template isNil ifTrue: [^0].
	0 to: height - 1 do: [:y | 0 to: width - 1 do: [:x | sum := sum + (self coverageAtX: x y: y)]].
	^sum
! !

!GlyphInfo class methodsFor: 'instance creation'!
blank
	^self new setTemplate: nil page: nil width: 0 height: 0
!
template: aByteArray page: aPage width: w height: h
	^self new setTemplate: aByteArray page: aPage width: w height: h
! !
