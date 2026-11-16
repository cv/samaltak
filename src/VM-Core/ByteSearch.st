VMModule subclass: #ByteSearch
	instanceVariableNames: 'libc blocks'
	classVariableNames: ''
	package: 'VM-Core'!

ByteSearch comment: 'Where bytes occur in bytes, for the string search primitives (ObjectPrimitives). A block of positions is looked at all at once (blocks, ByteBlocks: what the CPU does best) for those that have the first and the last byte sought; only those are compared further. Nothing outside what is searched is read.'!

!ByteSearch class methodsFor: 'declaring'!
declarations
	^#((libc LibC) (blocks ByteBlocks))
! !

!ByteSearch methodsFor: 'searching'!
indexOfByte: c in: a size: n from: start
	"The index of the first c in a[start..n), -1 if there is none; start >= 0."
	| p |
	start >= n ifTrue: [^-1].
	p := libc memchr: a + start value: c size: (n - start) asUInt64.
	p isNull ifTrue: [^-1].
	^(self cCoerce: p to: 'uint8_t *') - a
!
indexOfBytes: b size: m in: a size: n from: start
	"The index of the first occurrence of b[0..m) in a[0..n) at or after start, -1 if there is none; m >= 1, start >= 0. A block that would reach past the last position is the one that ends there instead, and the positions it repeats are dropped: nothing outside a[0..n) and b[0..m) is read."
	<function>
	<returns: 'int64_t'>
	| last i k f l j |
	last := n - m.
	start > last ifTrue: [^-1].
	m = 1 ifTrue: [^self indexOfByte: (b at: 0) in: a size: n from: start].
	last < (blocks blockSize - 1) ifTrue: [
		start to: last do: [:p |
			((a at: p) = (b at: 0) and: [(a at: p + m - 1) = (b at: m - 1) and: [self matchAt: a + p bytes: b size: m]]) ifTrue: [^p]].
		^-1].
	f := blocks broadcast: (b at: 0).
	l := blocks broadcast: (b at: m - 1).
	i := start.
	[i + blocks blockSize - 1 <= last] whileTrue: [
		j := self candidates: (blocks candidatesAt: a + i first: f last: l distance: m - 1) at: i in: a bytes: b size: m.
		j >= 0 ifTrue: [^j].
		i := i + blocks blockSize].
	i > last ifTrue: [^-1].
	k := last - blocks blockSize + 1.
	^self candidates: (blocks drop: i - k from: (blocks candidatesAt: a + k first: f last: l distance: m - 1)) at: i in: a bytes: b size: m
!
candidates: aMask at: i in: a bytes: b size: m
	"The first position of aMask, a block at i, where a has b's m bytes; -1 if there is none."
	| mask j |
	mask := aMask.
	[mask ~= 0] whileTrue: [
		j := i + (blocks firstOf: mask).
		(self matchAt: a + j bytes: b size: m) ifTrue: [^j].
		mask := mask bitAnd: mask - 1].
	^-1
!
matchAt: p bytes: b size: m
	"Whether the m bytes at p are b's, given that the first and the last are: a short middle compared here, a long one by memcmp."
	| k |
	m > 18 ifTrue: [^(libc memcmp: p + 1 with: b + 1 size: (m - 2) asUInt64) = 0].
	k := 1.
	[k < (m - 1) and: [(p at: k) = (b at: k)]] whileTrue: [k := k + 1].
	^k >= (m - 1)
! !

VMModule subclass: #ByteBlocks
	instanceVariableNames: 'builtins'
	classVariableNames: ''
	package: 'VM-Core'!

ByteBlocks comment: 'I look at a block of positions of bytes at once (ByteSearch): an arch interface (VMModule class>>isArchInterface), so ByteSearch is translated with my subclass for each CPU, whose inline methods expand there. Sse2ByteBlocks on x86-64, SwarByteBlocks on every other CPU.'!

!ByteBlocks class methodsFor: 'declaring'!
declarations
	^#((builtins Builtins))
!
isAbstractModule
	^self == ByteBlocks
!
isArchInterface
	^self == ByteBlocks
! !

!ByteBlocks methodsFor: 'blocks'!
blockSize
	"The positions in a block."
	self subclassResponsibility
!
broadcast: aByte
	"aByte in each byte of a block, for candidatesAt:first:last:distance:."
	self subclassResponsibility
!
candidatesAt: p first: f last: l distance: d
	"The positions p + i (i < blockSize) that have f's byte, with l's at p + i + d, as the bits of a mask (firstOf:)."
	self subclassResponsibility
!
firstOf: mask
	"The first position of a mask that is not 0, from the start of its block."
	self subclassResponsibility
!
drop: n from: mask
	"The mask of a block, as the mask of the block that starts n positions later (without the positions after the block)."
	self subclassResponsibility
! !

ByteBlocks subclass: #Sse2ByteBlocks
	instanceVariableNames: 'sse'
	classVariableNames: ''
	package: 'VM-Core'!

Sse2ByteBlocks comment: 'Blocks on x86-64: 16 positions, compared with SSE2; bit i of a mask is position i.'!

!Sse2ByteBlocks class methodsFor: 'declaring'!
declarations
	^#((sse Sse2))
!
targetArch
	^#x86_64
! !

!Sse2ByteBlocks methodsFor: 'blocks'!
blockSize
	^16
!
broadcast: aByte
	^sse set1: aByte asInt8
!
candidatesAt: p first: f last: l distance: d
	^(sse movemask: (sse
		and: (sse cmpeq: (sse loadu: (self cCoerce: p to: '__m128i *')) with: f)
		with: (sse cmpeq: (sse loadu: (self cCoerce: p + d to: '__m128i *')) with: l))) asUInt32
!
firstOf: mask
	^builtins ctz: mask
!
drop: n from: mask
	^mask >> n
! !

ByteBlocks subclass: #SwarByteBlocks
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

SwarByteBlocks comment: 'Blocks on every CPU but x86-64 (the build compiles arm64''s modules there): 8 positions, the bytes of a 64-bit word, compared with integer arithmetic; the top bit of byte i of a mask is position i. Byte i is the word''s i-th least significant: the VM is little-endian (docs/implementation.md).'!

!SwarByteBlocks class methodsFor: 'declaring'!
targetArch
	^#arm64
! !

!SwarByteBlocks methodsFor: 'blocks'!
blockSize
	^8
!
broadcast: aByte
	^aByte asUInt64 * 16r0101010101010101
!
candidatesAt: p first: f last: l distance: d
	"z has a zero byte where both match; ((z & 0x7F..) + 0x7F..) | z sets the top bit of each byte of z that is not 0 and of no other (a byte's low 7 bits plus 0x7F reach its top bit unless they are 0, and never the next byte)."
	| z |
	z := ((self cCoerce: p to: 'uint64_t *') value bitXor: f) bitOr: ((self cCoerce: p + d to: 'uint64_t *') value bitXor: l).
	^(((z bitAnd: 16r7F7F7F7F7F7F7F7F) + 16r7F7F7F7F7F7F7F7F) bitOr: z) bitInvert64 bitAnd: 16r8080808080808080
!
firstOf: mask
	^(builtins ctz64: mask) >> 3
!
drop: n from: mask
	^mask >> (n * 8)
! !
