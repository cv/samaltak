VMModule subclass: #PixelRows
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PixelRows comment: 'I do rows of 32-bit pixels several at a time for PlatformRaster: an arch interface (VMModule class>>isArchInterface), so PlatformRaster is translated with my subclass for each CPU, whose inline methods expand there: NeonPixelRows on arm64 (and every CPU but x86-64), Sse2PixelRows on x86-64. Each does the first pixels of a row in blocks of 4 and answers how many it did (n rounded down to a multiple of 4, which may be 0); PlatformRaster does the rest one by one, so the results are its own to the bit. over: is its premultiplied source-over (PlatformRaster>>over:color:), c + d * (255 - c.a) / 255 per channel rounded once ((t + (t >> 8)) >> 8 of t = d (255 - c.a) + 128), saturated; with a source of alpha 255 it is the source, with 0 (every channel 0) the destination, so rows need not test for either.'!

!PixelRows class methodsFor: 'declaring'!
isAbstractModule
	^self == PixelRows
!
isArchInterface
	^self == PixelRows
! !

!PixelRows methodsFor: 'rows'!
fill: p count: n value: v
	"p[0 .. k) := v; answer k."
	self subclassResponsibility
!
swap: d from: s count: n
	"d[0 .. k) := s[0 .. k) with red and blue swapped (RGBA8 <-> BGRA8); answer k."
	self subclassResponsibility
!
over: d color: c count: n
	"d[i] := c over d[i] for i < k (premultiplied); answer k."
	self subclassResponsibility
!
over: d texels: s count: n swap: swap
	"d[i] := s[i] (red and blue swapped if swap) over d[i] for i < k (premultiplied); answer k."
	self subclassResponsibility
! !

PixelRows subclass: #NeonPixelRows
	instanceVariableNames: 'neon'
	classVariableNames: ''
	package: 'VM-Platform'!

NeonPixelRows comment: 'Rows on arm64 with NEON (Neon): 4 pixels a vector, 16 at a time for fills. over: multiplies the bytes into 16-bit lanes (umull), adds the rounded high byte (ursra) and narrows with rounding (rshrn), which is (t + (t >> 8)) >> 8 of t = d (255 - a) + 128, then adds the source saturating (uqadd); a pixel''s alpha reaches its four bytes and red and blue swap with a table lookup (tbl).'!

!NeonPixelRows class methodsFor: 'declaring'!
declarations
	^#((neon Neon))
!
targetArch
	^#arm64
! !

!NeonPixelRows methodsFor: 'private'!
swapIndex
	"The bytes of a vector of pixels with red and blue swapped: 2 1 0 3, 6 5 4 7, ..."
	^neon combine: (neon create: 16r0704050603000102) with: (neon create: 16r0F0C0D0E0B08090A)
!
alphaIndex
	"Each pixel's alpha in its four bytes: 3 3 3 3, 7 7 7 7, ..."
	^neon combine: (neon create: 16r0707070703030303) with: (neon create: 16r0F0F0F0F0B0B0B0B)
!
over: dv color: cv inverse: ia
	"cv over dv, ia each byte 255 minus its pixel's alpha."
	| lo hi |
	lo := neon mull: (neon low: dv) with: (neon low: ia).
	hi := neon mullHigh: dv with: ia.
	lo := neon rsra: lo with: lo shift: 8.
	hi := neon rsra: hi with: hi shift: 8.
	^neon qadd: (neon rshrnHigh: (neon rshrn: lo shift: 8) with: hi shift: 8) with: cv
! !

!NeonPixelRows methodsFor: 'rows'!
fill: p count: n value: v
	| x i |
	x := neon dupU32: v.
	i := 0.
	[i + 16 <= n] whileTrue: [
		neon storeU32: p + i value: x.
		neon storeU32: p + i + 4 value: x.
		neon storeU32: p + i + 8 value: x.
		neon storeU32: p + i + 12 value: x.
		i := i + 16].
	[i + 4 <= n] whileTrue: [
		neon storeU32: p + i value: x.
		i := i + 4].
	^i
!
swap: d from: s count: n
	| ix i |
	ix := self swapIndex.
	i := 0.
	[i + 4 <= n] whileTrue: [
		neon store: (self cCoerce: d + i to: 'uint8_t *') value: (neon tbl: (neon load: (self cCoerce: s + i to: 'uint8_t *')) index: ix).
		i := i + 4].
	^i
!
over: d color: c count: n
	| cv ia i p |
	cv := neon u8FromU32: (neon dupU32: c).
	ia := neon dupU8: (255 - (c >> 24)) asUInt8.
	i := 0.
	[i + 4 <= n] whileTrue: [
		p := self cCoerce: d + i to: 'uint8_t *'.
		neon store: p value: (self over: (neon load: p) color: cv inverse: ia).
		i := i + 4].
	^i
!
over: d texels: s count: n swap: swap
	| ax i p t |
	ax := self alphaIndex.
	i := 0.
	[i + 4 <= n] whileTrue: [
		t := neon load: (self cCoerce: s + i to: 'uint8_t *').
		swap ifTrue: [t := neon tbl: t index: self swapIndex].
		p := self cCoerce: d + i to: 'uint8_t *'.
		neon store: p value: (self over: (neon load: p) color: t inverse: (neon not: (neon tbl: t index: ax))).
		i := i + 4].
	^i
! !

PixelRows subclass: #Sse2PixelRows
	instanceVariableNames: 'sse'
	classVariableNames: ''
	package: 'VM-Platform'!

Sse2PixelRows comment: 'Rows on x86-64 with SSE2 (Sse2): 4 pixels a vector, 16 at a time for fills. over: widens the bytes to 16-bit lanes, multiplies, adds 128 and the high byte, shifts, packs and adds the source saturating; a pixel''s alpha reaches its four lanes with shuffles, red and blue swap with shifts and masks.'!

!Sse2PixelRows class methodsFor: 'declaring'!
declarations
	^#((sse Sse2))
!
targetArch
	^#x86_64
! !

!Sse2PixelRows methodsFor: 'private'!
vectorAt: p
	^sse loadu: (self cCoerce: p to: '__m128i *')
!
vectorAt: p put: v
	sse storeu: (self cCoerce: p to: '__m128i *') value: v
!
swapped: v
	"v's pixels with red and blue swapped."
	| m |
	m := sse set1U32: 255.
	^sse
		or: (sse and: v with: (sse set1U32: 16rFF00FF00 asInt32))
		with: (sse or: (sse and: (sse srli32: v count: 16) with: m) with: (sse slli32: (sse and: v with: m) count: 16))
!
half: dv inverse: ia
	"(t + (t >> 8)) >> 8 of t = dv * ia + 128, in 16-bit lanes."
	| t |
	t := sse add16: (sse mullo16: dv with: ia) with: (sse set1U16: 128).
	^sse srli16: (sse add16: t with: (sse srli16: t count: 8)) count: 8
!
over: dv color: cv inverseLow: iaLow high: iaHigh
	"cv over dv; iaLow and iaHigh 255 minus the alpha of each byte's pixel, 16-bit lanes for dv's first and last 8 bytes."
	| z |
	z := sse zero.
	^sse addsU8: (sse packus16: (self half: (sse unpackLow8: dv with: z) inverse: iaLow) with: (self half: (sse unpackHigh8: dv with: z) inverse: iaHigh)) with: cv
!
inverseAlpha: pair
	"255 minus each pixel's alpha in its four 16-bit lanes, of two pixels widened to 16-bit lanes."
	^sse sub16: (sse set1U16: 255) with: (sse shuffleHigh16: (sse shuffleLow16: pair select: 16rFF) select: 16rFF)
! !

!Sse2PixelRows methodsFor: 'rows'!
fill: p count: n value: v
	| x i |
	x := sse set1U32: v asInt32.
	i := 0.
	[i + 16 <= n] whileTrue: [
		self vectorAt: p + i put: x.
		self vectorAt: p + i + 4 put: x.
		self vectorAt: p + i + 8 put: x.
		self vectorAt: p + i + 12 put: x.
		i := i + 16].
	[i + 4 <= n] whileTrue: [
		self vectorAt: p + i put: x.
		i := i + 4].
	^i
!
swap: d from: s count: n
	| i |
	i := 0.
	[i + 4 <= n] whileTrue: [
		self vectorAt: d + i put: (self swapped: (self vectorAt: s + i)).
		i := i + 4].
	^i
!
over: d color: c count: n
	| cv ia i |
	cv := sse set1U32: c asInt32.
	ia := sse set1U16: (255 - (c >> 24)) asInt16.
	i := 0.
	[i + 4 <= n] whileTrue: [
		self vectorAt: d + i put: (self over: (self vectorAt: d + i) color: cv inverseLow: ia high: ia).
		i := i + 4].
	^i
!
over: d texels: s count: n swap: swap
	| z i t |
	z := sse zero.
	i := 0.
	[i + 4 <= n] whileTrue: [
		t := self vectorAt: s + i.
		swap ifTrue: [t := self swapped: t].
		self vectorAt: d + i put: (self
			over: (self vectorAt: d + i)
			color: t
			inverseLow: (self inverseAlpha: (sse unpackLow8: t with: z))
			high: (self inverseAlpha: (sse unpackHigh8: t with: z))).
		i := i + 4].
	^i
! !
