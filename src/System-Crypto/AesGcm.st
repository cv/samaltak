Object subclass: #AesGcm
	instanceVariableNames: 'aes table words'
	classVariableNames: 'Reduction'
	package: 'System-Crypto'!

AesGcm comment: 'I am AES in Galois/Counter Mode (NIST SP 800-38D), TLS 1.3''s TLS_AES_128_GCM_SHA256 and TLS_AES_256_GCM_SHA384: (AesGcm key: k) with a 16-, 24- or 32-byte key; encrypt: plaintext nonce: iv aad: a answers the ciphertext with the 16-byte tag appended; decrypt: data nonce: iv aad: a answers the plaintext, or signals CryptoError if the tag does not verify (compared in constant time, before anything is decrypted). The nonce is 12 bytes in TLS; any other non-empty size is hashed into the first counter block, as the standard says. Class side: nonceSize (12), tagSize (16).

GHASH multiplies by H with Shoup''s 8-bit tables: table holds b·H for every byte b, four big-endian 32-bit words each (the key''s, 4 KB as SmallIntegers), Reduction what the 8 bits a shift by a byte drops add back at the top (x^128 = x^7 + x^2 + x + 1), so a block is 16 lookups, shifts and xors. CTR mode''s counter blocks go through Aes>>encryptWords:with:with:with:into: as little-endian words; the counter, big-endian in the last word, is byte-swapped.'!

!AesGcm class methodsFor: 'class initialization'!
initialize
	"Reduction at: b + 1: what multiplying by x^8 adds to the top 16 bits when the dropped byte is b (its bit j, the coefficient of x^(127 - j), becomes x^128 times x^(7 - j): x^7 + x^2 + x + 1, 16rE100 in the top 16 bits, shifted right by 7 - j)."
	Reduction := Array new: 256.
	0 to: 255 do: [:b | | r |
		r := 0.
		0 to: 7 do: [:j | ((b bitShift: 0 - j) bitAnd: 1) = 1 ifTrue: [r := r bitXor: (16rE100 bitShift: j - 7)]].
		Reduction at: b + 1 put: r]
! !

!AesGcm class methodsFor: 'instance creation'!
key: aByteArray
	^self new setKey: aByteArray
! !

!AesGcm class methodsFor: 'accessing'!
nonceSize
	^12
!
tagSize
	^16
!
maxPlaintextSize
	"SP 800-38D, 5.2.1.1: at most 2^39 - 256 bits, 2^32 - 2 blocks, so that the 32-bit counter never wraps onto J0 and reuses the key stream."
	^(1 bitShift: 36) - 32
! !

!AesGcm methodsFor: 'initialization'!
setKey: aByteArray
	| h v0 v1 v2 v3 carry i j |
	aes := Aes key: aByteArray.
	words := Array new: 4.
	h := aes encryptBlock: (ByteArray new: 16).
	table := Array new: 1024 withAll: 0.
	"b = 128 (the coefficient of x^0 alone) is H; halving b is multiplying by x: a shift right with reduction."
	v0 := h netUint32At: 1. v1 := h netUint32At: 5. v2 := h netUint32At: 9. v3 := h netUint32At: 13.
	i := 128.
	[i > 0] whileTrue: [
		table at: i * 4 + 1 put: v0; at: i * 4 + 2 put: v1; at: i * 4 + 3 put: v2; at: i * 4 + 4 put: v3.
		carry := v3 bitAnd: 1.
		v3 := (v3 bitShift: -1) bitOr: ((v2 bitAnd: 1) bitShift: 31).
		v2 := (v2 bitShift: -1) bitOr: ((v1 bitAnd: 1) bitShift: 31).
		v1 := (v1 bitShift: -1) bitOr: ((v0 bitAnd: 1) bitShift: 31).
		v0 := (v0 bitShift: -1) bitXor: carry * 16rE1000000.
		i := i // 2].
	i := 2.
	[i < 256] whileTrue: [
		1 to: i - 1 do: [:k |
			j := i + k.
			1 to: 4 do: [:w | table at: j * 4 + w put: ((table at: i * 4 + w) bitXor: (table at: k * 4 + w))]].
		i := i * 2]
! !

!AesGcm methodsFor: 'encrypting'!
encrypt: plaintext nonce: iv aad: aad
	| j0 out n |
	j0 := self counterBlock: iv.
	n := plaintext size.
	n > self class maxPlaintextSize ifTrue: [^CryptoError signal: 'AES-GCM: longer than 2^32 - 2 blocks'].
	out := ByteArray new: n + 16.
	self ctr: plaintext from: 1 to: n into: out at: 1 counter: j0 startingAt: 2.
	out replaceFrom: n + 1 to: n + 16 with: (self tag: out size: n aad: aad counter: j0) startingAt: 1.
	^out
!
decrypt: data nonce: iv aad: aad
	| j0 n |
	j0 := self counterBlock: iv.
	data size < 16 ifTrue: [^CryptoError signal: 'AES-GCM: shorter than a tag'].
	n := data size - 16.
	n > self class maxPlaintextSize ifTrue: [^CryptoError signal: 'AES-GCM: longer than 2^32 - 2 blocks'].
	((self tag: data size: n aad: aad counter: j0) constantTimeEquals: (data copyFrom: n + 1 to: data size)) ifFalse: [^CryptoError signal: 'AES-GCM: the tag does not verify'].
	^self ctr: data from: 1 to: n into: (ByteArray new: n) at: 1 counter: j0 startingAt: 2
! !

!AesGcm methodsFor: 'private'!
counterBlock: iv
	"J0 (SP 800-38D, 7.1): iv || 0^31 || 1 for a 12-byte iv, else GHASH of iv, padded, and its length in bits."
	| j0 y lengths |
	iv isEmpty ifTrue: [^CryptoError signal: 'AES-GCM: the nonce is empty'].
	iv size = 12 ifTrue: [
		j0 := ByteArray new: 16.
		j0 replaceFrom: 1 to: 12 with: iv startingAt: 1.
		j0 at: 16 put: 1.
		^j0].
	y := ByteArray new: 16.
	self ghash: y with: iv from: 1 to: iv size.
	lengths := ByteArray new: 16.
	lengths netUint32At: 9 put: (iv size * 8 bitShift: -32); netUint32At: 13 put: (iv size * 8 bitAnd: 16rFFFFFFFF).
	self ghash: y with: lengths from: 1 to: 16.
	^y
!
ctr: input from: start to: stop into: output at: outStart counter: j0 startingAt: first
	"Xor input from start to stop with E(K, inc32^k(J0)), k from first - 1 on, into output; answer output."
	| w c0 c1 c2 counter i o e |
	w := words.
	c0 := j0 uint32At: 1.
	c1 := j0 uint32At: 5.
	c2 := j0 uint32At: 9.
	counter := (j0 netUint32At: 13) + first - 1 bitAnd: 16rFFFFFFFF.
	i := start.
	o := outStart.
	[i <= stop] whileTrue: [
		aes encryptWords: c0 with: c1 with: c2 with: ((((counter bitAnd: 255) bitShift: 24) bitOr: ((counter bitAnd: 16rFF00) bitShift: 8)) bitOr: (((counter bitShift: -8) bitAnd: 16rFF00) bitOr: (counter bitShift: -24))) into: w.
		counter := counter + 1 bitAnd: 16rFFFFFFFF.
		stop - i >= 15
			ifTrue: [
				output uint32At: o put: ((input uint32At: i) bitXor: (w at: 1)).
				output uint32At: o + 4 put: ((input uint32At: i + 4) bitXor: (w at: 2)).
				output uint32At: o + 8 put: ((input uint32At: i + 8) bitXor: (w at: 3)).
				output uint32At: o + 12 put: ((input uint32At: i + 12) bitXor: (w at: 4))]
			ifFalse: [
				0 to: stop - i do: [:b |
					e := w at: b // 4 + 1.
					output at: o + b put: ((input at: i + b) bitXor: ((e bitShift: b \\ 4 * -8) bitAnd: 255))]].
		i := i + 16.
		o := o + 16].
	^output
!
tag: ciphertext size: n aad: aad counter: j0
	"E(K, J0) xor GHASH(aad, padded; ciphertext, padded; their lengths in bits)."
	| a y lengths t |
	a := aad ifNil: [#[]].
	y := ByteArray new: 16.
	self ghash: y with: a from: 1 to: a size.
	self ghash: y with: ciphertext from: 1 to: n.
	lengths := ByteArray new: 16.
	lengths netUint32At: 1 put: (a size * 8 bitShift: -32); netUint32At: 5 put: (a size * 8 bitAnd: 16rFFFFFFFF).
	lengths netUint32At: 9 put: (n * 8 bitShift: -32); netUint32At: 13 put: (n * 8 bitAnd: 16rFFFFFFFF).
	self ghash: y with: lengths from: 1 to: 16.
	t := aes encryptBlock: j0.
	1 to: 16 do: [:k | t at: k put: ((t at: k) bitXor: (y at: k))].
	^t
!
ghash: y with: bytes from: start to: stop
	"y := (y xor each block of bytes from start to stop, the last padded with zeros) times H, block by block."
	| m r i b z0 z1 z2 z3 x |
	m := table.
	r := Reduction.
	i := start.
	[i <= stop] whileTrue: [
		stop - i >= 15
			ifTrue: [1 to: 16 do: [:k | y at: k put: ((y at: k) bitXor: (bytes at: i + k - 1))]]
			ifFalse: [0 to: stop - i do: [:k | y at: k + 1 put: ((y at: k + 1) bitXor: (bytes at: i + k))]].
		x := (y at: 16) * 4.
		z0 := m at: x + 1. z1 := m at: x + 2. z2 := m at: x + 3. z3 := m at: x + 4.
		15 to: 1 by: -1 do: [:k |
			b := z3 bitAnd: 255.
			z3 := (z3 bitShift: -8) bitOr: ((z2 bitAnd: 255) bitShift: 24).
			z2 := (z2 bitShift: -8) bitOr: ((z1 bitAnd: 255) bitShift: 24).
			z1 := (z1 bitShift: -8) bitOr: ((z0 bitAnd: 255) bitShift: 24).
			z0 := (z0 bitShift: -8) bitXor: ((r at: b + 1) bitShift: 16).
			x := (y at: k) * 4.
			z0 := z0 bitXor: (m at: x + 1).
			z1 := z1 bitXor: (m at: x + 2).
			z2 := z2 bitXor: (m at: x + 3).
			z3 := z3 bitXor: (m at: x + 4)].
		y at: 1 put: (z0 bitShift: -24); at: 2 put: ((z0 bitShift: -16) bitAnd: 255); at: 3 put: ((z0 bitShift: -8) bitAnd: 255); at: 4 put: (z0 bitAnd: 255).
		y at: 5 put: (z1 bitShift: -24); at: 6 put: ((z1 bitShift: -16) bitAnd: 255); at: 7 put: ((z1 bitShift: -8) bitAnd: 255); at: 8 put: (z1 bitAnd: 255).
		y at: 9 put: (z2 bitShift: -24); at: 10 put: ((z2 bitShift: -16) bitAnd: 255); at: 11 put: ((z2 bitShift: -8) bitAnd: 255); at: 12 put: (z2 bitAnd: 255).
		y at: 13 put: (z3 bitShift: -24); at: 14 put: ((z3 bitShift: -16) bitAnd: 255); at: 15 put: ((z3 bitShift: -8) bitAnd: 255); at: 16 put: (z3 bitAnd: 255).
		i := i + 16].
	^y
! !
