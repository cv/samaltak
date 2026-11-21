CryptoHash subclass: #SHA512
	instanceVariableNames: 'state high low'
	classVariableNames: 'KHigh KLow'
	package: 'System-Crypto'!

SHA512 comment: 'I am SHA-512 (FIPS 180-4, 6.4): a 64-byte digest of 128-byte blocks; SHA384 is my truncated variant. SHA512 hash: bytes; SHA512 new update: bytes; update: more; digest (CryptoHash). A 64-bit word does not fit a SmallInteger (63 bits, signed), so each is two 32-bit halves, high and low: the state is 16 halves, the message schedule two Arrays (high, low); a rotation by n < 32 takes each half''s top bits from the other half (by n >= 32 the halves swap first), a sum adds the low halves and carries their bits above 32 into the high one.'!

!SHA512 class methodsFor: 'class initialization'!
initialize
	"The first 64 bits of the fractional parts of the cube roots of the first 80 primes, in halves."
	| k |
	k := #(
		16r428A2F98D728AE22 16r7137449123EF65CD 16rB5C0FBCFEC4D3B2F 16rE9B5DBA58189DBBC
		16r3956C25BF348B538 16r59F111F1B605D019 16r923F82A4AF194F9B 16rAB1C5ED5DA6D8118
		16rD807AA98A3030242 16r12835B0145706FBE 16r243185BE4EE4B28C 16r550C7DC3D5FFB4E2
		16r72BE5D74F27B896F 16r80DEB1FE3B1696B1 16r9BDC06A725C71235 16rC19BF174CF692694
		16rE49B69C19EF14AD2 16rEFBE4786384F25E3 16r0FC19DC68B8CD5B5 16r240CA1CC77AC9C65
		16r2DE92C6F592B0275 16r4A7484AA6EA6E483 16r5CB0A9DCBD41FBD4 16r76F988DA831153B5
		16r983E5152EE66DFAB 16rA831C66D2DB43210 16rB00327C898FB213F 16rBF597FC7BEEF0EE4
		16rC6E00BF33DA88FC2 16rD5A79147930AA725 16r06CA6351E003826F 16r142929670A0E6E70
		16r27B70A8546D22FFC 16r2E1B21385C26C926 16r4D2C6DFC5AC42AED 16r53380D139D95B3DF
		16r650A73548BAF63DE 16r766A0ABB3C77B2A8 16r81C2C92E47EDAEE6 16r92722C851482353B
		16rA2BFE8A14CF10364 16rA81A664BBC423001 16rC24B8B70D0F89791 16rC76C51A30654BE30
		16rD192E819D6EF5218 16rD69906245565A910 16rF40E35855771202A 16r106AA07032BBD1B8
		16r19A4C116B8D2D0C8 16r1E376C085141AB53 16r2748774CDF8EEB99 16r34B0BCB5E19B48A8
		16r391C0CB3C5C95A63 16r4ED8AA4AE3418ACB 16r5B9CCA4F7763E373 16r682E6FF3D6B2B8A3
		16r748F82EE5DEFB2FC 16r78A5636F43172F60 16r84C87814A1F0AB72 16r8CC702081A6439EC
		16r90BEFFFA23631E28 16rA4506CEBDE82BDE9 16rBEF9A3F7B2C67915 16rC67178F2E372532B
		16rCA273ECEEA26619C 16rD186B8C721C0C207 16rEADA7DD6CDE0EB1E 16rF57D4F7FEE6ED178
		16r06F067AA72176FBA 16r0A637DC5A2C898A6 16r113F9804BEF90DAE 16r1B710B35131C471B
		16r28DB77F523047D84 16r32CAAB7B40C72493 16r3C9EBE0A15C9BEBC 16r431D67C49C100D4C
		16r4CC5D4BECB3E42B6 16r597F299CFC657E2A 16r5FCB6FAB3AD6FAEC 16r6C44198C4A475817).
	KHigh := k collect: [:each | each bitShift: -32].
	KLow := k collect: [:each | each bitAnd: 16rFFFFFFFF]
! !

!SHA512 class methodsFor: 'accessing'!
digestSize
	^64
!
blockSize
	^128
!
lengthSize
	^16
! !

!SHA512 methodsFor: 'initialization'!
resetState
	state := self initialState copy.
	high := Array new: 80.
	low := Array new: 80
!
initialState
	"H(0), high and low halves of each word."
	^#(16r6A09E667 16rF3BCC908 16rBB67AE85 16r84CAA73B 16r3C6EF372 16rFE94F82B 16rA54FF53A 16r5F1D36F1
		16r510E527F 16rADE682D1 16r9B05688C 16r2B3E6C1F 16r1F83D9AB 16rFB41BD6B 16r5BE0CD19 16r137E2179)
!
postCopy
	super postCopy.
	state := state copy.
	high := Array new: 80.
	low := Array new: 80
! !

!SHA512 methodsFor: 'private'!
processBlock: bytes at: offset
	| wh wl kh kl i xh xl s0h s0l s1h s1l ah al bh bl ch cl dh dl eh el fh fl gh gl hh hl t1h t1l t2h t2l |
	wh := high.
	wl := low.
	kh := KHigh.
	kl := KLow.
	i := offset.
	1 to: 16 do: [:j |
		wh at: j put: ((((bytes at: i + 1) bitShift: 24) bitOr: ((bytes at: i + 2) bitShift: 16)) bitOr: (((bytes at: i + 3) bitShift: 8) bitOr: (bytes at: i + 4))).
		wl at: j put: ((((bytes at: i + 5) bitShift: 24) bitOr: ((bytes at: i + 6) bitShift: 16)) bitOr: (((bytes at: i + 7) bitShift: 8) bitOr: (bytes at: i + 8))).
		i := i + 8].
	17 to: 80 do: [:j |
		"σ0: rotr 1, rotr 8, shr 7; σ1: rotr 19, rotr 61, shr 6"
		xh := wh at: j - 15.
		xl := wl at: j - 15.
		s0h := (((xh bitShift: -1) bitXor: (xh bitShift: -8)) bitXor: (xh bitShift: -7)) bitXor: ((((xl bitAnd: 1) bitShift: 31) bitXor: (xl bitShift: 24)) bitAnd: 16rFFFFFFFF).
		s0l := (((xl bitShift: -1) bitXor: (xl bitShift: -8)) bitXor: (xl bitShift: -7)) bitXor: (((((xh bitAnd: 1) bitShift: 31) bitXor: (xh bitShift: 24)) bitXor: (xh bitShift: 25)) bitAnd: 16rFFFFFFFF).
		xh := wh at: j - 2.
		xl := wl at: j - 2.
		s1h := (((xh bitShift: -19) bitXor: (xl bitShift: -29)) bitXor: (xh bitShift: -6)) bitXor: (((xl bitShift: 13) bitXor: (xh bitShift: 3)) bitAnd: 16rFFFFFFFF).
		s1l := (((xl bitShift: -19) bitXor: (xh bitShift: -29)) bitXor: (xl bitShift: -6)) bitXor: ((((xh bitShift: 13) bitXor: (xl bitShift: 3)) bitXor: (xh bitShift: 26)) bitAnd: 16rFFFFFFFF).
		t1l := s1l + (wl at: j - 7) + s0l + (wl at: j - 16).
		wl at: j put: (t1l bitAnd: 16rFFFFFFFF).
		wh at: j put: (s1h + (wh at: j - 7) + s0h + (wh at: j - 16) + (t1l bitShift: -32) bitAnd: 16rFFFFFFFF)].
	ah := state at: 1. al := state at: 2. bh := state at: 3. bl := state at: 4.
	ch := state at: 5. cl := state at: 6. dh := state at: 7. dl := state at: 8.
	eh := state at: 9. el := state at: 10. fh := state at: 11. fl := state at: 12.
	gh := state at: 13. gl := state at: 14. hh := state at: 15. hl := state at: 16.
	1 to: 80 do: [:j |
		"Σ1: rotr 14, rotr 18, rotr 41; Σ0: rotr 28, rotr 34, rotr 39"
		s1h := (((eh bitShift: -14) bitXor: (eh bitShift: -18)) bitXor: (el bitShift: -9)) bitXor: ((((el bitShift: 18) bitXor: (el bitShift: 14)) bitXor: (eh bitShift: 23)) bitAnd: 16rFFFFFFFF).
		s1l := (((el bitShift: -14) bitXor: (el bitShift: -18)) bitXor: (eh bitShift: -9)) bitXor: ((((eh bitShift: 18) bitXor: (eh bitShift: 14)) bitXor: (el bitShift: 23)) bitAnd: 16rFFFFFFFF).
		t1l := hl + s1l + (gl bitXor: (el bitAnd: (fl bitXor: gl))) + (kl at: j) + (wl at: j).
		t1h := hh + s1h + (gh bitXor: (eh bitAnd: (fh bitXor: gh))) + (kh at: j) + (wh at: j).
		s0h := (((ah bitShift: -28) bitXor: (al bitShift: -2)) bitXor: (al bitShift: -7)) bitXor: ((((al bitShift: 4) bitXor: (ah bitShift: 30)) bitXor: (ah bitShift: 25)) bitAnd: 16rFFFFFFFF).
		s0l := (((al bitShift: -28) bitXor: (ah bitShift: -2)) bitXor: (ah bitShift: -7)) bitXor: ((((ah bitShift: 4) bitXor: (al bitShift: 30)) bitXor: (al bitShift: 25)) bitAnd: 16rFFFFFFFF).
		t2l := s0l + ((al bitAnd: bl) bitOr: (cl bitAnd: (al bitOr: bl))).
		t2h := s0h + ((ah bitAnd: bh) bitOr: (ch bitAnd: (ah bitOr: bh))).
		hh := gh. hl := gl.
		gh := fh. gl := fl.
		fh := eh. fl := el.
		el := dl + t1l.
		eh := dh + t1h + (el bitShift: -32) bitAnd: 16rFFFFFFFF.
		el := el bitAnd: 16rFFFFFFFF.
		dh := ch. dl := cl.
		ch := bh. cl := bl.
		bh := ah. bl := al.
		al := t1l + t2l.
		ah := t1h + t2h + (al bitShift: -32) bitAnd: 16rFFFFFFFF.
		al := al bitAnd: 16rFFFFFFFF].
	self add: ah low: al at: 1.
	self add: bh low: bl at: 3.
	self add: ch low: cl at: 5.
	self add: dh low: dl at: 7.
	self add: eh low: el at: 9.
	self add: fh low: fl at: 11.
	self add: gh low: gl at: 13.
	self add: hh low: hl at: 15
!
add: h low: l at: index
	| sum |
	sum := (state at: index + 1) + l.
	state at: index + 1 put: (sum bitAnd: 16rFFFFFFFF).
	state at: index put: ((state at: index) + h + (sum bitShift: -32) bitAnd: 16rFFFFFFFF)
!
digestBytes
	| out |
	out := ByteArray new: self class digestSize.
	1 to: out size // 4 do: [:i | out netUint32At: i * 4 - 3 put: (state at: i)].
	^out
! !
