TestCase subclass: #PackRowsTest
	instanceVariableNames: 'sim random'
	classVariableNames: ''
	package: 'Tests-VM'!

PackRowsTest comment: 'PackRows and PixelPacker, run as Smalltalk (VMSimulation) with the rows of each CPU (both run here: NEON''s and SSE2''s intrinsics as the simulation of Neon and Sse2), against the packing written out here: rows of 0 to 40 pixels at every alignment of a 16-byte block, both byte orders. pack: must pack the pixels it answers it did (a multiple of 4, at most all but 2) and write nothing beyond 4 bytes after them; PixelPacker must pack rectangles of rows of any stride exactly, touching nothing else.'!

!PackRowsTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!PackRowsTest methodsFor: 'helpers'!
bytes: size
	^((1 to: size) collect: [:i | (random nextInt: 256) - 1]) asByteArray
!
pointerAt: anAddress
	^sim memory pointerTo: (CTypeRegistry default at: 'uint8_t') at: anAddress
!
put: aByteArray at: anAddress skew: skew
	"anAddress: 96 bytes of guards around aByteArray at 16 + skew."
	sim memory bytesAt: anAddress put: (ByteArray new: 96 + aByteArray size withAll: 16rA5).
	sim memory bytesAt: anAddress + 16 + skew put: aByteArray
!
packed: src stride: stride width: w height: h swap: aBoolean
	"The definition: bytes 0 1 2 of each pixel, or 2 1 0."
	| out |
	out := WriteStream on: (ByteArray new: w * h * 3).
	0 to: h - 1 do: [:y | 0 to: w - 1 do: [:x | | i |
		i := y * stride + (x * 4).
		aBoolean
			ifTrue: [out nextPut: (src at: i + 3); nextPut: (src at: i + 2); nextPut: (src at: i + 1)]
			ifFalse: [out nextPut: (src at: i + 1); nextPut: (src at: i + 2); nextPut: (src at: i + 3)]]].
	^out contents
!
runRows: aRowsClass
	| rows srcA dstA |
	sim := VMSimulation modules: {aRowsClass}.
	rows := sim module: aRowsClass.
	random := Random seed: 2468.
	srcA := sim memory allocate: 40 * 4 + 128.
	dstA := sim memory allocate: 40 * 3 + 128.
	#(0 1) do: [:swap | 0 to: 40 do: [:w | 0 to: 15 do: [:skew |
		| src k expected got |
		src := self bytes: w * 4.
		self put: src at: srcA skew: skew.
		self put: (ByteArray new: w * 3 withAll: 16rA5) at: dstA skew: 15 - skew.
		k := rows pack: (self pointerAt: srcA + 16 + skew) count: w swap: swap into: (self pointerAt: dstA + 16 + 15 - skew).
		self assert: k equals: ((w - 2 max: 0) bitClear: 3).
		expected := self packed: src stride: w * 4 width: k height: 1 swap: swap = 1.
		got := sim memory bytesAt: dstA + 16 + 15 - skew count: k * 3.
		self assert: got equals: expected.
		self assert: (sim memory bytesAt: dstA count: 16 + 15 - skew) = ((ByteArray new: 16 + 15 - skew withAll: 16rA5)) description: 'nothing before'.
		self assert: (sim memory bytesAt: dstA + 16 + 15 - skew + (k * 3) + 4 count: 40) = ((ByteArray new: 40 withAll: 16rA5)) description: 'at most 4 bytes after'.
		self assert: (sim memory bytesAt: srcA + 16 + skew count: src size) equals: src]]]
!
runPacker: aRowsClass
	"PixelPacker on rectangles of 1 to 21 pixels by 1 to 3 rows, rows with bytes between them."
	| packer |
	sim := VMSimulation modules: {PixelPacker. aRowsClass}.
	packer := sim module: PixelPacker.
	random := Random seed: 1357.
	#(0 1) do: [:swap | #(1 2 3 5 6 7 8 11 13 21) do: [:w | 1 to: 3 do: [:h | #(0 4 12) do: [:pad |
		| stride src srcA dstA out |
		stride := w * 4 + pad.
		src := self bytes: stride * h.
		srcA := sim memory allocate: src size + 96.
		dstA := sim memory allocate: w * h * 3 + 96.
		self put: src at: srcA skew: 0.
		self put: (ByteArray new: w * h * 3) at: dstA skew: 0.
		packer pack: (self pointerAt: srcA + 16) stride: stride width: w height: h swap: swap into: (self pointerAt: dstA + 16).
		out := self packed: src stride: stride width: w height: h swap: swap = 1.
		self assert: (sim memory bytesAt: dstA count: out size + 96) equals: (ByteArray new: 16 withAll: 16rA5) , out , (ByteArray new: 80 withAll: 16rA5).
		sim memory free: srcA.
		sim memory free: dstA]]]]
! !

!PackRowsTest methodsFor: 'tests'!
testNeonRows
	self runRows: NeonPackRows
!
testSse2Rows
	self runRows: Sse2PackRows
!
testNeonPacker
	self runPacker: NeonPackRows
!
testSse2Packer
	self runPacker: Sse2PackRows
! !
