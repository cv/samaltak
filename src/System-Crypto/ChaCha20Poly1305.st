CryptoAead subclass: #ChaCha20Poly1305
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

ChaCha20Poly1305 comment: 'I am the AEAD_CHACHA20_POLY1305 of RFC 8439 (2.8), TLS''s ChaCha20-Poly1305 suites: (ChaCha20Poly1305 key: k32) with a 12-byte nonce; encrypt:nonce:aad: and decrypt:nonce:aad: as CryptoAead. The VM does it (CryptoExports). Class side: keySize, nonceSize, tagSize.'!

!ChaCha20Poly1305 class methodsFor: 'accessing'!
algorithm
	^2
!
keySize
	^32
!
checkKey: aByteArray
	aByteArray size = 32 ifFalse: [^CryptoError signal: 'ChaCha20-Poly1305: the key must be 32 bytes']
!
checkNonce: aByteArray
	aByteArray size = 12 ifFalse: [^CryptoError signal: 'ChaCha20-Poly1305: the nonce must be 12 bytes']
! !
