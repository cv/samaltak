VMModule subclass: #ByteSearch
	instanceVariableNames: 'libc blocks'
	classVariableNames: ''
	package: 'VM-Core'!

ByteSearch comment: 'Bytes of strings a block of positions at a time (blocks, ByteBlocks: what the CPU does best), for the string primitives (ObjectPrimitives). Where bytes occur in bytes: a block is looked at all at once for the positions that have the first and the last byte sought; only those are compared further. Where two runs of bytes first or last differ (mismatchOf:with:from:size:, lastMismatchOf:with:size:, for comparing). Their case changed (convertCase:into:size:upper:, Character''s asUppercase and asLowercase of the bytes: uppercase:, lowercase:). Nothing outside the bytes given is read or written.'!

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
!
mismatchOf: a with: b from: start size: n
	"The first index i >= start where a[i] and b[i] differ, n if they do not before n; 0 <= start <= n."
	<function>
	<var: #a type: 'uint8_t *'>
	<var: #b type: 'uint8_t *'>
	<var: #start type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| i mask |
	i := start.
	[i + blocks blockSize <= n] whileTrue: [
		mask := blocks mismatchesAt: a + i with: b + i.
		mask ~= 0 ifTrue: [^i + (blocks firstOf: mask)].
		i := i + blocks blockSize].
	[i < n] whileTrue: [
		(a at: i) = (b at: i) ifFalse: [^i].
		i := i + 1].
	^n
!
lastMismatchOf: a with: b size: n
	"The last index i < n where a[i] and b[i] differ, -1 if they do not; n >= 0. Blocks from the end, the bytes left at the start one by one."
	<function>
	<var: #a type: 'uint8_t *'>
	<var: #b type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| i mask |
	i := n.
	[i >= blocks blockSize] whileTrue: [
		i := i - blocks blockSize.
		mask := blocks mismatchesAt: a + i with: b + i.
		mask ~= 0 ifTrue: [^i + (blocks lastOf: mask)]].
	[i > 0] whileTrue: [
		i := i - 1.
		(a at: i) = (b at: i) ifFalse: [^i]].
	^-1
!
convertCase: a into: b size: n upper: upper
	"b[0..n) := the uppercase (upper) or lowercase bytes of a[0..n); false, going up, if a has 255 (ÿ, whose uppercase is wide), and b is then partly written."
	<function>
	<var: #a type: 'uint8_t *'>
	<var: #b type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<var: #upper type: 'bool'>
	<returns: 'bool'>
	| i c |
	i := 0.
	[i + blocks blockSize <= n] whileTrue: [
		(blocks case: a + i into: b + i upper: upper) ifFalse: [^false].
		i := i + blocks blockSize].
	[i < n] whileTrue: [
		c := (a at: i) asInt32.
		upper
			ifTrue: [
				c = 255 ifTrue: [^false].
				c := self uppercase: c]
			ifFalse: [c := self lowercase: c].
		b at: i put: c asUInt8.
		i := i + 1].
	^true
!
lowercase: c
	"Character>>asLowercase of the byte c: A-Z and À-Þ but × go up 32."
	^((c >= 65 and: [c <= 90]) or: [c >= 192 and: [c <= 222 and: [c ~= 215]]]) ifTrue: [c + 32] ifFalse: [c]
!
uppercase: c
	"Character>>asUppercase of the byte c (not ÿ, whose uppercase is wide): a-z and à-þ but ÷ go down 32."
	^((c >= 97 and: [c <= 122]) or: [c >= 224 and: [c <= 254 and: [c ~= 247]]]) ifTrue: [c - 32] ifFalse: [c]
! !

VMModule subclass: #ByteBlocks
	instanceVariableNames: 'builtins'
	classVariableNames: ''
	package: 'VM-Core'!

ByteBlocks comment: 'I look at a block of positions of bytes at once (ByteSearch): an arch interface (VMModule class>>isArchInterface), so ByteSearch is translated with my subclass for each CPU, whose inline methods expand there. Sse2ByteBlocks on x86-64, NeonByteBlocks on arm64 (and every CPU but x86-64): 16 positions each. A mask has a bit or bits for each position of a block (firstOf: finds the first, lastOf: the last; clearing the lowest set bit drops a position).'!

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
	"The positions p + i (i < blockSize) that have f's byte, with l's at p + i + d, as the bits of a mask (firstOf:), one bit each."
	self subclassResponsibility
!
mismatchesAt: p with: q
	"The positions i (i < blockSize) where p[i] and q[i] differ, as a mask (firstOf:)."
	self subclassResponsibility
!
case: p into: q upper: upper
	"q[0..blockSize) := the uppercase (upper) or lowercase bytes of p's (ByteSearch>>uppercase:, lowercase:); answer false if upper and one is 255."
	self subclassResponsibility
!
firstOf: mask
	"The first position of a mask that is not 0, from the start of its block."
	self subclassResponsibility
!
lastOf: mask
	"The last position of a mask that is not 0, from the start of its block."
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

Sse2ByteBlocks comment: 'Blocks on x86-64: 16 positions, compared with SSE2; bit i of a mask is position i. Unsigned ranges with min (lo <= x < lo + k where min(x - lo, k - 1) = x - lo).'!

!Sse2ByteBlocks class methodsFor: 'declaring'!
declarations
	^#((sse Sse2))
!
targetArch
	^#x86_64
! !

!Sse2ByteBlocks methodsFor: 'private'!
load: p
	^sse loadu: (self cCoerce: p to: '__m128i *')
!
byte: x from: lo below: k
	"255 where lo <= x < lo + k."
	| y |
	y := sse sub8: x with: (sse set1: lo asInt8).
	^sse cmpeq: (sse minU8: y with: (sse set1: (k - 1) asInt8)) with: y
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
		and: (sse cmpeq: (self load: p) with: f)
		with: (sse cmpeq: (self load: p + d) with: l))) asUInt32
!
mismatchesAt: p with: q
	^((sse movemask: (sse cmpeq: (self load: p) with: (self load: q))) bitXor: 16rFFFF) asUInt32
!
case: p into: q upper: upper
	| x m |
	x := self load: p.
	upper
		ifTrue: [
			m := sse or: (self byte: x from: 97 below: 26) with: (sse andNot: (sse cmpeq: x with: (sse set1: 247 asInt8)) with: (self byte: x from: 224 below: 31)).
			sse storeu: (self cCoerce: q to: '__m128i *') value: (sse sub8: x with: (sse and: m with: (sse set1: 32)))]
		ifFalse: [
			m := sse or: (self byte: x from: 65 below: 26) with: (sse andNot: (sse cmpeq: x with: (sse set1: 215 asInt8)) with: (self byte: x from: 192 below: 31)).
			sse storeu: (self cCoerce: q to: '__m128i *') value: (sse add8: x with: (sse and: m with: (sse set1: 32)))].
	^upper not or: [(sse movemask: (sse cmpeq: x with: (sse set1: -1))) = 0]
!
firstOf: mask
	^builtins ctz: mask
!
lastOf: mask
	^31 - (builtins clz: mask)
!
drop: n from: mask
	^mask >> n
! !

ByteBlocks subclass: #NeonByteBlocks
	instanceVariableNames: 'neon'
	classVariableNames: ''
	package: 'VM-Core'!

NeonByteBlocks comment: 'Blocks on arm64 (and every CPU but x86-64: the build compiles arm64''s modules there): 16 positions, compared with NEON. NEON has no movemask: a mask is the bytes of a comparison (0 or 255) narrowed by shrn #4 of their 16-bit lanes into a 64-bit word, 4 bits a position, position i at bits 4i..4i+3; candidates keep the top one of each (one bit a position).'!

!NeonByteBlocks class methodsFor: 'declaring'!
declarations
	^#((neon Neon))
!
targetArch
	^#arm64
! !

!NeonByteBlocks methodsFor: 'private'!
maskOf: v
	"The bytes of v, each 0 or 255, as 4 bits each of a 64-bit word."
	^neon lane: (neon u64FromU8x8: (neon shrn: (neon u16FromU8: v) shift: 4)) at: 0
!
byte: x from: lo below: k
	"255 where lo <= x < lo + k."
	^neon lt: (neon sub: x with: (neon dupU8: lo)) with: (neon dupU8: k)
! !

!NeonByteBlocks methodsFor: 'blocks'!
blockSize
	^16
!
broadcast: aByte
	^neon dupU8: aByte
!
candidatesAt: p first: f last: l distance: d
	^(self maskOf: (neon and: (neon eq: (neon load: p) with: f) with: (neon eq: (neon load: p + d) with: l))) bitAnd: 16r8888888888888888
!
mismatchesAt: p with: q
	^self maskOf: (neon not: (neon eq: (neon load: p) with: (neon load: q)))
!
case: p into: q upper: upper
	| x m |
	x := neon load: p.
	upper
		ifTrue: [
			m := neon or: (self byte: x from: 97 below: 26) with: (neon bic: (self byte: x from: 224 below: 31) with: (neon eq: x with: (neon dupU8: 247))).
			neon store: q value: (neon sub: x with: (neon and: m with: (neon dupU8: 32)))]
		ifFalse: [
			m := neon or: (self byte: x from: 65 below: 26) with: (neon bic: (self byte: x from: 192 below: 31) with: (neon eq: x with: (neon dupU8: 215))).
			neon store: q value: (neon add: x with: (neon and: m with: (neon dupU8: 32)))].
	^upper not or: [(neon max: x) < 255]
!
firstOf: mask
	^(builtins ctz64: mask) >> 2
!
lastOf: mask
	^(63 - (builtins clz64: mask)) >> 2
!
drop: n from: mask
	^mask >> (n * 4)
! !
