Object subclass: #RfbCursor
	instanceVariableNames: 'width height hotspot bgra mask'
	classVariableNames: ''
	package: 'System-Remote'!

RfbCursor comment: 'I am a pointer shape for RFB''s Cursor pseudo-encoding (-239): width x height BGRA8 pixels, a mask (a bit a pixel, rows byte-aligned, most significant bit first: 1 where the pointer is drawn) and the hotspot. The viewer draws me where its own pointer is, so pointer motion has no round trip and the frames stay pointer-free. arrow is the FirmwareScreen''s arrow (X black, o white).'!

!RfbCursor methodsFor: 'initialization'!
setWidth: w height: h hotspot: aPoint bgra: pixels mask: maskBytes
	width := w.
	height := h.
	hotspot := aPoint.
	bgra := pixels.
	mask := maskBytes
! !

!RfbCursor methodsFor: 'accessing'!
width
	^width
!
height
	^height
!
hotspot
	^hotspot
!
bgra
	^bgra
!
mask
	^mask
! !

!RfbCursor class methodsFor: 'instance creation'!
fromRows: anArrayOfStrings hotspot: aPoint
	"Rows of X (black), o (white) and anything else (transparent)."
	| w h bgra mask rowBytes |
	h := anArrayOfStrings size.
	w := anArrayOfStrings first size.
	bgra := ByteArray new: w * h * 4.
	rowBytes := w + 7 // 8.
	mask := ByteArray new: rowBytes * h.
	anArrayOfStrings doWithIndex: [:row :y |
		row doWithIndex: [:c :x | | o v |
			(c = $X or: [c = $o]) ifTrue: [
				o := (y - 1) * w + x - 1 * 4.
				v := c = $X ifTrue: [0] ifFalse: [255].
				bgra at: o + 1 put: v; at: o + 2 put: v; at: o + 3 put: v; at: o + 4 put: 255.
				o := (y - 1) * rowBytes + (x - 1 // 8) + 1.
				mask at: o put: ((mask at: o) bitOr: (128 bitShift: (x - 1 \\ 8) negated))]]].
	^self new setWidth: w height: h hotspot: aPoint bgra: bgra mask: mask
!
arrow
	"The FirmwareScreen's arrow, hotspot at its tip."
	^self fromRows: ((FirmwareScreen classPool at: #Arrow ifAbsent: [nil]) ifNil: [#('X')]) hotspot: 0 @ 0
! !
