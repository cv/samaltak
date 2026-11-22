Object subclass: #PNGReader
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Graphics-Canvas'!

PNGReader comment: 'I decode PNG files of bit depth 8, not interlaced, into Forms: grayscale (0), RGB (2), indexed (3, with tRNS), gray with alpha (4) and RGBA (6); every filter type; chunk CRCs checked. Pixels come back as stored (no premultiplication), so a Form written by PNGWriter reads back identical. Anything else is an Error.

	PNGReader formFrom: pngBytes
	PNGReader formFromFile: ''/tmp/shot.png'''!

!PNGReader class methodsFor: 'decoding'!
formFromFile: aPath
	^self formFrom: (File readBytes: aPath)
!
formFrom: bytes
	| p w h depth type interlace palette alpha idat n channels raw |
	(bytes size >= 8 and: [(bytes copyFrom: 1 to: 8) = #[137 80 78 71 13 10 26 10]]) ifFalse: [^self error: 'not a PNG file'].
	idat := WriteStream on: (ByteArray new: bytes size).
	p := 9.
	[p + 11 <= bytes size] whileTrue: [ | t body |
		n := self uint32In: bytes at: p.
		p + 11 + n > bytes size ifTrue: [^self error: 'PNG chunk cut short'].
		t := (bytes copyFrom: p + 4 to: p + 7) asString.
		(self uint32In: bytes at: p + 8 + n) = (PNGWriter crc32Of: bytes from: p + 4 to: p + 7 + n) ifFalse: [^self error: 'PNG chunk CRC mismatch: ', t].
		body := bytes copyFrom: p + 8 to: p + 7 + n.
		t = 'IHDR' ifTrue: [
			w := self uint32In: body at: 1.
			h := self uint32In: body at: 5.
			depth := body at: 9.
			type := body at: 10.
			interlace := body at: 13].
		t = 'PLTE' ifTrue: [palette := body].
		t = 'tRNS' ifTrue: [alpha := body].
		t = 'IDAT' ifTrue: [idat nextPutAll: body].
		p := p + 12 + n].
	w isNil ifTrue: [^self error: 'PNG without IHDR'].
	(depth = 8 and: [interlace = 0]) ifFalse: [^self error: 'unsupported PNG: bit depth ', depth printString, ', interlace ', interlace printString].
	channels := #(1 nil 3 1 2 nil 4) at: type + 1 ifAbsent: [nil].
	channels isNil ifTrue: [^self error: 'unsupported PNG color type ', type printString].
	(type = 3 and: [palette isNil]) ifTrue: [^self error: 'indexed PNG without PLTE'].
	raw := ZLib decompress: idat contents.
	raw size = ((w * channels + 1) * h) ifFalse: [^self error: 'PNG image data has the wrong size'].
	^self formFrom: raw width: w height: h type: type channels: channels palette: palette alpha: alpha
!
formFrom: raw width: w height: h type: type channels: n palette: palette alpha: alpha
	"Undo each row's filter, then pack the pixels into words (red in the low byte)."
	| stride cur prior bits swap |
	stride := w * n.
	cur := ByteArray new: stride.
	prior := ByteArray new: stride.
	bits := Bitmap new: w * h.
	0 to: h - 1 do: [:y | | rowStart filter |
		rowStart := y * (stride + 1) + 1.
		filter := raw at: rowStart.
		filter > 4 ifTrue: [^self error: 'invalid PNG filter type ', filter printString].
		1 to: stride do: [:i | | x a b c |
			x := raw at: rowStart + i.
			filter = 0 ifFalse: [
				a := i > n ifTrue: [cur at: i - n] ifFalse: [0].
				b := prior at: i.
				filter = 1 ifTrue: [x := x + a].
				filter = 2 ifTrue: [x := x + b].
				filter = 3 ifTrue: [x := x + (a + b // 2)].
				filter = 4 ifTrue: [
					c := i > n ifTrue: [prior at: i - n] ifFalse: [0].
					x := x + (PNGWriter paeth: a with: b with: c)]].
			cur at: i put: (x bitAnd: 255)].
		0 to: w - 1 do: [:x | | k r g b a |
			k := x * n.
			type = 3
				ifTrue: [ | index |
					index := cur at: k + 1.
					index * 3 + 3 > palette size ifTrue: [^self error: 'PNG palette index out of range'].
					r := palette at: index * 3 + 1.
					g := palette at: index * 3 + 2.
					b := palette at: index * 3 + 3.
					a := (alpha notNil and: [index < alpha size]) ifTrue: [alpha at: index + 1] ifFalse: [255]]
				ifFalse: [
					n <= 2
						ifTrue: [r := g := b := cur at: k + 1. a := n = 2 ifTrue: [cur at: k + 2] ifFalse: [255]]
						ifFalse: [
							r := cur at: k + 1.
							g := cur at: k + 2.
							b := cur at: k + 3.
							a := n = 4 ifTrue: [cur at: k + 4] ifFalse: [255]]].
			bits at: y * w + x + 1 put: r + (g bitShift: 8) + (b bitShift: 16) + (a bitShift: 24)].
		swap := prior.
		prior := cur.
		cur := swap].
	^Form width: w height: h bits: bits
!
uint32In: bytes at: index
	"Big-endian."
	^((((bytes at: index) bitShift: 24) + ((bytes at: index + 1) bitShift: 16)) + ((bytes at: index + 2) bitShift: 8)) + (bytes at: index + 3)
! !
