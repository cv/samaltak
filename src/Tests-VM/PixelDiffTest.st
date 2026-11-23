TestCase subclass: #PixelDiffTest
	instanceVariableNames: 'sim random'
	classVariableNames: ''
	package: 'Tests-VM'!

PixelDiffTest comment: 'PixelDiff, run as Smalltalk (VMSimulation) with the blocks of each CPU (both run here), against its definition written out here: a block of the rectangle (on the screen''s grid of the block size, clipped to the rectangle) is marked when any byte of a pixel of it differs from the copy''s, and the rectangle''s pixels are copied in. Rectangles of every alignment to the blocks and of 1 to 40 pixels each way, changes of one byte anywhere (the first and last of a block, of a row), many or none, block sizes 16 and 5; nothing written outside the rectangle in the copy, nor past the marks.'!

!PixelDiffTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!PixelDiffTest methodsFor: 'helpers'!
pointerAt: anAddress
	^sim memory pointerTo: (CTypeRegistry default at: 'uint8_t') at: anAddress
!
run: aBlocksClass
	| diff ext stride copyA |
	sim := VMSimulation modules: {PixelDiff. ByteSearch. aBlocksClass}.
	diff := sim module: PixelDiff.
	random := Random seed: 1357.
	ext := 61 @ 45.
	stride := ext x * 4 + 8.
	copyA := sim memory allocate: stride * ext y.
	1 to: 60 do: [:t | | bs copy x y w h rect src expected marks first cols bands srcA marksA n count |
		bs := t odd ifTrue: [16] ifFalse: [5].
		copy := ((1 to: stride * ext y) collect: [:i | random nextInt: 3]) asByteArray.
		x := (random nextInt: ext x) - 1.
		y := (random nextInt: ext y) - 1.
		w := random nextInt: (ext x - x min: 40).
		h := random nextInt: (ext y - y min: 40).
		src := ByteArray new: w * h * 4.
		0 to: h - 1 do: [:j | src replaceFrom: j * w * 4 + 1 to: j + 1 * w * 4 with: copy startingAt: (y + j) * stride + (x * 4) + 1].
		((#(0 1 3 30 300) at: t \\ 5 + 1) min: src size) timesRepeat: [| i |
			i := random nextInt: src size.
			src at: i put: (src at: i) + 1 \\ 256].
		first := x // bs.
		cols := (x + w - 1) // bs - first + 1.
		bands := (y + h - 1) // bs - (y // bs) + 1.
		marks := ByteArray new: cols * bands.
		0 to: h - 1 do: [:j | 0 to: w - 1 do: [:i |
			(src copyFrom: (j * w + i) * 4 + 1 to: (j * w + i) * 4 + 4) = (copy copyFrom: (y + j) * stride + (x + i * 4) + 1 to: (y + j) * stride + (x + i * 4) + 4) ifFalse: [
				marks at: ((y + j) // bs - (y // bs)) * cols + ((x + i) // bs - first) + 1 put: 1]]].
		expected := copy copy.
		0 to: h - 1 do: [:j | expected replaceFrom: (y + j) * stride + (x * 4) + 1 to: (y + j) * stride + (x + w * 4) with: src startingAt: j * w * 4 + 1].
		sim memory bytesAt: copyA put: copy.
		srcA := sim memory allocate: src size + 1.
		sim memory bytesAt: srcA put: src.
		marksA := sim memory allocate: marks size + 16.
		sim memory bytesAt: marksA put: (ByteArray new: marks size + 16 withAll: 16rA5).
		n := diff blocks: (self pointerAt: srcA) width: w height: h into: (self pointerAt: copyA) stride: stride left: x top: y block: bs marks: (self pointerAt: marksA).
		count := marks inject: 0 into: [:s :m | s + m].
		self assert: n equals: count.
		self assert: (sim memory bytesAt: marksA count: marks size + 16) equals: marks , (ByteArray new: 16 withAll: 16rA5).
		self assert: (sim memory bytesAt: copyA count: copy size) equals: expected.
		self assert: (sim memory bytesAt: srcA count: src size) equals: src.
		sim memory free: srcA.
		sim memory free: marksA].
	sim memory free: copyA
! !

!PixelDiffTest methodsFor: 'tests'!
testNeon
	self run: NeonByteBlocks
!
testSse2
	self run: Sse2ByteBlocks
! !
