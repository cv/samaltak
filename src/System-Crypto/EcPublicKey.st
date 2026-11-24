Object subclass: #EcPublicKey
	instanceVariableNames: 'curve x y handle'
	classVariableNames: ''
	package: 'System-Crypto'!

EcPublicKey comment: 'I am an elliptic-curve public key, a point on an EcCurve (P-256 or P-384), and I verify ECDSA signatures (FIPS 186-4 / SEC 1) in their DER encoding, SEQUENCE { INTEGER r, INTEGER s }, as X.509 and TLS carry them. The DER must be strict (minimal lengths and integers, nothing after it); r and s must be in [1, n-1]. A digest longer than the order is truncated to its leftmost bits. Every verify answers a Boolean.

	key := EcPublicKey curve: #p256 point: uncompressedBytes.	"04 || X || Y; CryptoError unless on the curve"
	key verify: derSignature message: bytes hash: SHA256.
	key verify: derSignature digest: digestBytes.

The VM verifies (CryptoExports: libcrypto hosted, mbedTLS on UEFI), from my DER SubjectPublicKeyInfo, under a handle it keeps; the signature''s DER and the range of r and s are checked here first, the same for both.'!

!EcPublicKey methodsFor: 'accessing'!
curve
	^curve
!
x
	^x
!
y
	^y
!
bytes
	"The uncompressed encoding: 04 || X || Y."
	^curve encodeX: x y: y
! !

!EcPublicKey methodsFor: 'verifying'!
verify: derSignature message: message hash: hashClass
	"Whether derSignature is message's ECDSA signature with hashClass."
	^self verify: derSignature digest: (hashClass hash: message)
!
verify: derSignature digest: digest
	"Whether derSignature is ECDSA's on the precomputed digest (of SHA-256, -384 or -512, by its size)."
	| rs n hash r |
	rs := self class decodeSignature: derSignature.
	rs isNil ifTrue: [^false].
	n := curve order.
	(rs allSatisfy: [:each | each between: 1 and: n - 1]) ifFalse: [^false].
	hash := #(32 48 64) indexOf: digest size.
	hash = 0 ifTrue: [^false].
	r := [CryptoExports
		withKey: handle
		make: [CryptoExports publicKey: self subjectPublicKeyInfo]
		do: [:h | CryptoExports verify: h params: 3 + (hash bitShift: 4) digest: digest signature: derSignature]]
			on: CryptoError do: [:e | e return: 0].
	^r = 1
! !

!EcPublicKey methodsFor: 'encoding'!
subjectPublicKeyInfo
	"My DER SubjectPublicKeyInfo (RFC 5480): id-ecPublicKey, the named curve, the uncompressed point."
	^(curve name == #p256
		ifTrue: [#[16r30 16r59 16r30 16r13 16r06 16r07 16r2A 16r86 16r48 16rCE 16r3D 16r02 16r01 16r06 16r08 16r2A 16r86 16r48 16rCE 16r3D 16r03 16r01 16r07 16r03 16r42 16r00]]
		ifFalse: [#[16r30 16r76 16r30 16r10 16r06 16r07 16r2A 16r86 16r48 16rCE 16r3D 16r02 16r01 16r06 16r05 16r2B 16r81 16r04 16r00 16r22 16r03 16r62 16r00]]) , self bytes
! !

!EcPublicKey methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [curve == anObject curve and: [x = anObject x and: [y = anObject y]]]
!
hash
	^x hash bitXor: y hash
! !

!EcPublicKey methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an EcPublicKey ('; print: curve name; nextPut: $)
! !

!EcPublicKey methodsFor: 'private'!
setCurve: anEcCurve x: px y: py
	curve := anEcCurve.
	x := px.
	y := py.
	handle := Array new: 2
! !

!EcPublicKey class methodsFor: 'instance creation'!
curve: aSymbol point: bytes
	"The key of the uncompressed point bytes on the curve named aSymbol (#p256 or #p384). CryptoError if it is not a point on the curve."
	| c xy |
	c := EcCurve named: aSymbol.
	xy := c decodePoint: bytes.
	xy isNil ifTrue: [^CryptoError signal: 'EC: not an uncompressed point on ', c name].
	^self new setCurve: c x: (xy at: 1) y: (xy at: 2)
! !

!EcPublicKey class methodsFor: 'encoding'!
decodeSignature: der
	"{r. s} of a strict DER Ecdsa-Sig-Value, nil if der is not one. Lengths are short-form: up to P-384 a signature is at most 104 bytes."
	| pos r s readInteger |
	(der size >= 8 and: [(der at: 1) = 16r30 and: [(der at: 2) = (der size - 2)]]) ifFalse: [^nil].
	(der at: 2) < 128 ifFalse: [^nil].
	pos := 3.
	readInteger := [:dummy | | len value |
		(pos + 1 <= der size and: [(der at: pos) = 2]) ifFalse: [^nil].
		len := der at: pos + 1.
		(len between: 1 and: 127) ifFalse: [^nil].
		pos + 1 + len <= der size ifFalse: [^nil].
		(der at: pos + 2) >= 128 ifTrue: [^nil].
		(len > 1 and: [(der at: pos + 2) = 0 and: [(der at: pos + 3) < 128]]) ifTrue: [^nil].
		value := 0.
		pos + 2 to: pos + 1 + len do: [:i | value := (value bitShift: 8) + (der at: i)].
		pos := pos + 2 + len.
		value].
	r := readInteger value: nil.
	s := readInteger value: nil.
	pos = (der size + 1) ifFalse: [^nil].
	^{r. s}
! !
