VMModule subclass: #DeflateCoder
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

DeflateCoder comment: 'The Huffman coding of a deflate block''s tokens for the zlibWriteTokens and zlibTokenCounts primitives (ObjectPrimitives), bit for bit what ZLib>>writeTokensInSmalltalk:distances:count:table: writes: each token (ZLib>>matchesFrom:head:prev:literals:distances:: a literal byte, or 256 + a match''s length with its distance, uint16 each) as its literal/length code, its length''s extra bits, its distance''s code and extra bits, then the end-of-block code, least significant bit first into bytes. The codes come from a table of 286 literal/length then 30 distance entries, each a uint32 of the (bit-reversed) code and its length << 16; the length and distance codes and extra bits are computed (RFC 1951 3.2.5). Tokens out of range and codes longer than 15 bits end the coding with a failure, so at most 6 bytes are written a token.'!

!DeflateCoder methodsFor: 'codes'!
lengthCodeOf: len
	"The length code (0 to 28: symbol 257 + it) of a match's length, 3 to 258."
	| e |
	len = 258 ifTrue: [^28].
	len - 3 < 8 ifTrue: [^len - 3].
	e := (self log2: len - 3) - 2.
	^4 * (e + 1) + ((len - 3 >> e) bitAnd: 3)
!
lengthExtraOf: c
	"The extra bits of length code c."
	(c < 8 or: [c = 28]) ifTrue: [^0].
	^(c >> 2) - 1
!
distanceCodeOf: dd
	"The distance code (0 to 29) of a distance minus one, 0 to 32767."
	| k |
	dd < 4 ifTrue: [^dd].
	k := self log2: dd.
	^2 * k + ((dd >> (k - 1)) bitAnd: 1)
!
distanceExtraOf: c
	"The extra bits of distance code c."
	c < 4 ifTrue: [^0].
	^(c >> 1) - 1
!
log2: v
	"The index of v''s highest one bit (v >= 1)."
	| k |
	k := 0.
	[(v >> (k + 1)) > 0] whileTrue: [k := k + 1].
	^k
!
write: lits distances: dists count: count table: table into: out at: start bits: pending count: pendingCount
	"Code count tokens into out from byte start, after the pendingCount (< 8) bits pending; answer the bytes written in all times 8 plus the bits left, which are in the byte after them; -1 for an invalid token. out has room for 6 bytes a token and 8 more."
	<function>
	<var: #lits type: 'uint16_t *'>
	<var: #dists type: 'uint16_t *'>
	<var: #count type: 'int64_t'>
	<var: #table type: 'uint32_t *'>
	<var: #out type: 'uint8_t *'>
	<var: #start type: 'int64_t'>
	<var: #pending type: 'uint64_t'>
	<var: #pendingCount type: 'int64_t'>
	<returns: 'int64_t'>
	| acc n p i v len c e entry d dd |
	0 to: 315 do: [:j | (table at: j) >> 16 > 15 ifTrue: [^-1]].
	acc := pending.
	n := pendingCount.
	p := start.
	i := 0.
	[i <= count] whileTrue: [
		v := 256.
		i < count ifTrue: [v := (lits at: i) asInt64].
		v <= 256
			ifTrue: [
				entry := (table at: v) asUInt64.
				acc := acc bitOr: ((entry bitAnd: 16rFFFF) << n).
				n := n + (entry >> 16) asInt64]
			ifFalse: [
				len := v - 256.
				(len < 3 or: [len > 258]) ifTrue: [^-1].
				c := self lengthCodeOf: len.
				e := self lengthExtraOf: c.
				entry := (table at: 257 + c) asUInt64.
				acc := acc bitOr: ((entry bitAnd: 16rFFFF) << n).
				n := n + (entry >> 16) asInt64.
				e > 0 ifTrue: [
					acc := acc bitOr: (((len - 3) bitAnd: (1 << e) - 1) asUInt64 << n).
					n := n + e].
				d := (dists at: i) asInt64.
				(d < 1 or: [d > 32768]) ifTrue: [^-1].
				dd := d - 1.
				c := self distanceCodeOf: dd.
				e := self distanceExtraOf: c.
				entry := (table at: 286 + c) asUInt64.
				acc := acc bitOr: ((entry bitAnd: 16rFFFF) << n).
				n := n + (entry >> 16) asInt64.
				e > 0 ifTrue: [
					acc := acc bitOr: ((dd bitAnd: (1 << e) - 1) asUInt64 << n).
					n := n + e]].
		[n >= 8] whileTrue: [
			out at: p put: (acc bitAnd: 255) asUInt8.
			p := p + 1.
			acc := acc >> 8.
			n := n - 8].
		i := i + 1].
	out at: p put: (acc bitAnd: 255) asUInt8.
	^p * 8 + n
!
count: lits distances: dists count: count into: freqs
	"freqs (286 literal/length then 30 distance uint32 counters) += the codes of count tokens; answer the extra bits they need, -1 for an invalid token (freqs partly counted)."
	<function>
	<var: #lits type: 'uint16_t *'>
	<var: #dists type: 'uint16_t *'>
	<var: #count type: 'int64_t'>
	<var: #freqs type: 'uint32_t *'>
	<returns: 'int64_t'>
	| extra v c d |
	extra := 0.
	0 to: count - 1 do: [:i |
		v := (lits at: i) asInt64.
		v < 256
			ifTrue: [freqs at: v put: (freqs at: v) + 1]
			ifFalse: [
				(v < 259 or: [v > 514]) ifTrue: [^-1].
				c := self lengthCodeOf: v - 256.
				freqs at: 257 + c put: (freqs at: 257 + c) + 1.
				extra := extra + (self lengthExtraOf: c).
				d := (dists at: i) asInt64.
				(d < 1 or: [d > 32768]) ifTrue: [^-1].
				c := self distanceCodeOf: d - 1.
				freqs at: 286 + c put: (freqs at: 286 + c) + 1.
				extra := extra + (self distanceExtraOf: c)]].
	^extra
! !
