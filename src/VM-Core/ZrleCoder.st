VMModule subclass: #ZrleCoder
	instanceVariableNames: 'search packer'
	classVariableNames: ''
	package: 'VM-Core'!

ZrleCoder comment: 'The tiles of a ZRLE rectangle (RFC 6143, 7.7.6) for the zrleTiles primitive (ObjectPrimitives>>primZrleTiles), byte for byte what RfbZrleEncoder''s Smalltalk writes (tilesInSmalltalk:width:height:bytesPerPixel:cpixelSize:offset:): the rectangle cut into 64x64 tiles, left to right, top to bottom; each tile scanned once in raster order for its runs and its palette (up to 127 colours, in the order they first start a run), then coded the cheapest of solid, packed palette, plain RLE, palette RLE and raw by the encoder''s rule (ties go to the earlier of raw, plain RLE, packed, palette RLE). A pixel is 1, 2 or 4 bytes, read little-endian as a key (its bytes as they lie); its CPIXEL is cp of its bytes from off (cp = bpp and off = 0, or 3 bytes of a 4-byte pixel from 0 or 1). A run goes on while each pixel''s bytes are the previous one''s: search''s mismatchOf: (ByteBlocks: NEON or SSE2, 16 bytes at a time) on the row against itself one pixel later. Raw tiles of 4-byte pixels as 3-byte CPIXELs are packer''s (PackRows: NEON or SSE2).

The scratch s (uint32 words, scratchWords of them) holds a tile''s runs: lengths at 0, keys at 4096, palette indices at 8192; the palette''s keys at 12288 and their slots at 12416; the palette''s open-addressed table of 256 slots, keys at 12544 and index + 1 (0: empty) at 12800, emptied before the first tile and after each.'!

!ZrleCoder class methodsFor: 'declaring'!
declarations
	^#((search ByteSearch) (packer PixelPacker))
! !

!ZrleCoder methodsFor: 'coding'!
scratchWords
	^13056
!
tiles: px width: w height: h bpp: bpp cpixel: cp offset: off scratch: s into: out
	"The ZRLE tiles of the w x h pixels at px (rows w * bpp bytes) into out; answer the bytes written: at most w * h * cp and a byte a tile. s's palette table is emptied first."
	<function>
	<var: #px type: 'uint8_t *'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #bpp type: 'int64_t'>
	<var: #cp type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<var: #s type: 'uint32_t *'>
	<var: #out type: 'uint8_t *'>
	<returns: 'int64_t'>
	| ty tx tw th o |
	0 to: 255 do: [:j | s at: 12800 + j put: 0 asUInt32].
	o := 0.
	ty := 0.
	[ty < h] whileTrue: [
		th := h - ty min: 64.
		tx := 0.
		[tx < w] whileTrue: [
			tw := w - tx min: 64.
			o := self tile: px + ((ty * w + tx) * bpp) stride: w * bpp width: tw height: th bpp: bpp cpixel: cp offset: off scratch: s into: out at: o.
			tx := tx + 64].
		ty := ty + 64].
	^o
!
tile: p stride: stride width: tw height: th bpp: bpp cpixel: cp offset: off scratch: s into: out at: start
	"One tile at p into out from start; answer where it ends."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #stride type: 'int64_t'>
	<var: #tw type: 'int64_t'>
	<var: #th type: 'int64_t'>
	<var: #bpp type: 'int64_t'>
	<var: #cp type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<var: #s type: 'uint32_t *'>
	<var: #out type: 'uint8_t *'>
	<var: #start type: 'int64_t'>
	<returns: 'int64_t'>
	| r count n tooMany o i len plain prle best choice bits packed index |
	r := self scan: p stride: stride width: tw height: th bpp: bpp scratch: s.
	count := r >> 8.
	tooMany := (r >> 7) bitAnd: 1.
	n := r bitAnd: 127.
	o := start.
	(tooMany = 0 and: [n = 1]) ifTrue: [
		out at: o put: 1.
		^self cpixel: (s at: 12288) cpixel: cp offset: off into: out at: o + 1].
	plain := 0.
	prle := 0.
	i := 0.
	[i < count] whileTrue: [
		len := (s at: i) asInt64.
		plain := plain + cp + ((len - 1) quo: 255) + 1.
		len = 1
			ifTrue: [prle := prle + 1]
			ifFalse: [prle := prle + 2 + ((len - 1) quo: 255)].
		i := i + 1].
	best := tw * th * cp.
	choice := 0.
	plain < best ifTrue: [best := plain. choice := 1].
	bits := 0.
	tooMany = 0 ifTrue: [
		n <= 16 ifTrue: [
			bits := 4.
			n <= 4 ifTrue: [bits := 2].
			n = 2 ifTrue: [bits := 1].
			packed := n * cp + (th * ((tw * bits + 7) quo: 8)).
			packed < best ifTrue: [best := packed. choice := 2]].
		n * cp + prle < best ifTrue: [best := n * cp + prle. choice := 3]].
	choice = 0 ifTrue: [^self raw: p stride: stride width: tw height: th bpp: bpp cpixel: cp offset: off into: out at: o].
	choice = 1 ifTrue: [
		out at: o put: 128.
		o := o + 1.
		i := 0.
		[i < count] whileTrue: [
			o := self cpixel: (s at: 4096 + i) cpixel: cp offset: off into: out at: o.
			o := self runLength: (s at: i) asInt64 into: out at: o.
			i := i + 1].
		^o].
	choice = 2
		ifTrue: [out at: o put: n asUInt8]
		ifFalse: [out at: o put: (128 + n) asUInt8].
	o := o + 1.
	i := 0.
	[i < n] whileTrue: [
		o := self cpixel: (s at: 12288 + i) cpixel: cp offset: off into: out at: o.
		i := i + 1].
	choice = 2 ifTrue: [^self packed: s count: count width: tw bits: bits into: out at: o].
	i := 0.
	[i < count] whileTrue: [
		index := (s at: 8192 + i) asInt64.
		len := (s at: i) asInt64.
		len = 1
			ifTrue: [
				out at: o put: index asUInt8.
				o := o + 1]
			ifFalse: [
				out at: o put: (index + 128) asUInt8.
				o := self runLength: len into: out at: o + 1].
		i := i + 1].
	^o
!
scan: p stride: stride width: tw height: th bpp: bpp scratch: s
	"The tile's runs (lengths, keys and, while the palette has room, palette indices) and palette into s, in raster order across its rows; answer the runs' count << 8, 128 if there are more than 127 colours (the palette then has 127 and later runs no indices), and the palette's size."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #stride type: 'int64_t'>
	<var: #tw type: 'int64_t'>
	<var: #th type: 'int64_t'>
	<var: #bpp type: 'int64_t'>
	<var: #s type: 'uint32_t *'>
	<var: #row type: 'uint8_t *'>
	<var: #v type: 'uint32_t'>
	<var: #prev type: 'uint32_t'>
	<returns: 'int64_t'>
	| count n tooMany y x row v prev e i m k |
	count := 0.
	n := 0.
	tooMany := 0.
	prev := 0 asUInt32.
	y := 0.
	[y < th] whileTrue: [
		row := p + (y * stride).
		x := 0.
		[x < tw] whileTrue: [
			v := self key: row + (x * bpp) bpp: bpp.
			(count > 0 and: [v = prev])
				ifTrue: [
					"the run goes on: to the first pixel of the row that is not the one before it"
					e := tw.
					x + 1 < tw ifTrue: [
						m := (tw - 1) * bpp.
						i := search mismatchOf: row + bpp with: row from: x * bpp size: m.
						i < m ifTrue: [e := (i quo: bpp) + 1]].
					s at: count - 1 put: (s at: count - 1) + (e - x) asUInt32.
					x := e]
				ifFalse: [
					s at: count put: 1 asUInt32.
					s at: 4096 + count put: v.
					tooMany = 0 ifTrue: [
						k := self indexOf: v scratch: s size: n.
						k < 0
							ifTrue: [tooMany := 1]
							ifFalse: [
								k = n ifTrue: [n := n + 1].
								s at: 8192 + count put: k asUInt32]].
					count := count + 1.
					prev := v.
					x := x + 1]].
		y := y + 1].
	i := 0.
	[i < n] whileTrue: [
		s at: 12800 + (s at: 12416 + i) asInt64 put: 0 asUInt32.
		i := i + 1].
	^((count << 8) bitOr: (tooMany << 7)) bitOr: n
!
key: q bpp: bpp
	"The pixel at q, its bpp bytes little-endian."
	<var: #q type: 'uint8_t *'>
	<var: #bpp type: 'int64_t'>
	<returns: 'uint32_t'>
	bpp = 4 ifTrue: [^((((q at: 0) asUInt64 bitOr: ((q at: 1) asUInt64 << 8)) bitOr: ((q at: 2) asUInt64 << 16)) bitOr: ((q at: 3) asUInt64 << 24)) asUInt32].
	bpp = 2 ifTrue: [^((q at: 0) asUInt64 bitOr: ((q at: 1) asUInt64 << 8)) asUInt32].
	^(q at: 0) asUInt32
!
indexOf: v scratch: s size: n
	"v's palette index (0-based): n if it is new, added; -1 if it is new and the palette (n colours) is full."
	<var: #v type: 'uint32_t'>
	<var: #s type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| h |
	h := (((v bitXor: (v >> 7)) bitXor: (v >> 17)) bitAnd: 255) asInt64.
	[(s at: 12800 + h) ~= 0] whileTrue: [
		(s at: 12544 + h) = v ifTrue: [^(s at: 12800 + h) asInt64 - 1].
		h := h + 1 bitAnd: 255].
	n >= 127 ifTrue: [^-1].
	s at: 12544 + h put: v.
	s at: 12800 + h put: (n + 1) asUInt32.
	s at: 12288 + n put: v.
	s at: 12416 + n put: h asUInt32.
	^n
!
cpixel: v cpixel: cp offset: off into: out at: o
	"The CPIXEL of the pixel v: cp of its bytes from off."
	<var: #v type: 'uint32_t'>
	<var: #cp type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #o type: 'int64_t'>
	<returns: 'int64_t'>
	| k |
	k := 0.
	[k < cp] whileTrue: [
		out at: o + k put: ((v >> (8 * (off + k))) bitAnd: 255) asUInt8.
		k := k + 1].
	^o + cp
!
runLength: len into: out at: start
	"A run's length L as L - 1 in bytes of 255 and a last one below 255."
	<var: #len type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #start type: 'int64_t'>
	<returns: 'int64_t'>
	| rest o |
	rest := len - 1.
	o := start.
	[rest >= 255] whileTrue: [
		out at: o put: 255.
		o := o + 1.
		rest := rest - 255].
	out at: o put: rest asUInt8.
	^o + 1
!
packed: s count: count width: tw bits: bits into: out at: start
	"The runs' palette indices, bits each, most significant first, each row of the tile byte-aligned."
	<function>
	<var: #s type: 'uint32_t *'>
	<var: #count type: 'int64_t'>
	<var: #tw type: 'int64_t'>
	<var: #bits type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #start type: 'int64_t'>
	<returns: 'int64_t'>
	| acc nb x o i j len index |
	acc := 0.
	nb := 0.
	x := 0.
	o := start.
	i := 0.
	[i < count] whileTrue: [
		index := (s at: 8192 + i) asInt64.
		len := (s at: i) asInt64.
		j := 0.
		[j < len] whileTrue: [
			acc := (acc << bits) bitOr: index.
			nb := nb + bits.
			nb = 8 ifTrue: [
				out at: o put: acc asUInt8.
				o := o + 1.
				acc := 0.
				nb := 0].
			x := x + 1.
			x = tw ifTrue: [
				nb > 0 ifTrue: [
					out at: o put: (acc << (8 - nb)) asUInt8.
					o := o + 1.
					acc := 0.
					nb := 0].
				x := 0].
			j := j + 1].
		i := i + 1].
	^o
!
raw: p stride: stride width: tw height: th bpp: bpp cpixel: cp offset: off into: out at: start
	"A raw tile: each pixel's CPIXEL, row after row."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #stride type: 'int64_t'>
	<var: #tw type: 'int64_t'>
	<var: #th type: 'int64_t'>
	<var: #bpp type: 'int64_t'>
	<var: #cp type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #start type: 'int64_t'>
	<var: #row type: 'uint8_t *'>
	<returns: 'int64_t'>
	| o y x row |
	out at: start put: 0.
	o := start + 1.
	(bpp = 4 and: [cp = 3]) ifTrue: [
		packer pack: p + off stride: stride width: tw height: th swap: 0 into: out + o.
		^o + (tw * th * 3)].
	y := 0.
	[y < th] whileTrue: [
		row := p + (y * stride).
		x := 0.
		[x < (tw * bpp)] whileTrue: [
			out at: o put: (row at: x).
			o := o + 1.
			x := x + 1].
		y := y + 1].
	^o
! !
