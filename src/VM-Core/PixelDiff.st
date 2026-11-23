VMModule subclass: #PixelDiff
	instanceVariableNames: 'search libc'
	classVariableNames: ''
	package: 'VM-Core'!

PixelDiff comment: 'Which square blocks of a rectangle of 4-byte pixels changed, for the pixelBlocksDiff primitive (ObjectPrimitives>>primPixelBlocksDiff, RfbDiffSource>>compare:with:into:), as RfbDiffSource''s Smalltalk finds them (compareInSmalltalk:with:into:): the rectangle''s new rows are compared with a kept copy of the screen in place, row by row, each row''s blocks not yet known to differ in its band (the blocks'' rows: a multiple of the block size on the screen) at once (search''s mismatchOf:, ByteBlocks: NEON or SSE2, 16 bytes at a time), marking the block of the first pixel that differs and going on after it; then the row is copied into the copy. The marks: a byte a block, the bands of the rectangle top to bottom, each its blocks left to right (blocks on the screen''s grid, clipped to the rectangle).'!

!PixelDiff class methodsFor: 'declaring'!
declarations
	^#((search ByteSearch) (libc LibC))
! !

!PixelDiff methodsFor: 'comparing'!
blocks: src width: w height: h into: dst stride: stride left: left top: top block: bs marks: marks
	"Compare the w x h pixels at src (rows w * 4 bytes) with those of dst (rows stride bytes) at left, top, copy them in, and mark the bs x bs blocks that differ (marks: as my comment says, set to 0 first); answer how many do."
	<function>
	<var: #src type: 'uint8_t *'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #dst type: 'uint8_t *'>
	<var: #stride type: 'int64_t'>
	<var: #left type: 'int64_t'>
	<var: #top type: 'int64_t'>
	<var: #bs type: 'int64_t'>
	<var: #marks type: 'uint8_t *'>
	<var: #m type: 'uint8_t *'>
	<var: #from type: 'uint8_t *'>
	<var: #to type: 'uint8_t *'>
	<returns: 'int64_t'>
	| first cols bands right count y m from to x e n i px |
	first := left quo: bs.
	cols := (left + w - 1 quo: bs) - first + 1.
	bands := (top + h - 1 quo: bs) - (top quo: bs) + 1.
	libc memset: marks value: 0 size: (cols * bands) asUInt64.
	right := left + w.
	count := 0.
	y := 0.
	[y < h] whileTrue: [
		m := marks + (((top + y quo: bs) - (top quo: bs)) * cols).
		from := src + (y * w * 4).
		to := dst + ((top + y) * stride) + (left * 4).
		x := left.
		[x < right] whileTrue: [
			(m at: (x quo: bs) - first) = 0
				ifTrue: [
					e := x.
					[e < right and: [(m at: (e quo: bs) - first) = 0]] whileTrue: [
						e := ((e quo: bs) + 1) * bs min: right].
					n := (e - x) * 4.
					i := search mismatchOf: from + ((x - left) * 4) with: to + ((x - left) * 4) from: 0 size: n.
					i = n
						ifTrue: [x := e]
						ifFalse: [
							px := x + (i quo: 4).
							m at: (px quo: bs) - first put: 1.
							count := count + 1.
							x := ((px quo: bs) + 1) * bs]]
				ifFalse: [x := ((x quo: bs) + 1) * bs]].
		libc memcpy: to from: from size: (w * 4) asUInt64.
		y := y + 1].
	^count
! !
