Object subclass: #EcPrivateKey
	instanceVariableNames: 'curve scalar'
	classVariableNames: ''
	package: 'System-Crypto'!

EcPrivateKey comment: 'I am an elliptic-curve private key on an EcCurve (P-256, P-384) for ECDH (SEC 1, section 3.3.1; TLS 1.3''s secp256r1 and secp384r1 key shares): a scalar in [1, n-1].

	key := EcPrivateKey newOn: #p256.
	key publicKeyBytes.	"04 || X || Y, the key share to send"
	key sharedSecret: peerPublicKeyBytes.	"X of the shared point, a ByteArray as long as a field element; CryptoError unless the peer''s point is on the curve"

Not constant-time (EcCurve''s double-and-add branches on the scalar''s bits; the arithmetic is the VM''s LargeInteger primitives): acceptable for ephemeral keys, used once, as TLS uses them; not for long-term keys.'!

!EcPrivateKey methodsFor: 'accessing'!
curve
	^curve
!
publicKeyBytes
	"My public key, uncompressed."
	| xy |
	xy := curve toAffine: (curve multiply: curve generator by: scalar).
	^curve encodeX: (xy at: 1) y: (xy at: 2)
!
publicKey
	^EcPublicKey curve: curve name point: self publicKeyBytes
! !

!EcPrivateKey methodsFor: 'key agreement'!
sharedSecret: peerPublicKeyBytes
	"The ECDH shared secret with the peer's uncompressed public key: the x-coordinate of my scalar times its point."
	| xy shared out |
	xy := curve decodePoint: peerPublicKeyBytes.
	xy isNil ifTrue: [^CryptoError signal: 'ECDH: the peer''s public key is not an uncompressed point on ', curve name].
	shared := curve toAffine: (curve multiply: {xy at: 1. xy at: 2. 1} by: scalar).
	shared isNil ifTrue: [^CryptoError signal: 'ECDH: the shared point is infinity'].
	out := ByteArray new: curve byteLength.
	1 to: curve byteLength do: [:i | out at: curve byteLength + 1 - i put: ((shared at: 1) digitAt: i)].
	^out
! !

!EcPrivateKey methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an EcPrivateKey ('; print: curve name; nextPut: $)
! !

!EcPrivateKey methodsFor: 'private'!
setCurve: anEcCurve scalar: anInteger
	curve := anEcCurve.
	scalar := anInteger
! !

!EcPrivateKey class methodsFor: 'instance creation'!
curve: aSymbol scalar: bytes
	"The key of the big-endian scalar bytes on the curve aSymbol (#p256, #p384). CryptoError unless it is in [1, n-1]."
	| c d |
	c := EcCurve named: aSymbol.
	d := 0.
	bytes do: [:b | d := (d bitShift: 8) + b].
	(d between: 1 and: c order - 1) ifFalse: [^CryptoError signal: 'EC: private scalar out of range'].
	^self new setCurve: c scalar: d
!
newOn: aSymbol
	"A random key on the curve aSymbol: a scalar from SecureRandom, retried until it is in [1, n-1] (at most a few times on P-256 and P-384)."
	| c bytes d |
	c := EcCurve named: aSymbol.
	[bytes := SecureRandom default nextBytes: c byteLength.
	 d := 0.
	 bytes do: [:b | d := (d bitShift: 8) + b].
	 d between: 1 and: c order - 1] whileFalse.
	^self new setCurve: c scalar: d
! !
