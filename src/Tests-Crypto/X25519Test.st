TestCase subclass: #X25519Test
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

X25519Test comment: 'Tests X25519 against RFC 7748 (section 5.2''s vectors, the iterated one to 1000 iterations, section 6.1''s Diffie-Hellman) and a Wycheproof subset (WycheproofVectors x25519: twists, non-canonical and small-order public keys).'!

!X25519Test methodsFor: 'tests'!
testRfc7748Vectors
	self
		assert: (X25519
			scalar: (ByteArray fromHex: 'a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4')
			u: (ByteArray fromHex: 'e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c'))
		equals: (ByteArray fromHex: 'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552').
	self
		assert: (X25519
			scalar: (ByteArray fromHex: '4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d')
			u: (ByteArray fromHex: 'e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493'))
		equals: (ByteArray fromHex: '95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957')
!
testIterated
	"RFC 7748, section 5.2: k and u start as 9; each round k, u := X25519(k, u), k."
	| k u next |
	k := X25519 basePoint.
	u := X25519 basePoint.
	1 to: 1000 do: [:i |
		next := X25519 scalar: k u: u.
		u := k.
		k := next.
		i = 1 ifTrue: [self assert: k equals: (ByteArray fromHex: '422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079')]].
	self assert: k equals: (ByteArray fromHex: '684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51')
!
testDiffieHellman
	"RFC 7748, section 6.1."
	| alice bob alicePublic bobPublic shared |
	alice := ByteArray fromHex: '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'.
	bob := ByteArray fromHex: '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb'.
	alicePublic := X25519 publicKeyFor: alice.
	bobPublic := X25519 publicKeyFor: bob.
	self assert: alicePublic equals: (ByteArray fromHex: '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a').
	self assert: bobPublic equals: (ByteArray fromHex: 'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f').
	shared := ByteArray fromHex: '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742'.
	self assert: (X25519 sharedSecret: alice peer: bobPublic) equals: shared.
	self assert: (X25519 sharedSecret: bob peer: alicePublic) equals: shared
!
testSmallOrderPeer
	"A public key of small order (here 0 and 1) makes the shared secret zero: refused."
	| priv |
	priv := ByteArray fromHex: '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'.
	self should: [X25519 sharedSecret: priv peer: (ByteArray new: 32)] raise: CryptoError.
	self should: [X25519 sharedSecret: priv peer: ((ByteArray new: 32) at: 1 put: 1; yourself)] raise: CryptoError
!
testWrongSizes
	self should: [X25519 scalar: (ByteArray new: 31) u: X25519 basePoint] raise: CryptoError.
	self should: [X25519 scalar: (ByteArray new: 32) u: (ByteArray new: 33)] raise: CryptoError
!
testWycheproof
	| count |
	count := 0.
	WycheproofVectors x25519 do: [:row | | shared |
		shared := [X25519 scalar: (ByteArray fromHex: (row at: 2)) u: (ByteArray fromHex: (row at: 3))] on: CryptoError do: [:e | nil].
		self assert: (shared = (ByteArray fromHex: (row at: 4))) = (row at: 5) description: 'Wycheproof x25519 tcId ', (row at: 1) printString.
		count := count + 1].
	self assert: count > 10
! !
