Object subclass: #ZLib
	instanceVariableNames: 'input inputSize output size bits bitCount position maxChain head prev litLens distances adler'
	classVariableNames: 'CodeLengthOrder DistanceBase DistanceCodes DistanceExtra FixedDistanceLengths FixedLiteralLengths LengthBase LengthCodes LengthExtra'
	package: 'System-Support'!

ZLib comment: 'I compress and decompress zlib streams (RFC 1950) of deflate data (RFC 1951), in Smalltalk.

	ZLib compress: aByteArray       "a zlib stream"
	ZLib decompress: aByteArray     "the bytes again; an Error when the stream is corrupt"
	ZLib deflate: aByteArray / ZLib inflate: aByteArray   "raw deflate data, without the zlib header and checksum"

Compressing: LZ77 over a 32 KB window (hash chains on three bytes, greedy, at most maxChain candidates per position; positions inside a long match are not hashed; the VM''s primitive finds the matches, ZLib>>matchesFrom:head:prev:literals:distances:), then each block of up to 65535 tokens (so that a block of literals fits one stored block) is written as dynamic Huffman (code lengths limited to 15 bits, 7 for the code-length code), fixed Huffman or stored, whichever is shortest. Decompressing reads all three block types (canonical Huffman decoding, one bit at a time). An instance is one coder: its input, its output and the bit buffer between them.

An instance is also one stream over many calls (an RFB connection''s ZRLE stream, which the viewer inflates as it comes): deflate:final: answers the next piece of raw deflate data, compress:final: of a zlib stream (its header before the first piece, its Adler-32 after the final one). A piece that is not final ends with a sync flush (an empty stored block: 00 00 FF FF), so it is byte-aligned and a reader can inflate all of it before the next arrives; matches reach back into the bytes of earlier calls (the 32 KB window and the hash chains are kept).

	| z |
	z := ZLib new.
	(z compress: first final: false), (z compress: second final: false), (z compress: #[] final: true)   "one zlib stream"'!

!ZLib class methodsFor: 'compressing'!
compress: bytes
	"A zlib stream of bytes: header 78 9C, deflate data, Adler-32 (big-endian)."
	| deflated out adler |
	deflated := self deflate: bytes.
	out := ByteArray new: deflated size + 6.
	out at: 1 put: 16r78.
	out at: 2 put: 16r9C.
	out replaceFrom: 3 to: deflated size + 2 with: deflated startingAt: 1.
	adler := self adler32Of: bytes.
	0 to: 3 do: [:i | out at: deflated size + 3 + i put: ((adler bitShift: (3 - i) * -8) bitAnd: 255)].
	^out
!
deflate: bytes
	^self new deflate: bytes
!
decompress: bytes
	"The bytes of a zlib stream; an Error if its header, data or checksum is wrong."
	| coder result p adler |
	bytes size < 6 ifTrue: [^self error: 'zlib stream too short'].
	(((bytes at: 1) bitAnd: 15) = 8 and: [((bytes at: 1) * 256 + (bytes at: 2)) \\ 31 = 0]) ifFalse: [^self error: 'not a zlib stream'].
	((bytes at: 2) bitAnd: 32) = 0 ifFalse: [^self error: 'zlib preset dictionaries are not supported'].
	coder := self new.
	result := coder inflate: bytes from: 3.
	p := coder position.
	p + 3 > bytes size ifTrue: [^self error: 'zlib stream without its checksum'].
	adler := 0.
	0 to: 3 do: [:i | adler := (adler bitShift: 8) + (bytes at: p + i)].
	adler = (self adler32Of: result) ifFalse: [^self error: 'zlib checksum mismatch'].
	^result
!
inflate: bytes
	^self new inflate: bytes from: 1
!
adler32Of: bytes
	"The VM's primitive (DeflateMatcher), else adler32InSmalltalkOf:."
	^(self primAdler32Of: bytes) ifNil: [self adler32InSmalltalkOf: bytes]
!
primAdler32Of: bytes
	<primitive: 'zlibAdler32'>
	^nil
!
primCount: litLens distances: distances count: count into: counts
	"ZLib>>countTokens:distances:count:literals:distances: in the VM: counts (286 literal/length then 30 distance uint32) += the tokens' codes; answers their extra bits; nil if it cannot."
	<primitive: 'zlibTokenCounts'>
	^nil
!
primWriteTokens: litLens distances: distances count: count table: table into: output size: size bits: bits count: bitCount
	"ZLib>>writeTokens:distances:count:literals:distances: in the VM: answers the output's new size times 8 plus the bits pending, which are in the byte after it; nil if it cannot (an older VM, a token out of range)."
	<primitive: 'zlibWriteTokens'>
	^nil
!
primMatches: input from: start head: head prev: prev literals: litLens distances: distances chain: maxChain
	"ZLib>>matchesFrom:head:prev:literals:distances: in the VM; nil if it cannot (an older VM, maxChain beyond 1 to 4096)."
	<primitive: 'zlibMatches'>
	^nil
!
primMatches: input from: start head: head prev: prev literals: litLens distances: distances chain: maxChain size: n
	"The same of input's first n bytes only (a buffer with room after them); nil if it cannot (an older VM, n beyond input's size)."
	<primitive: 'zlibMatches'>
	^nil
!
adler32: a1 then: a2 length: n
	"The Adler-32 of two byte sequences one after the other, from the first's (a1), the second's (a2) and the second's size n."
	| s1 s2 |
	s1 := (a1 bitAnd: 65535) + (a2 bitAnd: 65535) - 1 \\ 65521.
	s2 := (a1 bitShift: -16) + (a2 bitShift: -16) + (n \\ 65521 * ((a1 bitAnd: 65535) - 1)) \\ 65521.
	^(s2 bitShift: 16) + s1
!
historyLimit
	"The most bytes a stream keeps of its earlier pieces and the next together before it drops all but the window (deflate:final:): 1 MB, in a buffer the pieces are copied into, so that the window moves (and the hash chains are rebased) only once a megabyte."
	^1048576
!
adler32InSmalltalkOf: bytes
	"Sums are reduced modulo 65521 every 5552 bytes."
	| a b i n stop |
	a := 1.
	b := 0.
	i := 1.
	n := bytes size.
	[i <= n] whileTrue: [
		stop := i + 5551 min: n.
		i to: stop do: [:k |
			a := a + (bytes at: k).
			b := b + a].
		a := a \\ 65521.
		b := b \\ 65521.
		i := stop + 1].
	^(b bitShift: 16) + a
! !

!ZLib class methodsFor: 'tables'!
tables
	"Build the deflate tables once."
	LengthCodes isNil ifFalse: [^self].
	LengthBase := #(3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258).
	LengthExtra := #(0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0).
	DistanceBase := #(1 2 3 4 5 7 9 13 17 25 33 49 65 97 129 193 257 385 513 769 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577).
	DistanceExtra := #(0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13).
	CodeLengthOrder := #(16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15).
	FixedLiteralLengths := (1 to: 288) asArray collect: [:i |
		i <= 144 ifTrue: [8] ifFalse: [i <= 256 ifTrue: [9] ifFalse: [i <= 280 ifTrue: [7] ifFalse: [8]]]].
	FixedDistanceLengths := Array new: 30 withAll: 5.
	DistanceCodes := ByteArray new: 32768.
	0 to: 29 do: [:c | | base |
		base := DistanceBase at: c + 1.
		base to: (base + (1 bitShift: (DistanceExtra at: c + 1)) - 1 min: 32768) do: [:d | DistanceCodes at: d put: c]].
	LengthCodes := ByteArray new: 258.
	0 to: 28 do: [:c | | base |
		base := LengthBase at: c + 1.
		base to: (base + (1 bitShift: (LengthExtra at: c + 1)) - 1 min: 258) do: [:len | LengthCodes at: len put: c]]
!
lengthsFor: freqs limit: maxBits
	"Huffman code lengths for the frequencies, none longer than maxBits (frequencies are flattened until they fit). At least two symbols get a code, so that every code is complete."
	| f lengths |
	f := freqs copy.
	(f count: [:each | each > 0]) < 2 ifTrue: [
		(f at: 1) = 0 ifTrue: [f at: 1 put: 1].
		(f count: [:each | each > 0]) < 2 ifTrue: [f at: 2 put: 1]].
	[lengths := self huffmanLengths: f.
	 (lengths inject: 0 into: [:a :b | a max: b]) > maxBits] whileTrue: [
		f := f collect: [:each | each = 0 ifTrue: [0] ifFalse: [each + 1 // 2]]].
	^lengths
!
huffmanLengths: freqs
	"Unlimited Huffman code lengths: merge the two lightest nodes until one is left (of equal weights the one made first: leaves in symbol order, then merged nodes in the order they were made); a leaf's length is its depth. Two queues, the leaves sorted by weight and the merged nodes (whose weights never decrease), give the lightest at once."
	| used m weights parents leaves li ni next pick depths lengths |
	lengths := Array new: freqs size withAll: 0.
	m := 0.
	used := Array new: freqs size.
	1 to: freqs size do: [:i | (freqs at: i) > 0 ifTrue: [used at: (m := m + 1) put: i]].
	weights := Array new: 2 * m.
	parents := Array new: 2 * m withAll: 0.
	1 to: m do: [:i | weights at: i put: (freqs at: (used at: i))].
	leaves := (1 to: m) asArray sort: [:x :y | (weights at: x) < (weights at: y) or: [(weights at: x) = (weights at: y) and: [x < y]]].
	li := 1.
	ni := m + 1.
	next := m.
	pick := [| node |
		(li <= m and: [ni > next or: [(weights at: (leaves at: li)) <= (weights at: ni)]])
			ifTrue: [node := leaves at: li. li := li + 1]
			ifFalse: [node := ni. ni := ni + 1].
		node].
	[m - li + 1 + (next - ni + 1) > 1] whileTrue: [| a b |
		a := pick value.
		b := pick value.
		next := next + 1.
		weights at: next put: (weights at: a) + (weights at: b).
		parents at: a put: next.
		parents at: b put: next].
	depths := Array new: 2 * m withAll: 0.
	next - 1 to: 1 by: -1 do: [:node | depths at: node put: (depths at: (parents at: node)) + 1].
	1 to: m do: [:i | lengths at: (used at: i) put: (depths at: i)].
	^lengths
!
removeLightest: nodes weights: weights
	| best index |
	index := 1.
	best := weights at: nodes first.
	2 to: nodes size do: [:i | (weights at: (nodes at: i)) < best ifTrue: [index := i. best := weights at: (nodes at: i)]].
	^nodes removeIndex: index
!
codesFor: lengths
	"Canonical Huffman codes for the lengths, bit-reversed (deflate sends them most significant bit first into a least significant first stream)."
	| counts next code codes |
	counts := Array new: 16 withAll: 0.
	lengths do: [:each | each > 0 ifTrue: [counts at: each + 1 put: (counts at: each + 1) + 1]].
	next := Array new: 16 withAll: 0.
	code := 0.
	1 to: 15 do: [:n |
		code := code + (counts at: n) bitShift: 1.
		next at: n + 1 put: code].
	codes := Array new: lengths size withAll: 0.
	1 to: lengths size do: [:i | | n |
		n := lengths at: i.
		n > 0 ifTrue: [
			codes at: i put: (self reverse: (next at: n + 1) bits: n).
			next at: n + 1 put: (next at: n + 1) + 1]].
	^codes
!
reverse: anInteger bits: n
	| r c |
	r := 0.
	c := anInteger.
	n timesRepeat: [
		r := (r bitShift: 1) bitOr: (c bitAnd: 1).
		c := c bitShift: -1].
	^r
! !

!ZLib methodsFor: 'initialization'!
initialize
	maxChain := 16.
	bits := 0.
	bitCount := 0.
	size := 0
!
maxChain: anInteger
	"How many earlier positions with the same hash are tried for each match (16 by default)."
	maxChain := anInteger
!
position
	"After inflating: the index of the first input byte after the deflate data."
	^position
! !

!ZLib methodsFor: 'compressing'!
deflate: bytes
	"The raw deflate data of bytes: blocks of the tokens of matchesFrom:head:prev:literals:distances:."
	| n head prev litLens distances count blockStart pos r final |
	self class tables.
	input := bytes.
	inputSize := n := bytes size.
	output := ByteArray new: n // 4 + 1024.
	head := ByteArray new: 131072.
	prev := ByteArray new: 131072.
	litLens := ByteArray new: 131070.
	distances := ByteArray new: 131070.
	blockStart := 1.
	final := false.
	pos := 1.
	[pos <= n] whileTrue: [
		r := self matchesFrom: pos head: head prev: prev literals: litLens distances: distances.
		pos := r bitShift: -16.
		count := r bitAnd: 65535.
		final := pos > n.
		self writeBlock: litLens distances: distances count: count from: blockStart to: pos - 1 final: final.
		blockStart := pos].
	final ifFalse: [self writeBlock: litLens distances: distances count: 0 from: blockStart to: n final: true].
	bitCount > 0 ifTrue: [self putByte: (bits bitAnd: 255)].
	^output copyFrom: 1 to: size
!
matchesFrom: start head: head prev: prev literals: litLens distances: distances
	"The LZ77 tokens of a block from start, until there are 65535 or the input ends: token i (0-based) is the uint16 at 2i + 1 of litLens (a literal byte, or 256 + a match's length) and of distances (the match's distance, 0 for a literal); head and prev are the hash chains, 32768 uint32 each (positions, 0 for none). Answer the position after the tokens times 65536 plus their count. The VM's primitive (DeflateMatcher), else matchesInSmalltalkFrom:head:prev:literals:distances:."
	^(self class primMatches: input from: start head: head prev: prev literals: litLens distances: distances chain: maxChain size: inputSize)
		ifNil: [self matchesInSmalltalkFrom: start head: head prev: prev literals: litLens distances: distances]
!
matchesInSmalltalkFrom: start head: head prev: prev literals: litLens distances: distances
	"matchesFrom:head:prev:literals:distances: in Smalltalk: greedy, at most maxChain candidates a position (each before it, nearer than 32768); the positions inside a match of at most 16 bytes are hashed too."
	| n pos count best bestDistance candidate chain limit length hash |
	n := inputSize.
	pos := start.
	count := 0.
	[pos <= n and: [count < 65535]] whileTrue: [
		best := 0.
		bestDistance := 0.
		pos + 2 <= n ifTrue: [
			hash := self hashAt: pos.
			candidate := head uint32At: hash * 4 + 1.
			prev uint32At: (pos bitAnd: 32767) * 4 + 1 put: candidate.
			head uint32At: hash * 4 + 1 put: pos.
			limit := n - pos + 1 min: 258.
			chain := maxChain.
			[candidate > 0 and: [candidate < pos and: [chain > 0 and: [pos - candidate < 32768]]]] whileTrue: [
				(input at: candidate + best) = (input at: pos + best) ifTrue: [
					length := 0.
					[length < limit and: [(input at: candidate + length) = (input at: pos + length)]] whileTrue: [length := length + 1].
					length > best ifTrue: [
						best := length.
						bestDistance := pos - candidate.
						best = limit ifTrue: [chain := 1]]].
				candidate := prev uint32At: (candidate bitAnd: 32767) * 4 + 1.
				chain := chain - 1]].
		best >= 3
			ifTrue: [
				litLens uint16At: count * 2 + 1 put: 256 + best.
				distances uint16At: count * 2 + 1 put: bestDistance.
				best <= 16 ifTrue: [
					pos + 1 to: (pos + best - 1 min: n - 2) do: [:p |
						hash := self hashAt: p.
						prev uint32At: (p bitAnd: 32767) * 4 + 1 put: (head uint32At: hash * 4 + 1).
						head uint32At: hash * 4 + 1 put: p]].
				pos := pos + best]
			ifFalse: [
				litLens uint16At: count * 2 + 1 put: (input at: pos).
				distances uint16At: count * 2 + 1 put: 0.
				pos := pos + 1].
		count := count + 1].
	^(pos bitShift: 16) + count
!
hashAt: p
	"The hash (0 to 32767) of the three bytes at p."
	^((input at: p) bitShift: 7) bitXor: (((input at: p + 1) bitShift: 4) bitXor: (input at: p + 2))
!
writeBlock: litLens distances: distances count: count from: start to: stop final: final
	"Write count tokens (input bytes start to stop) as the shortest of a dynamic, fixed or stored block."
	| litFreq distFreq extraBits litLengths distLengths header dynamicBits fixedBits storedBits counts |
	counts := ByteArray new: 1264.
	extraBits := self class primCount: litLens distances: distances count: count into: counts.
	extraBits isNil
		ifTrue: [
			litFreq := Array new: 286 withAll: 0.
			distFreq := Array new: 30 withAll: 0.
			extraBits := self countTokens: litLens distances: distances count: count literals: litFreq distances: distFreq]
		ifFalse: [
			litFreq := (0 to: 285) collect: [:i | counts uint32At: i * 4 + 1].
			distFreq := (0 to: 29) collect: [:i | counts uint32At: i * 4 + 1145]].
	litFreq at: 257 put: 1.
	litLengths := self class lengthsFor: litFreq limit: 15.
	distLengths := self class lengthsFor: distFreq limit: 15.
	header := self headerFor: litLengths distances: distLengths.
	dynamicBits := 3 + (header at: 4) + (self cost: litFreq lengths: litLengths) + (self cost: distFreq lengths: distLengths) + extraBits.
	fixedBits := 3 + (self cost: litFreq lengths: FixedLiteralLengths) + (self cost: distFreq lengths: FixedDistanceLengths) + extraBits.
	storedBits := (stop - start + 1) * 8 + (40 * ((stop - start + 65535) // 65535 max: 1)).
	(storedBits < dynamicBits and: [storedBits < fixedBits]) ifTrue: [^self writeStoredFrom: start to: stop final: final].
	self writeBits: (final ifTrue: [1] ifFalse: [0]) count: 1.
	fixedBits <= dynamicBits
		ifTrue: [
			self writeBits: 1 count: 2.
			self writeTokens: litLens distances: distances count: count literals: FixedLiteralLengths distances: FixedDistanceLengths]
		ifFalse: [
			self writeBits: 2 count: 2.
			self writeHeader: header.
			self writeTokens: litLens distances: distances count: count literals: litLengths distances: distLengths]
!
countTokens: litLens distances: distances count: count literals: litFreq distances: distFreq
	"litFreq and distFreq += the codes of count tokens; answer the extra bits they need. The fallback of the VM's zlibTokenCounts."
	| extraBits |
	extraBits := 0.
	1 to: count do: [:i | | v c d |
		v := litLens uint16At: 2 * i - 1.
		v < 256
			ifTrue: [litFreq at: v + 1 put: (litFreq at: v + 1) + 1]
			ifFalse: [
				c := LengthCodes at: v - 256.
				litFreq at: c + 258 put: (litFreq at: c + 258) + 1.
				d := DistanceCodes at: (distances uint16At: 2 * i - 1).
				distFreq at: d + 1 put: (distFreq at: d + 1) + 1.
				extraBits := extraBits + (LengthExtra at: c + 1) + (DistanceExtra at: d + 1)]].
	^extraBits
!
cost: freqs lengths: lengths
	| sum |
	sum := 0.
	1 to: freqs size do: [:i | sum := sum + ((freqs at: i) * (lengths at: i))].
	^sum
!
headerFor: litLengths distances: distLengths
	"{the code-length symbols (symbol, extra value). code-length code lengths. HCLEN. header bits after the block type} for a dynamic block."
	| hlit hdist all symbols i freqs clLengths hclen headerBits |
	hlit := 257.
	257 to: 286 do: [:k | (litLengths at: k) > 0 ifTrue: [hlit := k]].
	hdist := 1.
	1 to: 30 do: [:k | (distLengths at: k) > 0 ifTrue: [hdist := k]].
	all := Array new: hlit + hdist.
	all replaceFrom: 1 to: hlit with: litLengths startingAt: 1.
	all replaceFrom: hlit + 1 to: hlit + hdist with: distLengths startingAt: 1.
	symbols := OrderedCollection new: 2 * all size + 8.
	i := 1.
	[i <= all size] whileTrue: [ | len run r k |
		len := all at: i.
		run := 1.
		[i + run <= all size and: [(all at: i + run) = len]] whileTrue: [run := run + 1].
		len = 0
			ifTrue: [
				r := run.
				[r >= 11] whileTrue: [k := r min: 138. symbols add: 18; add: k - 11. r := r - k].
				r >= 3 ifTrue: [symbols add: 17; add: r - 3. r := 0].
				r timesRepeat: [symbols add: 0; add: 0]]
			ifFalse: [
				symbols add: len; add: 0.
				r := run - 1.
				[r >= 3] whileTrue: [k := r min: 6. symbols add: 16; add: k - 3. r := r - k].
				r timesRepeat: [symbols add: len; add: 0]].
		i := i + run].
	freqs := Array new: 19 withAll: 0.
	1 to: symbols size by: 2 do: [:k | freqs at: (symbols at: k) + 1 put: (freqs at: (symbols at: k) + 1) + 1].
	clLengths := self class lengthsFor: freqs limit: 7.
	hclen := 4.
	1 to: 19 do: [:k | (clLengths at: (CodeLengthOrder at: k) + 1) > 0 ifTrue: [hclen := k max: 4]].
	headerBits := 14 + (3 * hclen) + (self cost: freqs lengths: clLengths)
		+ (2 * (freqs at: 17)) + (3 * (freqs at: 18)) + (7 * (freqs at: 19)).
	^Array with: symbols with: clLengths with: (Array with: hlit with: hdist with: hclen) with: headerBits
!
writeHeader: header
	| symbols clLengths counts codes |
	symbols := header at: 1.
	clLengths := header at: 2.
	counts := header at: 3.
	self writeBits: (counts at: 1) - 257 count: 5.
	self writeBits: (counts at: 2) - 1 count: 5.
	self writeBits: (counts at: 3) - 4 count: 4.
	1 to: (counts at: 3) do: [:k | self writeBits: (clLengths at: (CodeLengthOrder at: k) + 1) count: 3].
	codes := self class codesFor: clLengths.
	1 to: symbols size by: 2 do: [:k | | s |
		s := symbols at: k.
		self writeBits: (codes at: s + 1) count: (clLengths at: s + 1).
		s = 16 ifTrue: [self writeBits: (symbols at: k + 1) count: 2].
		s = 17 ifTrue: [self writeBits: (symbols at: k + 1) count: 3].
		s = 18 ifTrue: [self writeBits: (symbols at: k + 1) count: 7]]
!
writeTokens: litLens distances: distances count: count literals: litLengths distances: distLengths
	"The tokens' codes and the end of the block: the VM's primitive (DeflateCoder), else writeTokensInSmalltalk:distances:count:literals:distances:."
	| litCodes distCodes table r |
	litCodes := self class codesFor: litLengths.
	distCodes := self class codesFor: distLengths.
	table := ByteArray new: 1264.
	0 to: 285 do: [:i | table uint32At: i * 4 + 1 put: (litCodes at: i + 1) + ((litLengths at: i + 1) bitShift: 16)].
	0 to: 29 do: [:i | table uint32At: i * 4 + 1145 put: (distCodes at: i + 1) + ((distLengths at: i + 1) bitShift: 16)].
	self ensure: count * 6 + 8.
	r := self class primWriteTokens: litLens distances: distances count: count table: table into: output size: size bits: bits count: bitCount.
	r isNil ifTrue: [^self writeTokensInSmalltalk: litLens distances: distances count: count literals: litLengths distances: distLengths].
	size := r bitShift: -3.
	bitCount := r bitAnd: 7.
	bits := (output at: size + 1) bitAnd: (1 bitShift: bitCount) - 1
!
writeTokensInSmalltalk: litLens distances: distances count: count literals: litLengths distances: distLengths
	| litCodes distCodes |
	litCodes := self class codesFor: litLengths.
	distCodes := self class codesFor: distLengths.
	1 to: count do: [:i | | v len c e d dc |
		v := litLens uint16At: 2 * i - 1.
		v < 256
			ifTrue: [self writeBits: (litCodes at: v + 1) count: (litLengths at: v + 1)]
			ifFalse: [
				len := v - 256.
				c := LengthCodes at: len.
				self writeBits: (litCodes at: c + 258) count: (litLengths at: c + 258).
				e := LengthExtra at: c + 1.
				e > 0 ifTrue: [self writeBits: len - (LengthBase at: c + 1) count: e].
				d := distances uint16At: 2 * i - 1.
				dc := DistanceCodes at: d.
				self writeBits: (distCodes at: dc + 1) count: (distLengths at: dc + 1).
				e := DistanceExtra at: dc + 1.
				e > 0 ifTrue: [self writeBits: d - (DistanceBase at: dc + 1) count: e]]].
	self writeBits: (litCodes at: 257) count: (litLengths at: 257)
!
writeStoredFrom: start to: stop final: final
	"Stored blocks of at most 65535 bytes; only the last one of a final block is marked final."
	| p n |
	p := start.
	[n := stop - p + 1 min: 65535.
	 self writeBits: ((final and: [p + n > stop]) ifTrue: [1] ifFalse: [0]) count: 3.
	 bitCount > 0 ifTrue: [self putByte: (bits bitAnd: 255)].
	 bits := 0.
	 bitCount := 0.
	 self putByte: (n bitAnd: 255); putByte: (n bitShift: -8); putByte: ((n bitXor: 16rFFFF) bitAnd: 255); putByte: ((n bitXor: 16rFFFF) bitShift: -8).
	 self ensure: n.
	 output replaceFrom: size + 1 to: size + n with: input startingAt: p.
	 size := size + n.
	 p := p + n.
	 p <= stop] whileTrue
!
writeBits: anInteger count: n
	"Append the n low bits of anInteger, least significant first."
	bits := bits bitOr: (anInteger bitShift: bitCount).
	bitCount := bitCount + n.
	[bitCount >= 8] whileTrue: [
		self putByte: (bits bitAnd: 255).
		bits := bits bitShift: -8.
		bitCount := bitCount - 8]
!
putByte: aByte
	size = output size ifTrue: [self ensure: 1].
	size := size + 1.
	output at: size put: aByte
!
ensure: n
	"Room for n more output bytes."
	| grown |
	size + n <= output size ifTrue: [^self].
	grown := ByteArray new: (output size * 2 max: size + n + 1024).
	grown replaceFrom: 1 to: size with: output startingAt: 1.
	output := grown
! !

!ZLib methodsFor: 'streaming'!
deflate: bytes final: aBoolean
	"The next piece of my raw deflate stream: bytes as blocks that may refer back 32 KB into the bytes of my earlier pieces, then a sync flush (aBoolean false: an empty stored block, so the piece ends byte-aligned) or the final block (true: the stream ends; the next call starts another)."
	| n pos r count blockStart final |
	self class tables.
	self startStream.
	self append: bytes.
	n := inputSize.
	(output isNil or: [output size < (bytes size // 4 + 64)]) ifTrue: [output := ByteArray new: bytes size // 4 + 64].
	size := 0.
	pos := n - bytes size + 1.
	blockStart := pos.
	final := false.
	[pos <= n] whileTrue: [
		r := self matchesFrom: pos head: head prev: prev literals: litLens distances: distances.
		pos := r bitShift: -16.
		count := r bitAnd: 65535.
		final := aBoolean and: [pos > n].
		self writeBlock: litLens distances: distances count: count from: blockStart to: pos - 1 final: final.
		blockStart := pos].
	aBoolean
		ifTrue: [
			final ifFalse: [self writeBlock: litLens distances: distances count: 0 from: n + 1 to: n final: true].
			bitCount > 0 ifTrue: [self putByte: (bits bitAnd: 255)].
			self endStream]
		ifFalse: [self syncFlush].
	^output copyFrom: 1 to: size
!
compress: bytes final: aBoolean
	"The next piece of my zlib stream: deflate:final:'s, after the header (78 9C) the first time and before the Adler-32 of all the bytes of the stream the last (aBoolean)."
	| first sum body out |
	first := adler isNil.
	sum := self class adler32: (first ifTrue: [1] ifFalse: [adler]) then: (self class adler32Of: bytes) length: bytes size.
	body := self deflate: bytes final: aBoolean.
	adler := aBoolean ifFalse: [sum].
	out := WriteStream on: (ByteArray new: body size + 6).
	first ifTrue: [out nextPut: 16r78; nextPut: 16r9C].
	out nextPutAll: body.
	aBoolean ifTrue: [0 to: 3 do: [:i | out nextPut: ((sum bitShift: (3 - i) * -8) bitAnd: 255)]].
	^out contents
!
startStream
	"The tables of a stream, the first time."
	head isNil ifFalse: [^self].
	head := ByteArray new: 131072.
	prev := ByteArray new: 131072.
	litLens := ByteArray new: 131070.
	distances := ByteArray new: 131070.
	input := ByteArray new: 65536.
	inputSize := 0.
	bits := 0.
	bitCount := 0
!
endStream
	head := prev := litLens := distances := nil.
	input := nil.
	inputSize := 0.
	bits := 0.
	bitCount := 0
!
append: bytes
	"Copy bytes into input after what is kept of the earlier pieces (its first inputSize bytes: at least the last 32 KB, the window). When that would pass historyLimit, the bytes before the window are dropped in steps of 32768, so that the hash chains' positions only move by that (prev is indexed by the position modulo 32768); the buffer grows when it must."
	| shift grown |
	inputSize + bytes size > self class historyLimit ifTrue: [
		shift := inputSize - 32768 // 32768 * 32768.
		shift > 0 ifTrue: [
			input replaceFrom: 1 to: inputSize - shift with: input startingAt: shift + 1.
			inputSize := inputSize - shift.
			self rebase: head by: shift.
			self rebase: prev by: shift]].
	inputSize + bytes size > input size ifTrue: [
		grown := ByteArray new: (inputSize + bytes size) * 3 // 2.
		grown replaceFrom: 1 to: inputSize with: input startingAt: 1.
		input := grown].
	input replaceFrom: inputSize + 1 to: inputSize + bytes size with: bytes startingAt: 1.
	inputSize := inputSize + bytes size
!
rebase: aTable by: shift
	"The positions (uint32, 0 none) in aTable moved back by shift; those dropped become none."
	0 to: aTable size - 4 by: 4 do: [:i | | v |
		v := aTable uint32At: i + 1.
		v > 0 ifTrue: [aTable uint32At: i + 1 put: (v > shift ifTrue: [v - shift] ifFalse: [0])]]
!
syncFlush
	"An empty stored block, not final: up to the byte boundary, then 00 00 FF FF."
	self writeBits: 0 count: 3.
	bitCount > 0 ifTrue: [self putByte: (bits bitAnd: 255)].
	bits := 0.
	bitCount := 0.
	self putByte: 0; putByte: 0; putByte: 255; putByte: 255
! !

!ZLib methodsFor: 'decompressing'!
inflate: bytes from: start
	"The bytes of the deflate data in bytes from index start; afterwards position is the index after it."
	| final type |
	self class tables.
	input := bytes.
	position := start.
	bits := 0.
	bitCount := 0.
	size := 0.
	output := ByteArray new: (bytes size * 4 max: 1024).
	[final := self readBits: 1.
	 type := self readBits: 2.
	 type = 0 ifTrue: [self inflateStored].
	 type = 1 ifTrue: [self inflateWith: (self decoderFor: FixedLiteralLengths) distances: (self decoderFor: FixedDistanceLengths)].
	 type = 2 ifTrue: [self inflateDynamic].
	 type = 3 ifTrue: [self error: 'invalid deflate block type'].
	 final = 1] whileFalse.
	^output copyFrom: 1 to: size
!
inflateStored
	| n |
	bits := 0.
	bitCount := 0.
	position + 3 > input size ifTrue: [^self error: 'deflate data ends early'].
	n := (input at: position) + ((input at: position + 1) bitShift: 8).
	(n bitXor: 16rFFFF) = ((input at: position + 2) + ((input at: position + 3) bitShift: 8)) ifFalse: [^self error: 'corrupt stored block length'].
	position := position + 4.
	position + n - 1 > input size ifTrue: [^self error: 'deflate data ends early'].
	self ensure: n.
	output replaceFrom: size + 1 to: size + n with: input startingAt: position.
	size := size + n.
	position := position + n
!
inflateDynamic
	| hlit hdist hclen cl clDecoder lengths i |
	hlit := (self readBits: 5) + 257.
	hdist := (self readBits: 5) + 1.
	hclen := (self readBits: 4) + 4.
	cl := Array new: 19 withAll: 0.
	1 to: hclen do: [:k | cl at: (CodeLengthOrder at: k) + 1 put: (self readBits: 3)].
	clDecoder := self decoderFor: cl.
	lengths := Array new: hlit + hdist withAll: 0.
	i := 0.
	[i < (hlit + hdist)] whileTrue: [ | sym value repeat |
		sym := self decode: clDecoder.
		sym < 16
			ifTrue: [i := i + 1. lengths at: i put: sym]
			ifFalse: [
				sym = 16 ifTrue: [
					i = 0 ifTrue: [^self error: 'invalid code length repeat'].
					value := lengths at: i.
					repeat := 3 + (self readBits: 2)].
				sym = 17 ifTrue: [value := 0. repeat := 3 + (self readBits: 3)].
				sym = 18 ifTrue: [value := 0. repeat := 11 + (self readBits: 7)].
				i + repeat > (hlit + hdist) ifTrue: [^self error: 'too many code lengths'].
				repeat timesRepeat: [i := i + 1. lengths at: i put: value]]].
	self
		inflateWith: (self decoderFor: (lengths copyFrom: 1 to: hlit))
		distances: (self decoderFor: (lengths copyFrom: hlit + 1 to: hlit + hdist))
!
inflateWith: literals distances: distances
	| sym len d from |
	[sym := self decode: literals.
	 sym = 256] whileFalse: [
		sym < 256
			ifTrue: [self putByte: sym]
			ifFalse: [
				sym := sym - 257.
				sym >= 29 ifTrue: [^self error: 'invalid length code'].
				len := (LengthBase at: sym + 1) + (self readBits: (LengthExtra at: sym + 1)).
				sym := self decode: distances.
				sym >= 30 ifTrue: [^self error: 'invalid distance code'].
				d := (DistanceBase at: sym + 1) + (self readBits: (DistanceExtra at: sym + 1)).
				d > size ifTrue: [^self error: 'distance too far back'].
				self ensure: len.
				from := size - d.
				1 to: len do: [:k | output at: size + k put: (output at: from + k)].
				size := size + len]]
!
decoderFor: lengths
	"{counts of codes per length (index length + 1). symbols in canonical order}."
	| counts offsets symbols |
	counts := Array new: 16 withAll: 0.
	lengths do: [:each | counts at: each + 1 put: (counts at: each + 1) + 1].
	counts at: 1 put: 0.
	offsets := Array new: 16 withAll: 0.
	2 to: 15 do: [:n | offsets at: n + 1 put: (offsets at: n) + (counts at: n)].
	symbols := Array new: lengths size withAll: 0.
	1 to: lengths size do: [:i | | n |
		n := lengths at: i.
		n > 0 ifTrue: [
			symbols at: (offsets at: n + 1) + 1 put: i - 1.
			offsets at: n + 1 put: (offsets at: n + 1) + 1]].
	^Array with: counts with: symbols
!
decode: aDecoder
	"The next symbol: read one bit at a time until the code is one of aDecoder's."
	| counts symbols code first index count |
	counts := aDecoder at: 1.
	symbols := aDecoder at: 2.
	code := 0.
	first := 0.
	index := 0.
	1 to: 15 do: [:len |
		code := code bitOr: (self readBits: 1).
		count := counts at: len + 1.
		code - count < first ifTrue: [^symbols at: index + (code - first) + 1].
		index := index + count.
		first := first + count bitShift: 1.
		code := code bitShift: 1].
	^self error: 'invalid Huffman code'
!
readBits: n
	| value |
	[bitCount < n] whileTrue: [
		position > input size ifTrue: [^self error: 'deflate data ends early'].
		bits := bits bitOr: ((input at: position) bitShift: bitCount).
		position := position + 1.
		bitCount := bitCount + 8].
	value := bits bitAnd: (1 bitShift: n) - 1.
	bits := bits bitShift: n negated.
	bitCount := bitCount - n.
	^value
! !
