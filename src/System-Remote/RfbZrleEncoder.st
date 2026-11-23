Object subclass: #RfbZrleEncoder
	instanceVariableNames: 'zstream bpp cp cpOffset pixels width out runStarts runLengths runIndexes runCount paletteOffsets paletteSize slotKeys slotIndexes slotGenerations generation scratch tileBuffer'
	classVariableNames: ''
	package: 'System-Remote'!

RfbZrleEncoder comment: 'I encode rectangles in ZRLE (RFC 6143, 7.7.6) for one RFB connection, over its one zlib stream (RfbZStream). A rectangle is cut into 64x64 tiles, left to right, top to bottom; each tile is coded the cheapest of five ways, judged from one pass over it that finds its runs and its colours (up to 127, in a small open-addressed table reused from tile to tile), which the coding then uses without looking at the pixels again: solid (one CPIXEL), packed palette (2-16 colours, 1, 2 or 4 bits an index, rows byte-aligned), plain RLE (CPIXEL and run length), palette RLE (2-127 colours, an index byte, run lengths after the long ones), or raw. A run''s length L is L - 1 as bytes of 255 and a last byte below it. Pixels come in the client''s format (RfbPixelFormat convertBgra:count:), CPIXELs cut out of them (cpixelSize, cpixelOffset).

The VM''s zrleTiles primitive (ZrleCoder: runs found 16 bytes at a time with NEON or SSE2) codes a whole rectangle''s tiles in one call; the Smalltalk here (tilesInSmalltalk:width:height:bytesPerPixel:cpixelSize:offset:) is what it does byte for byte, and what runs where it cannot.'!

!RfbZrleEncoder methodsFor: 'encoding'!
encode: clientPixels width: w height: h format: aFormat
	"The bytes of a ZRLE rectangle after its header: a 32-bit length and that much of the zlib stream."
	| data |
	data := zstream deflate: (self tiles: clientPixels width: w height: h format: aFormat).
	^((ByteArray new: 4)
		at: 1 put: ((data size bitShift: -24) bitAnd: 255);
		at: 2 put: ((data size bitShift: -16) bitAnd: 255);
		at: 3 put: ((data size bitShift: -8) bitAnd: 255);
		at: 4 put: (data size bitAnd: 255);
		yourself), data
!
encode: clientPixels width: w height: h format: aFormat on: aStream
	"encode:width:height:format:'s bytes onto aStream."
	| data |
	data := zstream deflate: (self tiles: clientPixels width: w height: h format: aFormat).
	aStream
		nextPut: ((data size bitShift: -24) bitAnd: 255);
		nextPut: ((data size bitShift: -16) bitAnd: 255);
		nextPut: ((data size bitShift: -8) bitAnd: 255);
		nextPut: (data size bitAnd: 255);
		nextPutAll: data
!
tiles: clientPixels width: w height: h format: aFormat
	"The uncompressed tile data of a rectangle."
	| size buffer n |
	size := w * h * aFormat cpixelSize + ((w + 63 // 64) * (h + 63 // 64)).
	buffer := (tileBuffer notNil and: [tileBuffer size >= size])
		ifTrue: [tileBuffer]
		ifFalse: [ByteArray new: size].
	n := self primTiles: clientPixels width: w height: h bytesPerPixel: aFormat bytesPerPixel cpixelSize: aFormat cpixelSize offset: (aFormat cpixelOffset ifNil: [0]) scratch: self scratch into: buffer.
	n isNil ifTrue: [^self tilesInSmalltalk: clientPixels width: w height: h bytesPerPixel: aFormat bytesPerPixel cpixelSize: aFormat cpixelSize offset: (aFormat cpixelOffset ifNil: [0])].
	"a buffer of up to 1 MB is kept for the next rectangle"
	(buffer ~~ tileBuffer and: [size <= 1048576]) ifTrue: [tileBuffer := buffer].
	^buffer copyFrom: 1 to: n
!
tilesInSmalltalk: clientPixels width: w height: h bytesPerPixel: aBpp cpixelSize: aCp offset: anOffset
	"tiles:width:height:format:'s bytes, made here: a CPIXEL aCp bytes of each pixel's aBpp from anOffset."
	pixels := clientPixels.
	width := w.
	bpp := aBpp.
	cp := aCp.
	cpOffset := anOffset.
	out := WriteStream on: (ByteArray new: (w * h * cp // 4 max: 64)).
	0 to: h - 1 by: 64 do: [:ty |
		0 to: w - 1 by: 64 do: [:tx |
			self tileX: tx y: ty width: (64 min: w - tx) height: (64 min: h - ty)]].
	^out contents
! !

!RfbZrleEncoder methodsFor: 'private'!
primTiles: px width: w height: h bytesPerPixel: aBpp cpixelSize: aCp offset: anOffset scratch: aByteArray into: buffer
	"The VM's zrleTiles (ObjectPrimitives>>primZrleTiles): the tiles into buffer, answering their size; nil if it cannot (an older VM, arguments out of range)."
	<primitive: 'zrleTiles'>
	^nil
!
scratch
	"The zrleTiles primitive's working memory: a tile's runs and palette."
	^scratch ifNil: [scratch := ByteArray new: 52224]
!
valueAt: offset
	"The pixel at byte offset (1-based) as an Integer (its bytes as they lie: a key, not a colour)."
	bpp = 4 ifTrue: [^pixels uint32At: offset].
	bpp = 2 ifTrue: [^pixels uint16At: offset].
	^pixels at: offset
!
putCpixelAt: offset
	| o |
	o := offset + cpOffset.
	1 to: cp do: [:k | out nextPut: (pixels at: o + k - 1)]
!
putRunLength: n
	| rest |
	rest := n - 1.
	[rest >= 255] whileTrue: [out nextPut: 255. rest := rest - 255].
	out nextPut: rest
!
tileX: tx y: ty width: tw height: th
	| n tooMany plainCost paletteRleCost rawCost packedCost bits best choice |
	tooMany := self scanX: tx y: ty width: tw height: th.
	n := paletteSize.
	(tooMany not and: [n = 1]) ifTrue: [
		out nextPut: 1.
		^self putCpixelAt: (paletteOffsets at: 1)].
	plainCost := 0.
	paletteRleCost := 0.
	1 to: runCount do: [:i | | length |
		length := runLengths at: i.
		plainCost := plainCost + cp + ((length - 1) // 255) + 1.
		paletteRleCost := paletteRleCost + (length = 1 ifTrue: [1] ifFalse: [2 + ((length - 1) // 255)])].
	rawCost := tw * th * cp.
	best := rawCost.
	choice := #raw.
	plainCost < best ifTrue: [best := plainCost. choice := #plainRle].
	tooMany ifFalse: [
		n <= 16 ifTrue: [
			bits := n = 2 ifTrue: [1] ifFalse: [n <= 4 ifTrue: [2] ifFalse: [4]].
			packedCost := n * cp + (th * ((tw * bits + 7) // 8)).
			packedCost < best ifTrue: [best := packedCost. choice := #packed]].
		n * cp + paletteRleCost < best ifTrue: [best := n * cp + paletteRleCost. choice := #paletteRle]].
	choice == #raw ifTrue: [^self rawX: tx y: ty width: tw height: th].
	choice == #plainRle ifTrue: [
		out nextPut: 128.
		^1 to: runCount do: [:i |
			self putCpixelAt: (runStarts at: i).
			self putRunLength: (runLengths at: i)]].
	out nextPut: (choice == #packed ifTrue: [n] ifFalse: [128 + n]).
	1 to: n do: [:i | self putCpixelAt: (paletteOffsets at: i)].
	choice == #packed ifTrue: [^self packedWidth: tw bits: bits].
	1 to: runCount do: [:i | | index length |
		index := runIndexes at: i.
		length := runLengths at: i.
		length = 1
			ifTrue: [out nextPut: index]
			ifFalse: [
				out nextPut: index + 128.
				self putRunLength: length]]
!
scanX: tx y: ty width: tw height: th
	"One pass over a tile in raster order (across its rows): its runs of equal pixels (runStarts, runLengths, runCount) and its palette (up to 127 colours, indexed in the order they first start a run: paletteOffsets, paletteSize, and each run's index, runIndexes). Answer whether it has more colours than that."
	| prev run count tooMany |
	self newPalette.
	count := 0.
	run := 0.
	prev := nil.
	tooMany := false.
	0 to: th - 1 do: [:y | | o stop |
		o := (ty + y) * width + tx * bpp + 1.
		stop := o + (tw * bpp).
		[o < stop] whileTrue: [| v |
			v := bpp = 4 ifTrue: [pixels uint32At: o] ifFalse: [self valueAt: o].
			v = prev
				ifTrue: [run := run + 1]
				ifFalse: [
					count > 0 ifTrue: [runLengths at: count put: run].
					count := count + 1.
					runStarts at: count put: o.
					prev := v.
					run := 1.
					tooMany ifFalse: [| index |
						index := self paletteIndexOf: v at: o.
						index isNil ifTrue: [tooMany := true] ifFalse: [runIndexes at: count put: index]]].
			o := o + bpp]].
	runLengths at: count put: run.
	runCount := count.
	^tooMany
!
newPalette
	"An empty palette: the slots of an earlier one are stale by their generation."
	paletteSize := 0.
	generation := generation + 1.
	generation > 16r3FFFFFFF ifTrue: [
		slotGenerations atAllPut: 0.
		generation := 1]
!
paletteIndexOf: v at: offset
	"v's index in the palette (0-based), added as the next one (first seen at offset) if it is new and there is room; nil if there is none. An open-addressed table of 256 slots."
	| h |
	h := ((v bitXor: (v bitShift: -7)) bitXor: (v bitShift: -17)) bitAnd: 255.
	[(slotGenerations at: h + 1) = generation] whileTrue: [
		(slotKeys at: h + 1) = v ifTrue: [^slotIndexes at: h + 1].
		h := h + 1 bitAnd: 255].
	paletteSize >= 127 ifTrue: [^nil].
	slotGenerations at: h + 1 put: generation.
	slotKeys at: h + 1 put: v.
	slotIndexes at: h + 1 put: paletteSize.
	paletteSize := paletteSize + 1.
	paletteOffsets at: paletteSize put: offset.
	^paletteSize - 1
!
rawX: tx y: ty width: tw height: th
	out nextPut: 0.
	(bpp = 4 and: [cp = 3 and: [cpOffset = 0]]) ifTrue: [
		"the low three bytes of each pixel: PixelPack's vector primitive"
		^out nextPutAll: (PixelPack pack: pixels stride: width * 4 x: tx y: ty width: tw height: th swap: false into: (ByteArray new: tw * th * 3))].
	0 to: th - 1 do: [:y | | row |
		row := (ty + y) * width + tx * bpp + 1.
		cp = bpp
			ifTrue: [out nextPutAll: (pixels copyFrom: row to: row + (tw * bpp) - 1)]
			ifFalse: [0 to: tw - 1 do: [:x | self putCpixelAt: row + (x * bpp)]]]
!
packedWidth: tw bits: bits
	"The runs' palette indices, bits each, packed into bytes, each row of the tile byte-aligned."
	| acc count x |
	acc := 0.
	count := 0.
	x := 0.
	1 to: runCount do: [:i | | index |
		index := runIndexes at: i.
		(runLengths at: i) timesRepeat: [
			acc := (acc bitShift: bits) + index.
			count := count + bits.
			count = 8 ifTrue: [out nextPut: acc. acc := 0. count := 0].
			x := x + 1.
			x = tw ifTrue: [
				count > 0 ifTrue: [out nextPut: (acc bitShift: 8 - count). acc := 0. count := 0].
				x := 0]]]
! !

!RfbZrleEncoder methodsFor: 'initialization'!
initialize
	zstream := RfbZStream new.
	runStarts := Array new: 4096.
	runLengths := Array new: 4096.
	runIndexes := Array new: 4096.
	paletteOffsets := Array new: 127.
	slotKeys := Array new: 256.
	slotIndexes := Array new: 256.
	slotGenerations := Array new: 256 withAll: 0.
	generation := 0
! !

!RfbZrleEncoder methodsFor: 'accessing'!
zstream
	^zstream
! !
