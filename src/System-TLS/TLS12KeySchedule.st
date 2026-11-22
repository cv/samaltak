Object subclass: #TLS12KeySchedule
	instanceVariableNames: 'suite masterSecret clientKey serverKey clientIv serverIv'
	classVariableNames: ''
	package: 'System-TLS'!

TLS12KeySchedule comment: 'I am the key derivation of a TLS 1.2 connection (RFC 5246, sections 5, 6.3, 7.4.9 and 8.1) with an AEAD cipher suite: the PRF (P_hash with the suite''s hash), the master secret from the premaster secret (the ECDHE shared secret) and the randoms, or with extended_master_secret from the session hash (RFC 7627), the key block (client and server write keys and IVs), the record ciphers (TLS12RecordCipher) and the verify_data of a Finished.

	ks := TLS12KeySchedule suite: TLSCipherSuite ecdheRsaAes128GcmSha256.
	ks extendedMasterSecret: ecdhe sessionHash: hash.
	ks deriveKeysClientRandom: clientRandom serverRandom: serverRandom.
	ks clientCipher; serverCipher; verifyData: ''client finished'' transcriptHash: hash'!

!TLS12KeySchedule methodsFor: 'initialization'!
setSuite: aCipherSuite
	suite := aCipherSuite
! !

!TLS12KeySchedule methodsFor: 'accessing'!
suite
	^suite
!
masterSecret
	^masterSecret
! !

!TLS12KeySchedule methodsFor: 'deriving'!
prf: secret label: aString seed: seed length: count
	"PRF(secret, label, seed) (section 5): P_hash of the suite's hash, count bytes."
	| labelSeed a out |
	labelSeed := aString asByteArray, seed.
	out := WriteStream on: (ByteArray new: count + 64).
	a := labelSeed.
	[out position < count] whileTrue: [
		a := HMAC hash: suite hashClass key: secret message: a.
		out nextPutAll: (HMAC hash: suite hashClass key: secret message: a, labelSeed)].
	^out contents copyFrom: 1 to: count
!
masterSecret: premasterSecret clientRandom: clientRandom serverRandom: serverRandom
	masterSecret := self prf: premasterSecret label: 'master secret' seed: clientRandom, serverRandom length: 48
!
extendedMasterSecret: premasterSecret sessionHash: aHash
	"RFC 7627: the master secret bound to the hash of the handshake up to ClientKeyExchange."
	masterSecret := self prf: premasterSecret label: 'extended master secret' seed: aHash length: 48
!
deriveKeysClientRandom: clientRandom serverRandom: serverRandom
	"The key block (section 6.3): client and server write keys, then client and server IVs (no MAC keys with an AEAD)."
	| k i block |
	k := suite keySize.
	i := suite fixedIvSize.
	block := self prf: masterSecret label: 'key expansion' seed: serverRandom, clientRandom length: 2 * k + (2 * i).
	clientKey := block copyFrom: 1 to: k.
	serverKey := block copyFrom: k + 1 to: 2 * k.
	clientIv := block copyFrom: 2 * k + 1 to: 2 * k + i.
	serverIv := block copyFrom: 2 * k + i + 1 to: 2 * k + (2 * i)
!
clientCipher
	^TLS12RecordCipher aead: (suite aeadWithKey: clientKey) iv: clientIv explicitNonce: suite explicitNonceSize > 0
!
serverCipher
	^TLS12RecordCipher aead: (suite aeadWithKey: serverKey) iv: serverIv explicitNonce: suite explicitNonceSize > 0
!
verifyData: aString transcriptHash: aHash
	"The verify_data of a Finished (section 7.4.9): aString is 'client finished' or 'server finished'."
	^self prf: masterSecret label: aString seed: aHash length: 12
! !

!TLS12KeySchedule class methodsFor: 'instance creation'!
suite: aCipherSuite
	^self new setSuite: aCipherSuite
! !
