Object subclass: #PNGWriter
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Graphics-Canvas'!

PNGWriter comment: 'I encode 8-bit RGBA images as PNG: IHDR, PLTE and tRNS for indexed color, one IDAT with a zlib stream (ZLib compress:), IEND; every chunk with its CRC-32. The color type is the smallest that holds the pixels exactly: indexed (type 3, filter None) when there are at most 256 distinct pixels, else RGB (type 2) when every pixel is opaque, else RGBA (type 6); RGB and RGBA rows each take the filter (None, Sub, Up, Average, Paeth) with the smallest sum of absolute differences. Pixels are written as given (pass straight alpha; opaque renders need no conversion). PNGReader reads them back.

	PNGWriter write: aForm to: ''/tmp/shot.png''
	PNGWriter bytesFor: rgbaByteArray width: w height: h'!

!PNGWriter class methodsFor: 'encoding'!
bytesFor: rgba width: w height: h
	"Answer the PNG file bytes of an RGBA ByteArray (rows top to bottom)."
	| palette opaque |
	palette := self paletteOf: rgba limit: 256.
	palette isNil ifFalse: [^self indexedBytesFor: rgba width: w height: h palette: palette].
	opaque := true.
	4 to: rgba size by: 4 do: [:i | (rgba at: i) = 255 ifFalse: [opaque := false]].
	^self
		pngWidth: w
		height: h
		colorType: (opaque ifTrue: [2] ifFalse: [6])
		chunks: (Array with: 'IDAT' -> (ZLib compress: (self filtered: rgba width: w height: h channels: (opaque ifTrue: [3] ifFalse: [4]))))
!
bytesForForm: aForm
	^self bytesFor: aForm asByteArray width: aForm width height: aForm height
!
write: aFormOrSurface to: aPath
	"Write a Form (or a Surface, read back) as a PNG file."
	| bytes |
	bytes := (aFormOrSurface isKindOf: Form)
		ifTrue: [self bytesForForm: aFormOrSurface]
		ifFalse: [self bytesFor: aFormOrSurface readbackBytes width: aFormOrSurface width height: aFormOrSurface height].
	File writeBytes: bytes to: aPath
!
paletteOf: rgba limit: max
	"A Dictionary from each distinct pixel (a little-endian RGBA word) to its index, in order of first use; nil if there are more than max."
	| map previous word |
	map := Dictionary new.
	previous := nil.
	1 to: rgba size by: 4 do: [:i |
		word := rgba uint32At: i.
		word = previous ifFalse: [
			(map includesKey: word) ifFalse: [
				map size = max ifTrue: [^nil].
				map at: word put: map size].
			previous := word]].
	^map
!
indexedBytesFor: rgba width: w height: h palette: palette
	"Color type 3: rows of one index byte per pixel, filter None; PLTE, and tRNS when a color is not opaque."
	| raw p previous index plte trns opaque |
	raw := ByteArray new: (w + 1) * h.
	p := 1.
	previous := nil.
	index := 0.
	0 to: h - 1 do: [:y |
		p := p + 1.
		y * w * 4 + 1 to: (y + 1) * w * 4 by: 4 do: [:i | | word |
			word := rgba uint32At: i.
			word = previous ifFalse: [index := palette at: word. previous := word].
			raw at: p put: index.
			p := p + 1]].
	plte := ByteArray new: palette size * 3.
	trns := ByteArray new: palette size.
	opaque := true.
	palette keysAndValuesDo: [:word :i |
		plte at: i * 3 + 1 put: (word bitAnd: 255).
		plte at: i * 3 + 2 put: ((word bitShift: -8) bitAnd: 255).
		plte at: i * 3 + 3 put: ((word bitShift: -16) bitAnd: 255).
		trns at: i + 1 put: ((word bitShift: -24) bitAnd: 255).
		(trns at: i + 1) = 255 ifFalse: [opaque := false]].
	^self
		pngWidth: w
		height: h
		colorType: 3
		chunks: (opaque
			ifTrue: [Array with: 'PLTE' -> plte with: 'IDAT' -> (ZLib compress: raw)]
			ifFalse: [Array with: 'PLTE' -> plte with: 'tRNS' -> trns with: 'IDAT' -> (ZLib compress: raw)])
!
filtered: rgba width: w height: h channels: n
	"Rows of n channels (RGB or RGBA) each after its filter type byte, with the filter whose output has the smallest sum of absolute (signed byte) values."
	| stride raw cur prior sums rowStart best |
	stride := w * n.
	raw := ByteArray new: (stride + 1) * h.
	cur := ByteArray new: stride.
	prior := ByteArray new: stride.
	sums := Array new: 5.
	0 to: h - 1 do: [:y | | s k swap |
		n = 4
			ifTrue: [cur replaceFrom: 1 to: stride with: rgba startingAt: y * stride + 1]
			ifFalse: [
				s := y * w * 4.
				k := 0.
				w timesRepeat: [
					cur at: k + 1 put: (rgba at: s + 1).
					cur at: k + 2 put: (rgba at: s + 2).
					cur at: k + 3 put: (rgba at: s + 3).
					k := k + 3.
					s := s + 4]].
		sums atAllPut: 0.
		1 to: stride do: [:i | | x a b c |
			x := cur at: i.
			a := i > n ifTrue: [cur at: i - n] ifFalse: [0].
			b := prior at: i.
			c := i > n ifTrue: [prior at: i - n] ifFalse: [0].
			sums at: 1 put: (sums at: 1) + (self signedSize: x).
			sums at: 2 put: (sums at: 2) + (self signedSize: x - a).
			sums at: 3 put: (sums at: 3) + (self signedSize: x - b).
			sums at: 4 put: (sums at: 4) + (self signedSize: x - (a + b // 2)).
			sums at: 5 put: (sums at: 5) + (self signedSize: x - (self paeth: a with: b with: c))].
		best := 1.
		2 to: 5 do: [:t | (sums at: t) < (sums at: best) ifTrue: [best := t]].
		rowStart := y * (stride + 1) + 1.
		raw at: rowStart put: best - 1.
		1 to: stride do: [:i | | x a b c |
			x := cur at: i.
			best = 1 ifFalse: [
				a := i > n ifTrue: [cur at: i - n] ifFalse: [0].
				b := prior at: i.
				best = 2 ifTrue: [x := x - a].
				best = 3 ifTrue: [x := x - b].
				best = 4 ifTrue: [x := x - (a + b // 2)].
				best = 5 ifTrue: [
					c := i > n ifTrue: [prior at: i - n] ifFalse: [0].
					x := x - (self paeth: a with: b with: c)]].
			raw at: rowStart + i put: (x bitAnd: 255)].
		swap := prior.
		prior := cur.
		cur := swap].
	^raw
!
signedSize: aDifference
	"The absolute value of a byte difference read as a signed byte."
	| v |
	v := aDifference bitAnd: 255.
	^v < 128 ifTrue: [v] ifFalse: [256 - v]
!
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
pngWidth: w height: h colorType: anInteger chunks: anArray
	"The file: signature, IHDR (bit depth 8), the chunks (type -> data, in order), IEND."
	| header out p |
	header := self headerWidth: w height: h.
	header at: 10 put: anInteger.
	out := ByteArray new: 8 + 25 + (anArray inject: 0 into: [:sum :each | sum + each value size + 12]) + 12.
	#(137 80 78 71 13 10 26 10) doWithIndex: [:b :i | out at: i put: b].
	p := self chunk: 'IHDR' data: header into: out at: 9.
	anArray do: [:each | p := self chunk: each key data: each value into: out at: p].
	self chunk: 'IEND' data: ByteArray new into: out at: p.
	^out
!
headerWidth: w height: h
	| d |
	d := ByteArray new: 13.
	self putUint32: w in: d at: 1.
	self putUint32: h in: d at: 5.
	d at: 9 put: 8.
	d at: 10 put: 6.
	^d
!
chunk: type data: data into: out at: start
	"Write a chunk at start; answer the index after it."
	| p crc |
	self putUint32: data size in: out at: start.
	p := start + 4.
	1 to: 4 do: [:i | out at: p + i - 1 put: (type at: i) value].
	out replaceFrom: p + 4 to: p + 3 + data size with: data startingAt: 1.
	crc := self crc32Of: out from: p to: p + 3 + data size.
	self putUint32: crc in: out at: p + 4 + data size.
	^p + 8 + data size
!
storedBytesFor: rgba width: w height: h
	"The PNG I wrote before I compressed: RGBA, filter None, stored deflate blocks (for tests of images that big)."
	| raw rowBytes |
	rowBytes := w * 4.
	raw := ByteArray new: (rowBytes + 1) * h.
	0 to: h - 1 do: [:y |
		raw replaceFrom: y * (rowBytes + 1) + 2 to: y + 1 * (rowBytes + 1) with: rgba startingAt: y * rowBytes + 1].
	^self pngWidth: w height: h colorType: 6 chunks: (Array with: 'IDAT' -> (self zlibStored: raw))
!
zlibStored: raw
	"A zlib stream of stored deflate blocks (at most 65535 bytes each)."
	| blocks out p n remaining src |
	blocks := (raw size + 65534) // 65535 max: 1.
	out := ByteArray new: 2 + (blocks * 5) + raw size + 4.
	out at: 1 put: 16r78.
	out at: 2 put: 16r01.
	p := 3.
	src := 1.
	remaining := raw size.
	blocks timesRepeat: [
		n := remaining min: 65535.
		out at: p put: (remaining <= 65535 ifTrue: [1] ifFalse: [0]).
		out at: p + 1 put: (n bitAnd: 255).
		out at: p + 2 put: (n bitShift: -8).
		out at: p + 3 put: ((n bitXor: 16rFFFF) bitAnd: 255).
		out at: p + 4 put: ((n bitXor: 16rFFFF) bitShift: -8).
		out replaceFrom: p + 5 to: p + 4 + n with: raw startingAt: src.
		p := p + 5 + n.
		src := src + n.
		remaining := remaining - n].
	self putUint32: (self adler32Of: raw) in: out at: p.
	^out
!
putUint32: anInteger in: bytes at: index
	"Big-endian."
	bytes at: index put: ((anInteger bitShift: -24) bitAnd: 255).
	bytes at: index + 1 put: ((anInteger bitShift: -16) bitAnd: 255).
	bytes at: index + 2 put: ((anInteger bitShift: -8) bitAnd: 255).
	bytes at: index + 3 put: (anInteger bitAnd: 255)
! !

!PNGWriter class methodsFor: 'checksums'!
crc32Of: bytes
	^self crc32Of: bytes from: 1 to: bytes size
!
crc32Of: bytes from: start to: stop
	^Crc32 checksumOf: bytes from: start to: stop
!
adler32Of: bytes
	^ZLib adler32Of: bytes
! !
