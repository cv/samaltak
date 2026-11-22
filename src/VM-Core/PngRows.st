VMModule subclass: #PngRows
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

PngRows comment: 'I filter rows of PNG pixels 16 bytes at a time for PngFilter: an arch interface (VMModule class>>isArchInterface), so PngFilter is translated with my subclass for each CPU, whose inline methods expand there: NeonPngRows on arm64 (and every CPU but x86-64), Sse2PngRows on x86-64. A row p of m bytes after its first pixel (n bytes, 3 or 4: p - n is the row''s start) over the row q above it (q - n likewise): byte i is x = p[i], with a = p[i - n] to its left, b = q[i] above, c = q[i - n] above left. Each does the last k bytes of the row, k = m rounded down to a multiple of 16 (which may be 0), and answers k; PngFilter does the rest one by one (PngFilter>>filterOf:left:up:upLeft:, costOf:), so the results are its own to the bit. The five filters'' outputs are None x, Sub x - a, Up x - b, Average x - ((a + b) >> 1), Paeth x - paeth(a, b, c), modulo 256; a cost the sum of the outputs read as signed bytes, |v| = min(v, 256 - v).'!

!PngRows class methodsFor: 'declaring'!
isAbstractModule
	^self == PngRows
!
isArchInterface
	^self == PngRows
! !

!PngRows methodsFor: 'rows'!
costs: p prior: q count: m channels: n into: sums
	"sums[f] := sums[f] + the cost of filter f (0 None ... 4 Paeth) over p[m - k .. m); answer k. Nothing is written but sums."
	self subclassResponsibility
!
apply: f to: p prior: q count: m channels: n
	"p[i] := filter f''s output (1 Sub ... 4 Paeth; 0 None leaves p) for m - k <= i < m, in place: block by block from the end, each read before it is written, so the bytes to the left are still the row''s own. Answer k."
	self subclassResponsibility
! !

PngRows subclass: #NeonPngRows
	instanceVariableNames: 'neon'
	classVariableNames: ''
	package: 'VM-Core'!

NeonPngRows comment: 'Rows on arm64 with NEON (Neon): 16 bytes a vector. |v| is min(v, -v) (umin); Average is uhadd; Paeth''s distances are 8-bit: pa = |b - c|, pb = |a - c| (uabd), and pc = |a + b - 2c| is pa + pb where b - c and a - c have the same sign (saturated: it is only compared with pa and pb), else |pa - pb|. Costs add pairs of bytes into 16-bit lanes (uadalp) for at most 128 blocks, then pairs of those into 32-bit lanes.'!

!NeonPngRows class methodsFor: 'declaring'!
declarations
	^#((neon Neon))
!
targetArch
	^#arm64
! !

!NeonPngRows methodsFor: 'private'!
abs: v zero: z
	"Each byte as a signed byte''s magnitude: min(v, -v)."
	^neon min: v with: (neon sub: z with: v)
!
paeth: a with: b with: c
	"The Paeth predictor of each byte: a, b or c, whichever is nearest a + b - c (ties: a, then b)."
	| pa pb pc |
	pa := neon abd: b with: c.
	pb := neon abd: a with: c.
	pc := neon bsl: (neon xor: (neon ge: a with: c) with: (neon ge: b with: c)) with: (neon abd: pa with: pb) with: (neon qadd: pa with: pb).
	^neon bsl: (neon and: (neon le: pa with: pb) with: (neon le: pa with: pc)) with: a with: (neon bsl: (neon le: pb with: pc) with: b with: c)
!
from: start to: m backwardsDo: aBlock
	"aBlock with the start of each block of [start, m), the last first."
	| i |
	i := m - 16.
	[i >= start] whileTrue: [
		aBlock value: i.
		i := i - 16]
! !

!NeonPngRows methodsFor: 'rows'!
costs: p prior: q count: m channels: n into: sums
	| k i end z x a b c s0 s1 s2 s3 s4 h0 h1 h2 h3 h4 |
	k := m bitClear: 15.
	z := neon dupU8: 0.
	s0 := neon dupU32: 0.
	s1 := neon dupU32: 0.
	s2 := neon dupU32: 0.
	s3 := neon dupU32: 0.
	s4 := neon dupU32: 0.
	i := m - k.
	[i < m] whileTrue: [
		"at most 128 blocks: 2 * 128 * 255 fits a 16-bit lane"
		end := i + 2048.
		end > m ifTrue: [end := m].
		h0 := neon dupU16: 0.
		h1 := neon dupU16: 0.
		h2 := neon dupU16: 0.
		h3 := neon dupU16: 0.
		h4 := neon dupU16: 0.
		[i < end] whileTrue: [
			x := neon load: p + i.
			a := neon load: p + i - n.
			b := neon load: q + i.
			c := neon load: q + i - n.
			h0 := neon padal: h0 with: (self abs: x zero: z).
			h1 := neon padal: h1 with: (self abs: (neon sub: x with: a) zero: z).
			h2 := neon padal: h2 with: (self abs: (neon sub: x with: b) zero: z).
			h3 := neon padal: h3 with: (self abs: (neon sub: x with: (neon hadd: a with: b)) zero: z).
			h4 := neon padal: h4 with: (self abs: (neon sub: x with: (self paeth: a with: b with: c)) zero: z).
			i := i + 16].
		s0 := neon padalU16: s0 with: h0.
		s1 := neon padalU16: s1 with: h1.
		s2 := neon padalU16: s2 with: h2.
		s3 := neon padalU16: s3 with: h3.
		s4 := neon padalU16: s4 with: h4].
	sums at: 0 put: (sums at: 0) + (neon addvU32: s0).
	sums at: 1 put: (sums at: 1) + (neon addvU32: s1).
	sums at: 2 put: (sums at: 2) + (neon addvU32: s2).
	sums at: 3 put: (sums at: 3) + (neon addvU32: s3).
	sums at: 4 put: (sums at: 4) + (neon addvU32: s4).
	^k
!
apply: f to: p prior: q count: m channels: n
	| k |
	k := m bitClear: 15.
	f = 1 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		neon store: p + i value: (neon sub: (neon load: p + i) with: (neon load: p + i - n))]].
	f = 2 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		neon store: p + i value: (neon sub: (neon load: p + i) with: (neon load: q + i))]].
	f = 3 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		neon store: p + i value: (neon sub: (neon load: p + i) with: (neon hadd: (neon load: p + i - n) with: (neon load: q + i)))]].
	f = 4 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		neon store: p + i value: (neon sub: (neon load: p + i) with: (self paeth: (neon load: p + i - n) with: (neon load: q + i) with: (neon load: q + i - n)))]].
	^k
! !

PngRows subclass: #Sse2PngRows
	instanceVariableNames: 'sse'
	classVariableNames: ''
	package: 'VM-Core'!

Sse2PngRows comment: 'Rows on x86-64 with SSE2 (Sse2): 16 bytes a vector. |v| is min(v, -v) (pminub); Average is pavgb minus the bit it rounds up, (a xor b) and 1; |x - y| is the or of the two saturated differences, x <= y where x - y saturates to 0, a choice and-andnot-or; Paeth as NeonPngRows. Costs are psadbw against 0: the sums of each 8 bytes in 64-bit lanes.'!

!Sse2PngRows class methodsFor: 'declaring'!
declarations
	^#((sse Sse2))
!
targetArch
	^#x86_64
! !

!Sse2PngRows methodsFor: 'private'!
at: p
	^sse loadu: (self cCoerce: p to: '__m128i *')
!
at: p put: v
	sse storeu: (self cCoerce: p to: '__m128i *') value: v
!
abs: v zero: z
	^sse minU8: v with: (sse sub8: z with: v)
!
abd: x with: y
	^sse or: (sse subsU8: x with: y) with: (sse subsU8: y with: x)
!
le: x with: y zero: z
	"255 where x <= y."
	^sse cmpeq: (sse subsU8: x with: y) with: z
!
select: mask from: a else: b
	^sse or: (sse and: mask with: a) with: (sse andNot: mask with: b)
!
average: a with: b
	"(a + b) >> 1."
	^sse sub8: (sse avgU8: a with: b) with: (sse and: (sse xor: a with: b) with: (sse set1: 1))
!
paeth: a with: b with: c zero: z
	| pa pb pc |
	pa := self abd: b with: c.
	pb := self abd: a with: c.
	pc := self
		select: (sse xor: (self le: c with: a zero: z) with: (self le: c with: b zero: z))
		from: (self abd: pa with: pb)
		else: (sse addsU8: pa with: pb).
	^self
		select: (sse and: (self le: pa with: pb zero: z) with: (self le: pa with: pc zero: z))
		from: a
		else: (self select: (self le: pb with: pc zero: z) from: b else: c)
!
cost: v zero: z
	"The sums of v''s bytes as signed bytes'' magnitudes, of each 8 bytes in a 64-bit lane."
	^sse sadU8: (self abs: v zero: z) with: z
!
sum: v
	"The two 64-bit lanes added."
	^(sse low64: v) + (sse low64: (sse unpackHigh64: v with: v))
!
from: start to: m backwardsDo: aBlock
	| i |
	i := m - 16.
	[i >= start] whileTrue: [
		aBlock value: i.
		i := i - 16]
! !

!Sse2PngRows methodsFor: 'rows'!
costs: p prior: q count: m channels: n into: sums
	| k i z x a b c s0 s1 s2 s3 s4 |
	k := m bitClear: 15.
	z := sse zero.
	s0 := z.
	s1 := z.
	s2 := z.
	s3 := z.
	s4 := z.
	i := m - k.
	[i < m] whileTrue: [
		x := self at: p + i.
		a := self at: p + i - n.
		b := self at: q + i.
		c := self at: q + i - n.
		s0 := sse add64: s0 with: (self cost: x zero: z).
		s1 := sse add64: s1 with: (self cost: (sse sub8: x with: a) zero: z).
		s2 := sse add64: s2 with: (self cost: (sse sub8: x with: b) zero: z).
		s3 := sse add64: s3 with: (self cost: (sse sub8: x with: (self average: a with: b)) zero: z).
		s4 := sse add64: s4 with: (self cost: (sse sub8: x with: (self paeth: a with: b with: c zero: z)) zero: z).
		i := i + 16].
	sums at: 0 put: (sums at: 0) + (self sum: s0).
	sums at: 1 put: (sums at: 1) + (self sum: s1).
	sums at: 2 put: (sums at: 2) + (self sum: s2).
	sums at: 3 put: (sums at: 3) + (self sum: s3).
	sums at: 4 put: (sums at: 4) + (self sum: s4).
	^k
!
apply: f to: p prior: q count: m channels: n
	| k z |
	k := m bitClear: 15.
	z := sse zero.
	f = 1 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		self at: p + i put: (sse sub8: (self at: p + i) with: (self at: p + i - n))]].
	f = 2 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		self at: p + i put: (sse sub8: (self at: p + i) with: (self at: q + i))]].
	f = 3 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		self at: p + i put: (sse sub8: (self at: p + i) with: (self average: (self at: p + i - n) with: (self at: q + i)))]].
	f = 4 ifTrue: [self from: m - k to: m backwardsDo: [:i |
		self at: p + i put: (sse sub8: (self at: p + i) with: (self paeth: (self at: p + i - n) with: (self at: q + i) with: (self at: q + i - n) zero: z))]].
	^k
! !
