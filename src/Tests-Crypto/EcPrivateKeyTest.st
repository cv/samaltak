TestCase subclass: #EcPrivateKeyTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

EcPrivateKeyTest comment: 'Tests ECDH on P-256 (EcPrivateKey) against a Wycheproof subset (WycheproofVectors ecdhP256: points not on the curve, bad encodings, edge-case coordinates), and that two keys agree.'!

!EcPrivateKeyTest methodsFor: 'tests'!
testWycheproof
	| count |
	count := 0.
	WycheproofVectors ecdhP256 do: [:row | | shared |
		shared := [(EcPrivateKey curve: #p256 scalar: (ByteArray fromHex: (row at: 2))) sharedSecret: (ByteArray fromHex: (row at: 3))]
			on: CryptoError do: [:e | nil].
		self assert: (shared = (ByteArray fromHex: (row at: 4))) = (row at: 5) description: 'Wycheproof tcId ', (row at: 1) printString.
		count := count + 1].
	self assert: count > 10
!
testAgreement
	#(#p256 #p384) do: [:name | | a b |
		a := EcPrivateKey curve: name scalar: #[1 2 3 4 5 6 7 8 9].
		b := EcPrivateKey curve: name scalar: #[255 254 253 252 251 250].
		self assert: (a sharedSecret: b publicKeyBytes) equals: (b sharedSecret: a publicKeyBytes).
		self assert: (a sharedSecret: b publicKeyBytes) size equals: a curve byteLength.
		self assert: a publicKey curve equals: a curve]
!
testRandomKeys
	#(#p256 #p384) do: [:name | | a b |
		a := EcPrivateKey newOn: name.
		b := EcPrivateKey newOn: name.
		self deny: a publicKeyBytes = b publicKeyBytes.
		self assert: (a sharedSecret: b publicKeyBytes) equals: (b sharedSecret: a publicKeyBytes)]
!
testBadKeys
	| a |
	self should: [EcPrivateKey curve: #p256 scalar: #[0]] raise: CryptoError.
	self should: [EcPrivateKey curve: #p256 scalar: (ByteArray new: 32 withAll: 255)] raise: CryptoError.
	a := EcPrivateKey curve: #p256 scalar: #[42].
	self should: [a sharedSecret: (ByteArray new: 65)] raise: CryptoError.
	self should: [a sharedSecret: ((EcPrivateKey curve: #p384 scalar: #[42]) publicKeyBytes)] raise: CryptoError
! !
