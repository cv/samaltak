Object subclass: #ChaCha20Poly1305
	instanceVariableNames: 'key'
	classVariableNames: ''
	package: 'System-Crypto'!

ChaCha20Poly1305 comment: 'I am the AEAD_CHACHA20_POLY1305 of RFC 8439 (2.8), TLS 1.3''s TLS_CHACHA20_POLY1305_SHA256: (ChaCha20Poly1305 key: k32) encrypt: plaintext nonce: n12 aad: a answers the ciphertext with the 16-byte tag appended; decrypt: data nonce: n aad: a answers the plaintext, or signals CryptoError if the tag does not verify (compared in constant time, before anything is decrypted). The Poly1305 key is the first half of ChaCha20''s block 0, the plaintext is encrypted from block 1; the tag covers the aad and the ciphertext, each padded to 16 bytes, and their lengths. Class side: keySize, nonceSize, tagSize.'!

!ChaCha20Poly1305 class methodsFor: 'instance creation'!
key: aByteArray
	aByteArray size = self keySize ifFalse: [^CryptoError signal: 'ChaCha20-Poly1305: the key must be 32 bytes'].
	^self new setKey: aByteArray
! !

!ChaCha20Poly1305 class methodsFor: 'accessing'!
keySize
	^32
!
nonceSize
	^12
!
tagSize
	^16
! !

!ChaCha20Poly1305 methodsFor: 'initialization'!
setKey: aByteArray
	key := aByteArray copy
! !

!ChaCha20Poly1305 methodsFor: 'encrypting'!
encrypt: plaintext nonce: nonce aad: aad
	| cipher otk out |
	cipher := ChaCha20 key: key nonce: nonce.
	otk := cipher nextBlock.
	out := ByteArray new: plaintext size + 16.
	cipher xor: plaintext from: 1 to: plaintext size into: out at: 1.
	out replaceFrom: plaintext size + 1 to: out size with: (self tag: out size: plaintext size aad: aad key: otk) startingAt: 1.
	^out
!
decrypt: data nonce: nonce aad: aad
	| cipher otk n tag |
	cipher := ChaCha20 key: key nonce: nonce.
	data size < 16 ifTrue: [^CryptoError signal: 'ChaCha20-Poly1305: shorter than a tag'].
	otk := cipher nextBlock.
	n := data size - 16.
	tag := self tag: data size: n aad: aad key: otk.
	(tag constantTimeEquals: (data copyFrom: n + 1 to: data size)) ifFalse: [^CryptoError signal: 'ChaCha20-Poly1305: the tag does not verify'].
	^cipher xor: data from: 1 to: n into: (ByteArray new: n) at: 1
! !

!ChaCha20Poly1305 methodsFor: 'private'!
tag: ciphertext size: n aad: aad key: block0
	| mac a lengths |
	a := aad ifNil: [#[]].
	mac := Poly1305 key: (block0 copyFrom: 1 to: 32).
	mac update: a.
	mac update: (ByteArray new: 16 - (a size \\ 16) \\ 16).
	mac update: ciphertext from: 1 to: n.
	mac update: (ByteArray new: 16 - (n \\ 16) \\ 16).
	lengths := ByteArray new: 16.
	lengths uint32At: 1 put: (a size bitAnd: 16rFFFFFFFF); uint32At: 5 put: (a size bitShift: -32).
	lengths uint32At: 9 put: (n bitAnd: 16rFFFFFFFF); uint32At: 13 put: (n bitShift: -32).
	mac update: lengths.
	^mac digest
! !
