Object subclass: #RfbZrleEncoder
	instanceVariableNames: 'zstream bpp cp cpOffset pixels width out'
	classVariableNames: ''
	package: 'System-Remote'!

RfbZrleEncoder comment: 'I encode rectangles in ZRLE (RFC 6143, 7.7.6) for one RFB connection, over its one zlib stream (RfbZStream). A rectangle is cut into 64x64 tiles, left to right, top to bottom; each tile is coded the cheapest of five ways, judged from one pass over it that counts its colours (up to 127) and its runs: solid (one CPIXEL), packed palette (2-16 colours, 1, 2 or 4 bits an index, rows byte-aligned), plain RLE (CPIXEL and run length), palette RLE (2-127 colours, an index byte, run lengths after the long ones), or raw. A run''s length L is L - 1 as bytes of 255 and a last byte below it. Pixels come in the client''s format (RfbPixelFormat convertBgra:count:), CPIXELs cut out of them (cpixelSize, cpixelOffset).'!

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
tiles: clientPixels width: w height: h format: aFormat
	"The uncompressed tile data of a rectangle."
	pixels := clientPixels.
	width := w.
	bpp := aFormat bytesPerPixel.
	cp := aFormat cpixelSize.
	cpOffset := aFormat cpixelOffset ifNil: [0].
	out := WriteStream on: (ByteArray new: (w * h * cp // 4 max: 64)).
	0 to: h - 1 by: 64 do: [:ty |
		0 to: w - 1 by: 64 do: [:tx |
			self tileX: tx y: ty width: (64 min: w - tx) height: (64 min: h - ty)]].
	^out contents
! !

!RfbZrleEncoder methodsFor: 'private'!
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
	| palette offsets prev run plainCost paletteRleCost tooMany n rawCost packedCost bits best choice account |
	palette := Dictionary new.
	offsets := OrderedCollection new.
	prev := nil.
	run := 0.
	plainCost := 0.
	paletteRleCost := 0.
	tooMany := false.
	account := [:length |
		plainCost := plainCost + cp + ((length - 1) // 255) + 1.
		paletteRleCost := paletteRleCost + (length = 1 ifTrue: [1] ifFalse: [2 + ((length - 1) // 255)])].
	0 to: th - 1 do: [:y | | row |
		row := (ty + y) * width + tx * bpp + 1.
		0 to: tw - 1 do: [:x | | o v |
			o := row + (x * bpp).
			v := self valueAt: o.
			v = prev
				ifTrue: [run := run + 1]
				ifFalse: [
					prev isNil ifFalse: [account value: run].
					prev := v.
					run := 1.
					(tooMany or: [palette includesKey: v]) ifFalse: [
						palette size >= 127
							ifTrue: [tooMany := true]
							ifFalse: [palette at: v put: palette size. offsets add: o]]]]].
	account value: run.
	n := palette size.
	(tooMany not and: [n = 1]) ifTrue: [
		out nextPut: 1.
		^self putCpixelAt: offsets first].
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
	choice == #plainRle ifTrue: [^self plainRleX: tx y: ty width: tw height: th].
	out nextPut: (choice == #packed ifTrue: [n] ifFalse: [128 + n]).
	offsets do: [:o | self putCpixelAt: o].
	choice == #packed ifTrue: [^self packedX: tx y: ty width: tw height: th palette: palette bits: bits].
	self paletteRleX: tx y: ty width: tw height: th palette: palette
!
rawX: tx y: ty width: tw height: th
	out nextPut: 0.
	0 to: th - 1 do: [:y | | row |
		row := (ty + y) * width + tx * bpp + 1.
		cp = bpp
			ifTrue: [out nextPutAll: (pixels copyFrom: row to: row + (tw * bpp) - 1)]
			ifFalse: [0 to: tw - 1 do: [:x | self putCpixelAt: row + (x * bpp)]]]
!
packedX: tx y: ty width: tw height: th palette: palette bits: bits
	0 to: th - 1 do: [:y | | row acc count |
		row := (ty + y) * width + tx * bpp + 1.
		acc := 0.
		count := 0.
		0 to: tw - 1 do: [:x |
			acc := (acc bitShift: bits) + (palette at: (self valueAt: row + (x * bpp))).
			count := count + bits.
			count = 8 ifTrue: [out nextPut: acc. acc := 0. count := 0]].
		count > 0 ifTrue: [out nextPut: (acc bitShift: 8 - count)]]
!
runsX: tx y: ty width: tw height: th do: aBlock
	"aBlock value: offset value: length for each run of equal pixels, in raster order across the tile's rows."
	| prev start run |
	prev := nil.
	run := 0.
	0 to: th - 1 do: [:y | | row |
		row := (ty + y) * width + tx * bpp + 1.
		0 to: tw - 1 do: [:x | | o v |
			o := row + (x * bpp).
			v := self valueAt: o.
			v = prev
				ifTrue: [run := run + 1]
				ifFalse: [
					prev isNil ifFalse: [aBlock value: start value: run].
					prev := v.
					start := o.
					run := 1]]].
	aBlock value: start value: run
!
plainRleX: tx y: ty width: tw height: th
	out nextPut: 128.
	self runsX: tx y: ty width: tw height: th do: [:o :length |
		self putCpixelAt: o.
		self putRunLength: length]
!
paletteRleX: tx y: ty width: tw height: th palette: palette
	self runsX: tx y: ty width: tw height: th do: [:o :length | | index |
		index := palette at: (self valueAt: o).
		length = 1
			ifTrue: [out nextPut: index]
			ifFalse: [
				out nextPut: index + 128.
				self putRunLength: length]]
! !

!RfbZrleEncoder methodsFor: 'initialization'!
initialize
	zstream := RfbZStream new
! !

!RfbZrleEncoder methodsFor: 'accessing'!
zstream
	^zstream
! !
