TestCase subclass: #PixelRowsTest
	instanceVariableNames: 'sim rows random'
	classVariableNames: ''
	package: 'Tests-VM'!

PixelRowsTest comment: 'PixelRows, run as Smalltalk (VMSimulation) with the rows of each CPU (both run here: NEON''s and SSE2''s intrinsics as the simulation of Neon and Sse2), against PlatformRaster''s own pixel arithmetic (over:color:, swapRB:), on rows of every length to 13 at every alignment of a 16-byte block: pixels at the edges (0, opaque, transparent, channels above alpha) and at random. Each must answer how many pixels it did (a multiple of 4, at most 3 short of the row), do those and touch nothing else.'!

!PixelRowsTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!PixelRowsTest methodsFor: 'helpers'!
pixel
	"An edge case or a random pixel."
	| edges |
	edges := #(0 16rFFFFFFFF 16rFF000000 16r00FFFFFF 16r80808080 16r01FF7F00 16r7F7F7F7F 16rFE010203).
	^(random nextInt: 3) = 1
		ifTrue: [edges at: (random nextInt: edges size)]
		ifFalse: [((random nextInt: 65536) - 1 bitShift: 16) + (random nextInt: 65536) - 1]
!
row: anArray
	"A pointer to the words of anArray in simulated memory, with a guard word before and after."
	| a |
	a := sim memory allocate: anArray size + 2 * 4.
	0 to: anArray size + 1 do: [:i | sim memory uint32At: a + (4 * i) put: 16rDEADBEEF].
	anArray doWithIndex: [:w :i | sim memory uint32At: a + (4 * i) put: w].
	^sim memory pointerTo: (CTypeRegistry default at: 'uint32_t') at: a + 4
!
wordsAt: p count: n
	"The n words at p and the guard words around them."
	| a |
	a := sim memory addressOf: p.
	^(-1 to: n) collect: [:i | sim memory uint32At: a + (4 * i)]
!
check: p skew: skew original: d done: k count: n expect: aBlock
	"k pixels done of the n at p, skew words into the row d: the first k as aBlock answers for each index, the others, the skew words before them and the guards as they were."
	| words |
	words := self wordsAt: p - skew count: n + skew.
	self assert: k \\ 4 equals: 0.
	self assert: (k between: n - 3 and: n).
	self assert: words first equals: 16rDEADBEEF.
	self assert: words last equals: 16rDEADBEEF.
	1 to: skew do: [:i | self assert: (words at: i + 1) equals: (d at: i)].
	1 to: n do: [:i | self assert: (words at: skew + i + 1) equals: (aBlock value: i value: i <= k)]
!
run: aRowsClass
	"Each row operation on rows of 0 to 13 pixels, starting at each word of a block."
	| raster |
	sim := VMSimulation modules: {aRowsClass}.
	rows := sim module: aRowsClass.
	raster := PlatformRaster basicNew.
	random := Random seed: 4321.
	0 to: 13 do: [:n |
		0 to: 3 do: [:skew |
			| d s c dp sp k |
			d := (1 to: n + skew) collect: [:i | self pixel].
			s := (1 to: n + skew) collect: [:i | self pixel].
			c := self pixel.
			"fill"
			dp := (self row: d) + skew.
			k := rows fill: dp count: n value: c.
			self check: dp skew: skew original: d done: k count: n expect: [:i :done | done ifTrue: [c] ifFalse: [d at: skew + i]].
			"swap"
			dp := (self row: d) + skew.
			sp := (self row: s) + skew.
			k := rows swap: dp from: sp count: n.
			self check: dp skew: skew original: d done: k count: n expect: [:i :done | done ifTrue: [raster swapRB: (s at: skew + i)] ifFalse: [d at: skew + i]].
			"over a color"
			dp := (self row: d) + skew.
			k := rows over: dp color: c count: n.
			self check: dp skew: skew original: d done: k count: n expect: [:i :done | done ifTrue: [raster over: (d at: skew + i) color: c] ifFalse: [d at: skew + i]].
			"over texels, swapped or not"
			#(false true) do: [:swap |
				dp := (self row: d) + skew.
				sp := (self row: s) + skew.
				k := rows over: dp texels: sp count: n swap: swap.
				self check: dp skew: skew original: d done: k count: n expect: [:i :done |
					done
						ifTrue: [raster over: (d at: skew + i) color: (swap ifTrue: [raster swapRB: (s at: skew + i)] ifFalse: [s at: skew + i])]
						ifFalse: [d at: skew + i]]]]]
! !

!PixelRowsTest methodsFor: 'tests'!
testNeonRows
	self run: NeonPixelRows
!
testSse2Rows
	self run: Sse2PixelRows
! !
