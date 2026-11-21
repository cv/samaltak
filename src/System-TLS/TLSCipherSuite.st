Object subclass: #TLSCipherSuite
	instanceVariableNames: 'code name hash keySize aead'
	classVariableNames: ''
	package: 'System-TLS'!

TLSCipherSuite comment: 'I am a TLS 1.3 cipher suite (RFC 8446, section B.4): an AEAD with its key size and the hash of the key schedule and the transcript. all answers the ones the client offers, in its order of preference; withCode: one of them by its number.

	TLSCipherSuite aes128GcmSha256 code	"16r1301"
	(TLSCipherSuite withCode: 16r1303) name	"''TLS_CHACHA20_POLY1305_SHA256''"'!

!TLSCipherSuite methodsFor: 'initialization'!
setCode: anInteger name: aString hash: aHashClass keySize: keyBytes aead: anAeadClass
	code := anInteger.
	name := aString.
	hash := aHashClass.
	keySize := keyBytes.
	aead := anAeadClass
! !

!TLSCipherSuite methodsFor: 'accessing'!
code
	^code
!
name
	^name
!
hashClass
	"The hash class (SHA256, SHA384)."
	^hash
!
hashSize
	^hash digestSize
!
keySize
	^keySize
!
ivSize
	^12
!
tagSize
	^16
!
aeadWithKey: key
	"An AEAD of my algorithm keyed with key."
	^aead key: key
! !

!TLSCipherSuite methodsFor: 'comparing'!
= other
	^(other isKindOf: TLSCipherSuite) and: [code = other code]
!
hash
	^code hash
! !

!TLSCipherSuite methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: name
! !

!TLSCipherSuite class methodsFor: 'suites'!
aes128GcmSha256
	^self new setCode: 16r1301 name: 'TLS_AES_128_GCM_SHA256' hash: SHA256 keySize: 16 aead: AesGcm
!
aes256GcmSha384
	^self new setCode: 16r1302 name: 'TLS_AES_256_GCM_SHA384' hash: SHA384 keySize: 32 aead: AesGcm
!
chacha20Poly1305Sha256
	^self new setCode: 16r1303 name: 'TLS_CHACHA20_POLY1305_SHA256' hash: SHA256 keySize: 32 aead: ChaCha20Poly1305
!
all
	"The suites the client offers, the one it prefers first."
	^{self aes128GcmSha256. self chacha20Poly1305Sha256. self aes256GcmSha384}
!
withCode: anInteger
	"The suite numbered anInteger, or nil if I do not know it."
	^self all detect: [:each | each code = anInteger] ifNone: [nil]
! !
