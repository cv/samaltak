TestCase subclass: #RsaPublicKeyTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Crypto'!

RsaPublicKeyTest comment: 'Tests RsaPublicKey: RSASSA-PKCS1-v1_5 with SHA-256, -384 and -512 on 2048-, 3072- and 4096-bit keys, RSASSA-PSS with salts of 32, 48 and 0 bytes, against Wycheproof subsets (WycheproofVectors), and refusing unusable keys.'!

!RsaPublicKeyTest methodsFor: 'tests'!
testPkcs1Sha256
	self check: WycheproofVectors rsaPkcs1Rsa2048Sha256 pss: false hash: SHA256 salt: nil
!
testPkcs1Sha384
	self check: WycheproofVectors rsaPkcs1Rsa3072Sha384 pss: false hash: SHA384 salt: nil
!
testPkcs1Sha512
	self check: WycheproofVectors rsaPkcs1Rsa4096Sha512 pss: false hash: SHA512 salt: nil
!
testPssSha256
	self check: WycheproofVectors rsaPssRsa2048Sha256Salt32 pss: true hash: SHA256 salt: 32
!
testPssSha384
	self check: WycheproofVectors rsaPssRsa4096Sha384Salt48 pss: true hash: SHA384 salt: 48
!
testPssEmptySalt
	self check: WycheproofVectors rsaPssRsa2048Sha256Salt0 pss: true hash: SHA256 salt: 0
!
testPssSaltLength
	"verifyPss:message:hash: wants the salt as long as the hash; saltLength: nil takes any."
	| data row key msg sig |
	data := WycheproofVectors rsaPssRsa2048Sha256Salt0.
	row := data last detect: [:each | each last].
	key := self keyOf: row in: data.
	msg := ByteArray fromHex: (row at: 3).
	sig := ByteArray fromHex: (row at: 4).
	self deny: (key verifyPss: sig message: msg hash: SHA256).
	self assert: (key verifyPss: sig message: msg hash: SHA256 saltLength: nil).
	self assert: (key verifyPss: sig message: msg hash: SHA256 saltLength: 0).
	self deny: (key verifyPss: sig message: msg hash: SHA256 saltLength: 1)
!
testWrongHash
	| data row key msg sig |
	data := WycheproofVectors rsaPkcs1Rsa2048Sha256.
	row := data last detect: [:each | each last].
	key := self keyOf: row in: data.
	msg := ByteArray fromHex: (row at: 3).
	sig := ByteArray fromHex: (row at: 4).
	self assert: (key verifyPkcs1: sig message: msg hash: SHA256).
	self deny: (key verifyPkcs1: sig message: msg hash: SHA384).
	self deny: (key verifyPss: sig message: msg hash: SHA256).
	self deny: (key verifyPkcs1: sig message: msg, #[0] hash: SHA256)
!
testBadKeys
	self should: [RsaPublicKey modulus: (1 bitShift: 512) + 1 exponent: 65537] raise: CryptoError.
	self should: [RsaPublicKey modulus: (1 bitShift: 2048) exponent: 65537] raise: CryptoError.
	self should: [RsaPublicKey modulus: (1 bitShift: 2048) + 1 exponent: 1] raise: CryptoError.
	self should: [RsaPublicKey modulus: (1 bitShift: 2048) + 1 exponent: 65536] raise: CryptoError
! !

!RsaPublicKeyTest methodsFor: 'private'!
keyOf: row in: data
	| key |
	key := data first at: (row at: 2).
	^RsaPublicKey modulus: (self integerOf: (key at: 1)) exponent: (self integerOf: (key at: 2))
!
integerOf: hex
	| n |
	n := 0.
	(ByteArray fromHex: hex) do: [:b | n := (n bitShift: 8) + b].
	^n
!
check: data pss: isPss hash: hashClass salt: saltLength
	| count |
	count := 0.
	data last do: [:row | | key msg sig ok |
		key := [self keyOf: row in: data] on: CryptoError do: [:e | nil].
		msg := ByteArray fromHex: (row at: 3).
		sig := ByteArray fromHex: (row at: 4).
		ok := key notNil and: [isPss
			ifTrue: [key verifyPss: sig message: msg hash: hashClass saltLength: saltLength]
			ifFalse: [key verifyPkcs1: sig message: msg hash: hashClass]].
		self assert: ok = (row at: 5) description: 'Wycheproof tcId ', (row at: 1) printString.
		count := count + 1].
	self assert: count > 10
! !
