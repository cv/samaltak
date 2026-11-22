TestCase subclass: #PngRowsTest
	instanceVariableNames: 'sim random'
	classVariableNames: ''
	package: 'Tests-VM'!

PngRowsTest comment: 'PngRows and PngFilter, run as Smalltalk (VMSimulation) with the rows of each CPU (both run here: NEON''s and SSE2''s intrinsics as the simulation of Neon and Sse2), against the PNG filters'' definitions written out here (PNGWriter class>>filteredInSmalltalk:width:height:channels:''s): rows of every length to 40 bytes after the first pixel at every alignment of a 16-byte block, 3 and 4 channels, bytes at the edges (0, 1, 127, 128, 254, 255), few distinct ones (Paeth''s ties) and random. costs: must add each filter''s cost over the last whole blocks of the row and answer how many bytes those are, apply: must filter exactly those bytes, both touching nothing else; PngFilter must filter small images (packing, the first row and pixel, the bottom-up order) as the definitions do.'!

!PngRowsTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!PngRowsTest methodsFor: 'definitions'!
paeth: a with: b with: c
	| p pa pb pc |
	p := a + b - c.
	pa := (p - a) abs.
	pb := (p - b) abs.
	pc := (p - c) abs.
	(pa <= pb and: [pa <= pc]) ifTrue: [^a].
	pb <= pc ifTrue: [^b].
	^c
!
output: f x: x a: a b: b c: c
	"Filter f's output for the byte x."
	| d |
	d := f = 0 ifTrue: [x] ifFalse: [f = 1 ifTrue: [x - a] ifFalse: [f = 2 ifTrue: [x - b] ifFalse: [f = 3 ifTrue: [x - (a + b // 2)] ifFalse: [x - (self paeth: a with: b with: c)]]]].
	^d bitAnd: 255
!
cost: v
	^v < 128 ifTrue: [v] ifFalse: [256 - v]
!
output: f of: cur prior: prior at: i channels: n
	"Filter f's output for byte i (1-based) of the row cur over prior (nil for the first row)."
	^self
		output: f
		x: (cur at: i)
		a: (i > n ifTrue: [cur at: i - n] ifFalse: [0])
		b: (prior isNil ifTrue: [0] ifFalse: [prior at: i])
		c: ((i > n and: [prior notNil]) ifTrue: [prior at: i - n] ifFalse: [0])
!
filtered: rgba width: w height: h channels: n
	"The PNG rows of rgba as PNGWriter writes them."
	| raw stride prior |
	stride := w * n.
	raw := ByteArray new: (stride + 1) * h.
	prior := nil.
	0 to: h - 1 do: [:y | | cur costs best |
		cur := ByteArray new: stride.
		0 to: w - 1 do: [:x | 1 to: n do: [:k | cur at: x * n + k put: (rgba at: (y * w + x) * 4 + k)]].
		costs := (0 to: 4) collect: [:f | (1 to: stride) inject: 0 into: [:s :i | s + (self cost: (self output: f of: cur prior: prior at: i channels: n))]].
		best := 1.
		2 to: 5 do: [:f | (costs at: f) < (costs at: best) ifTrue: [best := f]].
		raw at: y * (stride + 1) + 1 put: best - 1.
		1 to: stride do: [:i | raw at: y * (stride + 1) + 1 + i put: (self output: best - 1 of: cur prior: prior at: i channels: n)].
		prior := cur].
	^raw
! !

!PngRowsTest methodsFor: 'helpers'!
byte: mode
	mode = 1 ifTrue: [^#(0 1 127 128 254 255) at: (random nextInt: 6)].
	mode = 2 ifTrue: [^#(0 1 2 3) at: (random nextInt: 4)].
	^(random nextInt: 256) - 1
!
bytes: size
	"Bytes at the edges, of few values or random."
	| mode |
	mode := random nextInt: 3.
	^((1 to: size) collect: [:i | self byte: mode]) asByteArray
!
pointerAt: anAddress
	^sim memory pointerTo: (CTypeRegistry default at: 'uint8_t') at: anAddress
!
put: aByteArray at: anAddress skew: skew
	"anAddress: 96 bytes of guards around aByteArray at 16 + skew."
	sim memory bytesAt: anAddress put: (ByteArray new: 96 + aByteArray size withAll: 16rA5).
	sim memory bytesAt: anAddress + 16 + skew put: aByteArray
!
check: anAddress skew: skew holds: aByteArray
	| expected |
	expected := ByteArray new: 96 + aByteArray size withAll: 16rA5.
	expected replaceFrom: 17 + skew to: 16 + skew + aByteArray size with: aByteArray startingAt: 1.
	self assert: (sim memory bytesAt: anAddress count: expected size) equals: expected
!
runRows: aRowsClass
	"costs: and apply: of each filter on rows of every length to 40 after a pixel of n bytes, at every alignment."
	| rows curA priorA sumsA |
	sim := VMSimulation modules: {aRowsClass}.
	rows := sim module: aRowsClass.
	random := Random seed: 4321.
	curA := sim memory allocate: 256.
	priorA := sim memory allocate: 256.
	sumsA := sim memory allocate: 40.
	#(3 4) do: [:n | 0 to: 40 do: [:m | 0 to: 15 do: [:skew |
		| cur prior k start initial sums |
		cur := self bytes: n + m.
		prior := self bytes: n + m.
		self put: cur at: curA skew: skew.
		self put: prior at: priorA skew: skew.
		initial := (1 to: 5) collect: [:f | random nextInt: 100000].
		initial doWithIndex: [:s :f | sim memory uint64At: sumsA + (8 * (f - 1)) put: s].
		k := rows
			costs: (self pointerAt: curA + 16 + skew + n)
			prior: (self pointerAt: priorA + 16 + skew + n)
			count: m channels: n
			into: (sim memory pointerTo: (CTypeRegistry default at: 'uint64_t') at: sumsA).
		self assert: k equals: m - (m \\ 16).
		start := n + m - k.
		sums := (0 to: 4) collect: [:f | sim memory uint64At: sumsA + (8 * f)].
		self assert: sums equals: ((0 to: 4) collect: [:f |
			(initial at: f + 1) + ((start + 1 to: n + m) inject: 0 into: [:s :i | s + (self cost: (self output: f of: cur prior: prior at: i channels: n))])]).
		self check: curA skew: skew holds: cur.
		self check: priorA skew: skew holds: prior.
		0 to: 4 do: [:f | | out |
			self put: cur at: curA skew: skew.
			k := rows
				apply: f
				to: (self pointerAt: curA + 16 + skew + n)
				prior: (self pointerAt: priorA + 16 + skew + n)
				count: m channels: n.
			self assert: k equals: m - (m \\ 16).
			out := cur copy.
			f = 0 ifFalse: [start + 1 to: n + m do: [:i | out at: i put: (self output: f of: cur prior: prior at: i channels: n)]].
			self check: curA skew: skew holds: out.
			self check: priorA skew: skew holds: prior]]]]
!
runFilter: aRowsClass
	"PngFilter on images of 1 to 3 rows of 1 to 21 pixels, 3 and 4 channels."
	| png |
	sim := VMSimulation modules: {PngFilter. aRowsClass}.
	png := sim module: PngFilter.
	random := Random seed: 8765.
	#(3 4) do: [:n | #(1 2 3 5 6 11 13 21) do: [:w | 1 to: 3 do: [:h |
		| rgba rgbaA rawA |
		rgba := self bytes: w * h * 4.
		rgbaA := sim memory allocate: rgba size + 96.
		rawA := sim memory allocate: (w * n + 1) * h + 96.
		self put: rgba at: rgbaA skew: 0.
		self put: (ByteArray new: (w * n + 1) * h) at: rawA skew: 0.
		png filterPng: (self pointerAt: rgbaA + 16) width: w height: h channels: n into: (self pointerAt: rawA + 16).
		self check: rawA skew: 0 holds: (self filtered: rgba width: w height: h channels: n).
		self check: rgbaA skew: 0 holds: rgba.
		sim memory free: rgbaA.
		sim memory free: rawA]]]
! !

!PngRowsTest methodsFor: 'tests'!
testNeonRows
	self runRows: NeonPngRows
!
testSse2Rows
	self runRows: Sse2PngRows
!
testNeonFilter
	self runFilter: NeonPngRows
!
testSse2Filter
	self runFilter: Sse2PngRows
! !
