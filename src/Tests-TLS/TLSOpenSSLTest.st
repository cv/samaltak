TestCase subclass: #TLSOpenSSLTest
	instanceVariableNames: 'servers trust'
	classVariableNames: 'Fixtures'
	package: 'Tests-TLS'!

TLSOpenSSLTest comment: 'I check the Smalltalk TLS client against OpenSSL''s test server (openssl s_server -tls1_3) on 127.0.0.1, with a test CA and server certificates (RSA and P-256 ECDSA, for localhost and 127.0.0.1) made once per image run in a temporary directory (fixtures), and a second CA that signed nothing: each cipher suite, a HelloRetryRequest, an ECDSA certificate, a server that asks for a client certificate, a wrong host name and an untrusted CA, 3 MB down and 2 MB up and back with KeyUpdates between, and HTTPClient over a TLSSocket that uses the Smalltalk TLS, also streaming server-sent events. Each test starts its servers (startServer:, on a free port) and kills them.'!

!TLSOpenSSLTest methodsFor: 'running'!
setUp
	| roots |
	self keep: #useSmalltalkTLS of: TLSSocket.
	roots := TLSSocket trustStoreSetting.
	self addCleanup: [TLSSocket trustStore: roots].
	servers := OrderedCollection new.
	trust := TrustStore new.
	trust add: (X509Certificate fromPem: (File readText: self fixtures, '/ca.pem'))
!
tearDown
	servers do: [:each | OSProcess run: 'kill $(cat ', self fixtures, '/pid-', each printString, ') 2>/dev/null']
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
	^self startServer: options version: '-tls1_3'
!
startServer12: options
	^self startServer: options version: '-tls1_2'
!
startServer: options version: versionOption
	"Start openssl s_server (versionOption: -tls1_3, -tls1_2) with options on a free port of 127.0.0.1 and answer the port once it accepts."
	| probe port process start |
	probe := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 1.
	port := probe localPort.
	probe close.
	process := OSProcess command: 'cd ', self fixtures, ' && { openssl s_server -accept 127.0.0.1:', port printString,
		' ', versionOption, ' -naccept 20 ', options, ' & echo $!! > pid-', port printString, '; wait; }'.
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
!
refusal: serverOptions
	"The TLSError of a handshake with a TLS 1.3 server with serverOptions, for localhost; the connection must be closed."
	^self refusal: serverOptions version: '-tls1_3'
!
refusal: serverOptions version: versionOption
	| port connection error |
	port := self startServer: serverOptions version: versionOption.
	connection := self connect: port host: 'localhost'.
	error := self failureOf: connection.
	self assert: error notNil.
	self deny: connection isOpen.
	^error
!
lowSecurity
	"Let s_server use weak certificates (OpenSSL's default security level 2 refuses to)."
	^' -cipher ALL@SECLEVEL=0 '
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
testTLS12EachCipherSuite
	#(#('ECDHE-ECDSA-AES128-GCM-SHA256' 'ec' 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256')
	  #('ECDHE-RSA-AES128-GCM-SHA256' 'rsa' 'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256')
	  #('ECDHE-ECDSA-CHACHA20-POLY1305' 'ec' 'TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256')
	  #('ECDHE-RSA-CHACHA20-POLY1305' 'rsa' 'TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256')
	  #('ECDHE-ECDSA-AES256-GCM-SHA384' 'ec' 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384')
	  #('ECDHE-RSA-AES256-GCM-SHA384' 'rsa' 'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384')) do: [:each | | port connection response |
		port := self startServer12: '-cert ', (each at: 2), '.pem -key ', (each at: 2), '.key -www -alpn http/1.1 -cipher ', (each at: 1).
		connection := self handshake: (self connect: port host: 'localhost').
		self assert: connection version equals: 16r0303.
		self assert: connection cipherSuite name equals: (each at: 3).
		self assert: connection protocol equals: 'http/1.1'.
		response := (self get: '/' over: connection) asString.
		self assert: (response beginsWith: 'HTTP/1.0 200 ok').
		self assert: (response includesSubstring: (each at: 1))]
!
testTLS12P256
	| port connection |
	port := self startServer12: self rsa, '-www -groups P-256'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: connection keyExchangeGroup equals: 16r17.
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testTLS12CertificateRequest
	| port connection |
	port := self startServer12: self rsa, '-www -verify 1'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testTLS12LargeDownload
	| port connection response expected |
	port := self startServer12: self rsa, '-WWW'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: connection version equals: 16r0303.
	response := self get: '/big.bin' over: connection.
	expected := File readBytes: self fixtures, '/big.bin'.
	self assert: (response copyFrom: response size - expected size + 1 to: response size) = expected
!
testTLS12NoSharedCipherSuite
	"Servers with only RSA key exchange, CBC, NULL or anonymous suites: we offer none of them, the server refuses."
	#('AES128-SHA' 'ECDHE-RSA-AES128-SHA' 'ECDHE-RSA-NULL-SHA:@SECLEVEL=0' 'ADH-AES128-GCM-SHA256:@SECLEVEL=0' 'AECDH-AES128-SHA:@SECLEVEL=0') do: [:cipher | | error |
		error := self refusal: self rsa, '-www -cipher ', cipher version: '-tls1_2'.
		self assert: error isFromPeer.
		self assert: error alert equals: #handshakeFailure]
!
testExpiredCertificate
	| error |
	error := self refusal: '-cert expired.pem -key rsa.key -www'.
	self assert: (error messageText includesSubstring: 'expired at 2020-02-01').
	self assert: error alert equals: #certificateExpired
!
testSelfSignedCertificate
	| error |
	error := self refusal: '-cert self.pem -key rsa.key -www'.
	self assert: (error messageText includesSubstring: 'not trusted').
	self assert: error alert equals: #unknownCa
!
testIncompleteChain
	"The leaf of a chain of four intermediates without them."
	| error |
	error := self refusal: '-cert deep.pem -key rsa.key -www'.
	self assert: (error messageText includesSubstring: 'issued by CN=Samaltak Test int4, which is not trusted').
	self assert: error alert equals: #unknownCa
!
testLongChain
	"Four intermediates, sent in order and then shuffled."
	#('deepchain.pem' 'deepshuffled.pem') do: [:chain | | port connection |
		port := self startServer: '-cert deep.pem -key rsa.key -cert_chain ', chain, ' -www'.
		connection := self handshake: (self connect: port host: 'localhost').
		self assert: connection peerCertificates size equals: 5.
		self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')]
!
testWeakKey
	| error |
	error := self refusal: '-cert weak.pem -key weak.key -www', self lowSecurity.
	self assert: (error messageText includesSubstring: 'RSA key of 1024 bits').
	self assert: error alert equals: #badCertificate
!
testSHA1Signature
	| error |
	error := self refusal: '-cert sha1.pem -key rsa.key -www', self lowSecurity.
	self assert: (error messageText includesSubstring: 'sha1WithRSAEncryption, which is too weak').
	self assert: error alert equals: #badCertificate
!
testLargeCertificate
	"A leaf with 1500 names, over 40 KB: the Certificate message spans records."
	| port connection |
	port := self startServer: '-cert bigcert.pem -key rsa.key -www'.
	connection := self handshake: (self connect: port host: 'localhost').
	self assert: connection peerCertificates first der size > 40000.
	self assert: connection peerCertificates first dnsNames size equals: 1501.
	self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')
!
testManySequentialConnections
	"100 connections in a row, TLS 1.3 and 1.2 in turn, each a GET: no handle is left open."
	| port12 port13 before |
	port13 := self startServer: '-cert ec.pem -key ec.key -www -naccept 100'.
	port12 := self startServer12: '-cert ec.pem -key ec.key -www -naccept 100'.
	before := Smalltalk vm platformHandleCounts at: #sockets.
	1 to: 100 do: [:i | | connection |
		connection := self handshake: (self connect: (i odd ifTrue: [port13] ifFalse: [port12]) host: 'localhost').
		self assert: connection version equals: (i odd ifTrue: [16r0304] ifFalse: [16r0303]).
		self assert: ((self get: '/' over: connection) asString beginsWith: 'HTTP/1.0 200 ok')].
	self assert: (Smalltalk vm platformHandleCounts at: #sockets) equals: before
!
testCloseWhileReceiving
	"Another Process closes the connection while one waits to receive (cancelling it): the receiver sees the end (0) at once, not an error or its timeout."
	| port connection outcome start |
	port := self startServer: self rsa, '-rev'.
	connection := self handshake: (self connect: port host: 'localhost').
	self fork: [
		outcome := [connection receiveInto: (ByteArray new: 100) timeout: 10000] on: TLSError do: [:e | e messageText]].
	(Delay forMilliseconds: 100) wait.
	self assert: outcome isNil.
	start := Time millisecondClockValue.
	connection close.
	self assert: (self waitFor: [outcome notNil]).
	self assert: outcome equals: 0.
	self assert: Time millisecondClockValue - start < 5000
!
testReceiveTimeout
	"Nothing to read within the timeout answers nil and leaves the connection usable."
	| port connection buffer start n |
	port := self startServer: self rsa, '-rev'.
	connection := self handshake: (self connect: port host: 'localhost').
	buffer := ByteArray new: 100.
	start := Time millisecondClockValue.
	self assert: (connection receiveInto: buffer timeout: 200) isNil.
	self assert: Time millisecondClockValue - start >= 200.
	self assert: (connection sendAll: 'abc', String lf).
	n := connection receiveInto: buffer timeout: 5000.
	self assert: ((buffer copyFrom: 1 to: n) asString includesSubstring: 'cba').
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
inter() {
openssl req -newkey rsa:2048 -nodes -keyout $1.key -out $1.csr -subj "/CN=Samaltak Test $1" 2>/dev/null
printf "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n" > inter.cnf
openssl x509 -req -in $1.csr -CA $2.pem -CAkey $2.key -CAcreateserial -out $1.pem -days 2 -extfile inter.cnf 2>/dev/null
}
inter int1 ca
inter int2 int1
inter int3 int2
inter int4 int3
openssl x509 -req -in rsa.csr -CA int4.pem -CAkey int4.key -CAcreateserial -out deep.pem -days 2 -extfile ext.cnf 2>/dev/null
cat int4.pem int3.pem int2.pem int1.pem > deepchain.pem
cat int2.pem int4.pem int1.pem int3.pem > deepshuffled.pem
openssl req -x509 -key rsa.key -out self.pem -days 2 -subj /CN=localhost -addext subjectAltName=DNS:localhost 2>/dev/null
openssl req -newkey rsa:1024 -nodes -keyout weak.key -out weak.csr -subj /CN=localhost 2>/dev/null
openssl x509 -req -in weak.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out weak.pem -days 2 -extfile ext.cnf 2>/dev/null
openssl x509 -req -sha1 -in rsa.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out sha1.pem -days 2 -extfile ext.cnf 2>/dev/null
printf "[ca]\ndefault_ca=d\n[d]\ndatabase=index.txt\nnew_certs_dir=.\nserial=serial\ndefault_md=sha256\npolicy=p\n[p]\ncommonName=supplied\n" > old.cnf
touch index.txt
echo 1000 > serial
openssl ca -batch -config old.cnf -cert ca.pem -keyfile ca.key -in rsa.csr -out expired.pem -startdate 20200101000000Z -enddate 20200201000000Z -extfile ext.cnf -notext 2>/dev/null
{ printf "subjectAltName=DNS:localhost"; i=0; while [ $i -lt 1500 ]; do printf ",DNS:host%d.samaltak-test.example" $i; i=$((i + 1)); done; printf "\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n"; } > big.cnf
openssl x509 -req -in rsa.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out bigcert.pem -days 2 -extfile big.cnf 2>/dev/null
head -c 3000000 /dev/urandom > big.bin
printf "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\nevent: a\ndata: 1\n\ndata: two\n\n" > events
touch done'
! !
