VMModule subclass: #PackRows
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

PackRows comment: 'I pack rows of 4-byte pixels (BGRA or RGBA) into 3-byte pixels for PixelPacker, 16 bytes at a time: an arch interface (VMModule class>>isArchInterface), so PixelPacker is translated with my subclass for each CPU, whose inline methods expand there: NeonPackRows on arm64 (and every CPU but x86-64), Sse2PackRows on x86-64. Each packs the first k of a row''s w pixels, k a multiple of 4 at most w - 2, and answers k; PixelPacker does the rest one by one. A vector store writes 16 bytes for 12, so up to 4 bytes after d + 3k are written too: the 2 or more pixels PixelPacker packs after k write them again.'!

!PackRows class methodsFor: 'declaring'!
isAbstractModule
	^self == PackRows
!
isArchInterface
	^self == PackRows
! !

!PackRows methodsFor: 'rows'!
pack: s count: w swap: swap into: d
	"d[3i .. 3i + 3) := bytes 0 1 2 (swap 0) or 2 1 0 (swap 1) of the pixel s[4i .. 4i + 4), for i < k; answer k (see my comment)."
	self subclassResponsibility
! !

PackRows subclass: #NeonPackRows
	instanceVariableNames: 'neon'
	classVariableNames: ''
	package: 'VM-Core'!

NeonPackRows comment: 'Packing on arm64 with NEON (Neon): 4 pixels a vector, their 12 bytes picked by one table lookup (tbl, an index above 15 gives 0).'!

!NeonPackRows class methodsFor: 'declaring'!
declarations
	^#((neon Neon))
!
targetArch
	^#arm64
! !

!NeonPackRows methodsFor: 'rows'!
pack: s count: w swap: swap into: d
	| k i idx |
	k := w - 2.
	k < 0 ifTrue: [k := 0].
	k := k bitClear: 3.
	idx := neon combine: (neon create: 16r0908060504020100) with: (neon create: 16r7F7F7F7F0E0D0C0A).
	swap = 0 ifFalse: [idx := neon combine: (neon create: 16r090A040506000102) with: (neon create: 16r7F7F7F7F0C0D0E08)].
	i := 0.
	[i < k] whileTrue: [
		neon store: d + (i * 3) value: (neon tbl: (neon load: s + (i * 4)) index: idx).
		i := i + 4].
	^k
! !

PackRows subclass: #Sse2PackRows
	instanceVariableNames: 'sse'
	classVariableNames: ''
	package: 'VM-Core'!

Sse2PackRows comment: 'Packing on x86-64 with SSE2 (Sse2), which has no byte shuffle: 4 pixels a vector, swapped by 32-bit shifts and masks if asked, their alpha masked off, then each 64-bit lane''s two pixels joined into 6 bytes (the upper one shifted down by 8 bits), and the upper lane''s 6 bytes moved down next to the lower''s (a 2-byte shift of the register).'!

!Sse2PackRows class methodsFor: 'declaring'!
declarations
	^#((sse Sse2))
!
targetArch
	^#x86_64
! !

!Sse2PackRows methodsFor: 'rows'!
pack: s count: w swap: swap into: d
	| k i z ones mask24 low64 mid64 lo6 hi6 lowByte midByte x y |
	k := w - 2.
	k < 0 ifTrue: [k := 0].
	k := k bitClear: 3.
	z := sse zero.
	ones := sse cmpeq: z with: z.
	mask24 := sse srli32: ones count: 8.
	lowByte := sse srli32: ones count: 24.
	midByte := sse slli32: lowByte count: 8.
	low64 := sse srli64: ones count: 40.
	mid64 := sse slli64: low64 count: 24.
	lo6 := sse srliBytes: ones count: 10.
	hi6 := sse slliBytes: lo6 count: 6.
	i := 0.
	[i < k] whileTrue: [
		x := sse loadu: (self cCoerce: s + (i * 4) to: '__m128i *').
		swap = 0 ifFalse: [
			x := sse or: (sse or: (sse slli32: (sse and: x with: lowByte) count: 16) with: (sse and: x with: midByte)) with: (sse and: (sse srli32: x count: 16) with: lowByte)].
		x := sse and: x with: mask24.
		y := sse or: (sse and: x with: low64) with: (sse and: (sse srli64: x count: 8) with: mid64).
		sse storeu: (self cCoerce: d + (i * 3) to: '__m128i *') value: (sse or: (sse and: y with: lo6) with: (sse and: (sse srliBytes: y count: 2) with: hi6)).
		i := i + 4].
	^k
! !
