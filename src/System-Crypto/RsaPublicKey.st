Object subclass: #RsaPublicKey
	instanceVariableNames: 'modulus exponent handle'
	classVariableNames: ''
	package: 'System-Crypto'!

RsaPublicKey comment: 'I am an RSA public key (RFC 8017): a modulus and a public exponent. I verify signatures: RSASSA-PKCS1-v1_5 (the encoded DigestInfo rebuilt and compared byte for byte, NULL parameters required) and RSASSA-PSS (MGF1 with the same hash; the salt as long as the hash, as TLS 1.3 requires, or of a given length, or any). The hash is a class with hash: and digestSize (SHA256, SHA384, SHA512); DigestInfo is chosen by its digestSize. Every verify answers a Boolean; malformed signatures are false, never an error.

	key := RsaPublicKey modulus: n exponent: 65537.
	key verifyPkcs1: signature message: bytes hash: SHA256.
	key verifyPss: signature message: bytes hash: SHA256.	"salt length = 32"
	key verifyPss: signature message: bytes hash: SHA256 saltLength: nil.	"any salt length"

The VM verifies (CryptoExports: libcrypto, hosted; none on UEFI), from my DER SubjectPublicKeyInfo, under a handle it keeps. Moduli of 1024 to 8192 bits are accepted (TLS uses 2048 to 4096).'!

!RsaPublicKey methodsFor: 'accessing'!
modulus
	^modulus
!
exponent
	^exponent
!
bitLength
	^modulus highBit
!
byteLength
	"k of RFC 8017: the length of the modulus and of signatures, in bytes."
	^modulus highBit + 7 // 8
! !

!RsaPublicKey methodsFor: 'verifying'!
verifyPkcs1: signature message: message hash: hashClass
	"Whether signature is message's RSASSA-PKCS1-v1_5 signature with hashClass."
	^self verifyPkcs1: signature digest: (hashClass hash: message) hash: hashClass
!
verifyPkcs1: signature digest: digest hash: hashClass
	"Whether signature is RSASSA-PKCS1-v1_5 of the precomputed digest."
	^self verify: signature digest: digest hash: hashClass scheme: 1 saltLength: nil
!
verifyPss: signature message: message hash: hashClass
	"Whether signature is message's RSASSA-PSS signature with hashClass, MGF1 with hashClass and a salt as long as the hash (TLS 1.3's rsa_pss_rsae_* and rsa_pss_pss_*)."
	^self verifyPss: signature message: message hash: hashClass saltLength: hashClass digestSize
!
verifyPss: signature message: message hash: hashClass saltLength: saltLength
	"As verifyPss:message:hash:, with a salt of saltLength bytes, or of any length if saltLength is nil."
	^self verifyPss: signature digest: (hashClass hash: message) hash: hashClass saltLength: saltLength
!
verifyPss: signature digest: mHash hash: hashClass saltLength: saltLength
	"EMSA-PSS-VERIFY of RFC 8017, section 9.1.2, on the precomputed digest mHash."
	^self verify: signature digest: mHash hash: hashClass scheme: 2 saltLength: saltLength
! !

!RsaPublicKey methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [modulus = anObject modulus and: [exponent = anObject exponent]]
!
hash
	^modulus hash bitXor: exponent hash
! !

!RsaPublicKey methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an RsaPublicKey ('; print: self bitLength; nextPutAll: ' bits, e = '; print: exponent; nextPut: $)
! !

!RsaPublicKey methodsFor: 'private'!
setModulus: n exponent: e
	modulus := n.
	exponent := e.
	handle := Array new: 2
!
verify: signature digest: digest hash: hashClass scheme: scheme saltLength: saltLength
	"The VM's verification (CryptoExports) of a signature k bytes long, of a digest of hashClass's size."
	| params r |
	(signature size = self byteLength and: [digest size = hashClass digestSize]) ifFalse: [^false].
	(saltLength notNil and: [saltLength < 0]) ifTrue: [^false].
	params := scheme + (hashClass algorithm bitShift: 4) + ((saltLength ifNil: [-1]) + 1 bitShift: 8).
	r := [CryptoExports
		withKey: handle
		make: [CryptoExports publicKey: self subjectPublicKeyInfo]
		do: [:h | CryptoExports verify: h params: params digest: digest signature: signature]]
			on: CryptoError do: [:e | e return: 0].
	^r = 1
!
subjectPublicKeyInfo
	"My DER SubjectPublicKeyInfo (RFC 8017, A.1.1): rsaEncryption, then RSAPublicKey in a BIT STRING."
	| c key |
	c := self class.
	key := c der: 16r30 of: (c derInteger: modulus) , (c derInteger: exponent).
	^c der: 16r30 of: #[16r30 16r0D 16r06 16r09 16r2A 16r86 16r48 16r86 16rF7 16r0D 16r01 16r01 16r01 16r05 16r00] ,
		(c der: 16r03 of: #[0] , key)
! !

!RsaPublicKey class methodsFor: 'instance creation'!
modulus: n exponent: e
	"A key of modulus n (an odd Integer of 1024 to 8192 bits) and public exponent e (odd, at least 3, less than n). CryptoError otherwise."
	(n isInteger and: [e isInteger]) ifFalse: [^CryptoError signal: 'RSA: the modulus and the exponent are Integers'].
	(n odd and: [n highBit between: 1024 and: 8192]) ifFalse: [^CryptoError signal: 'RSA: unsupported modulus (', n highBit printString, ' bits)'].
	(e odd and: [e >= 3 and: [e < n]]) ifFalse: [^CryptoError signal: 'RSA: bad public exponent'].
	^self new setModulus: n exponent: e
! !

!RsaPublicKey class methodsFor: 'encoding'!
integerFromBytes: bytes
	"The unsigned big-endian Integer bytes encode (OS2IP)."
	| n |
	n := 0.
	bytes do: [:b | n := (n bitShift: 8) + b].
	^n
!
bytesOf: anInteger length: length
	"anInteger as length big-endian bytes (I2OSP), nil if it does not fit."
	| out |
	anInteger digitLength > length ifTrue: [^nil].
	out := ByteArray new: length.
	1 to: anInteger digitLength do: [:i | out at: length + 1 - i put: (anInteger digitAt: i)].
	^out
!
der: tag of: contents
	"The DER of contents with tag: tag, the length (definite, minimal), contents."
	| n length |
	n := contents size.
	length := n < 128
		ifTrue: [ByteArray with: n]
		ifFalse: [(ByteArray with: 128 + n digitLength) , (self bytesOf: n length: n digitLength)].
	^(ByteArray with: tag) , length , contents
!
derInteger: aPositiveInteger
	"The DER INTEGER of aPositiveInteger: big-endian, a 0 in front if its top bit is set."
	| bytes |
	bytes := self bytesOf: aPositiveInteger length: (aPositiveInteger digitLength max: 1).
	(bytes at: 1) >= 128 ifTrue: [bytes := #[0] , bytes].
	^self der: 16r02 of: bytes
! !
