Object subclass: #Des
	instanceVariableNames: 'subkeys'
	classVariableNames: ''
	package: 'System-Crypto'!

Des comment: 'I am the Data Encryption Standard (FIPS 46-3), one 64-bit block at a time (ECB), with a key of 8 bytes (the low bit of each, the parity bit, unused). DES is broken: I exist for RFB''s VNC authentication (RFC 6143, 7.2.2), which encrypts the 16-byte challenge with the password as the key, and for nothing else. Written for clarity over speed, a bit at a time (a connection encrypts two blocks).

VNC''s quirk: its key is the password''s first 8 bytes (zero-padded) with the bits of each byte in reverse order (libvncauth''s deskey reads bits from the low end), see vncKeyFrom: and vncResponseTo:password:.'!

!Des methodsFor: 'initialization'!
setKey: aByteArray
	"The 16 round keys (48 bits each, as Arrays of 0/1) from the key's 56 bits."
	| cd c d |
	aByteArray size = 8 ifFalse: [^CryptoError signal: 'DES: a key is 8 bytes'].
	cd := self class permute: (self class bitsOf: aByteArray) by: self class pc1.
	c := cd copyFrom: 1 to: 28.
	d := cd copyFrom: 29 to: 56.
	subkeys := self class shifts collect: [:n |
		c := (c copyFrom: n + 1 to: 28), (c copyFrom: 1 to: n).
		d := (d copyFrom: n + 1 to: 28), (d copyFrom: 1 to: n).
		self class permute: c, d by: self class pc2]
! !

!Des methodsFor: 'ciphering'!
encryptBlock: aByteArray
	"The 8-byte block aByteArray encrypted."
	^self crypt: aByteArray keys: subkeys
!
decryptBlock: aByteArray
	^self crypt: aByteArray keys: subkeys reversed
!
encrypt: bytes
	"bytes (a multiple of 8) encrypted block by block (ECB)."
	^self ecb: bytes with: [:block | self encryptBlock: block]
!
decrypt: bytes
	^self ecb: bytes with: [:block | self decryptBlock: block]
! !

!Des methodsFor: 'private'!
ecb: bytes with: aBlock
	| out |
	bytes size \\ 8 = 0 ifFalse: [^CryptoError signal: 'DES: the data is not a multiple of 8 bytes'].
	out := ByteArray new: bytes size.
	1 to: bytes size by: 8 do: [:i |
		out replaceFrom: i to: i + 7 with: (aBlock value: (bytes copyFrom: i to: i + 7)) startingAt: 1].
	^out
!
crypt: aByteArray keys: keys
	"The initial permutation, 16 Feistel rounds with keys, the halves swapped, the final permutation."
	| bits l r |
	aByteArray size = 8 ifFalse: [^CryptoError signal: 'DES: a block is 8 bytes'].
	bits := self class permute: (self class bitsOf: aByteArray asByteArray) by: self class ip.
	l := bits copyFrom: 1 to: 32.
	r := bits copyFrom: 33 to: 64.
	keys do: [:k | | f |
		f := self f: r key: k.
		f := (1 to: 32) collect: [:i | (l at: i) bitXor: (f at: i)].
		l := r.
		r := f].
	^self class bytesOf: (self class permute: r, l by: self class fp)
!
f: r key: k
	"The round function: r expanded to 48 bits, xored with k, through the eight S-boxes, permuted."
	| x out boxes |
	x := self class permute: r by: self class e.
	boxes := self class sBoxes.
	out := Array new: 32.
	1 to: 8 do: [:s | | o v row col |
		o := s - 1 * 6.
		v := 0.
		1 to: 6 do: [:j | v := v * 2 + ((x at: o + j) bitXor: (k at: o + j))].
		row := ((v bitShift: -4) bitAnd: 2) + (v bitAnd: 1).
		col := (v bitShift: -1) bitAnd: 15.
		v := (boxes at: s) at: row * 16 + col + 1.
		1 to: 4 do: [:j | out at: s - 1 * 4 + j put: ((v bitShift: j - 4) bitAnd: 1)]].
	^self class permute: out by: self class p
! !

!Des class methodsFor: 'instance creation'!
key: aByteArray
	^self new setKey: aByteArray
! !

!Des class methodsFor: 'VNC authentication'!
vncKeyFrom: aPassword
	"RFB's VNC authentication key: the password's first 8 bytes (Latin-1, zero-padded), each byte's bits reversed."
	| key |
	key := ByteArray new: 8.
	1 to: (aPassword size min: 8) do: [:i | | b r |
		b := (aPassword at: i) isCharacter ifTrue: [(aPassword at: i) codePoint bitAnd: 255] ifFalse: [aPassword at: i].
		r := 0.
		8 timesRepeat: [r := r * 2 + (b bitAnd: 1). b := b bitShift: -1].
		key at: i put: r].
	^key
!
vncResponseTo: aChallenge password: aPassword
	"The client's answer to a VNC authentication challenge (16 bytes): the challenge encrypted with the password."
	^(self key: (self vncKeyFrom: aPassword)) encrypt: aChallenge
! !

!Des class methodsFor: 'private'!
bitsOf: aByteArray
	"An Array of the bits of aByteArray, most significant first."
	| bits |
	bits := Array new: aByteArray size * 8.
	aByteArray doWithIndex: [:b :i |
		1 to: 8 do: [:j | bits at: i - 1 * 8 + j put: ((b bitShift: j - 8) bitAnd: 1)]].
	^bits
!
bytesOf: bits
	| bytes |
	bytes := ByteArray new: bits size // 8.
	1 to: bytes size do: [:i | | b |
		b := 0.
		1 to: 8 do: [:j | b := b * 2 + (bits at: i - 1 * 8 + j)].
		bytes at: i put: b].
	^bytes
!
permute: bits by: aTable
	"FIPS 46's permutations: bit i of the result is bit (aTable at: i) of bits (1-based)."
	^aTable collect: [:i | bits at: i]
! !

!Des class methodsFor: 'tables'!
ip
	^#(58 50 42 34 26 18 10 2 60 52 44 36 28 20 12 4 62 54 46 38 30 22 14 6 64 56 48 40 32 24 16 8 57 49 41 33 25 17 9 1 59 51 43 35 27 19 11 3 61 53 45 37 29 21 13 5 63 55 47 39 31 23 15 7)
!
fp
	^#(40 8 48 16 56 24 64 32 39 7 47 15 55 23 63 31 38 6 46 14 54 22 62 30 37 5 45 13 53 21 61 29 36 4 44 12 52 20 60 28 35 3 43 11 51 19 59 27 34 2 42 10 50 18 58 26 33 1 41 9 49 17 57 25)
!
e
	^#(32 1 2 3 4 5 4 5 6 7 8 9 8 9 10 11 12 13 12 13 14 15 16 17 16 17 18 19 20 21 20 21 22 23 24 25 24 25 26 27 28 29 28 29 30 31 32 1)
!
p
	^#(16 7 20 21 29 12 28 17 1 15 23 26 5 18 31 10 2 8 24 14 32 27 3 9 19 13 30 6 22 11 4 25)
!
pc1
	^#(57 49 41 33 25 17 9 1 58 50 42 34 26 18 10 2 59 51 43 35 27 19 11 3 60 52 44 36 63 55 47 39 31 23 15 7 62 54 46 38 30 22 14 6 61 53 45 37 29 21 13 5 28 20 12 4)
!
pc2
	^#(14 17 11 24 1 5 3 28 15 6 21 10 23 19 12 4 26 8 16 7 27 20 13 2 41 52 31 37 47 55 30 40 51 45 33 48 44 49 39 56 34 53 46 42 50 36 29 32)
!
shifts
	^#(1 1 2 2 2 2 2 2 1 2 2 2 2 2 2 1)
!
sBoxes
	^#(
		#(14 4 13 1 2 15 11 8 3 10 6 12 5 9 0 7 0 15 7 4 14 2 13 1 10 6 12 11 9 5 3 8 4 1 14 8 13 6 2 11 15 12 9 7 3 10 5 0 15 12 8 2 4 9 1 7 5 11 3 14 10 0 6 13)
		#(15 1 8 14 6 11 3 4 9 7 2 13 12 0 5 10 3 13 4 7 15 2 8 14 12 0 1 10 6 9 11 5 0 14 7 11 10 4 13 1 5 8 12 6 9 3 2 15 13 8 10 1 3 15 4 2 11 6 7 12 0 5 14 9)
		#(10 0 9 14 6 3 15 5 1 13 12 7 11 4 2 8 13 7 0 9 3 4 6 10 2 8 5 14 12 11 15 1 13 6 4 9 8 15 3 0 11 1 2 12 5 10 14 7 1 10 13 0 6 9 8 7 4 15 14 3 11 5 2 12)
		#(7 13 14 3 0 6 9 10 1 2 8 5 11 12 4 15 13 8 11 5 6 15 0 3 4 7 2 12 1 10 14 9 10 6 9 0 12 11 7 13 15 1 3 14 5 2 8 4 3 15 0 6 10 1 13 8 9 4 5 11 12 7 2 14)
		#(2 12 4 1 7 10 11 6 8 5 3 15 13 0 14 9 14 11 2 12 4 7 13 1 5 0 15 10 3 9 8 6 4 2 1 11 10 13 7 8 15 9 12 5 6 3 0 14 11 8 12 7 1 14 2 13 6 15 0 9 10 4 5 3)
		#(12 1 10 15 9 2 6 8 0 13 3 4 14 7 5 11 10 15 4 2 7 12 9 5 6 1 13 14 0 11 3 8 9 14 15 5 2 8 12 3 7 0 4 10 1 13 11 6 4 3 2 12 9 5 15 10 11 14 1 7 6 0 8 13)
		#(4 11 2 14 15 0 8 13 3 12 9 7 5 10 6 1 13 0 11 7 4 9 1 10 14 3 5 12 2 15 8 6 1 4 11 13 12 3 7 14 10 15 6 8 0 5 9 2 6 11 13 8 1 4 10 7 9 5 0 15 14 2 3 12)
		#(13 2 8 4 6 15 11 1 10 9 3 14 5 0 12 7 1 15 13 8 10 3 7 4 12 5 6 11 0 14 9 2 7 11 4 1 9 12 14 2 0 6 10 13 15 3 5 8 2 1 14 7 4 10 8 13 15 12 9 0 3 5 6 11))
! !
