TestCase subclass: #EcPublicKeyTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

EcPublicKeyTest comment: 'Tests ECDSA verification (EcPublicKey, EcCurve) on P-256 and P-384 against Wycheproof subsets (WycheproofVectors: malformed DER, r or s out of range, edge-case arithmetic), and the curves'' parameters and point decoding.'!

!EcPublicKeyTest methodsFor: 'tests'!
testP256Sha256
	self check: WycheproofVectors ecdsaP256Sha256 curve: #p256 hash: SHA256
!
testP384Sha384
	self check: WycheproofVectors ecdsaP384Sha384 curve: #p384 hash: SHA384
!
testP384Sha256
	self check: WycheproofVectors ecdsaP384Sha256 curve: #p384 hash: SHA256
!
testCurves
	#(#p256 #p384) do: [:name | | c g |
		c := EcCurve named: name.
		g := c generator.
		self assert: (c isOnCurveX: (g at: 1) y: (g at: 2)).
		self assert: ((c multiply: g by: c order) at: 3) equals: 0.
		self assert: (c toAffine: (c multiply: g by: 2)) equals: (c toAffine: (c add: g to: g)).
		self assert: (c toAffine: (c multiply: g by: 5)) equals: (c toAffine: (c add: (c double: (c double: g)) to: g))].
	self assert: (EcCurve named: #secp256r1) == (EcCurve named: #p256).
	self should: [EcCurve named: #p521] raise: CryptoError
!
testPointDecoding
	| c g bytes |
	c := EcCurve named: #p256.
	g := c generator.
	bytes := c encodeX: (g at: 1) y: (g at: 2).
	self assert: bytes size equals: 65.
	self assert: (EcPublicKey curve: #p256 point: bytes) bytes equals: bytes.
	bytes at: 65 put: ((bytes at: 65) bitXor: 1).
	self should: [EcPublicKey curve: #p256 point: bytes] raise: CryptoError.
	self should: [EcPublicKey curve: #p256 point: (bytes copyFrom: 1 to: 33)] raise: CryptoError.
	self should: [EcPublicKey curve: #p384 point: (c encodeX: (g at: 1) y: (g at: 2))] raise: CryptoError
!
testSignatureEncoding
	self assert: (EcPublicKey decodeSignature: #[16r30 6 2 1 1 2 1 2]) equals: #(1 2).
	self assert: (EcPublicKey decodeSignature: #[16r30 7 2 2 0 128 2 1 2]) equals: #(128 2).
	self assert: (EcPublicKey decodeSignature: #[16r30 7 2 2 0 1 2 1 2]) isNil description: 'leading zero'.
	self assert: (EcPublicKey decodeSignature: #[16r30 6 2 1 129 2 1 2]) isNil description: 'negative'.
	self assert: (EcPublicKey decodeSignature: #[16r30 7 2 1 1 2 1 2 0]) isNil description: 'trailing byte'.
	self assert: (EcPublicKey decodeSignature: #[16r30 16r81 6 2 1 1 2 1 2]) isNil description: 'long form length'.
	self assert: (EcPublicKey decodeSignature: #[16r31 6 2 1 1 2 1 2]) isNil description: 'not a SEQUENCE'
! !

!EcPublicKeyTest methodsFor: 'private'!
check: rows curve: curveName hash: hashClass
	| count |
	count := 0.
	rows do: [:row | | key ok |
		key := EcPublicKey curve: curveName point: (ByteArray fromHex: (row at: 2)).
		ok := key verify: (ByteArray fromHex: (row at: 4)) message: (ByteArray fromHex: (row at: 3)) hash: hashClass.
		self assert: ok = (row at: 5) description: 'Wycheproof tcId ', (row at: 1) printString.
		count := count + 1].
	self assert: count > 10
! !
