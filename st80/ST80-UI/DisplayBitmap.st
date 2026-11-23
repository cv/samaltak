Object subclass: #DisplayBitmap
	instanceVariableNames: 'width height stride pixels patterns scratch'
	classVariableNames: ''
	package: 'ST80-UI'!

DisplayBitmap comment: 'I draw into a packed 1-bit framebuffer. Each row starts at a byte boundary, with the leftmost pixel in the high bit. One is black; unused low bits at the right stay zero.'!

!DisplayBitmap methodsFor: 'initialization'!
extent: aPoint
	width := aPoint x.
	height := aPoint y.
	stride := width + 7 // 8.
	pixels := ByteArray new: stride * height.
	patterns := Array
		with: (ByteArray new: stride)
		with: (ByteArray new: stride withAll: 255)
		with: (ByteArray new: stride withAll: 16rAA)
		with: (ByteArray new: stride withAll: 16r55).
	scratch := ByteArray new: stride.
	^self
! !

!DisplayBitmap methodsFor: 'accessing'!
snapshot
	"Publish a copy: subsequent drawing must not mutate a completed frame."
	^pixels copy
! !

!DisplayBitmap methodsFor: 'drawing'!
fill: aRectangle rule: rule
	"Rules: 0 white, 1 black, 2 checkerboard anchored at 0@0, 3 invert. Answer whether a region was drawn."
	| x0 x1 y0 y1 first last leftMask rightMask start stop pattern |
	x0 := aRectangle left max: 0.
	x1 := aRectangle right min: width.
	y0 := aRectangle top max: 0.
	y1 := aRectangle bottom min: height.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^false].
	first := x0 // 8 + 1.
	last := x1 - 1 // 8 + 1.
	leftMask := 255 bitShift: (x0 \\ 8) negated.
	rightMask := 255 - (255 bitShift: (x1 - 1 \\ 8 + 1) negated).
	first = last ifTrue: [leftMask := leftMask bitAnd: rightMask].
	y0 to: y1 - 1 do: [:y |
		start := y * stride + first.
		stop := y * stride + last.
		rule = 3
			ifTrue: [
				pixels at: start put: ((pixels at: start) bitXor: leftMask).
				start < stop ifTrue: [
					start + 1 to: stop - 1 do: [:i | pixels at: i put: (255 - (pixels at: i))].
					pixels at: stop put: ((pixels at: stop) bitXor: rightMask)]]
			ifFalse: [
				pattern := patterns at: (rule = 2 ifTrue: [3 + (y \\ 2)] ifFalse: [rule + 1]).
				self store: (pattern at: 1) mask: leftMask at: start rule: 0.
				start < stop ifTrue: [
					pixels replaceFrom: start + 1 to: stop - 1 with: pattern startingAt: 1.
					self store: (pattern at: 1) mask: rightMask at: stop rule: 0]]].
	^true
!
copy: aRectangle to: aPoint
	"Clip both ends in the same coordinate system. Copy backwards when moving down, and use a row snapshot when shifting bits."
	| x y dx dy x0 x1 y0 y1 sx tx count rows sy ty from to |
	x := aRectangle left.
	y := aRectangle top.
	dx := aPoint x.
	dy := aPoint y.
	x0 := (0 max: x negated) max: dx negated.
	x1 := (aRectangle width min: width - x) min: width - dx.
	y0 := (0 max: y negated) max: dy negated.
	y1 := (aRectangle height min: height - y) min: height - dy.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^false].
	(x = dx and: [y = dy]) ifTrue: [^false].
	sx := x + x0.
	tx := dx + x0.
	count := x1 - x0.
	rows := dy > y ifTrue: [y1 - 1 to: y0 by: -1] ifFalse: [y0 to: y1 - 1].
	((sx bitOr: (tx bitOr: count)) bitAnd: 7) = 0
		ifTrue: [
			rows do: [:r |
				from := y + r * stride + (sx // 8) + 1.
				to := dy + r * stride + (tx // 8) + 1.
				pixels replaceFrom: to to: to + (count // 8) - 1 with: pixels startingAt: from]]
		ifFalse: [
			rows do: [:r |
				sy := y + r * stride.
				ty := dy + r * stride.
				scratch replaceFrom: 1 to: stride with: pixels startingAt: sy + 1.
				self blitRow: scratch offset: 0 stride: stride from: sx to: tx width: count at: ty rule: 0]].
	^true
!
bits: bytes extent: aPoint at: origin rule: rule
	"Rules: 0 opaque, 1 paint source ones black, 2 invert at source ones."
	| x0 x1 y0 y1 w h sourceStride |
	w := aPoint x.
	h := aPoint y.
	sourceStride := w + 7 // 8.
	bytes size < (sourceStride * h) ifTrue: [^self error: 'Bitmap data is too short'].
	x0 := 0 max: origin x negated.
	x1 := w min: width - origin x.
	y0 := 0 max: origin y negated.
	y1 := h min: height - origin y.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^false].
	y0 to: y1 - 1 do: [:r |
		self blitRow: bytes offset: r * sourceStride stride: sourceStride
			from: x0 to: origin x + x0 width: x1 - x0 at: (origin y + r) * stride rule: rule].
	^true
!
glyph: rows x: x y: y
	"Opaque seven-pixel glyph, one byte per row. Shift it into one or two destination bytes."
	| left right top bottom first last shift leftMask rightMask bits i |
	left := x max: 0.
	right := x + 7 min: width.
	top := y max: 0.
	bottom := y + rows size min: height.
	(left < right and: [top < bottom]) ifFalse: [^false].
	first := left // 8 + 1.
	last := right - 1 // 8 + 1.
	shift := (left // 8 * 8) - x.
	leftMask := 255 bitShift: (left \\ 8) negated.
	rightMask := 255 - (255 bitShift: (right - 1 \\ 8 + 1) negated).
	first = last ifTrue: [leftMask := leftMask bitAnd: rightMask].
	top to: bottom - 1 do: [:r |
		i := r * stride + first.
		bits := rows at: r - y + 1.
		self store: (bits bitShift: shift) mask: leftMask at: i rule: 0.
		first < last ifTrue: [
			self store: (bits bitShift: shift + 8) mask: rightMask at: i + 1 rule: 0]].
	^true
! !

!DisplayBitmap methodsFor: 'private'!
blitRow: source offset: offset stride: sourceStride from: sx to: dx width: count at: destOffset rule: rule
	"Place source bits in destination bytes, applying a mask at each edge. The byte outside either end of the source row is treated as zero."
	| first last firstMask lastMask sourceX si shift nextShift b mask i j |
	first := dx // 8 + 1.
	last := dx + count - 1 // 8 + 1.
	sourceX := sx - (dx \\ 8).
	si := sourceX // 8 + 1.
	shift := sourceX \\ 8.
	(shift = 0 and: [(dx bitOr: count) \\ 8 = 0 and: [rule = 0]]) ifTrue: [
		^pixels replaceFrom: destOffset + first to: destOffset + last with: source startingAt: offset + si].
	nextShift := shift - 8.
	firstMask := 255 bitShift: (dx \\ 8) negated.
	lastMask := 255 - (255 bitShift: (dx + count - 1 \\ 8 + 1) negated).
	first to: last do: [:col |
		i := destOffset + col.
		j := si + col - first.
		b := j > 0 ifTrue: [(source at: offset + j) bitShift: shift] ifFalse: [0].
		(shift > 0 and: [j < sourceStride]) ifTrue: [
			b := b bitOr: ((source at: offset + j + 1) bitShift: nextShift)].
		mask := col = first ifTrue: [firstMask] ifFalse: [255].
		col = last ifTrue: [mask := mask bitAnd: lastMask].
		self store: b mask: mask at: i rule: rule]
!
store: byte mask: mask at: index rule: rule
	| selected old |
	selected := byte bitAnd: mask.
	rule = 0 ifTrue: [
		mask = 255 ifTrue: [^pixels at: index put: selected].
		old := pixels at: index.
		^pixels at: index put: ((old bitAnd: 255 - mask) bitOr: selected)].
	selected = 0 ifTrue: [^self].
	old := pixels at: index.
	^pixels at: index put: (rule = 1 ifTrue: [old bitOr: selected] ifFalse: [old bitXor: selected])
! !
