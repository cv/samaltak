TestCase subclass: #ByteSearchTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

ByteSearchTest comment: 'ByteSearch, run as Smalltalk (VMSimulation) with the blocks of each CPU (both run here), answers what a naive search, comparison or case conversion answers and reads nothing outside the bytes it is given: each lies in simulated memory with nothing mapped after it.'!

!ByteSearchTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!ByteSearchTest methodsFor: 'helpers'!
place: aByteArray in: aSimulation
	"Its address in aSimulation's memory, a segment of its own (a 64 KB page: free it after use, or thousands of them fill a small heap)."
	| a |
	a := aSimulation memory allocate: aByteArray size.
	aSimulation memory bytesAt: a put: aByteArray.
	^a
!
pointerAt: anAddress in: aSimulation
	^aSimulation memory pointerTo: (CTypeRegistry default at: 'uint8_t') at: anAddress
!
naiveIndexOf: needle in: haystack from: start
	start to: haystack size - needle size do: [:i |
		(haystack copyFrom: i + 1 to: i + needle size) = needle ifTrue: [^i]].
	^-1
!
searchWith: aBlocksClass
	"Haystacks around the block sizes, alphabets of 1, 2 and 3 bytes (many partial matches; 254, 255 and 0) and of all 256; needles cut from the haystack at a random place and at its end, the same with a middle byte changed (the first and the last still match), and random ones; starts from 0 to past the last position."
	| sim search random |
	sim := VMSimulation modules: {ByteSearch. aBlocksClass}.
	search := sim module: ByteSearch.
	random := Random seed: 1234.
	#(0 1 2 7 8 9 15 16 17 18 23 24 31 32 33 40 47 48 49 70) do: [:n |
		#(1 2 3 256) do: [:k |
			| haystack address a |
			haystack := ((1 to: n) collect: [:i | 253 + (random nextInt: k) \\ 256]) asByteArray.
			address := self place: haystack in: sim.
			a := self pointerAt: address in: sim.
			((#(1 2 3 8 9 16 17 19 20) , {n - 1. n. n + 1}) select: [:m | m between: 1 and: n + 1]) asSet do: [:m |
				| last needles |
				last := n - m.
				needles := OrderedCollection with: ((1 to: m) collect: [:i | 253 + (random nextInt: k) \\ 256]) asByteArray.
				m <= n ifTrue: [
					{random nextInt: last + 1. last + 1} do: [:o |
						| needle j |
						needle := haystack copyFrom: o to: o + m - 1.
						needles add: needle.
						m > 2 ifTrue: [
							needle := needle copy.
							j := random between: 2 and: m - 1.
							needle at: j put: (needle at: j) + 1 \\ 256.
							needles add: needle]]].
				needles do: [:needle |
					| needleAddress b |
					needleAddress := self place: needle in: sim.
					b := self pointerAt: needleAddress in: sim.
					({0. 1. random nextInt: n + 1. last. last + 1. n + 1} select: [:s | s >= 0]) asSet do: [:s |
						self
							assert: (search indexOfBytes: b size: m in: a size: n from: s)
							equals: (self naiveIndexOf: needle in: haystack from: s)].
					m = 1 ifTrue: [
						{0. 1. last. last + 1. n} do: [:s |
							s >= 0 ifTrue: [
								self
									assert: (search indexOfByte: needle first in: a size: n from: s)
									equals: (self naiveIndexOf: needle in: haystack from: s)]]].
					sim memory free: needleAddress]].
			sim memory free: address]]
! !

!ByteSearchTest methodsFor: 'tests'!
testSse2Blocks
	self searchWith: Sse2ByteBlocks
!
testNeonBlocks
	self searchWith: NeonByteBlocks
!
testNeonMismatchAndCase
	self compareWith: NeonByteBlocks
!
testSse2MismatchAndCase
	self compareWith: Sse2ByteBlocks
! !

!ByteSearchTest methodsFor: 'helpers'!
compareWith: aBlocksClass
	"mismatchOf:with:from:size: of runs that differ at each place (or nowhere) from each start; convertCase:into:size:upper: of every byte at a random place of runs around the block size, against ByteSearch's own uppercase: and lowercase: (Character's asUppercase and asLowercase of the byte, but µ's, which is wide). The runs of one size share their simulated memory."
	| sim search random |
	sim := VMSimulation modules: {ByteSearch. aBlocksClass}.
	search := sim module: ByteSearch.
	random := Random seed: 99.
	#(0 1 7 15 16 17 31 32 33 47) do: [:n |
		| a aa ab pa pb |
		a := ((1 to: n) collect: [:i | (random nextInt: 256) - 1]) asByteArray.
		aa := self place: a in: sim.
		ab := self place: a in: sim.
		pa := self pointerAt: aa in: sim.
		pb := self pointerAt: ab in: sim.
		(0 to: n) do: [:at |
			| b |
			b := a copy.
			at < n ifTrue: [b at: at + 1 put: (b at: at + 1) + 1 + (random nextInt: 254) \\ 256].
			sim memory bytesAt: (sim memory addressOf: pb) put: b.
			(0 to: n) do: [:s |
				self
					assert: (search mismatchOf: pa with: pb from: s size: n)
					equals: (s <= at ifTrue: [at] ifFalse: [n])]].
		sim memory free: aa; free: ab].
	#(1 15 16 17 32 33) do: [:n |
		| aa ab pa pb |
		aa := self place: (ByteArray new: n) in: sim.
		ab := self place: (ByteArray new: n) in: sim.
		pa := self pointerAt: aa in: sim.
		pb := self pointerAt: ab in: sim.
		0 to: 255 do: [:c |
			| a ok |
			a := ((1 to: n) collect: [:i | (random nextInt: 256) - 1]) asByteArray.
			a at: (random nextInt: n) put: c.
			sim memory bytesAt: (sim memory addressOf: pa) put: a.
			#(true false) do: [:upper |
				ok := search convertCase: pa into: pb size: n upper: upper.
				self assert: ok equals: (upper not or: [(a includes: 255) not]).
				ok ifTrue: [
					self
						assert: (sim memory bytesAt: (sim memory addressOf: pb) count: n)
						equals: (a collect: [:x | upper ifTrue: [ByteSearch basicNew uppercase: x] ifFalse: [ByteSearch basicNew lowercase: x]])]]].
		sim memory free: aa; free: ab]
! !
