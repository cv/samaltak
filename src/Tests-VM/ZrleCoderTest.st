TestCase subclass: #ZrleCoderTest
	instanceVariableNames: 'sim random'
	classVariableNames: ''
	package: 'Tests-VM'!

ZrleCoderTest comment: 'ZrleCoder, run as Smalltalk (VMSimulation) with the blocks and rows of each CPU (both run here: NEON''s and SSE2''s intrinsics as the simulation of Neon and Sse2), against RfbZrleEncoder''s Smalltalk (tilesInSmalltalk:width:height:bytesPerPixel:cpixelSize:offset:): rectangles of 1 to 130 pixels by 1 to 66, 1-, 2- and 4-byte pixels with whole and 3-byte CPIXELs from either offset, pixels of one colour, two, a few, up to 127 and more (runs of every length, across rows, past 255) and noise, alpha bytes that differ under the same CPIXEL. The bytes must be the same, nothing written past them in the output and nothing at all in the pixels.'!

!ZrleCoderTest methodsFor: 'running'!
timeLimitMilliseconds
	^300000
! !

!ZrleCoderTest methodsFor: 'helpers'!
pointerAt: anAddress
	^sim memory pointerTo: (CTypeRegistry default at: 'uint8_t') at: anAddress
!
pixels: n bpp: bpp mode: mode
	"n pixels: of one colour (0), two (1), four (2), a dozen (3) or 200 (4) in runs of random lengths, or noise (5); in 4-byte pixels a random fourth byte of a few values."
	| colours out i |
	colours := (1 to: (#(1 2 4 12 200 1) at: mode + 1)) collect: [:k | ((1 to: bpp) collect: [:b | (random nextInt: 256) - 1]) asByteArray].
	out := ByteArray new: n * bpp.
	i := 0.
	[i < n] whileTrue: [| c len |
		c := colours at: (random nextInt: colours size).
		len := mode = 5 ifTrue: [1] ifFalse: [#(1 1 2 3 7 64 300) at: (random nextInt: 7)].
		len := len min: n - i.
		len timesRepeat: [
			mode = 5 ifTrue: [c := ((1 to: bpp) collect: [:b | (random nextInt: 256) - 1]) asByteArray].
			out replaceFrom: i * bpp + 1 to: i * bpp + bpp with: c startingAt: 1.
			(bpp = 4 and: [(random nextInt: 8) = 1]) ifTrue: [out at: i * bpp + 4 put: (random nextInt: 3) - 1].
			i := i + 1]].
	^out
!
check: anAddress size: n holds: aByteArray
	"aByteArray, then guard bytes to n."
	| expected |
	expected := ByteArray new: n withAll: 16rA5.
	expected replaceFrom: 1 to: aByteArray size with: aByteArray startingAt: 1.
	self assert: (sim memory bytesAt: anAddress count: n) equals: expected
!
run: aBlocksClass rows: aRowsClass
	| zrle scratchA encoder |
	sim := VMSimulation modules: {ZrleCoder. ByteSearch. aBlocksClass. PixelPacker. aRowsClass}.
	zrle := sim module: ZrleCoder.
	random := Random seed: 2468.
	scratchA := sim memory allocate: 52224.
	sim memory bytesAt: scratchA put: (ByteArray new: 52224 withAll: 16r5A).
	encoder := (Smalltalk at: #RfbZrleEncoder) new.
	#(#(4 3 0) #(4 3 1) #(4 4 0) #(2 2 0) #(1 1 0)) do: [:f | | bpp cp off |
		bpp := f at: 1.
		cp := f at: 2.
		off := f at: 3.
		#(#(1 1) #(3 2) #(17 5) #(64 64) #(65 3) #(130 2) #(5 66)) do: [:size | | w h |
			w := size at: 1.
			h := size at: 2.
			0 to: 5 do: [:mode | | px pxA outA outSize expected n |
				true ifTrue: [
					px := self pixels: w * h bpp: bpp mode: mode.
					expected := encoder tilesInSmalltalk: px width: w height: h bytesPerPixel: bpp cpixelSize: cp offset: off.
					pxA := sim memory allocate: px size.
					sim memory bytesAt: pxA put: px.
					outSize := w * h * cp + 64.
					outA := sim memory allocate: outSize.
					sim memory bytesAt: outA put: (ByteArray new: outSize withAll: 16rA5).
					n := zrle
						tiles: (self pointerAt: pxA) width: w height: h bpp: bpp cpixel: cp offset: off
						scratch: (sim memory pointerTo: (CTypeRegistry default at: 'uint32_t') at: scratchA)
						into: (self pointerAt: outA).
					self assert: n equals: expected size.
					self check: outA size: outSize holds: expected.
					self assert: (sim memory bytesAt: pxA count: px size) equals: px.
					sim memory free: pxA.
					sim memory free: outA]]]].
	sim memory free: scratchA
! !

!ZrleCoderTest methodsFor: 'tests'!
testNeon
	self run: NeonByteBlocks rows: NeonPackRows
!
testSse2
	self run: Sse2ByteBlocks rows: Sse2PackRows
! !
