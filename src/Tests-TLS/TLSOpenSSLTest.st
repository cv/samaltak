TestCase subclass: #TLSOpenSSLTest
	instanceVariableNames: 'servers trust'
	classVariableNames: 'Fixtures'
	package: 'Tests-TLS'!

TLSOpenSSLTest comment: 'I check the Smalltalk TLS client against OpenSSL''s test server (openssl s_server -tls1_3) on 127.0.0.1, with a test CA and server certificates (RSA and P-256 ECDSA, for localhost and 127.0.0.1) made once per image run in a temporary directory (fixtures), and a second CA that signed nothing: each cipher suite, a HelloRetryRequest, an ECDSA certificate, a server that asks for a client certificate, a wrong host name and an untrusted CA, 3 MB down and 2 MB up and back with KeyUpdates between, and HTTPClient over a TLSSocket that uses the Smalltalk TLS, also streaming server-sent events. Each test starts its servers (startServer:, on a free port) and kills them.'!

!TLSOpenSSLTest methodsFor: 'running'!
setUp
	servers := OrderedCollection new.
	trust := TrustStore new.
	trust add: (X509Certificate fromPem: (File readText: self fixtures, '/ca.pem'))
!
tearDown
	servers do: [:each | OSProcess run: 'kill $(cat ', self fixtures, '/pid-', each printString, ') 2>/dev/null'].
	TLSSocket useSmalltalkTLS: false; trustStore: nil
! !

!TLSOpenSSLTest methodsFor: 'support'!
fixtures
	"The directory with the CA, the certificates, their keys and the files the servers serve."
	(Fixtures notNil and: [File exists: Fixtures, '/done']) ifTrue: [^Fixtures].
	Fixtures := '/tmp/samaltak-tls-', (Time utcMicroseconds printString).
	(OSProcess run: (self class fixtureScript copyReplaceAll: 'DIR' with: Fixtures)) succeeded ifFalse: [
		self error: 'cannot make the TLS fixtures in ', Fixtures].
	^Fixtures
!
startServer: options
	"Start openssl s_server with options on a free port of 127.0.0.1 and answer the port once it accepts."
	| probe port process start |
	probe := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 1.
	port := probe localPort.
	probe close.
	process := OSProcess command: 'cd ', self fixtures, ' && { openssl s_server -accept 127.0.0.1:', port printString,
		' -tls1_3 -naccept 20 ', options, ' & echo $!! > pid-', port printString, '; wait; }'.
	process start.
	servers add: port.
	start := Time millisecondClockValue.
	[process outputSoFar includesSubstring: 'ACCEPT'] whileFalse: [
		(process isRunning not or: [Time millisecondClockValue - start > 10000]) ifTrue: [
			^self error: 'openssl s_server did not start: ', process outputSoFar].
		(Delay forMilliseconds: 20) wait].
	^port
!
rsa
	^'-cert rsa.pem -key rsa.key '
!
connect: port host: hostName
	"A TLSClientConnection to port, before the handshake, trusting the test CA."
	| connection |
	connection := TLSClientConnection on: (RemoteSocket connectTo: '127.0.0.1' port: port timeout: 5000) host: hostName.
	connection trustStore: trust.
	^connection
!
handshake: connection
	connection handshakeUntil: Time millisecondClockValue + 20000.
	^connection
!
get: path over: connection
	"The whole response to an HTTP/1.0 GET of path."
	| out buffer n |
	connection sendAll: 'GET ', path, ' HTTP/1.0', String crlf, String crlf.
	out := WriteStream on: (ByteArray new: 65536).
	buffer := ByteArray new: 65536.
	[(n := connection receiveInto: buffer timeout: 20000) isNil ifTrue: [^self error: 'timed out'].
	 n > 0] whileTrue: [out nextPutAll: (buffer copyFrom: 1 to: n)].
	connection close.
	^out contents
!
failureOf: connection
	^[self handshake: connection. nil] on: TLSError do: [:e | e return: e]
! !

!TLSOpenSSLTest methodsFor: 'tests'!
testEachCipherSuite
	#('TLS_AES_128_GCM_SHA256' 'TLS_CHACHA20_POLY1305_SHA256' 'TLS_AES_256_GCM_SHA384') do: [:name | | port connection response |
		port := self startServer: self rsa, '-www -ciphersuites ', name.
		connection := self handshake: (self connect: port host: 'localhost').
		self assert: connection cipherSuite name equals: name.
		self deny: connection wasRetried.
		self assert: connection peerCertificates size >= 1.
		response := (self get: '/' over: connection) asString.
		self assert: (response beginsWith: 'HTTP/1.0 200 ok').
		self assert: (response includesSubstring: 'Cipher is ', name)]
!
testHelloRetryRequest
	"The server takes only P-256: the client''s x25519 share gets a HelloRetryRequest."
	| port connection |
	port := self startServer: self rsa, '-www -groups P-256'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: connection wasRetried.
	self assert: (connection clientHello keyShares collect: [:each | each first]) equals: #(16r17).
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testHelloRetryRequestForX25519
	"No key share at first: the server asks for x25519."
	| port connection |
	port := self startServer: self rsa, '-www -groups X25519'.
	connection := self connect: port host: 'localhost'.
	connection keyShareGroups: #().
	self handshake: connection.
	self assert: connection wasRetried.
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testECDSACertificate
	| port connection |
	port := self startServer: '-cert ec.pem -key ec.key -www'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: (connection peerCertificates first publicKey isKindOf: EcPublicKey).
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testCertificateRequest
	"The server asks for a client certificate but does without: the client sends an empty Certificate."
	| port connection |
	port := self startServer: self rsa, '-www -verify 1'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testAddressInCertificate
	| port connection |
	port := self startServer: self rsa, '-www'.
	connection := self handshake: (self connect: port host: '127.0.0.1').
	self assert: connection clientHello serverName isNil.
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testWrongHost
	| port connection error |
	port := self startServer: self rsa, '-www'.
	connection := self connect: port host: 'wrong.example'.
	error := self failureOf: connection.
	self assert: error notNil.
	self assert: error alert notNil.
	self deny: connection isOpen
!
testUntrustedCA
	| port connection error |
	port := self startServer: self rsa, '-www'.
	connection := self connect: port host: 'localhost'.
	connection trustStore: (TrustStore new add: (X509Certificate fromPem: (File readText: self fixtures, '/other.pem')); yourself).
	error := self failureOf: connection.
	self assert: error notNil.
	self assert: error alert notNil.
	self deny: connection isOpen
!
testLargeDownload
	| port connection response expected |
	port := self startServer: self rsa, '-WWW'.
	connection := self handshake: (self connect: port host: 'localhost').
	response := self get: '/big.bin' over: connection.
	expected := File readBytes: self fixtures, '/big.bin'.
	self assert: response size > expected size.
	self assert: (response copyFrom: response size - expected size + 1 to: response size) = expected
!
testLargeUploadWithKeyUpdates
	"2 MB of lines up and back reversed (s_server -rev), the client updating its keys and asking the server to, now and then."
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
	lines doWithIndex: [:each :i |
		self assert: (connection sendAll: each, String lf).
		i \\ 500 = 0 ifTrue: [connection updateKeys]].
	self assert: (self waitFor: [received position >= total] timeout: 60000).
	text := received contents asString.
	self assert: text lines asArray equals: (lines collect: [:each | each reverse]) asArray.
	connection close
!
testHTTPClient
	| port response |
	port := self startServer: self rsa, '-www'.
	TLSSocket useSmalltalkTLS: true; trustStore: trust.
	response := HTTPClient new get: 'https://localhost:', port printString, '/' headers: nil.
	self assert: response status equals: 200
!
testServerSentEvents
	| port events client |
	port := self startServer: self rsa, '-HTTP'.
	TLSSocket useSmalltalkTLS: true; trustStore: trust.
	events := OrderedCollection new.
	client := HTTPClient new.
	client request: 'GET' url: 'https://localhost:', port printString, '/events' headers: nil body: nil do: [:text |
		(SSEReader do: [:event :data | events add: event -> data]) feed: text].
	self assert: events asArray equals: {'a' -> '1'. 'message' -> 'two'}
! !

!TLSOpenSSLTest class methodsFor: 'fixtures'!
fixtureScript
	"Make the CAs, the server certificates and the files served in DIR."
	^'set -e; mkdir -p DIR; cd DIR
ca() { openssl req -x509 -newkey rsa:2048 -nodes -keyout $1.key -out $1.pem -days 2 -subj "/CN=$2" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null; }
ca ca "Samaltak Test CA"
ca other "Samaltak Other CA"
printf "subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n" > ext.cnf
openssl req -newkey rsa:2048 -nodes -keyout rsa.key -out rsa.csr -subj /CN=localhost 2>/dev/null
openssl x509 -req -in rsa.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out rsa.pem -days 2 -extfile ext.cnf 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ec.key -out ec.csr -subj /CN=localhost 2>/dev/null
openssl x509 -req -in ec.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out ec.pem -days 2 -extfile ext.cnf 2>/dev/null
head -c 3000000 /dev/urandom > big.bin
printf "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\nevent: a\ndata: 1\n\ndata: two\n\n" > events
touch done'
! !
