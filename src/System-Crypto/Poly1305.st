Object subclass: #Poly1305
	instanceVariableNames: 'r0 r1 r2 r3 r4 h0 h1 h2 h3 h4 pad buffer bufferCount'
	classVariableNames: ''
	package: 'System-Crypto'!

Poly1305 comment: 'I am the Poly1305 one-time authenticator of RFC 8439 (2.5): a 32-byte one-time key (r, clamped, and s), a 16-byte tag. Poly1305 key: k message: m answers the tag; incremental, (Poly1305 key: k) update: m; update: more; digest, where digest leaves the receiver going on. Compare tags with ByteArray>>constantTimeEquals:. The accumulator h and r are five 26-bit limbs (as poly1305-donna''s 32-bit code), so the products and their sums stay below 2^60, SmallIntegers; the final reduction modulo 2^130 - 5 chooses between h and h - p by masks, not by a branch.'!

!Poly1305 class methodsFor: 'instance creation'!
key: aByteArray
	^self new setKey: aByteArray
! !

!Poly1305 class methodsFor: 'authenticating'!
key: aByteArray message: bytes
	^(self key: aByteArray) update: bytes; digest
! !

!Poly1305 methodsFor: 'initialization'!
setKey: key
	| t0 t1 t2 t3 |
	key size = 32 ifFalse: [^CryptoError signal: 'Poly1305: the key must be 32 bytes'].
	t0 := key uint32At: 1.
	t1 := key uint32At: 5.
	t2 := key uint32At: 9.
	t3 := key uint32At: 13.
	r0 := t0 bitAnd: 16r3FFFFFF.
	r1 := ((t0 bitShift: -26) bitOr: (t1 bitShift: 6)) bitAnd: 16r3FFFF03.
	r2 := ((t1 bitShift: -20) bitOr: (t2 bitShift: 12)) bitAnd: 16r3FFC0FF.
	r3 := ((t2 bitShift: -14) bitOr: (t3 bitShift: 18)) bitAnd: 16r3F03FFF.
	r4 := (t3 bitShift: -8) bitAnd: 16r00FFFFF.
	pad := (1 to: 4) collect: [:i | key uint32At: 13 + (4 * i)].
	h0 := h1 := h2 := h3 := h4 := 0.
	buffer := ByteArray new: 16.
	bufferCount := 0
!
postCopy
	buffer := buffer copy
! !

!Poly1305 methodsFor: 'authenticating'!
update: bytes
	^self update: bytes from: 1 to: bytes size
!
update: bytes from: start to: stop
	| i n full |
	i := start.
	bufferCount > 0 ifTrue: [
		n := 16 - bufferCount min: stop - i + 1.
		buffer replaceFrom: bufferCount + 1 to: bufferCount + n with: bytes startingAt: i.
		bufferCount := bufferCount + n.
		i := i + n.
		bufferCount = 16 ifTrue: [
			self blocks: buffer from: 1 to: 16 hibit: 16r1000000.
			bufferCount := 0]].
	full := stop - i + 1 // 16 * 16.
	full > 0 ifTrue: [
		self blocks: bytes from: i to: i + full - 1 hibit: 16r1000000.
		i := i + full].
	i <= stop ifTrue: [
		buffer replaceFrom: 1 to: stop - i + 1 with: bytes startingAt: i.
		bufferCount := stop - i + 1]
!
digest
	"The tag of the bytes given so far; the receiver is unchanged."
	^self copy finish
! !

!Poly1305 methodsFor: 'private'!
blocks: bytes from: start to: stop hibit: hibit
	"Add each 16 bytes from start to stop (a multiple of 16) to h, with hibit (2^128 in limb 4, or 0 for the padded last block), and multiply by r."
	| a0 a1 a2 a3 a4 b0 b1 b2 b3 b4 s1 s2 s3 s4 i t0 t1 t2 t3 d0 d1 d2 d3 d4 c |
	a0 := h0. a1 := h1. a2 := h2. a3 := h3. a4 := h4.
	b0 := r0. b1 := r1. b2 := r2. b3 := r3. b4 := r4.
	s1 := b1 * 5. s2 := b2 * 5. s3 := b3 * 5. s4 := b4 * 5.
	i := start.
	[i < stop] whileTrue: [
		t0 := bytes uint32At: i.
		t1 := bytes uint32At: i + 4.
		t2 := bytes uint32At: i + 8.
		t3 := bytes uint32At: i + 12.
		a0 := a0 + (t0 bitAnd: 16r3FFFFFF).
		a1 := a1 + (((t0 bitShift: -26) bitOr: (t1 bitShift: 6)) bitAnd: 16r3FFFFFF).
		a2 := a2 + (((t1 bitShift: -20) bitOr: (t2 bitShift: 12)) bitAnd: 16r3FFFFFF).
		a3 := a3 + (((t2 bitShift: -14) bitOr: (t3 bitShift: 18)) bitAnd: 16r3FFFFFF).
		a4 := a4 + ((t3 bitShift: -8) bitOr: hibit).
		d0 := (a0 * b0) + (a1 * s4) + (a2 * s3) + (a3 * s2) + (a4 * s1).
		d1 := (a0 * b1) + (a1 * b0) + (a2 * s4) + (a3 * s3) + (a4 * s2).
		d2 := (a0 * b2) + (a1 * b1) + (a2 * b0) + (a3 * s4) + (a4 * s3).
		d3 := (a0 * b3) + (a1 * b2) + (a2 * b1) + (a3 * b0) + (a4 * s4).
		d4 := (a0 * b4) + (a1 * b3) + (a2 * b2) + (a3 * b1) + (a4 * b0).
		c := d0 bitShift: -26. a0 := d0 bitAnd: 16r3FFFFFF.
		d1 := d1 + c. c := d1 bitShift: -26. a1 := d1 bitAnd: 16r3FFFFFF.
		d2 := d2 + c. c := d2 bitShift: -26. a2 := d2 bitAnd: 16r3FFFFFF.
		d3 := d3 + c. c := d3 bitShift: -26. a3 := d3 bitAnd: 16r3FFFFFF.
		d4 := d4 + c. c := d4 bitShift: -26. a4 := d4 bitAnd: 16r3FFFFFF.
		a0 := a0 + (c * 5). c := a0 bitShift: -26. a0 := a0 bitAnd: 16r3FFFFFF.
		a1 := a1 + c.
		i := i + 16].
	h0 := a0. h1 := a1. h2 := a2. h3 := a3. h4 := a4
!
finish
	| c g0 g1 g2 g3 g4 keep take f w0 w1 w2 w3 tag |
	bufferCount > 0 ifTrue: [
		buffer at: bufferCount + 1 put: 1.
		bufferCount + 2 to: 16 do: [:k | buffer at: k put: 0].
		self blocks: buffer from: 1 to: 16 hibit: 0].
	"Carry fully."
	c := h1 bitShift: -26. h1 := h1 bitAnd: 16r3FFFFFF.
	h2 := h2 + c. c := h2 bitShift: -26. h2 := h2 bitAnd: 16r3FFFFFF.
	h3 := h3 + c. c := h3 bitShift: -26. h3 := h3 bitAnd: 16r3FFFFFF.
	h4 := h4 + c. c := h4 bitShift: -26. h4 := h4 bitAnd: 16r3FFFFFF.
	h0 := h0 + (c * 5). c := h0 bitShift: -26. h0 := h0 bitAnd: 16r3FFFFFF.
	h1 := h1 + c.
	"g := h + 5 - 2^130; h if that is negative, else g."
	g0 := h0 + 5. c := g0 bitShift: -26. g0 := g0 bitAnd: 16r3FFFFFF.
	g1 := h1 + c. c := g1 bitShift: -26. g1 := g1 bitAnd: 16r3FFFFFF.
	g2 := h2 + c. c := g2 bitShift: -26. g2 := g2 bitAnd: 16r3FFFFFF.
	g3 := h3 + c. c := g3 bitShift: -26. g3 := g3 bitAnd: 16r3FFFFFF.
	g4 := h4 + c - 16r4000000.
	keep := (g4 bitShift: -40) bitAnd: 16r3FFFFFF.
	take := keep bitXor: 16r3FFFFFF.
	h0 := (h0 bitAnd: keep) bitOr: (g0 bitAnd: take).
	h1 := (h1 bitAnd: keep) bitOr: (g1 bitAnd: take).
	h2 := (h2 bitAnd: keep) bitOr: (g2 bitAnd: take).
	h3 := (h3 bitAnd: keep) bitOr: (g3 bitAnd: take).
	h4 := (h4 bitAnd: keep) bitOr: (g4 bitAnd: take).
	"h + s modulo 2^128, little-endian."
	w0 := (h0 bitOr: (h1 bitShift: 26)) bitAnd: 16rFFFFFFFF.
	w1 := ((h1 bitShift: -6) bitOr: (h2 bitShift: 20)) bitAnd: 16rFFFFFFFF.
	w2 := ((h2 bitShift: -12) bitOr: (h3 bitShift: 14)) bitAnd: 16rFFFFFFFF.
	w3 := ((h3 bitShift: -18) bitOr: (h4 bitShift: 8)) bitAnd: 16rFFFFFFFF.
	tag := ByteArray new: 16.
	f := w0 + (pad at: 1).
	tag uint32At: 1 put: (f bitAnd: 16rFFFFFFFF).
	f := w1 + (pad at: 2) + (f bitShift: -32).
	tag uint32At: 5 put: (f bitAnd: 16rFFFFFFFF).
	f := w2 + (pad at: 3) + (f bitShift: -32).
	tag uint32At: 9 put: (f bitAnd: 16rFFFFFFFF).
	f := w3 + (pad at: 4) + (f bitShift: -32).
	tag uint32At: 13 put: (f bitAnd: 16rFFFFFFFF).
	^tag
! !
