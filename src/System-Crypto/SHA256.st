CryptoHash subclass: #SHA256
	instanceVariableNames: 'state words'
	classVariableNames: 'K'
	package: 'System-Crypto'!

SHA256 comment: 'I am SHA-256 (FIPS 180-4, 6.2): a 32-byte digest of 64-byte blocks. SHA256 hash: bytes; SHA256 new update: bytes; update: more; digest (CryptoHash). The eight 32-bit words of state and the message schedule are SmallIntegers (63-bit signed: a 32-bit word shifted left by up to 30 bits still is one), so a rotation is two shifts, the left one masked to 32 bits (Σ0''s three left shifts are xored first, then masked once), and sums of up to five words are masked once.'!

!SHA256 class methodsFor: 'class initialization'!
initialize
	"The first 32 bits of the fractional parts of the cube roots of the first 64 primes."
	K := #(
		16r428A2F98 16r71374491 16rB5C0FBCF 16rE9B5DBA5 16r3956C25B 16r59F111F1 16r923F82A4 16rAB1C5ED5
		16rD807AA98 16r12835B01 16r243185BE 16r550C7DC3 16r72BE5D74 16r80DEB1FE 16r9BDC06A7 16rC19BF174
		16rE49B69C1 16rEFBE4786 16r0FC19DC6 16r240CA1CC 16r2DE92C6F 16r4A7484AA 16r5CB0A9DC 16r76F988DA
		16r983E5152 16rA831C66D 16rB00327C8 16rBF597FC7 16rC6E00BF3 16rD5A79147 16r06CA6351 16r14292967
		16r27B70A85 16r2E1B2138 16r4D2C6DFC 16r53380D13 16r650A7354 16r766A0ABB 16r81C2C92E 16r92722C85
		16rA2BFE8A1 16rA81A664B 16rC24B8B70 16rC76C51A3 16rD192E819 16rD6990624 16rF40E3585 16r106AA070
		16r19A4C116 16r1E376C08 16r2748774C 16r34B0BCB5 16r391C0CB3 16r4ED8AA4A 16r5B9CCA4F 16r682E6FF3
		16r748F82EE 16r78A5636F 16r84C87814 16r8CC70208 16r90BEFFFA 16rA4506CEB 16rBEF9A3F7 16rC67178F2)
! !

!SHA256 class methodsFor: 'accessing'!
digestSize
	^32
!
blockSize
	^64
!
lengthSize
	^8
! !

!SHA256 methodsFor: 'initialization'!
resetState
	state := Array new: 8.
	state at: 1 put: 16r6A09E667; at: 2 put: 16rBB67AE85; at: 3 put: 16r3C6EF372; at: 4 put: 16rA54FF53A;
		at: 5 put: 16r510E527F; at: 6 put: 16r9B05688C; at: 7 put: 16r1F83D9AB; at: 8 put: 16r5BE0CD19.
	words := Array new: 64
!
postCopy
	super postCopy.
	state := state copy.
	words := Array new: 64
! !

!SHA256 methodsFor: 'private'!
processBlock: bytes at: offset
	| w k i x s0 s1 a b c d e f g h t1 t2 |
	w := words.
	k := K.
	i := offset.
	1 to: 16 do: [:j |
		w at: j put: ((((bytes at: i + 1) bitShift: 24) bitOr: ((bytes at: i + 2) bitShift: 16)) bitOr: (((bytes at: i + 3) bitShift: 8) bitOr: (bytes at: i + 4))).
		i := i + 4].
	17 to: 64 do: [:j |
		x := w at: j - 15.
		s0 := (((x bitShift: -7) bitXor: (x bitShift: -18)) bitXor: (x bitShift: -3)) bitXor: (((x bitShift: 25) bitXor: (x bitShift: 14)) bitAnd: 16rFFFFFFFF).
		x := w at: j - 2.
		s1 := (((x bitShift: -17) bitXor: (x bitShift: -19)) bitXor: (x bitShift: -10)) bitXor: (((x bitShift: 15) bitXor: (x bitShift: 13)) bitAnd: 16rFFFFFFFF).
		w at: j put: ((w at: j - 16) + s0 + (w at: j - 7) + s1 bitAnd: 16rFFFFFFFF)].
	a := state at: 1. b := state at: 2. c := state at: 3. d := state at: 4.
	e := state at: 5. f := state at: 6. g := state at: 7. h := state at: 8.
	1 to: 64 do: [:j |
		t1 := h + ((((e bitShift: -6) bitXor: (e bitShift: -11)) bitXor: (e bitShift: -25)) bitXor: ((((e bitShift: 26) bitXor: (e bitShift: 21)) bitXor: (e bitShift: 7)) bitAnd: 16rFFFFFFFF))
			+ (g bitXor: (e bitAnd: (f bitXor: g))) + (k at: j) + (w at: j).
		t2 := ((((a bitShift: -2) bitXor: (a bitShift: -13)) bitXor: (a bitShift: -22)) bitXor: ((((a bitShift: 30) bitXor: (a bitShift: 19)) bitXor: (a bitShift: 10)) bitAnd: 16rFFFFFFFF))
			+ ((a bitAnd: b) bitOr: (c bitAnd: (a bitOr: b))).
		h := g.
		g := f.
		f := e.
		e := d + t1 bitAnd: 16rFFFFFFFF.
		d := c.
		c := b.
		b := a.
		a := t1 + t2 bitAnd: 16rFFFFFFFF].
	state at: 1 put: ((state at: 1) + a bitAnd: 16rFFFFFFFF).
	state at: 2 put: ((state at: 2) + b bitAnd: 16rFFFFFFFF).
	state at: 3 put: ((state at: 3) + c bitAnd: 16rFFFFFFFF).
	state at: 4 put: ((state at: 4) + d bitAnd: 16rFFFFFFFF).
	state at: 5 put: ((state at: 5) + e bitAnd: 16rFFFFFFFF).
	state at: 6 put: ((state at: 6) + f bitAnd: 16rFFFFFFFF).
	state at: 7 put: ((state at: 7) + g bitAnd: 16rFFFFFFFF).
	state at: 8 put: ((state at: 8) + h bitAnd: 16rFFFFFFFF)
!
digestBytes
	| out |
	out := ByteArray new: 32.
	1 to: 8 do: [:i | out netUint32At: i * 4 - 3 put: (state at: i)].
	^out
! !
