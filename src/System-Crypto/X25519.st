Object subclass: #X25519
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

X25519 comment: 'I am the X25519 Diffie-Hellman function of RFC 7748, computed by the VM (CryptoExports: libcrypto, hosted; none on UEFI). Keys and shared secrets are 32-byte ByteArrays, little-endian as the RFC encodes them. My class side is the API:

	priv := X25519 newPrivateKey.	"32 bytes of SecureRandom"
	pub := X25519 publicKeyFor: priv.
	secret := X25519 sharedSecret: priv peer: theirPublicKey.	"CryptoError if all zeros (a key of small order)"
	X25519 scalar: k u: u.	"the bare function"'!

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
	| r |
	(privateKey size = 32 and: [peerPublicKey size = 32]) ifFalse: [^CryptoError signal: 'X25519: keys are 32 bytes'].
	r := CryptoExports x25519: privateKey u: peerPublicKey.
	r last ifTrue: [^CryptoError signal: 'X25519: the shared secret is zero (a public key of small order)'].
	^r first
!
scalar: k u: u
	"The function X25519(k, u) of RFC 7748, section 5, on 32-byte strings."
	(k size = 32 and: [u size = 32]) ifFalse: [^CryptoError signal: 'X25519: keys are 32 bytes'].
	^(CryptoExports x25519: k u: u) first
! !

!X25519 class methodsFor: 'constants'!
basePoint
	^(ByteArray new: 32) at: 1 put: 9; yourself
! !
