TLSOpenSSLTest subclass: #MbedTLSOpenSSLTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

MbedTLSOpenSSLTest comment: 'I am TLSOpenSSLTest for the VM''s TLS engine (MbedTLSConnection, mbedTLS): the same servers, certificates and transfers, with what the engine tells (its names of versions and suites, mbedTLS''s reasons for refusing a certificate) in place of the Smalltalk client''s handshake details.'!

!MbedTLSOpenSSLTest methodsFor: 'running'!
setUp
	super setUp.
	self keep: #engine of: TLSSocket
! !

!MbedTLSOpenSSLTest methodsFor: 'support'!
connect: port host: hostName
	"An MbedTLSConnection to port, before the handshake, trusting the test CA."
	| connection |
	connection := MbedTLSConnection on: (RemoteSocket connectTo: '127.0.0.1' port: port timeout: 5000) host: hostName.
	connection trustStore: trust.
	^connection
!
assertGetOver: connection
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
! !

!MbedTLSOpenSSLTest methodsFor: 'tests'!
testEachCipherSuite
	#(#('TLS_AES_128_GCM_SHA256' 'TLS1-3-AES-128-GCM-SHA256') #('TLS_CHACHA20_POLY1305_SHA256' 'TLS1-3-CHACHA20-POLY1305-SHA256') #('TLS_AES_256_GCM_SHA384' 'TLS1-3-AES-256-GCM-SHA384')) do: [:each | | port connection response |
		port := self startServer: self rsa, '-www -ciphersuites ', each first.
		connection := self handshake: (self connect: port host: 'localhost').
		self assert: connection version equals: 'TLSv1.3'.
		self assert: connection cipherSuite equals: each last.
		response := (self get: '/' over: connection) asString.
		self assert: (response beginsWith: 'HTTP/1.0 200 ok').
		self assert: (response includesSubstring: 'Cipher is ', each first)]
!
testHelloRetryRequest
	"The server takes only P-256: the client's x25519 share gets a HelloRetryRequest."
	| port |
	port := self startServer: self rsa, '-www -groups P-256'.
	self assertGetOver: (self handshake: (self connect: port host: 'localhost'))
!
testHelloRetryRequestForX25519
	"The server takes only x25519, the engine's first share."
	| port |
	port := self startServer: self rsa, '-www -groups X25519'.
	self assertGetOver: (self handshake: (self connect: port host: 'localhost'))
!
testECDSACertificate
	| port |
	port := self startServer: '-cert ec.pem -key ec.key -www'.
	self assertGetOver: (self handshake: (self connect: port host: 'localhost'))
!
testAddressInCertificate
	| port |
	port := self startServer: self rsa, '-www'.
	self assertGetOver: (self handshake: (self connect: port host: '127.0.0.1'))
!
testWrongHost
	| port connection error |
	port := self startServer: self rsa, '-www'.
	connection := self connect: port host: 'wrong.example'.
	error := self failureOf: connection.
	self assert: error notNil.
	self assert: (error messageText includesSubstring: 'does not match with the expected CN').
	self deny: connection isOpen
!
testUntrustedCA
	| port connection error |
	port := self startServer: self rsa, '-www'.
	connection := self connect: port host: 'localhost'.
	connection trustStore: (TrustStore new add: (X509Certificate fromPem: (File readText: self fixtures, '/other.pem')); yourself).
	error := self failureOf: connection.
	self assert: error notNil.
	self assert: (error messageText includesSubstring: 'not correctly signed by the trusted CA').
	self deny: connection isOpen
!
testLargeUploadWithKeyUpdates
	"2 MB of lines up and back reversed (s_server -rev; mbedTLS 3.6 has no KeyUpdate)."
	| port connection lines received reader text total |
	port := self startServer: self rsa, '-rev'.
	connection := self handshake: (self connect: port host: 'localhost').
	lines := (1 to: 2000) collect: [:i | (String new: 1000 withAll: (Character value: 97 + (i \\ 26))), i printString].
	total := lines inject: 0 into: [:sum :each | sum + each size + 1].
	received := WriteStream on: (ByteArray new: total).
	reader := self fork: [| buffer n |
		buffer := ByteArray new: 32768.
		[(n := connection receiveInto: buffer timeout: 30000) notNil and: [n > 0 and: [received position < total]]] whileTrue: [
			received nextPutAll: (buffer copyFrom: 1 to: n)]].
	lines do: [:each | self assert: (connection sendAll: each, String lf)].
	self assert: (self waitFor: [received position >= total] timeout: 60000).
	text := received contents asString.
	self assert: text lines asArray equals: (lines collect: [:each | each reverse]) asArray.
	connection close
!
testTLS12EachCipherSuite
	#(#('ECDHE-ECDSA-AES128-GCM-SHA256' 'ec' 'TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256')
	  #('ECDHE-RSA-AES128-GCM-SHA256' 'rsa' 'TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256')
	  #('ECDHE-ECDSA-CHACHA20-POLY1305' 'ec' 'TLS-ECDHE-ECDSA-WITH-CHACHA20-POLY1305-SHA256')
	  #('ECDHE-RSA-CHACHA20-POLY1305' 'rsa' 'TLS-ECDHE-RSA-WITH-CHACHA20-POLY1305-SHA256')
	  #('ECDHE-ECDSA-AES256-GCM-SHA384' 'ec' 'TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384')
	  #('ECDHE-RSA-AES256-GCM-SHA384' 'rsa' 'TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384')) do: [:each | | port connection response |
		port := self startServer12: '-cert ', (each at: 2), '.pem -key ', (each at: 2), '.key -www -alpn http/1.1 -cipher ', (each at: 1).
		connection := self handshake: (self connect: port host: 'localhost').
		self assert: connection version equals: 'TLSv1.2'.
		self assert: connection cipherSuite equals: (each at: 3).
		self assert: connection protocol equals: 'http/1.1'.
		response := (self get: '/' over: connection) asString.
		self assert: (response beginsWith: 'HTTP/1.0 200 ok').
		self assert: (response includesSubstring: (each at: 1))]
!
testTLS12P256
	| port |
	port := self startServer12: self rsa, '-www -groups P-256'.
	self assertGetOver: (self handshake: (self connect: port host: 'localhost'))
!
testTLS12LargeDownload
	| port connection response expected |
	port := self startServer12: self rsa, '-WWW'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: connection version equals: 'TLSv1.2'.
	response := self get: '/big.bin' over: connection.
	expected := File readBytes: self fixtures, '/big.bin'.
	self assert: (response copyFrom: response size - expected size + 1 to: response size) = expected
!
testTLS12NoSharedCipherSuite
	"Servers with only RSA key exchange, CBC, NULL or anonymous suites: we offer none of them, the server refuses."
	#('AES128-SHA' 'ECDHE-RSA-AES128-SHA' 'ECDHE-RSA-NULL-SHA:@SECLEVEL=0' 'ADH-AES128-GCM-SHA256:@SECLEVEL=0' 'AECDH-AES128-SHA:@SECLEVEL=0') do: [:cipher |
		self assert: (self refusal: self rsa, '-www -cipher ', cipher version: '-tls1_2') notNil]
!
testExpiredCertificate
	self assert: ((self refusal: '-cert expired.pem -key rsa.key -www') messageText includesSubstring: 'validity has expired')
!
testSelfSignedCertificate
	self assert: ((self refusal: '-cert self.pem -key rsa.key -www') messageText includesSubstring: 'not correctly signed by the trusted CA')
!
testIncompleteChain
	"The leaf of a chain of four intermediates without them."
	self assert: ((self refusal: '-cert deep.pem -key rsa.key -www') messageText includesSubstring: 'not correctly signed by the trusted CA')
!
testLongChain
	"Four intermediates sent in order; mbedTLS looks for each issuer after its certificate only, so a shuffled chain fails."
	| port |
	port := self startServer: '-cert deep.pem -key rsa.key -cert_chain deepchain.pem -www'.
	self assertGetOver: (self handshake: (self connect: port host: 'localhost')).
	self assert: ((self refusal: '-cert deep.pem -key rsa.key -cert_chain deepshuffled.pem -www') messageText
		includesSubstring: 'not correctly signed by the trusted CA')
!
testWeakKey
	self assert: ((self refusal: '-cert weak.pem -key weak.key -www', self lowSecurity) messageText includesSubstring: 'unacceptable key')
!
testSHA1Signature
	self assert: ((self refusal: '-cert sha1.pem -key rsa.key -www', self lowSecurity) messageText includesSubstring: 'unacceptable hash')
!
testLargeCertificate
	"A leaf with 1500 names, over 40 KB: a Certificate message larger than mbedTLS's record buffer (16 KB) fails the handshake, and closes the connection."
	self assert: (self refusal: '-cert bigcert.pem -key rsa.key -www') notNil
!
testManySequentialConnections
	"100 connections in a row, TLS 1.3 and 1.2 in turn, each a GET: no handle is left open."
	| port12 port13 before |
	port13 := self startServer: '-cert ec.pem -key ec.key -www -naccept 100'.
	port12 := self startServer12: '-cert ec.pem -key ec.key -www -naccept 100'.
	before := Smalltalk vm platformHandleCounts at: #sockets.
	1 to: 100 do: [:i | | connection |
		connection := self handshake: (self connect: (i odd ifTrue: [port13] ifFalse: [port12]) host: 'localhost').
		self assert: connection version equals: (i odd ifTrue: ['TLSv1.3'] ifFalse: ['TLSv1.2']).
		self assertGetOver: connection].
	self assert: (Smalltalk vm platformHandleCounts at: #sockets) equals: before
!
testHTTPClient
	| port response |
	port := self startServer: self rsa, '-www'.
	TLSSocket engine: #mbedtls; trustStore: trust.
	response := HTTPClient new get: 'https://localhost:', port printString, '/' headers: nil.
	self assert: response status equals: 200
!
testServerSentEvents
	| port events client |
	port := self startServer: self rsa, '-HTTP'.
	TLSSocket engine: #mbedtls; trustStore: trust.
	events := OrderedCollection new.
	client := HTTPClient new.
	client request: 'GET' url: 'https://localhost:', port printString, '/events' headers: nil body: nil do: [:text |
		(SSEReader do: [:event :data | events add: event -> data]) feed: text].
	self assert: events asArray equals: {'a' -> '1'. 'message' -> 'two'}
!
testSocketIsMbedTLS
	| port socket |
	port := self startServer: self rsa, '-www'.
	TLSSocket engine: #mbedtls; trustStore: trust.
	socket := TLSSocket connectTo: 'localhost' port: port timeout: 5000.
	self assert: (socket connection isKindOf: MbedTLSConnection).
	self assert: (socket printString includesSubstring: 'mbedTLS').
	socket close
! !
