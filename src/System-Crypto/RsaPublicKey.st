Object subclass: #RsaPublicKey
	instanceVariableNames: 'modulus exponent'
	classVariableNames: ''
	package: 'System-Crypto'!

RsaPublicKey comment: 'I am an RSA public key (RFC 8017): a modulus and a public exponent. I verify signatures: RSASSA-PKCS1-v1_5 (the encoded DigestInfo rebuilt and compared byte for byte, NULL parameters required) and RSASSA-PSS (MGF1 with the same hash; the salt as long as the hash, as TLS 1.3 requires, or of a given length, or any). The hash is a class with hash: and digestSize (SHA256, SHA384, SHA512); DigestInfo is chosen by its digestSize. Every verify answers a Boolean; malformed signatures are false, never an error.

	key := RsaPublicKey modulus: n exponent: 65537.
	key verifyPkcs1: signature message: bytes hash: SHA256.
	key verifyPss: signature message: bytes hash: SHA256.	"salt length = 32"
	key verifyPss: signature message: bytes hash: SHA256 saltLength: nil.	"any salt length"

Verification uses the VM''s LargeInteger primitives (s^e mod n); it handles no secrets, so timing does not matter. Moduli of 1024 to 8192 bits are accepted (TLS uses 2048 to 4096).'!

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
	| prefix em k t expected |
	prefix := self class digestInfoPrefixFor: hashClass.
	(prefix isNil or: [digest size ~= hashClass digestSize]) ifTrue: [^false].
	em := self recover: signature length: self byteLength.
	em isNil ifTrue: [^false].
	k := self byteLength.
	t := prefix size + digest size.
	k < (t + 11) ifTrue: [^false].
	expected := ByteArray new: k.
	expected atAllPut: 255.
	expected at: 1 put: 0; at: 2 put: 1; at: k - t put: 0.
	expected replaceFrom: k - t + 1 to: k - digest size with: prefix startingAt: 1.
	expected replaceFrom: k - digest size + 1 to: k with: digest startingAt: 1.
	^em = expected
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
	| hLen emBits emLen em maskedDB h zeroBits db i salt mPrime |
	hLen := hashClass digestSize.
	mHash size = hLen ifFalse: [^false].
	emBits := modulus highBit - 1.
	emLen := emBits + 7 // 8.
	em := self recover: signature length: emLen.
	em isNil ifTrue: [^false].
	emLen < (hLen + (saltLength ifNil: [0]) + 2) ifTrue: [^false].
	(em at: emLen) = 16rBC ifFalse: [^false].
	maskedDB := em copyFrom: 1 to: emLen - hLen - 1.
	h := em copyFrom: emLen - hLen to: emLen - 1.
	zeroBits := 8 * emLen - emBits.
	(maskedDB at: 1) < (1 bitShift: 8 - zeroBits) ifFalse: [^false].
	db := self class mgf1: h length: maskedDB size hash: hashClass.
	1 to: db size do: [:j | db at: j put: ((db at: j) bitXor: (maskedDB at: j))].
	db at: 1 put: ((db at: 1) bitAnd: (255 bitShift: zeroBits negated)).
	i := 1.
	[i <= db size and: [(db at: i) = 0]] whileTrue: [i := i + 1].
	(i <= db size and: [(db at: i) = 1]) ifFalse: [^false].
	salt := db copyFrom: i + 1 to: db size.
	(saltLength notNil and: [salt size ~= saltLength]) ifTrue: [^false].
	mPrime := (ByteArray new: 8), mHash, salt.
	^(hashClass hash: mPrime) = h
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
	exponent := e
!
recover: signature length: length
	"s^e mod n of the signature as length big-endian bytes; nil unless the signature is k bytes and less than n, or if the result does not fit."
	| s m |
	signature size = self byteLength ifFalse: [^nil].
	s := self class integerFromBytes: signature.
	s >= modulus ifTrue: [^nil].
	m := s raisedTo: exponent modulo: modulus.
	^self class bytesOf: m length: length
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
mgf1: seed length: length hash: hashClass
	"MGF1 of RFC 8017, appendix B.2.1."
	| out counter block |
	out := WriteStream on: (ByteArray new: length + hashClass digestSize).
	counter := 0.
	[out position < length] whileTrue: [
		block := seed, (self bytesOf: counter length: 4).
		out nextPutAll: (hashClass hash: block).
		counter := counter + 1].
	^out contents copyFrom: 1 to: length
!
digestInfoPrefixFor: hashClass
	"The DER of DigestInfo up to the digest (RFC 8017, section 9.2, note 1), for SHA-256, -384 or -512 by digest size; nil for another."
	hashClass digestSize = 32 ifTrue: [^#[16r30 16r31 16r30 16r0D 16r06 16r09 16r60 16r86 16r48 16r01 16r65 16r03 16r04 16r02 16r01 16r05 16r00 16r04 16r20]].
	hashClass digestSize = 48 ifTrue: [^#[16r30 16r41 16r30 16r0D 16r06 16r09 16r60 16r86 16r48 16r01 16r65 16r03 16r04 16r02 16r02 16r05 16r00 16r04 16r30]].
	hashClass digestSize = 64 ifTrue: [^#[16r30 16r51 16r30 16r0D 16r06 16r09 16r60 16r86 16r48 16r01 16r65 16r03 16r04 16r02 16r03 16r05 16r00 16r04 16r40]].
	^nil
! !
