Object subclass: #ControlTokenHash
	instanceVariableNames: 'state words'
	classVariableNames: 'K'
	package: 'System-Remote'!

ControlTokenHash comment: 'SHA-256 (FIPS 180-4, 6.2), specialized to one 32-byte control token. The compression function is from the portable System-Crypto SHA256 (c350100). The words are 32 bits; rotations use shifts and masks.'!

!ControlTokenHash class methodsFor: 'class initialization'!
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

!ControlTokenHash class methodsFor: 'hashing'!
digestOf: bytes
	^self new digestOf: bytes
! !

!ControlTokenHash methodsFor: 'private'!
digestOf: bytes
	| block |
	bytes size = 32 ifFalse: [self error: 'expected a 32-byte canonical control token'].
	state := #(16r6A09E667 16rBB67AE85 16r3C6EF372 16rA54FF53A
		16r510E527F 16r9B05688C 16r1F83D9AB 16r5BE0CD19) copy.
	words := Array new: 64.
	block := ByteArray new: 64.
	^[block replaceFrom: 1 to: 32 with: bytes startingAt: 1.
	  block at: 33 put: 16r80.
	  block at: 63 put: 1. "256 bits of input, big-endian"
	  self processBlock: block.
	  self digestBytes] ensure: [
		block atAllPut: 0.
		words atAllPut: 0.
		state atAllPut: 0]
!
processBlock: bytes
	| w k i x s0 s1 a b c d e f g h t1 t2 |
	w := words.
	k := K.
	i := 0.
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
	1 to: 8 do: [:i | | word |
		word := state at: i.
		1 to: 4 do: [:j |
			out at: (i - 1) * 4 + j put: ((word bitShift: (j - 4) * 8) bitAnd: 255)]].
	^out
! !
