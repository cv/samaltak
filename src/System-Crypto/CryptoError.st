Error subclass: #CryptoError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Crypto'!

CryptoError comment: 'I am signaled when a cryptographic operation fails: an AEAD''s tag that does not verify (the plaintext is not answered), a key or nonce of the wrong size, a request a primitive cannot fulfil (HKDF beyond 255 blocks), no source of entropy. messageText says which.'!
