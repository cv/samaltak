Object subclass: #TLSCipherSuite
	instanceVariableNames: 'code name hash keySize aead version keyExchange'
	classVariableNames: ''
	package: 'System-TLS'!

TLSCipherSuite comment: 'I am a cipher suite: a TLS 1.3 one (RFC 8446, section B.4), an AEAD with its key size and the hash of the key schedule and the transcript, or a TLS 1.2 one (RFC 5289, RFC 7905) with ECDHE key exchange signed with an ECDSA or RSA key (keyExchange #ecdsa, #rsa), an AEAD and the hash of the PRF. all answers the ones the client offers, in its order of preference (TLS 1.3 first); tls13 and tls12 those of one version; withCode: one of them by its number.

	TLSCipherSuite aes128GcmSha256 code	"16r1301"
	(TLSCipherSuite withCode: 16r1303) name	"''TLS_CHACHA20_POLY1305_SHA256''"'!

!TLSCipherSuite methodsFor: 'initialization'!
setCode: anInteger name: aString hash: aHashClass keySize: keyBytes aead: anAeadClass
	code := anInteger.
	name := aString.
	hash := aHashClass.
	keySize := keyBytes.
	aead := anAeadClass.
	version := 16r0304
!
setTls12KeyExchange: aSymbol
	version := 16r0303.
	keyExchange := aSymbol
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
version
	"16r0304 (TLS 1.3) or 16r0303 (TLS 1.2)."
	^version
!
isTLS13
	^version = 16r0304
!
keyExchange
	"TLS 1.2: the key the server signs its ECDHE share with, #ecdsa or #rsa; nil for TLS 1.3."
	^keyExchange
!
fixedIvSize
	"TLS 1.2: the bytes of IV from the key block (RFC 5288: 4 for AES-GCM; RFC 7905: 12 for ChaCha20-Poly1305)."
	^aead == AesGcm ifTrue: [4] ifFalse: [12]
!
explicitNonceSize
	"TLS 1.2: the bytes of nonce sent in each record (8 for AES-GCM, none for ChaCha20-Poly1305)."
	^aead == AesGcm ifTrue: [8] ifFalse: [0]
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
ecdheEcdsaAes128GcmSha256
	^(self new setCode: 16rC02B name: 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256' hash: SHA256 keySize: 16 aead: AesGcm) setTls12KeyExchange: #ecdsa
!
ecdheRsaAes128GcmSha256
	^(self new setCode: 16rC02F name: 'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256' hash: SHA256 keySize: 16 aead: AesGcm) setTls12KeyExchange: #rsa
!
ecdheEcdsaAes256GcmSha384
	^(self new setCode: 16rC02C name: 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384' hash: SHA384 keySize: 32 aead: AesGcm) setTls12KeyExchange: #ecdsa
!
ecdheRsaAes256GcmSha384
	^(self new setCode: 16rC030 name: 'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384' hash: SHA384 keySize: 32 aead: AesGcm) setTls12KeyExchange: #rsa
!
ecdheEcdsaChacha20Poly1305Sha256
	^(self new setCode: 16rCCA9 name: 'TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256' hash: SHA256 keySize: 32 aead: ChaCha20Poly1305) setTls12KeyExchange: #ecdsa
!
ecdheRsaChacha20Poly1305Sha256
	^(self new setCode: 16rCCA8 name: 'TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256' hash: SHA256 keySize: 32 aead: ChaCha20Poly1305) setTls12KeyExchange: #rsa
!
all
	"The suites the client offers, the one it prefers first: TLS 1.3's, then TLS 1.2's."
	^self tls13, self tls12
!
tls13
	^{self aes128GcmSha256. self chacha20Poly1305Sha256. self aes256GcmSha384}
!
tls12
	"ECDHE and AEADs only (no RSA key exchange, CBC, RC4, 3DES, NULL or anonymous suites)."
	^{self ecdheEcdsaAes128GcmSha256. self ecdheRsaAes128GcmSha256. self ecdheEcdsaChacha20Poly1305Sha256.
		self ecdheRsaChacha20Poly1305Sha256. self ecdheEcdsaAes256GcmSha384. self ecdheRsaAes256GcmSha384}
!
withCode: anInteger
	"The suite numbered anInteger, or nil if I do not know it."
	^self all detect: [:each | each code = anInteger] ifNone: [nil]
! !
