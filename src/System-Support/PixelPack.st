Object subclass: #PixelPack
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Support'!

PixelPack comment: 'I pack 4-byte pixels (BGRA or RGBA rows, as a FrameTap reads them or a Form''s bytes) into 3-byte pixels: bytes 0 1 2 of each, or 2 1 0 (swap), alpha dropped. RFB''s ZRLE CPIXEL and Tight''s TPIXEL are the three low bytes of a 32-bit little-endian pixel of depth 24: from BGRA rows for a BGRX client as they are, from RGBA rows swapped; PNG''s RGB from RGBA rows as they are. The VM''s pixelsPack primitive (PixelPacker: NEON or SSE2), else packInSmalltalk:...; the results are the same to the byte.

	PixelPack pack: bgra width: 160 height: 20 swap: false     "160 * 20 * 3 bytes: B G R each"'!

!PixelPack class methodsFor: 'packing'!
pack: bytes width: w height: h swap: aBoolean
	"A new ByteArray of the w x h pixels of bytes (rows of w * 4 bytes) as 3-byte pixels."
	^self pack: bytes stride: w * 4 x: 0 y: 0 width: w height: h swap: aBoolean into: (ByteArray new: w * h * 3)
!
pack: src stride: stride x: x y: y width: w height: h swap: aBoolean into: dst
	"dst's first w * h * 3 bytes := the w x h pixels at x, y of src (rows of stride bytes, 4 bytes a pixel) as 3-byte pixels, row after row: bytes 0 1 2 of each, or 2 1 0 if aBoolean; answer dst. The rectangle must lie within src, and dst must not be src."
	(self primPack: src stride: stride x: x y: y width: w height: h swap: (aBoolean ifTrue: [1] ifFalse: [0]) into: dst) isNil ifFalse: [^dst].
	^self packInSmalltalk: src stride: stride x: x y: y width: w height: h swap: aBoolean into: dst
!
primPack: src stride: stride x: x y: y width: w height: h swap: swap into: dst
	"The VM's pixelsPack (ObjectPrimitives>>primPixelsPack); nil if it cannot (an older VM, arguments out of range)."
	<primitive: 'pixelsPack'>
	^nil
!
packInSmalltalk: src stride: stride x: x y: y width: w height: h swap: aBoolean into: dst
	| o0 o2 d |
	(src == dst or: [x < 0 or: [y < 0 or: [w < 0 or: [h < 0 or: [(x + w) * 4 > stride]]]]]) ifTrue: [^self error: 'bad pixel rectangle'].
	dst size < (w * h * 3) ifTrue: [^self error: 'destination too small'].
	(w > 0 and: [h > 0 and: [(y + h - 1) * stride + ((x + w) * 4) > src size]]) ifTrue: [^self error: 'rectangle beyond the source'].
	o0 := aBoolean ifTrue: [3] ifFalse: [1].
	o2 := aBoolean ifTrue: [1] ifFalse: [3].
	d := 1.
	0 to: h - 1 do: [:row | | s |
		s := (y + row) * stride + (x * 4).
		1 to: w do: [:i |
			dst at: d put: (src at: s + o0).
			dst at: d + 1 put: (src at: s + 2).
			dst at: d + 2 put: (src at: s + o2).
			d := d + 3.
			s := s + 4]].
	^dst
! !
