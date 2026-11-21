TestCase subclass: #TLSClientConnectionTest
	instanceVariableNames: 'socket connection hellos'
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSClientConnectionTest comment: 'I check what the TLS client sends (the ClientHello: SNI, groups, key shares, signature algorithms, ALPN, versions, session id, cipher suites; the second one after a HelloRetryRequest, with change_cipher_spec before it) and how it fails against a scripted server (a TLSTestSocket that answers each ClientHello): a server that does not speak TLS, speaks TLS 1.2, breaks the rules of a ServerHello or HelloRetryRequest, sends an alert, an overlong record, the wrong message, closes, or says nothing until the deadline. Each failure signals TLSError, sends the right alert (none for timeouts and the server''s own alerts) and closes the socket.'!

!TLSClientConnectionTest methodsFor: 'running'!
setUp
	hellos := OrderedCollection new.
	socket := TLSTestSocket new.
	connection := TLSClientConnection on: socket host: 'example.com'
! !

!TLSClientConnectionTest methodsFor: 'support'!
respond: aBlock
	"Answer each ClientHello with what aBlock answers for it (a TLSClientHello)."
	socket responder: [:bytes :s |
		bytes first = 22 ifTrue: [| hello |
			hello := TLSClientHello fromBytes: (bytes copyFrom: 6 to: bytes size).
			hellos add: hello.
			s deliver: (aBlock value: hello)]]
!
record: bytes type: type
	^TLSWriter new u8: type; u16: 16r0303; vector16: bytes; contents
!
serverHello: hello random: random suite: code extensions: pairs
	^self record: (TLSWriter new u8: 2; vector24Do: [:w |
		w u16: 16r0303; bytes: random; vector8: hello sessionId; u16: code; u8: 0.
		pairs isNil ifFalse: [w vector16Do: [:x | pairs do: [:each | x u16: each key; vector16: each value]]]]; contents) type: 22
!
serverHello: hello extensions: pairs
	^self serverHello: hello random: (ByteArray new: 32) suite: 16r1301 extensions: pairs
!
helloRetry: hello extensions: pairs
	^self serverHello: hello random: TLSServerHello helloRetryRandom suite: 16r1301 extensions: pairs
!
version13
	^43 -> #[3 4]
!
keyShare: publicKey
	^51 -> (TLSWriter new u16: 16r1D; vector16: publicKey; contents)
!
failure
	"The TLSError the handshake signals."
	| error |
	error := [connection handshakeUntil: Time millisecondClockValue + 2000. nil] on: TLSError do: [:e | e return: e].
	self assert: error notNil.
	self deny: socket isOpen.
	self deny: connection isOpen.
	self assert: connection failure equals: error messageText.
	^error
!
assertAlert: aSymbol
	"The last thing sent was the plaintext alert aSymbol."
	| sent |
	sent := socket sent.
	self assert: (sent copyFrom: sent size - 6 to: sent size) equals: #[21 3 3 0 2 2], (ByteArray with: (TLSError codeOf: aSymbol))
!
assertNoAlert
	"Nothing was sent but the ClientHellos."
	self assert: socket sent size equals: (hellos inject: 0 into: [:sum :each | sum + each bytes size + 5])
! !

!TLSClientConnectionTest methodsFor: 'tests'!
testClientHello
	| hello |
	self respond: [:h | #[]].
	self failure.
	hello := hellos first.
	self assert: (socket sent copyFrom: 1 to: 3) equals: #[22 3 1].
	self assert: hello serverName equals: 'example.com'.
	self assert: hello cipherSuites equals: #(16r1301 16r1303 16r1302).
	self assert: hello groups first equals: 16r1D.
	self assert: hello keyShares size equals: 1.
	self assert: hello keyShares first first equals: 16r1D.
	self assert: hello keyShares first last size equals: 32.
	self assert: hello signatureSchemes equals: #(16r0804 16r0805 16r0403 16r0503 16r0401 16r0501).
	self assert: hello protocols equals: #('http/1.1').
	self assert: hello sessionId size equals: 32.
	self assert: hello random size equals: 32.
	self assert: hello cookie isNil.
	self assert: ((TLSClientHello fromBytes: hello bytes) extensionTypes asSet) equals: #(0 10 13 16 43 51) asSet.
	self assert: (TLSClientHello fromBytes: hello bytes) bytes equals: hello bytes
!
testClientHelloEncodingRoundTrips
	| hello again |
	hello := TLSClientHello new random: (ByteArray new: 32 withAll: 7); sessionId: #[1 2 3]; cipherSuites: #(16r1303); serverName: 'a.example';
		groups: #(16r1D 16r17); keyShares: {{16r1D. ByteArray new: 32 withAll: 9}}; signatureSchemes: #(16r0804); protocols: #('h2' 'http/1.1'); cookie: #[5 5].
	again := TLSClientHello fromBytes: hello bytes.
	self assert: again random equals: hello random.
	self assert: again sessionId equals: #[1 2 3].
	self assert: again cipherSuites equals: #(16r1303).
	self assert: again serverName equals: 'a.example'.
	self assert: again groups equals: #(16r1D 16r17).
	self assert: again keyShares first last equals: (ByteArray new: 32 withAll: 9).
	self assert: again protocols equals: #('h2' 'http/1.1').
	self assert: again cookie equals: #[5 5].
	self assert: again bytes equals: hello bytes
!
testNoServerNameForAddresses
	self assert: (TLSClientConnection serverNameFor: '10.0.2.2') isNil.
	self assert: (TLSClientConnection serverNameFor: '::1') isNil.
	self assert: (TLSClientConnection serverNameFor: 'example.com.') equals: 'example.com'.
	connection := TLSClientConnection on: socket host: '127.0.0.1'.
	self respond: [:h | #[]].
	self failure.
	self assert: hellos first serverName isNil.
	self deny: (hellos first extensionTypes includes: 0)
!
testNotTLS
	self respond: [:h | 'HTTP/1.1 400 Bad Request', String crlf, String crlf].
	self assert: (self failure messageText includesSubstring: 'not a TLS record').
	self assertAlert: #unexpectedMessage
!
testTLS12Server
	self respond: [:h | self serverHello: h extensions: #()].
	self assert: (self failure messageText includesSubstring: 'TLS 1.2').
	self assertAlert: #protocolVersion
!
testWrongVersion
	self respond: [:h | self serverHello: h extensions: {43 -> #[3 3]}].
	self failure.
	self assertAlert: #illegalParameter
!
testWrongSessionId
	self respond: [:h | | other |
		other := TLSClientHello new sessionId: (ByteArray new: 32); yourself.
		self serverHello: other extensions: {self version13. self keyShare: (ByteArray new: 32 withAll: 9)}].
	self assert: (self failure messageText includesSubstring: 'session id').
	self assertAlert: #illegalParameter
!
testCipherSuiteNotOffered
	connection cipherSuites: {TLSCipherSuite chacha20Poly1305Sha256}.
	self respond: [:h | self serverHello: h extensions: {self version13. self keyShare: (ByteArray new: 32 withAll: 9)}].
	self failure.
	self assert: hellos first cipherSuites equals: #(16r1303).
	self assertAlert: #illegalParameter
!
testExtensionNotOffered
	self respond: [:h | self serverHello: h extensions: {self version13. 999 -> #[]. self keyShare: (ByteArray new: 32 withAll: 9)}].
	self failure.
	self assertAlert: #unsupportedExtension
!
testOfferedExtensionInServerHello
	self respond: [:h | self serverHello: h extensions: {self version13. 16 -> #[0 9 8 104 116 116 112 47 49 46 49]. self keyShare: (ByteArray new: 32 withAll: 9)}].
	self failure.
	self assertAlert: #illegalParameter
!
testMissingKeyShare
	self respond: [:h | self serverHello: h extensions: {self version13}].
	self failure.
	self assertAlert: #missingExtension
!
testKeyShareOfTheWrongSize
	self respond: [:h | self serverHello: h extensions: {self version13. self keyShare: (ByteArray new: 31 withAll: 9)}].
	self failure.
	self assertAlert: #illegalParameter
!
testZeroKeyShare
	"A public key of small order makes the shared secret zero."
	self respond: [:h | self serverHello: h extensions: {self version13. self keyShare: (ByteArray new: 32)}].
	self failure.
	self assertAlert: #illegalParameter
!
testMalformedServerHello
	self respond: [:h | self record: #[2 0 0 3 3 3 0] type: 22].
	self failure.
	self assertAlert: #decodeError
!
testUnexpectedMessage
	self respond: [:h | self record: #[8 0 0 2 0 0] type: 22].
	self assert: (self failure messageText includesSubstring: 'expected ServerHello, got EncryptedExtensions').
	self assertAlert: #unexpectedMessage
!
testApplicationDataBeforeTheKeys
	self respond: [:h | self record: 'hello' type: 23].
	self failure.
	self assertAlert: #unexpectedMessage
!
testRecordOverflow
	self respond: [:h | #[22 3 3 16r40 16r01]].
	self failure.
	self assertAlert: #recordOverflow
!
testOverlongHandshakeMessage
	self respond: [:h | self record: #[2 16rFF 16rFF 16rFF] type: 22].
	self failure.
	self assertAlert: #decodeError
!
testServerAlert
	self respond: [:h | self record: #[2 40] type: 21].
	self assert: self failure messageText equals: 'the server sent the alert handshake_failure'.
	self assertNoAlert
!
testServerCloses
	self respond: [:h | #[]].
	self assert: self failure messageText equals: 'the server closed the connection'.
	self assertNoAlert
!
testTimeout
	| start |
	socket stall.
	self respond: [:h | #[]].
	start := Time millisecondClockValue.
	self assert: self failure messageText equals: 'timed out'.
	self assert: Time millisecondClockValue - start >= 2000.
	self assertNoAlert
!
testServerHelloInPieces
	"A ServerHello split across two records and received a byte at a time gets the client its keys; then the server stalls."
	| server |
	server := X25519 newPrivateKey.
	socket chunkSize: 1; stall.
	self respond: [:h | | message |
		message := (TLSWriter new u8: 2; vector24Do: [:w |
			w u16: 16r0303; bytes: (ByteArray new: 32); vector8: h sessionId; u16: 16r1303; u8: 0;
				vector16Do: [:x | x u16: 43; vector16: #[3 4]; u16: 51; vector16: (TLSWriter new u16: 16r1D; vector16: (X25519 publicKeyFor: server); contents)]]; contents).
		(self record: (message copyFrom: 1 to: 10) type: 22), (self record: #[1] type: 20), (self record: (message copyFrom: 11 to: message size) type: 22)].
	self assert: self failure messageText equals: 'timed out'.
	self assert: connection cipherSuite equals: TLSCipherSuite chacha20Poly1305Sha256
!
testServerHelloSharingARecord
	"Keys change after ServerHello: nothing may follow it in its record."
	self respond: [:h | | message |
		message := (self serverHello: h extensions: {self version13. self keyShare: (X25519 publicKeyFor: X25519 newPrivateKey)}) allButFirst: 5.
		self record: message, #[8 0 0 2 0 0] type: 22].
	self failure.
	self assertAlert: #unexpectedMessage
!
testHelloRetryRequest
	"No key share in the first ClientHello: the server asks for one, with a cookie; the client sends change_cipher_spec and a second ClientHello."
	connection keyShareGroups: #().
	self respond: [:h |
		hellos size = 1
			ifTrue: [self helloRetry: h extensions: {self version13. 51 -> #[0 16r1D]. 44 -> #[0 3 1 2 3]}]
			ifFalse: [#[]]].
	self failure.
	self assert: hellos size equals: 2.
	self assert: hellos first keyShares isEmpty.
	self assert: (hellos last keyShares collect: [:each | each first]) equals: #(16r1D).
	self assert: hellos last cookie equals: #[1 2 3].
	self assert: hellos last random equals: hellos first random.
	self assert: hellos last sessionId equals: hellos first sessionId.
	self assert: (socket sent copyFrom: hellos first bytes size + 6 to: hellos first bytes size + 14) equals: #[20 3 3 0 1 1 22 3 3]
!
testSecondHelloRetryRequest
	connection keyShareGroups: #().
	self respond: [:h | self helloRetry: h extensions: {self version13. 51 -> #[0 16r1D]}].
	self assert: (self failure messageText includesSubstring: 'second HelloRetryRequest').
	self assertAlert: #unexpectedMessage
!
testHelloRetryRequestForAGroupWithAShare
	self respond: [:h | self helloRetry: h extensions: {self version13. 51 -> #[0 16r1D]}].
	self failure.
	self assertAlert: #illegalParameter
!
testHelloRetryRequestForAGroupNotOffered
	connection keyShareGroups: #().
	self respond: [:h | self helloRetry: h extensions: {self version13. 51 -> #[0 16r1E]}].
	self failure.
	self assertAlert: #illegalParameter
!
testHelloRetryRequestThatChangesNothing
	self respond: [:h | self helloRetry: h extensions: {self version13}].
	self failure.
	self assertAlert: #illegalParameter
!
testServerHelloSuiteDiffersFromHelloRetry
	connection keyShareGroups: #().
	self respond: [:h |
		hellos size = 1
			ifTrue: [self helloRetry: h extensions: {self version13. 51 -> #[0 16r1D]}]
			ifFalse: [self serverHello: h random: (ByteArray new: 32) suite: 16r1303 extensions: {self version13. self keyShare: (ByteArray new: 32 withAll: 9)}]].
	self failure.
	self assertAlert: #illegalParameter
!
testUnexpectedChangeCipherSpecContent
	self respond: [:h | self record: #[2] type: 20].
	self failure.
	self assertAlert: #unexpectedMessage
! !
