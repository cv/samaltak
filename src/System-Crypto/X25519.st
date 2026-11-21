Object subclass: #X25519
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

X25519 comment: 'I am the X25519 Diffie-Hellman function of RFC 7748: Curve25519''s Montgomery ladder on u-coordinates. Keys and shared secrets are 32-byte ByteArrays, little-endian as the RFC encodes them. My class side is the API:

	priv := X25519 newPrivateKey.
	pub := X25519 publicKeyFor: priv.
	secret := X25519 sharedSecret: priv peer: peerPublicKey.	"CryptoError if it is all zeros (RFC 7748, section 6.1)"

Not constant-time: the field arithmetic is the VM''s LargeInteger primitives, whose running time and allocations depend on the values, and the conditional swaps are branches. Fine for ephemeral TLS keys against a network observer at our timer resolution; not for long-term keys where an attacker can time many operations.'!

!X25519 class methodsFor: 'key agreement'!
newPrivateKey
	"32 random bytes: a private key (clamped when used, as the RFC says)."
	^SecureRandom default nextBytes: 32
!
publicKeyFor: privateKey
	"The public key of privateKey: X25519 of it and the base point, u = 9."
	^self scalar: privateKey u: self basePoint
!
sharedSecret: privateKey peer: peerPublicKey
	"The shared secret of privateKey and the peer's public key. CryptoError if it is all zeros: the peer's key is of small order."
	| secret |
	secret := self scalar: privateKey u: peerPublicKey.
	(secret allSatisfy: [:b | b = 0]) ifTrue: [^CryptoError signal: 'X25519: the shared secret is zero (a public key of small order)'].
	^secret
!
scalar: k u: u
	"The function X25519(k, u) of RFC 7748, section 5, on 32-byte strings."
	(k size = 32 and: [u size = 32]) ifFalse: [^CryptoError signal: 'X25519: keys are 32 bytes'].
	^self encode: (self ladder: (self decodeScalar: k) u: (self decodeU: u))
! !

!X25519 class methodsFor: 'constants'!
basePoint
	^(ByteArray new: 32) at: 1 put: 9; yourself
!
prime
	"2^255 - 19"
	^(1 bitShift: 255) - 19
! !

!X25519 class methodsFor: 'private'!
decodeScalar: bytes
	"The clamped scalar: low 3 bits cleared, bit 255 cleared, bit 254 set."
	| k |
	k := 0.
	32 to: 1 by: -1 do: [:i | k := (k bitShift: 8) + (bytes at: i)].
	^((k bitAnd: ((1 bitShift: 255) - 8)) bitOr: (1 bitShift: 254))
!
decodeU: bytes
	"The u-coordinate: little-endian, the top bit masked off, reduced modulo p (non-canonical values are accepted)."
	| u |
	u := (bytes at: 32) bitAnd: 127.
	31 to: 1 by: -1 do: [:i | u := (u bitShift: 8) + (bytes at: i)].
	^u \\ self prime
!
encode: anInteger
	| out |
	out := ByteArray new: 32.
	1 to: 32 do: [:i | out at: i put: (anInteger digitAt: i)].
	^out
!
ladder: k u: u
	"The Montgomery ladder of RFC 7748, section 5, with a24 = 121665. The swaps are branches: not constant-time."
	| p x1 x2 z2 x3 z3 swap kt a aa b bb e c d da cb t |
	p := self prime.
	x1 := u. x2 := 1. z2 := 0. x3 := u. z3 := 1.
	swap := 0.
	254 to: 0 by: -1 do: [:i |
		kt := (k bitShift: i negated) bitAnd: 1.
		(swap bitXor: kt) = 1 ifTrue: [
			t := x2. x2 := x3. x3 := t.
			t := z2. z2 := z3. z3 := t].
		swap := kt.
		a := x2 + z2.
		aa := a * a \\ p.
		b := x2 - z2.
		bb := b * b \\ p.
		e := aa - bb.
		c := x3 + z3.
		d := x3 - z3.
		da := d * a \\ p.
		cb := c * b \\ p.
		x3 := da + cb.
		x3 := x3 * x3 \\ p.
		z3 := da - cb.
		z3 := z3 * z3 \\ p * x1 \\ p.
		x2 := aa * bb \\ p.
		z2 := 121665 * e + aa * e \\ p].
	swap = 1 ifTrue: [x2 := x3. z2 := z3].
	^x2 * (z2 raisedTo: p - 2 modulo: p) \\ p
! !
