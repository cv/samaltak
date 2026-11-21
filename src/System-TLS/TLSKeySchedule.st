Object subclass: #TLSKeySchedule
	instanceVariableNames: 'suite handshakeSecret masterSecret clientHandshakeSecret serverHandshakeSecret clientApplicationSecret serverApplicationSecret'
	classVariableNames: ''
	package: 'System-TLS'!

TLSKeySchedule comment: 'I am the TLS 1.3 key schedule (RFC 8446, section 7.1) of a cipher suite, for a full handshake with (EC)DHE and no PSK: startWithSharedSecret:transcriptHash: derives the handshake secret and the handshake traffic secrets from the shared secret and the hash of ClientHello...ServerHello; deriveApplicationSecrets: the application traffic secrets from the hash up to the server''s Finished. Then: the Finished MAC of a traffic secret (verifyData:transcriptHash:), the record keys of one (cipherFor:: a TLSRecordCipher), and the next one after a KeyUpdate (updateClientApplicationSecret, updateServerApplicationSecret). Secrets are ByteArrays of the suite''s hash size.

	ks := TLSKeySchedule suite: TLSCipherSuite aes128GcmSha256.
	ks startWithSharedSecret: ecdhe transcriptHash: helloHash.
	reader := ks cipherFor: ks serverHandshakeSecret'!

!TLSKeySchedule methodsFor: 'initialization'!
setSuite: aCipherSuite
	suite := aCipherSuite
! !

!TLSKeySchedule methodsFor: 'accessing'!
suite
	^suite
!
handshakeSecret
	^handshakeSecret
!
masterSecret
	^masterSecret
!
clientHandshakeSecret
	^clientHandshakeSecret
!
serverHandshakeSecret
	^serverHandshakeSecret
!
clientApplicationSecret
	^clientApplicationSecret
!
serverApplicationSecret
	^serverApplicationSecret
! !

!TLSKeySchedule methodsFor: 'deriving'!
startWithSharedSecret: sharedSecret transcriptHash: helloHash
	"Derive the handshake traffic secrets: helloHash is the transcript hash of ClientHello...ServerHello."
	| zeros early |
	zeros := ByteArray new: suite hashSize.
	early := HKDF hash: suite hashClass extract: zeros ikm: zeros.
	handshakeSecret := HKDF hash: suite hashClass extract: (self deriveSecret: early label: 'derived' transcriptHash: self emptyHash) ikm: sharedSecret.
	clientHandshakeSecret := self deriveSecret: handshakeSecret label: 'c hs traffic' transcriptHash: helloHash.
	serverHandshakeSecret := self deriveSecret: handshakeSecret label: 's hs traffic' transcriptHash: helloHash.
	masterSecret := HKDF hash: suite hashClass extract: (self deriveSecret: handshakeSecret label: 'derived' transcriptHash: self emptyHash) ikm: zeros
!
deriveApplicationSecrets: finishedHash
	"Derive the application traffic secrets: finishedHash is the transcript hash of ClientHello...server Finished."
	clientApplicationSecret := self deriveSecret: masterSecret label: 'c ap traffic' transcriptHash: finishedHash.
	serverApplicationSecret := self deriveSecret: masterSecret label: 's ap traffic' transcriptHash: finishedHash
!
updateClientApplicationSecret
	clientApplicationSecret := self nextTrafficSecret: clientApplicationSecret
!
updateServerApplicationSecret
	serverApplicationSecret := self nextTrafficSecret: serverApplicationSecret
!
nextTrafficSecret: aSecret
	"application_traffic_secret_N+1 (section 7.2)."
	^self expand: aSecret label: 'traffic upd' context: #[] length: suite hashSize
!
verifyData: trafficSecret transcriptHash: aHash
	"The verify_data of a Finished (section 4.4.4): the HMAC of the transcript hash with the finished key of trafficSecret."
	^HMAC hash: suite hashClass key: (self expand: trafficSecret label: 'finished' context: #[] length: suite hashSize) message: aHash
!
cipherFor: trafficSecret
	"A TLSRecordCipher with the record key and IV of trafficSecret (section 7.3), at sequence number 0."
	^TLSRecordCipher
		aead: (suite aeadWithKey: (self trafficKeyOf: trafficSecret))
		iv: (self trafficIvOf: trafficSecret)
!
trafficKeyOf: trafficSecret
	^self expand: trafficSecret label: 'key' context: #[] length: suite keySize
!
trafficIvOf: trafficSecret
	^self expand: trafficSecret label: 'iv' context: #[] length: suite ivSize
!
deriveSecret: aSecret label: aString transcriptHash: aHash
	"Derive-Secret (section 7.1), given the transcript hash."
	^self expand: aSecret label: aString context: aHash length: suite hashSize
!
expand: aSecret label: aString context: aByteArray length: anInteger
	"HKDF-Expand-Label (section 7.1)."
	| info |
	info := TLSWriter new
		u16: anInteger;
		vector8: ('tls13 ', aString) asByteArray;
		vector8: aByteArray;
		contents.
	^HKDF hash: suite hashClass expand: aSecret info: info length: anInteger
!
emptyHash
	^suite hashClass hash: #[]
! !

!TLSKeySchedule class methodsFor: 'instance creation'!
suite: aCipherSuite
	^self new setSuite: aCipherSuite
! !
