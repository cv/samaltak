VMModule subclass: #PixelPacker
	instanceVariableNames: 'rows'
	classVariableNames: ''
	package: 'VM-Core'!

PixelPacker comment: 'Rows of 4-byte pixels (BGRA or RGBA) as 3-byte pixels for the pixelsPack primitive (ObjectPrimitives>>primPixelsPack, PixelPack class>>pack:stride:x:y:width:height:swap:into:), bit for bit what PixelPack''s Smalltalk does: bytes 0 1 2 of each pixel, or 2 1 0 (swapped), alpha dropped: RFB ZRLE''s CPIXEL and Tight''s TPIXEL in the client''s byte order, PNG''s RGB. The first pixels of each row go 4 at a time (rows, PackRows: NEON or SSE2), the rest one by one here, after them.'!

!PixelPacker class methodsFor: 'declaring'!
declarations
	^#((rows PackRows))
! !

!PixelPacker methodsFor: 'packing'!
pack: s stride: stride width: w height: h swap: swap into: d
	"d := the w x h pixels at s (rows stride bytes apart) as 3-byte pixels, rows w * 3 bytes apart. d does not overlap s."
	<function>
	<var: #s type: 'uint8_t *'>
	<var: #d type: 'uint8_t *'>
	<var: #stride type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #swap type: 'int64_t'>
	| y k x p q |
	y := 0.
	[y < h] whileTrue: [
		p := s + (y * stride).
		q := d + (y * w * 3).
		k := rows pack: p count: w swap: swap into: q.
		self packFrom: k to: w of: p swap: swap into: q.
		y := y + 1]
!
packFrom: start to: w of: p swap: swap into: q
	"Pixels start to w - 1 of the row p into the row q, one by one."
	<function>
	<var: #start type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<var: #p type: 'uint8_t *'>
	<var: #swap type: 'int64_t'>
	<var: #q type: 'uint8_t *'>
	| x |
	x := start.
	[x < w] whileTrue: [
		swap = 0
			ifTrue: [
				q at: x * 3 put: (p at: x * 4).
				q at: x * 3 + 2 put: (p at: x * 4 + 2)]
			ifFalse: [
				q at: x * 3 put: (p at: x * 4 + 2).
				q at: x * 3 + 2 put: (p at: x * 4)].
		q at: x * 3 + 1 put: (p at: x * 4 + 1).
		x := x + 1]
! !
