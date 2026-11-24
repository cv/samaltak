Object subclass: #CryptoAead
	instanceVariableNames: 'key handle'
	classVariableNames: ''
	package: 'System-Crypto'!

CryptoAead comment: 'I am an authenticated cipher of the VM''s (CryptoExports), AesGcm or ChaCha20Poly1305: (AesGcm key: k) encrypt: plaintext nonce: n aad: a answers the ciphertext with the 16-byte tag appended; decrypt: data nonce: n aad: a answers the plaintext, or signals CryptoError if the tag does not verify (nothing decrypted is answered then). Each is one call of the VM, sealing or opening a copy of the text in place under my key''s handle, which the VM keeps (made again when it dropped it or in a new session of the image). A subclass says its algorithm (CryptoExports'' number), checks its keys (checkKey:) and nonces (checkNonce:).'!

!CryptoAead class methodsFor: 'instance creation'!
key: aByteArray
	self checkKey: aByteArray.
	^self new setKey: aByteArray
! !

!CryptoAead class methodsFor: 'accessing'!
algorithm
	^self subclassResponsibility
!
nonceSize
	^12
!
tagSize
	^16
!
checkKey: aByteArray
	^self subclassResponsibility
!
checkNonce: aByteArray
	^self subclassResponsibility
!
maxPlaintextSize
	"RFC 8439's limit: 2^32 blocks of 64 bytes, but the first."
	^(1 bitShift: 38) - 64
! !

!CryptoAead methodsFor: 'initialization'!
setKey: aByteArray
	key := aByteArray copy.
	handle := Array new: 2
! !

!CryptoAead methodsFor: 'encrypting'!
encrypt: plaintext nonce: nonce aad: aad
	| text r |
	self class checkNonce: nonce.
	plaintext size > self class maxPlaintextSize ifTrue: [^CryptoError signal: self class name, ': longer than the cipher allows'].
	text := ByteArray new: plaintext size + 16.
	text replaceFrom: 1 to: plaintext size with: plaintext startingAt: 1.
	r := self run: text nonce: nonce aad: aad open: false.
	r = text size ifFalse: [^CryptoError signal: self class name, ': sealing failed'].
	^text
!
decrypt: data nonce: nonce aad: aad
	| text r |
	self class checkNonce: nonce.
	data size < 16 ifTrue: [^CryptoError signal: self class name, ': shorter than a tag'].
	data size - 16 > self class maxPlaintextSize ifTrue: [^CryptoError signal: self class name, ': longer than the cipher allows'].
	text := data copy.
	r := self run: text nonce: nonce aad: aad open: true.
	r = (data size - 16) ifFalse: [^CryptoError signal: self class name, ': the tag does not verify'].
	^text copyFrom: 1 to: r
! !

!CryptoAead methodsFor: 'private'!
run: text nonce: nonce aad: aad open: aBoolean
	| nonceAad |
	nonceAad := aad isEmpty ifTrue: [nonce] ifFalse: [nonce , aad].
	^[CryptoExports
		withKey: handle
		make: [CryptoExports aeadKey: self class algorithm bytes: key]
		do: [:h | CryptoExports aead: h + (nonce size bitShift: 24) + (aBoolean ifTrue: [1 bitShift: 40] ifFalse: [0]) nonceAad: nonceAad text: text]]
			on: CryptoError do: [:e | e return: -1]
! !
