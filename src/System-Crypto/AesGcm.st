CryptoAead subclass: #AesGcm
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

AesGcm comment: 'I am AES in Galois/Counter Mode (NIST SP 800-38D), TLS''s AES-GCM suites: (AesGcm key: k) with a 16-, 24- or 32-byte key; encrypt:nonce:aad: and decrypt:nonce:aad: as CryptoAead. The nonce is 12 bytes in TLS; any other size up to 128 bytes (OpenSSL''s limit) is hashed into the first counter block, as the standard says; a longer one is a CryptoError. The VM does it (CryptoExports: libcrypto, hosted; none on UEFI; the CPU''s AES and carry-less multiplication instructions).'!

!AesGcm class methodsFor: 'accessing'!
algorithm
	^1
!
checkKey: aByteArray
	(#(16 24 32) includes: aByteArray size) ifFalse: [^CryptoError signal: 'AES: the key must be 16, 24 or 32 bytes']
!
checkNonce: aByteArray
	(aByteArray size between: 1 and: 128) ifFalse: [^CryptoError signal: 'AES-GCM: the nonce must be 1 to 128 bytes']
!
maxPlaintextSize
	"SP 800-38D, 5.2.1.1: at most 2^39 - 256 bits, 2^32 - 2 blocks, so that the 32-bit counter never wraps onto J0 and reuses the key stream."
	^(1 bitShift: 36) - 32
! !
