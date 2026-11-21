Object subclass: #Aes
	instanceVariableNames: 'rounds encryptionKeys decryptionKeys words'
	classVariableNames: 'Sbox InverseSbox Te0 Te1 Te2 Te3 Td0 Td1 Td2 Td3'
	package: 'System-Crypto'!

Aes comment: 'I am the AES block cipher (FIPS 197) with a 16-, 24- or 32-byte key (AES-128, -192, -256; another size signals CryptoError): (Aes key: k) encryptBlock: sixteenBytes and decryptBlock: answer 16 new bytes; encrypt:at:into:at: works in place of the caller''s buffers; encryptWords:with:with:with:into: is what counter modes (AesGcm) call, on the block as four little-endian 32-bit words (each column''s first row in the low byte, as uint32At: reads them), the result into an Array of four. Rounds are table lookups (Te0-Te3, Td0-Td3: SubBytes, ShiftRows and MixColumns of a column in one word, the S-box''s multiples by MixColumns'' coefficients), computed with the S-box when the class initializes; decryption is the equivalent inverse cipher (its round keys through InvMixColumns). The words are SmallIntegers. Table lookups indexed by secret bytes take time that depends on the cache, as in every table-driven AES.'!

!Aes class methodsFor: 'class initialization'!
initialize
	| exp log s si t d |
	"Powers and logarithms of the generator 3 in GF(2^8) modulo x^8 + x^4 + x^3 + x + 1."
	exp := Array new: 256.
	log := Array new: 256.
	t := 1.
	0 to: 254 do: [:i |
		exp at: i + 1 put: t.
		log at: t + 1 put: i.
		t := t bitXor: (self xtime: t)].
	Sbox := ByteArray new: 256.
	InverseSbox := ByteArray new: 256.
	0 to: 255 do: [:x | | inv |
		inv := x = 0 ifTrue: [0] ifFalse: [exp at: 255 - (log at: x + 1) \\ 255 + 1].
		s := inv.
		1 to: 4 do: [:k | s := s bitXor: (((inv bitShift: k) bitOr: (inv bitShift: k - 8)) bitAnd: 255)].
		s := s bitXor: 16r63.
		Sbox at: x + 1 put: s.
		InverseSbox at: s + 1 put: x].
	Te0 := Array new: 256. Te1 := Array new: 256. Te2 := Array new: 256. Te3 := Array new: 256.
	Td0 := Array new: 256. Td1 := Array new: 256. Td2 := Array new: 256. Td3 := Array new: 256.
	0 to: 255 do: [:x |
		s := Sbox at: x + 1.
		t := ((self mul: s by: 2) bitOr: (s bitShift: 8)) bitOr: ((s bitShift: 16) bitOr: ((self mul: s by: 3) bitShift: 24)).
		Te0 at: x + 1 put: t.
		Te1 at: x + 1 put: (self rotateLeft: t by: 8).
		Te2 at: x + 1 put: (self rotateLeft: t by: 16).
		Te3 at: x + 1 put: (self rotateLeft: t by: 24).
		si := InverseSbox at: x + 1.
		d := ((self mul: si by: 14) bitOr: ((self mul: si by: 9) bitShift: 8)) bitOr: (((self mul: si by: 13) bitShift: 16) bitOr: ((self mul: si by: 11) bitShift: 24)).
		Td0 at: x + 1 put: d.
		Td1 at: x + 1 put: (self rotateLeft: d by: 8).
		Td2 at: x + 1 put: (self rotateLeft: d by: 16).
		Td3 at: x + 1 put: (self rotateLeft: d by: 24)]
!
xtime: a
	"a times x in GF(2^8)."
	^((a bitShift: 1) bitXor: ((a bitAnd: 16r80) = 0 ifTrue: [0] ifFalse: [16r1B])) bitAnd: 255
!
mul: a by: b
	| p x y |
	p := 0.
	x := a.
	y := b.
	[y > 0] whileTrue: [
		(y bitAnd: 1) = 1 ifTrue: [p := p bitXor: x].
		x := self xtime: x.
		y := y bitShift: -1].
	^p
!
rotateLeft: word by: n
	^((word bitShift: n) bitAnd: 16rFFFFFFFF) bitOr: (word bitShift: n - 32)
! !

!Aes class methodsFor: 'instance creation'!
key: aByteArray
	^self new setKey: aByteArray
! !

!Aes class methodsFor: 'accessing'!
blockSize
	^16
! !

!Aes methodsFor: 'initialization'!
setKey: key
	"The key schedule (FIPS 197, 5.2) in little-endian words: RotWord is a rotation right by 8, the round constant goes into the low byte."
	| nk total w t rcon sbox |
	(#(16 24 32) includes: key size) ifFalse: [^CryptoError signal: 'AES: the key must be 16, 24 or 32 bytes'].
	nk := key size // 4.
	rounds := nk + 6.
	total := 4 * (rounds + 1).
	w := Array new: total.
	1 to: nk do: [:i | w at: i put: (key uint32At: i * 4 - 3)].
	sbox := Sbox.
	rcon := 1.
	nk + 1 to: total do: [:i |
		t := w at: i - 1.
		(i - 1) \\ nk = 0
			ifTrue: [
				t := (self subWord: ((t bitShift: -8) bitOr: ((t bitAnd: 255) bitShift: 24))) bitXor: rcon.
				rcon := self class xtime: rcon]
			ifFalse: [(nk > 6 and: [(i - 1) \\ nk = 4]) ifTrue: [t := self subWord: t]].
		w at: i put: ((w at: i - nk) bitXor: t)].
	encryptionKeys := w.
	decryptionKeys := Array new: total.
	0 to: rounds do: [:r |
		1 to: 4 do: [:c | | k |
			k := w at: (rounds - r) * 4 + c.
			(r > 0 and: [r < rounds]) ifTrue: [
				k := (((Td0 at: (sbox at: (k bitAnd: 255) + 1) + 1)
					bitXor: (Td1 at: (sbox at: ((k bitShift: -8) bitAnd: 255) + 1) + 1))
					bitXor: (Td2 at: (sbox at: ((k bitShift: -16) bitAnd: 255) + 1) + 1))
					bitXor: (Td3 at: (sbox at: (k bitShift: -24) + 1) + 1)].
			decryptionKeys at: r * 4 + c put: k]].
	words := Array new: 4
!
subWord: w
	^(((Sbox at: (w bitAnd: 255) + 1) bitOr: ((Sbox at: ((w bitShift: -8) bitAnd: 255) + 1) bitShift: 8))
		bitOr: ((Sbox at: ((w bitShift: -16) bitAnd: 255) + 1) bitShift: 16))
		bitOr: ((Sbox at: (w bitShift: -24) + 1) bitShift: 24)
! !

!Aes methodsFor: 'encrypting'!
encryptBlock: bytes
	^self encrypt: bytes at: 1 into: (ByteArray new: 16) at: 1
!
decryptBlock: bytes
	^self decrypt: bytes at: 1 into: (ByteArray new: 16) at: 1
!
encrypt: input at: start into: output at: outStart
	"Encrypt the 16 bytes of input from start into output from outStart; answer output."
	| w |
	w := words.
	self encryptWords: (input uint32At: start) with: (input uint32At: start + 4) with: (input uint32At: start + 8) with: (input uint32At: start + 12) into: w.
	output uint32At: outStart put: (w at: 1); uint32At: outStart + 4 put: (w at: 2); uint32At: outStart + 8 put: (w at: 3); uint32At: outStart + 12 put: (w at: 4).
	^output
!
decrypt: input at: start into: output at: outStart
	| w |
	w := words.
	self decryptWords: (input uint32At: start) with: (input uint32At: start + 4) with: (input uint32At: start + 8) with: (input uint32At: start + 12) into: w.
	output uint32At: outStart put: (w at: 1); uint32At: outStart + 4 put: (w at: 2); uint32At: outStart + 8 put: (w at: 3); uint32At: outStart + 12 put: (w at: 4).
	^output
!
encryptWords: w0 with: w1 with: w2 with: w3 into: anArray
	"The block of the four little-endian words, encrypted, into anArray."
	| rk t0 t1 t2 t3 s0 s1 s2 s3 k e0 e1 e2 e3 sbox |
	rk := encryptionKeys.
	e0 := Te0. e1 := Te1. e2 := Te2. e3 := Te3.
	s0 := w0 bitXor: (rk at: 1).
	s1 := w1 bitXor: (rk at: 2).
	s2 := w2 bitXor: (rk at: 3).
	s3 := w3 bitXor: (rk at: 4).
	k := 4.
	2 to: rounds do: [:r |
		t0 := ((((e0 at: (s0 bitAnd: 255) + 1) bitXor: (e1 at: ((s1 bitShift: -8) bitAnd: 255) + 1)) bitXor: (e2 at: ((s2 bitShift: -16) bitAnd: 255) + 1)) bitXor: (e3 at: (s3 bitShift: -24) + 1)) bitXor: (rk at: k + 1).
		t1 := ((((e0 at: (s1 bitAnd: 255) + 1) bitXor: (e1 at: ((s2 bitShift: -8) bitAnd: 255) + 1)) bitXor: (e2 at: ((s3 bitShift: -16) bitAnd: 255) + 1)) bitXor: (e3 at: (s0 bitShift: -24) + 1)) bitXor: (rk at: k + 2).
		t2 := ((((e0 at: (s2 bitAnd: 255) + 1) bitXor: (e1 at: ((s3 bitShift: -8) bitAnd: 255) + 1)) bitXor: (e2 at: ((s0 bitShift: -16) bitAnd: 255) + 1)) bitXor: (e3 at: (s1 bitShift: -24) + 1)) bitXor: (rk at: k + 3).
		t3 := ((((e0 at: (s3 bitAnd: 255) + 1) bitXor: (e1 at: ((s0 bitShift: -8) bitAnd: 255) + 1)) bitXor: (e2 at: ((s1 bitShift: -16) bitAnd: 255) + 1)) bitXor: (e3 at: (s2 bitShift: -24) + 1)) bitXor: (rk at: k + 4).
		s0 := t0. s1 := t1. s2 := t2. s3 := t3.
		k := k + 4].
	sbox := Sbox.
	anArray at: 1 put: (((((sbox at: (s0 bitAnd: 255) + 1) bitOr: ((sbox at: ((s1 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((sbox at: ((s2 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((sbox at: (s3 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 1)).
	anArray at: 2 put: (((((sbox at: (s1 bitAnd: 255) + 1) bitOr: ((sbox at: ((s2 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((sbox at: ((s3 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((sbox at: (s0 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 2)).
	anArray at: 3 put: (((((sbox at: (s2 bitAnd: 255) + 1) bitOr: ((sbox at: ((s3 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((sbox at: ((s0 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((sbox at: (s1 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 3)).
	anArray at: 4 put: (((((sbox at: (s3 bitAnd: 255) + 1) bitOr: ((sbox at: ((s0 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((sbox at: ((s1 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((sbox at: (s2 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 4)).
	^anArray
!
decryptWords: w0 with: w1 with: w2 with: w3 into: anArray
	"The block of the four little-endian words, decrypted, into anArray."
	| rk t0 t1 t2 t3 s0 s1 s2 s3 k d0 d1 d2 d3 inv |
	rk := decryptionKeys.
	d0 := Td0. d1 := Td1. d2 := Td2. d3 := Td3.
	s0 := w0 bitXor: (rk at: 1).
	s1 := w1 bitXor: (rk at: 2).
	s2 := w2 bitXor: (rk at: 3).
	s3 := w3 bitXor: (rk at: 4).
	k := 4.
	2 to: rounds do: [:r |
		t0 := ((((d0 at: (s0 bitAnd: 255) + 1) bitXor: (d1 at: ((s3 bitShift: -8) bitAnd: 255) + 1)) bitXor: (d2 at: ((s2 bitShift: -16) bitAnd: 255) + 1)) bitXor: (d3 at: (s1 bitShift: -24) + 1)) bitXor: (rk at: k + 1).
		t1 := ((((d0 at: (s1 bitAnd: 255) + 1) bitXor: (d1 at: ((s0 bitShift: -8) bitAnd: 255) + 1)) bitXor: (d2 at: ((s3 bitShift: -16) bitAnd: 255) + 1)) bitXor: (d3 at: (s2 bitShift: -24) + 1)) bitXor: (rk at: k + 2).
		t2 := ((((d0 at: (s2 bitAnd: 255) + 1) bitXor: (d1 at: ((s1 bitShift: -8) bitAnd: 255) + 1)) bitXor: (d2 at: ((s0 bitShift: -16) bitAnd: 255) + 1)) bitXor: (d3 at: (s3 bitShift: -24) + 1)) bitXor: (rk at: k + 3).
		t3 := ((((d0 at: (s3 bitAnd: 255) + 1) bitXor: (d1 at: ((s2 bitShift: -8) bitAnd: 255) + 1)) bitXor: (d2 at: ((s1 bitShift: -16) bitAnd: 255) + 1)) bitXor: (d3 at: (s0 bitShift: -24) + 1)) bitXor: (rk at: k + 4).
		s0 := t0. s1 := t1. s2 := t2. s3 := t3.
		k := k + 4].
	inv := InverseSbox.
	anArray at: 1 put: (((((inv at: (s0 bitAnd: 255) + 1) bitOr: ((inv at: ((s3 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((inv at: ((s2 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((inv at: (s1 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 1)).
	anArray at: 2 put: (((((inv at: (s1 bitAnd: 255) + 1) bitOr: ((inv at: ((s0 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((inv at: ((s3 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((inv at: (s2 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 2)).
	anArray at: 3 put: (((((inv at: (s2 bitAnd: 255) + 1) bitOr: ((inv at: ((s1 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((inv at: ((s0 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((inv at: (s3 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 3)).
	anArray at: 4 put: (((((inv at: (s3 bitAnd: 255) + 1) bitOr: ((inv at: ((s2 bitShift: -8) bitAnd: 255) + 1) bitShift: 8)) bitOr: ((inv at: ((s1 bitShift: -16) bitAnd: 255) + 1) bitShift: 16)) bitOr: ((inv at: (s0 bitShift: -24) + 1) bitShift: 24)) bitXor: (rk at: k + 4)).
	^anArray
! !
