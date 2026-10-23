Object subclass: #PNGWriter
	instanceVariableNames: ''
	classVariableNames: 'CRCTable'
	package: 'Graphics-Canvas'!

PNGWriter comment: 'I encode 8-bit RGBA images as PNG: IHDR, one IDAT with a zlib stream of stored (uncompressed) deflate blocks and an Adler-32 checksum, IEND; every chunk with its CRC-32. Pixels are written as given (pass straight alpha; opaque renders need no conversion).

	PNGWriter write: aForm to: ''/tmp/shot.png''
	PNGWriter bytesFor: rgbaByteArray width: w height: h'!

!PNGWriter class methodsFor: 'encoding'!
bytesFor: rgba width: w height: h
	"Answer the PNG file bytes of an RGBA ByteArray (rows top to bottom)."
	| raw rowBytes zlib out p |
	rowBytes := w * 4.
	raw := ByteArray new: (rowBytes + 1) * h.
	0 to: h - 1 do: [:y |
		raw replaceFrom: y * (rowBytes + 1) + 2 to: y + 1 * (rowBytes + 1) with: rgba startingAt: y * rowBytes + 1].
	zlib := self zlibStored: raw.
	out := ByteArray new: 8 + 25 + (zlib size + 12) + 12.
	#(137 80 78 71 13 10 26 10) doWithIndex: [:b :i | out at: i put: b].
	p := self chunk: 'IHDR' data: (self headerWidth: w height: h) into: out at: 9.
	p := self chunk: 'IDAT' data: zlib into: out at: p.
	self chunk: 'IEND' data: ByteArray new into: out at: p.
	^out
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
	| table crc |
	table := self crcTable.
	crc := 16rFFFFFFFF.
	start to: stop do: [:i |
		crc := (table at: ((crc bitXor: (bytes at: i)) bitAnd: 255) + 1) bitXor: (crc bitShift: -8)].
	^crc bitXor: 16rFFFFFFFF
!
crcTable
	^CRCTable ifNil: [
		CRCTable := (0 to: 255) asArray collect: [:n |
			| c |
			c := n.
			8 timesRepeat: [
				c := (c bitAnd: 1) = 1
					ifTrue: [16rEDB88320 bitXor: (c bitShift: -1)]
					ifFalse: [c bitShift: -1]].
			c]]
!
adler32Of: bytes
	"Sums are reduced modulo 65521 every 5552 bytes (they cannot overflow SmallIntegers anyway)."
	| a b i n stop |
	a := 1.
	b := 0.
	i := 1.
	n := bytes size.
	[i <= n] whileTrue: [
		stop := i + 5551 min: n.
		i to: stop do: [:k |
			a := a + (bytes at: k).
			b := b + a].
		a := a \\ 65521.
		b := b \\ 65521.
		i := stop + 1].
	^(b bitShift: 16) + a
! !
