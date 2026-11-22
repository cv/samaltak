TestCase subclass: #TLSCodecTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSCodecTest comment: 'I check TLS''s presentation language (TLSReader, TLSWriter), the ServerHello decoder, the alert names and the cipher suites.'!

!TLSCodecTest methodsFor: 'tests'!
testWriter
	self assert: (TLSWriter new u8: 1; u16: 16r0203; u24: 16r040506; contents) equals: #[1 2 3 4 5 6].
	self assert: (TLSWriter new vector8: #[9 9]; vector16: #[7]; vector24: #[]; contents) equals: #[2 9 9 0 1 7 0 0 0].
	self assert: (TLSWriter new vector16Do: [:w | w u16: 16r1301; vector8Do: [:v | v u8: 5]]; contents) equals: #[0 4 16r13 1 1 5].
	self should: [TLSWriter new vector8: (ByteArray new: 256)] raise: TLSError
!
testReader
	| r sub |
	r := TLSReader on: #[1 2 3 4 5 6 7 8 9 10 2 11 12].
	self assert: r u8 equals: 1.
	self assert: r u16 equals: 16r0203.
	self assert: r u24 equals: 16r040506.
	self assert: r u32 equals: 16r0708090A.
	sub := r reader8.
	self assert: sub u16 equals: 16r0B0C.
	self assert: sub atEnd.
	self assert: r atEnd.
	r expectEnd
!
testReaderBounds
	self should: [(TLSReader on: #[1]) u16] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #decodeError].
	self should: [(TLSReader on: #[0 5 1 2]) vector16] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #decodeError].
	self should: [(TLSReader on: #[3 1 2 3 4]) vector8; expectEnd] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #decodeError].
	"a vector's reader stops at its end even when bytes follow"
	self should: [(TLSReader on: #[1 7 8]) reader8 u16] raise: TLSError
!
testExtensions
	| extensions |
	extensions := (TLSReader on: #[0 10 0 43 0 2 3 4 0 0 0 0]) extensions.
	self assert: (extensions at: 43) equals: #[3 4].
	self assert: (extensions at: 0) equals: #[].
	self should: [(TLSReader on: #[0 8 0 1 0 0 0 1 0 0]) extensions] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #illegalParameter]
!
testServerHello
	| body sh |
	body := TLSWriter new u16: 16r0303; bytes: (ByteArray new: 32 withAll: 1); vector8: #[5 6]; u16: 16r1302; u8: 0;
		vector16Do: [:w | w u16: 43; vector16: #[3 4]; u16: 51; vector16: #[0 16r1D 0 2 9 9]]; contents.
	sh := TLSServerHello fromBody: body.
	self deny: sh isHelloRetryRequest.
	self assert: sh sessionId equals: #[5 6].
	self assert: sh cipherSuite equals: 16r1302.
	self assert: sh selectedVersion equals: 16r0304.
	self assert: sh keyShare equals: {16r1D. #[9 9]}.
	self assert: sh cookie isNil.
	self should: [TLSServerHello fromBody: (body copyFrom: 1 to: body size - 1)] raise: TLSError
!
testHelloRetryRandom
	self assert: TLSServerHello helloRetryRandom equals: (SHA256 hash: 'HelloRetryRequest' asByteArray)
!
testAlerts
	self assert: (TLSError codeOf: #decodeError) equals: 50.
	self assert: (TLSError nameOf: 40) equals: #handshakeFailure.
	self assert: (TLSError nameOf: 200) equals: 200.
	self assert: (TLSError wireNameOf: #badRecordMac) equals: 'bad_record_mac'.
	self should: [TLSError peerAlert: 48] raise: TLSError withExceptionDo: [:e |
		self assert: e isFromPeer.
		self assert: e messageText equals: 'the server sent the alert unknown_ca']
!
testCipherSuites
	self assert: (TLSCipherSuite all collect: [:each | each code]) equals: #(16r1301 16r1303 16r1302 16rC02B 16rC02F 16rCCA9 16rCCA8 16rC02C 16rC030).
	self assert: (TLSCipherSuite tls13 allSatisfy: [:each | each isTLS13]).
	self assert: (TLSCipherSuite tls12 noneSatisfy: [:each | each isTLS13]).
	self assert: (TLSCipherSuite withCode: 16r1302) hashSize equals: 48.
	self assert: (TLSCipherSuite withCode: 16r1302) keySize equals: 32.
	self assert: (TLSCipherSuite withCode: 16r1304) isNil
!
bytesFrom: first to: last
	| bytes |
	bytes := ByteArray new: last - first + 1.
	1 to: bytes size do: [:i | bytes at: i put: first + i - 1].
	^bytes
!
testTls12Prf
	"The master secret (RFC 5246, section 8.1) as openssl kdf TLS1-PRF computes it."
	| ks |
	ks := TLS12KeySchedule suite: TLSCipherSuite ecdheRsaAes128GcmSha256.
	ks masterSecret: (self bytesFrom: 0 to: 47) clientRandom: (ByteArray new: 32 withAll: 16rAA) serverRandom: (ByteArray new: 32 withAll: 16rBB).
	self assert: ks masterSecret equals: (ByteArray fromHex: '44e5f0258adc3771e2041e1d3cc9f6033bfd16bd5982e25fb155e8338d76f17aaff929c218e691a5de6aeb3ee36a8df7').
	ks := TLS12KeySchedule suite: TLSCipherSuite ecdheRsaAes256GcmSha384.
	ks masterSecret: (self bytesFrom: 0 to: 47) clientRandom: (ByteArray new: 32 withAll: 16rAA) serverRandom: (ByteArray new: 32 withAll: 16rBB).
	self assert: ks masterSecret equals: (ByteArray fromHex: '4d579bbfd34de90f4f44157a715f581dcc7d6d38876335e97bea6a9711d15bc92f34f95bacb16ca294f70d31562f6adb')
!
testTls12RecordCiphers
	"AES-GCM with its explicit nonce (RFC 5288) and ChaCha20-Poly1305 (RFC 7905), the sixth record (sequence number 5), as Python's cryptography seals it."
	| gcm chacha record |
	gcm := [TLS12RecordCipher aead: (AesGcm key: (self bytesFrom: 0 to: 15)) iv: #[16rA0 16rA1 16rA2 16rA3] explicitNonce: true].
	chacha := [TLS12RecordCipher aead: (ChaCha20Poly1305 key: (self bytesFrom: 0 to: 31)) iv: (self bytesFrom: 16r40 to: 16r4B) explicitNonce: false].
	{gcm. '0000000000000005b97bffd249f365b2c605cef51c7ce1daae808c1c503c73b9b6bbbc2fb047'.
	 chacha. '2d41a6c8780a82fb3bd48350b53502b683462f54b507d007907392dc245c'} pairsDo: [:make :hex | | sealer opener expected tampered |
		sealer := make value.
		5 timesRepeat: [sealer seal: #[] type: 23 padding: 0].
		expected := ByteArray fromHex: hex.
		record := sealer seal: 'hello, TLS 1.2' type: 23 padding: 0.
		self assert: record equals: #[23 3 3 0], (ByteArray with: expected size), expected.
		opener := make value.
		5 timesRepeat: [opener seal: #[] type: 23 padding: 0].
		self assert: (opener open: (record copyFrom: 6 to: record size) header: (record copyFrom: 1 to: 5)) equals: {23. 'hello, TLS 1.2' asByteArray}.
		opener := make value.
		5 timesRepeat: [opener seal: #[] type: 23 padding: 0].
		tampered := record copy.
		tampered at: tampered size put: ((tampered at: tampered size) bitXor: 1).
		self should: [opener open: (tampered copyFrom: 6 to: tampered size) header: (tampered copyFrom: 1 to: 5)] raise: TLSError withExceptionDo: [:e |
			self assert: e alert equals: #badRecordMac]]
! !
