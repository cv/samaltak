TestCase subclass: #ZLibTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ZLibTest comment: 'I check ZLib: Python''s zlib stream of ''hello world'' decoded and reproduced byte for byte, round trips of empty, short, repetitive, random and mixed data (across 65536-token blocks and at distances near 32 KB), the block type chosen by size (dynamic for repetitive data, stored for random), the Adler-32 checksum, and corrupt streams refused.'!

!ZLibTest methodsFor: 'tests'!
testPythonHelloWorld
	"zlib.compress(b''hello world''): one fixed Huffman block."
	| z |
	z := #[16r78 16r9C 16rCB 16r48 16rCD 16rC9 16rC9 16r57 16r28 16rCF 16r2F 16rCA 16r49 16r01 16r00 16r1A 16r0B 16r04 16r5D].
	self assert: (ZLib decompress: z) asString equals: 'hello world'.
	self assert: (ZLib compress: 'hello world' asByteArray) equals: z
!
testShortRoundTrips
	#('' 'a' 'ab' 'abc' 'aaaa' 'hello hello hello hello') do: [:each |
		self assert: (ZLib decompress: (ZLib compress: each asByteArray)) equals: each asByteArray]
!
testRepetitiveDataIsDynamic
	| data z |
	data := ByteArray new: 200000.
	1 to: data size do: [:i | data at: i put: i \\ 37 * 5 + (i // 5000) \\ 256].
	z := ZLib compress: data.
	self assert: z size < 4000.
	self assert: ((z at: 3) bitShift: -1) \\ 4 equals: 2.
	self assert: (ZLib decompress: z) equals: data
!
testRandomDataIsStored
	| data z |
	data := self randomBytes: 100000 seed: 7.
	z := ZLib compress: data.
	"zlib header and checksum, and five bytes per stored block of at most 65535 bytes"
	self assert: z size <= (data size + 6 + 15).
	self assert: ((z at: 3) bitShift: -1) \\ 4 equals: 0.
	self assert: (ZLib decompress: z) equals: data
!
testMixedDataAcrossBlocks
	"Runs, random stretches and copies from almost 32 KB back, in more than one block of tokens."
	| random data z |
	random := self randomBytes: 40000 seed: 3.
	data := ByteArray new: 400000.
	1 to: data size do: [:i |
		data at: i put: (i \\ 1000 < 400
			ifTrue: [random at: i \\ 32760 + 1]
			ifFalse: [i \\ 1000 < 700 ifTrue: [0] ifFalse: [random at: i \\ 997 + 1]])].
	z := ZLib compress: data.
	self assert: z size < (data size // 2).
	self assert: (ZLib decompress: z) equals: data
!
testAdler32
	self assert: (ZLib adler32Of: 'Wikipedia' asByteArray) equals: 16r11E60398.
	self assert: (ZLib adler32Of: ByteArray new) equals: 1
!
testMatchesPrimitiveMatchesSmalltalk
	"The VM's LZ77 (zlibMatches) makes ZLib>>matchesInSmalltalkFrom:head:prev:literals:distances:'s tokens, chains and positions: on empty, short, run, few-valued, random and mixed data, from the start and part way, with chains of 1, 16 and 300, and with chains holding garbage (positions at or after the current one are not candidates)."
	| random inputs |
	random := Random seed: 99.
	inputs := {ByteArray new. #[7]. #[1 2 3]. #[1 2 3 1 2 3 1 2 3 1 2 3]. ByteArray new: 70000 withAll: 9.
		((1 to: 70000) collect: [:i | random nextInt: 3]) asByteArray.
		self randomBytes: 3000 seed: 5.
		((1 to: 140000) collect: [:i | i \\ 1000 < 500 ifTrue: [i \\ 7] ifFalse: [(random nextInt: 256) - 1]]) asByteArray}.
	inputs do: [:data | #(1 16 300) do: [:chain | {1. data size // 3 + 1} do: [:start |
		#(false true) do: [:garbage | | a b |
			a := self matchesOf: data from: start chain: chain garbage: garbage primitive: true.
			b := self matchesOf: data from: start chain: chain garbage: garbage primitive: false.
			self deny: (a at: 1) isNil.
			self assert: a equals: b]]]]
!
testMatchesPrimitiveRefusesBadArguments
	| head prev lits dists |
	head := ByteArray new: 131072.
	prev := ByteArray new: 131072.
	lits := ByteArray new: 131070.
	dists := ByteArray new: 131070.
	self assert: (ZLib primMatches: #[1 2 3] from: 1 head: head prev: prev literals: lits distances: dists chain: 16) notNil.
	self assert: (ZLib primMatches: #[1 2 3] from: 5 head: head prev: prev literals: lits distances: dists chain: 16) isNil.
	self assert: (ZLib primMatches: #[1 2 3] from: 1 head: head prev: prev literals: lits distances: dists chain: 0) isNil.
	self assert: (ZLib primMatches: #[1 2 3] from: 1 head: head prev: head literals: lits distances: dists chain: 16) isNil.
	self assert: (ZLib primMatches: #[1 2 3] from: 1 head: head prev: prev literals: (ByteArray new: 100) distances: dists chain: 16) isNil.
	self assert: (ZLib primMatches: #(1 2 3) from: 1 head: head prev: prev literals: lits distances: dists chain: 16) isNil.
	"Of the first bytes only."
	self assert: (ZLib primMatches: #[1 2 3 4 5] from: 1 head: head prev: prev literals: lits distances: dists chain: 16 size: 3) equals: (4 bitShift: 16) + 3.
	self assert: (ZLib primMatches: #[1 2 3] from: 1 head: head prev: prev literals: lits distances: dists chain: 16 size: 4) isNil.
	self assert: (ZLib primMatches: #[1 2 3] from: 5 head: head prev: prev literals: lits distances: dists chain: 16 size: 3) isNil
!
testTokenPrimitivesMatchSmalltalk
	"The VM's token coding (zlibWriteTokens) is ZLib's Smalltalk's, bit for bit, and ZLib's counting RFC 1951's (assertCountsOf:...): blocks of literals, short and long matches at every distance code, after 0 to 7 pending bits, with fixed and with skewed dynamic codes."
	| random data z head prev lits dists r count dynamic |
	random := Random seed: 17.
	data := ((1 to: 120000) collect: [:i | i \\ 3000 < 1500 ifTrue: [(random nextInt: 256) - 1] ifFalse: [i \\ 3000 < 2200 ifTrue: [i \\ 5] ifFalse: [i \\ 251]]]) asByteArray.
	1 to: 30000 do: [:i | data at: 90000 + i put: (data at: 90000 + i - (i \\ 7 * 4500 + 1))].
	head := ByteArray new: 131072.
	prev := ByteArray new: 131072.
	lits := ByteArray new: 131070.
	dists := ByteArray new: 131070.
	z := ZLib new.
	z instVarNamed: 'input' put: data; instVarNamed: 'inputSize' put: data size.
	r := z matchesInSmalltalkFrom: 1 head: head prev: prev literals: lits distances: dists.
	count := r bitAnd: 65535.
	self assert: count = 65535.
	self assert: ((0 to: count - 1) count: [:i | (lits uint16At: i * 2 + 1) > 256]) > 1000.
	self assertCountsOf: lits distances: dists count: count.
	self assertCountsOf: lits distances: dists count: 0.
	dynamic := (1 to: 286) collect: [:i | i <= 144 ifTrue: [i \\ 7 + 8] ifFalse: [i \\ 5 + 3]].
	0 to: 7 do: [:pending |
		self assertCodingOf: lits distances: dists count: count literals: (ZLib classPool at: #FixedLiteralLengths) distances: (ZLib classPool at: #FixedDistanceLengths) pending: pending.
		self assertCodingOf: lits distances: dists count: 1000 + pending literals: dynamic distances: ((1 to: 30) collect: [:i | i \\ 4 + 5]) pending: pending]
!
testTokenPrimitivesRefuseBadArguments
	| lits dists table |
	lits := ByteArray new: 131070.
	dists := ByteArray new: 131070.
	table := ByteArray new: 1264.
	self assert: (ZLib primWriteTokens: lits distances: dists count: 10 table: table into: (ByteArray new: 68) size: 0 bits: 0 count: 0) notNil.
	self assert: (ZLib primWriteTokens: lits distances: dists count: 10 table: table into: (ByteArray new: 67) size: 0 bits: 0 count: 0) isNil.
	self assert: (ZLib primWriteTokens: lits distances: dists count: 10 table: table into: (ByteArray new: 100) size: 0 bits: 4 count: 2) isNil.
	table uint32At: 5 put: 16r100000.
	self assert: (ZLib primWriteTokens: lits distances: dists count: 10 table: table into: (ByteArray new: 100) size: 0 bits: 0 count: 0) isNil
!
testAdler32
	"ZLib's Adler-32 is RFC 1950's (its sums reduced at every byte here), across its 5552-byte reductions, and its example's."
	| reference |
	reference := [:data | | a b |
		a := 1.
		b := 0.
		data do: [:x |
			a := a + x \\ 65521.
			b := b + a \\ 65521].
		(b bitShift: 16) + a].
	self assert: (ZLib adler32Of: 'Wikipedia' asByteArray) equals: 16r11E60398.
	#(0 1 3 4 5 5551 5552 5553 11104 100001) do: [:n | | data |
		data := self randomBytes: n seed: n.
		self assert: (ZLib adler32Of: data) equals: (reference value: data).
		data := ByteArray new: n withAll: 255.
		self assert: (ZLib adler32Of: data) equals: (reference value: data)]
!
testCorruptStreamsAreRefused
	| z |
	z := ZLib compress: 'hello hello hello hello' asByteArray.
	self should: [ZLib decompress: (z copyFrom: 1 to: z size - 1)] raise: Error.
	self should: [ZLib decompress: (z copy at: z size put: ((z at: z size) bitXor: 1); yourself)] raise: Error.
	self should: [ZLib decompress: (z copy at: 1 put: 16r79; yourself)] raise: Error.
	self should: [ZLib decompress: #[16r78 16r9C 16rFF 16rFF 16rFF 16rFF 16rFF 16rFF]] raise: Error
! !

!ZLibTest methodsFor: 'support'!
assertCountsOf: lits distances: dists count: count
	"countTokens: counts the codes RFC 1951 (3.2.5) gives the tokens, and their extra bits: its codes computed here."
	| litFreq distFreq extra lit dist bits |
	litFreq := Bitmap new: 286.
	distFreq := Bitmap new: 30.
	extra := ZLib new countTokens: lits distances: dists count: count literals: litFreq distances: distFreq.
	lit := Array new: 286 withAll: 0.
	dist := Array new: 30 withAll: 0.
	bits := 0.
	1 to: count do: [:i | | v len c dd |
		v := lits uint16At: 2 * i - 1.
		v < 256
			ifTrue: [lit at: v + 1 put: (lit at: v + 1) + 1]
			ifFalse: [
				len := v - 256.
				c := len = 258
					ifTrue: [28]
					ifFalse: [len - 3 < 8 ifTrue: [len - 3] ifFalse: [| e | e := (len - 3) highBit - 3. 4 * (e + 1) + ((len - 3 bitShift: e negated) bitAnd: 3)]].
				lit at: 258 + c put: (lit at: 258 + c) + 1.
				bits := bits + ((c < 8 or: [c = 28]) ifTrue: [0] ifFalse: [(c bitShift: -2) - 1]).
				dd := (dists uint16At: 2 * i - 1) - 1.
				c := dd < 4 ifTrue: [dd] ifFalse: [| k | k := dd highBit - 1. 2 * k + ((dd bitShift: 1 - k) bitAnd: 1)].
				dist at: c + 1 put: (dist at: c + 1) + 1.
				bits := bits + (c < 4 ifTrue: [0] ifFalse: [(c bitShift: -1) - 1])]].
	self assert: extra equals: bits.
	self assert: litFreq asArray equals: lit.
	self assert: distFreq asArray equals: dist
!
assertCodingOf: lits distances: dists count: count literals: litLengths distances: distLengths pending: pending
	"writeTokens: (the primitive) and writeTokensInSmalltalk: give the same bytes and pending bits after pending bits 1, 0, 1, ..."
	| coders |
	coders := (1 to: 2) collect: [:k | | c |
		c := ZLib new.
		c instVarNamed: 'output' put: (ByteArray new: 16).
		1 to: pending do: [:i | c writeBits: (i \\ 2) count: 1].
		c].
	(coders at: 1) writeTokens: lits distances: dists count: count literals: litLengths distances: distLengths.
	(coders at: 2) writeTokensInSmalltalk: lits distances: dists count: count literals: litLengths distances: distLengths.
	#('size' 'bits' 'bitCount') do: [:name |
		self assert: ((coders at: 1) instVarNamed: name) equals: ((coders at: 2) instVarNamed: name)].
	self assert: (((coders at: 1) instVarNamed: 'output') copyFrom: 1 to: ((coders at: 1) instVarNamed: 'size'))
		equals: (((coders at: 2) instVarNamed: 'output') copyFrom: 1 to: ((coders at: 2) instVarNamed: 'size'))
!
matchesOf: data from: start chain: chain garbage: garbage primitive: aBoolean
	"{the answer. head. prev. literals. distances} of a block of tokens of data from start, the chains first filled with a pattern (garbage) or empty."
	| z head prev lits dists r |
	head := ByteArray new: 131072.
	prev := ByteArray new: 131072.
	garbage ifTrue: [1 to: 32768 do: [:i | head uint32At: i * 4 - 3 put: i * 7919 \\ (data size + 50000). prev uint32At: i * 4 - 3 put: i * 104729 \\ (data size + 3)]].
	lits := ByteArray new: 131070.
	dists := ByteArray new: 131070.
	z := ZLib new maxChain: chain; yourself.
	z instVarNamed: 'input' put: data; instVarNamed: 'inputSize' put: data size.
	r := aBoolean
		ifTrue: [ZLib primMatches: data from: start head: head prev: prev literals: lits distances: dists chain: chain]
		ifFalse: [z matchesInSmalltalkFrom: start head: head prev: prev literals: lits distances: dists].
	^{r. head. prev. lits. dists}
!
randomBytes: n seed: anInteger
	| random bytes |
	random := Random seed: anInteger.
	bytes := ByteArray new: n.
	1 to: n do: [:i | bytes at: i put: (random nextInt: 256) - 1].
	^bytes
! !

!ZLibTest methodsFor: 'huffman'!
referenceLengths: freqs
	"Huffman code lengths as ZLib made them before its two queues: the two lightest of a list of nodes (of equal weights the first in it: leaves in symbol order, then merged nodes as made) merged until one is left."
	| used m weights parents active next lengths lightest |
	lengths := Array new: freqs size withAll: 0.
	used := (1 to: freqs size) select: [:i | (freqs at: i) > 0].
	m := used size.
	weights := Array new: 2 * m.
	parents := Array new: 2 * m withAll: 0.
	1 to: m do: [:i | weights at: i put: (freqs at: (used at: i))].
	active := (1 to: m) asOrderedCollection.
	next := m.
	lightest := [| index |
		index := 1.
		2 to: active size do: [:i | (weights at: (active at: i)) < (weights at: (active at: index)) ifTrue: [index := i]].
		active removeIndex: index].
	[active size > 1] whileTrue: [| a b |
		a := lightest value.
		b := lightest value.
		next := next + 1.
		weights at: next put: (weights at: a) + (weights at: b).
		parents at: a put: next.
		parents at: b put: next.
		active add: next].
	1 to: m do: [:i | | depth node |
		depth := 0.
		node := i.
		[(parents at: node) > 0] whileTrue: [depth := depth + 1. node := parents at: node].
		lengths at: (used at: i) put: depth].
	^lengths
!
testHuffmanLengthsBreakTiesAsBefore
	"Many equal weights (ties between leaves, and between leaves and merged nodes): the same lengths as the list of nodes gave, so that deflate's output is unchanged."
	| random |
	random := Random seed: 42.
	1 to: 200 do: [:k | | freqs |
		freqs := (1 to: (#(2 3 19 30 286) at: k \\ 5 + 1)) collect: [:i |
			(random next * 3) floor = 0 ifTrue: [0] ifFalse: [(random next * (#(2 5 40 1000) at: k \\ 4 + 1)) floor + 1]].
		self assert: (ZLib huffmanLengths: freqs) equals: (self referenceLengths: freqs)]
! !

!ZLibTest methodsFor: 'streaming'!
inflatePieces: pieces
	"The bytes of raw deflate pieces that are not final, ended here with an empty final stored block."
	^ZLib new inflate: (pieces inject: #[] into: [:all :each | all , each]) , #[1 0 0 255 255] from: 1
!
testStreamPiecesEndWithASyncFlush
	| z pieces data |
	z := ZLib new.
	data := #('hello ' 'world, ' '' 'hello again, world' 'x') collect: [:s | s asByteArray].
	pieces := data collect: [:d | z deflate: d final: false].
	pieces do: [:each | self assert: (each last: 4) equals: #[0 0 255 255]].
	self assert: (pieces at: 3) = (#[0 0 0 255 255]) description: 'an empty piece is the flush alone (3 bits, then the byte boundary)'.
	self assert: (self inflatePieces: pieces) equals: (data inject: #[] into: [:a :b | a , b]).
	"Each prefix of the pieces inflates by itself: a viewer decodes a rectangle before the next arrives."
	1 to: pieces size do: [:k |
		self assert: (self inflatePieces: (pieces first: k)) equals: ((data first: k) inject: #[] into: [:a :b | a , b])]
!
testStreamReachesBackIntoEarlierPieces
	| z chunk first second |
	z := ZLib new.
	chunk := self randomBytes: 2000 seed: 7.
	first := z deflate: chunk final: false.
	second := z deflate: chunk final: false.
	self assert: first size > 2000.
	self assert: second size < 40 description: 'the second copy is a match into the first piece'.
	self assert: (self inflatePieces: (Array with: first with: second)) equals: chunk , chunk
!
testStreamKeepsOnlyAWindow
	"Many pieces: what is kept stays bounded and matches still decode (positions moved by multiples of 32768)."
	| z pieces all |
	z := ZLib new.
	pieces := OrderedCollection new.
	all := #[].
	1 to: 40 do: [:i | | d |
		d := (self randomBytes: 3000 + (i * 97) seed: i \\ 5) , (self randomBytes: 500 seed: 99).
		all := all , d.
		pieces add: (z deflate: d final: false).
		self assert: (z instVarNamed: 'inputSize') <= (ZLib historyLimit + d size)].
	self assert: (self inflatePieces: pieces) equals: all.
	self assert: (pieces inject: 0 into: [:s :p | s + p size]) < (all size * 9 // 10) description: 'repeats across pieces were found'
!
testCompressFinalIsOneZlibStream
	| z pieces data stream |
	z := ZLib new.
	data := Array with: 'abcabcabc' asByteArray with: (self randomBytes: 70000 seed: 3) with: 'abcabc' asByteArray.
	pieces := OrderedCollection new.
	data doWithIndex: [:d :i | pieces add: (z compress: d final: i = data size)].
	self assert: (pieces first first: 2) equals: #[16r78 16r9C].
	self deny: ((pieces at: 2) first: 2) = #[16r78 16r9C].
	stream := pieces inject: #[] into: [:a :b | a , b].
	self assert: (ZLib decompress: stream) equals: (data inject: #[] into: [:a :b | a , b]).
	"After the final piece a new stream begins."
	self assert: (ZLib decompress: (z compress: 'again' asByteArray final: true)) equals: 'again' asByteArray
!
testDeflateFinalEndsTheStream
	| z a b |
	z := ZLib new.
	a := z deflate: 'one two one two' asByteArray final: false.
	b := z deflate: #[] final: true.
	self assert: (ZLib inflate: a , b) equals: 'one two one two' asByteArray
!
testAdlerOfTwoParts
	| a b |
	a := self randomBytes: 7000 seed: 11.
	b := self randomBytes: 70000 seed: 12.
	self assert: (ZLib adler32: (ZLib adler32Of: a) then: (ZLib adler32Of: b) length: b size) equals: (ZLib adler32Of: a , b).
	self assert: (ZLib adler32: (ZLib adler32Of: a) then: (ZLib adler32Of: #[]) length: 0) equals: (ZLib adler32Of: a).
	self assert: (ZLib adler32: 1 then: (ZLib adler32Of: b) length: b size) equals: (ZLib adler32Of: b)
! !
