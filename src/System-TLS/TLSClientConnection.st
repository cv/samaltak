Object subclass: #TLSClientConnection
	instanceVariableNames: 'socket host validator protocols suites groups shareGroups schemes padding state hello privateKeys suite schedule transcript readCipher writeCipher input inStart scratch handshakeBuffer data dataStart inputClosed sendLock sentChangeCipherSpec retried certificateRequest certificates protocol failure handshakeMilliseconds'
	classVariableNames: ''
	package: 'System-TLS'!

TLSClientConnection comment: 'I am the client of a TLS 1.3 connection (RFC 8446; no TLS 1.2, no PSK or 0-RTT, no client certificate) over a connected byte socket: anything that answers sendAll: (a Boolean), receiveInto:timeout: (bytes received, 0 at the end of the stream, nil after the timeout), isOpen and close, like a RemoteSocket, so on UEFI over the image''s TCP/IP stack.

	c := TLSClientConnection on: (RemoteSocket connectTo: ''example.com'' port: 443) host: ''example.com''.
	c handshakeUntil: Time millisecondClockValue + 10000.
	c sendAll: ''GET / HTTP/1.1'' ... ; receiveInto: buffer timeout: 5000.
	c close

Before the handshake: trustStore: (the roots the server''s certificate must chain to; TrustStore default unless set) or certificateValidator: (anything that answers validate:host:at:, signalling TLSError), protocols: (ALPN; #(''http/1.1'') by default, empty for none), cipherSuites: (TLSCipherSuites; all by default), keyShareGroups: (the groups the first ClientHello has key shares for, the first of the supported groups by default; empty forces a HelloRetryRequest), recordPadding: (pad the content of protected records to a multiple of that many bytes).

handshakeUntil: deadline (a millisecondClockValue, nil for none) does the handshake: ClientHello with SNI (unless host is an IP address), supported groups (x25519, secp256r1), a key share (x25519), signature algorithms, ALPN and a session id (middlebox compatibility: a change_cipher_spec before the second flight); a HelloRetryRequest; ServerHello; the key schedule; EncryptedExtensions; Certificate, validated for host; CertificateVerify; Finished both ways (an empty Certificate first if the server asked for one). It signals TLSError if anything fails, after sending the alert that says why and closing the socket.

Then: sendAll: (records of at most 2^14 bytes; false once the connection is gone), receiveInto:timeout: and receiveInto: (as a socket''s: 0 at the end, after the server''s close_notify, nil after the timeout; TLSError if the connection fails, closed), updateKeys (a KeyUpdate asking the server for one too; the server''s KeyUpdates are followed, NewSessionTickets ignored), close (close_notify, then the socket closes). One Process receives at a time; sending is mutually exclusive, also with the KeyUpdates receiving answers.

After it: cipherSuite, protocol (the one ALPN chose, or nil), peerCertificates (X509Certificates, the server''s first), wasRetried (whether the server sent a HelloRetryRequest), handshakeMilliseconds, failure (why it failed, or nil).'!

!TLSClientConnection methodsFor: 'initialization'!
setSocket: aSocket host: aString
	socket := aSocket.
	host := aString.
	state := #start.
	protocols := #('http/1.1').
	suites := TLSCipherSuite all.
	groups := self class supportedGroups.
	schemes := self class signatureSchemes.
	padding := 0.
	input := ByteArray new.
	inStart := 1.
	scratch := ByteArray new: 16384 + 256 + 5.
	handshakeBuffer := ByteArray new.
	inputClosed := false.
	sendLock := Semaphore forMutualExclusion.
	sentChangeCipherSpec := false.
	transcript := WriteStream on: (ByteArray new: 4096)
! !

!TLSClientConnection methodsFor: 'configuring'!
trustStore: aTrustStore
	validator := CertificateValidator new trustStore: aTrustStore
!
certificateValidator: aValidator
	"Something that answers validate: certificates host: aString at: aTime, signalling TLSError if they are not good."
	validator := aValidator
!
protocols: names
	protocols := names
!
cipherSuites: aCollection
	suites := aCollection asArray
!
keyShareGroups: codes
	shareGroups := codes asArray
!
recordPadding: anInteger
	padding := anInteger
! !

!TLSClientConnection methodsFor: 'accessing'!
host
	^host
!
socket
	^socket
!
cipherSuite
	^suite
!
protocol
	"The application protocol the server chose (ALPN), or nil."
	^protocol
!
peerCertificates
	^certificates
!
handshakeMilliseconds
	^handshakeMilliseconds
!
wasRetried
	"Did the server send a HelloRetryRequest?"
	^retried == true
!
failure
	"Why the connection failed, or nil."
	^failure
!
clientHello
	^hello
!
isOpen
	^state ~~ #closed
!
isConnected
	^state == #connected
! !

!TLSClientConnection methodsFor: 'handshake'!
handshakeUntil: deadline
	"Do the handshake unless deadline (a millisecondClockValue, nil for none) passes first. Signal TLSError if it fails."
	| start |
	state == #start ifFalse: [^TLSError signal: 'the handshake has begun already' alert: nil].
	start := Time millisecondClockValue.
	[self runHandshakeUntil: deadline] on: TLSError do: [:e |
		self abort: e.
		e pass].
	handshakeMilliseconds := Time millisecondClockValue - start
!
runHandshakeUntil: deadline
	| message serverHello |
	self sendClientHello.
	state := #handshake.
	message := self expect: 2 until: deadline.
	serverHello := TLSServerHello fromBody: (message at: 2).
	serverHello isHelloRetryRequest ifTrue: [
		self acceptHelloRetryRequest: serverHello message: message last.
		message := self expect: 2 until: deadline.
		serverHello := TLSServerHello fromBody: (message at: 2).
		serverHello isHelloRetryRequest ifTrue: [^TLSError signal: 'a second HelloRetryRequest' alert: #unexpectedMessage]].
	self acceptServerHello: serverHello message: message last.
	message := self expect: 8 until: deadline.
	self acceptEncryptedExtensions: (message at: 2).
	self addToTranscript: message last.
	message := self nextHandshakeMessageUntil: deadline.
	message first = 13 ifTrue: [
		self acceptCertificateRequest: (message at: 2).
		self addToTranscript: message last.
		message := self nextHandshakeMessageUntil: deadline].
	self check: message is: 11.
	self acceptCertificate: (message at: 2).
	self addToTranscript: message last.
	message := self expect: 15 until: deadline.
	self acceptCertificateVerify: (message at: 2).
	self addToTranscript: message last.
	message := self expect: 20 until: deadline.
	self acceptFinished: (message at: 2).
	self addToTranscript: message last.
	handshakeBuffer isEmpty ifFalse: [^TLSError signal: 'a message after Finished in its record' alert: #unexpectedMessage].
	self sendFinished.
	state := #connected
!
sendClientHello
	hello isNil ifTrue: [
		privateKeys := Dictionary new.
		(shareGroups ifNil: [groups copyFrom: 1 to: 1]) do: [:each | privateKeys at: each put: (self newPrivateKeyFor: each)].
		hello := TLSClientHello new
			random: (SecureRandom default nextBytes: 32);
			sessionId: (SecureRandom default nextBytes: 32);
			cipherSuites: (suites collect: [:each | each code]);
			serverName: (self class serverNameFor: host);
			groups: groups;
			keyShares: (self keySharesFor: (shareGroups ifNil: [groups copyFrom: 1 to: 1]));
			signatureSchemes: schemes;
			protocols: protocols].
	self addToTranscript: hello bytes.
	self sendPlaintext: hello bytes type: 22 version: 16r0301
!
acceptHelloRetryRequest: serverHello message: bytes
	"Answer the HelloRetryRequest with a second ClientHello (section 4.1.4)."
	| group hash |
	self checkServerHello: serverHello allowing: #(43 44 51).
	group := serverHello selectedGroup.
	(group isNil and: [serverHello cookie isNil]) ifTrue: [^TLSError signal: 'a HelloRetryRequest that changes nothing' alert: #illegalParameter].
	(group notNil and: [(groups includes: group) not or: [privateKeys includesKey: group]]) ifTrue: [
		^TLSError signal: 'a HelloRetryRequest for the group ', group printString, ', not offered or with a share already' alert: #illegalParameter].
	suite := TLSCipherSuite withCode: serverHello cipherSuite.
	retried := true.
	hash := suite hashClass hash: transcript contents.
	transcript := WriteStream on: (ByteArray new: 4096).
	transcript nextPutAll: (TLSWriter new u8: 254; vector24: hash; contents).
	self addToTranscript: bytes.
	group isNil ifFalse: [
		privateKeys := Dictionary new.
		privateKeys at: group put: (self newPrivateKeyFor: group).
		hello keyShares: (self keySharesFor: {group})].
	hello cookie: serverHello cookie.
	self sendChangeCipherSpec.
	self addToTranscript: hello bytes.
	self sendPlaintext: hello bytes type: 22 version: 16r0303
!
acceptServerHello: serverHello message: bytes
	| share key |
	self checkServerHello: serverHello allowing: #(43 51).
	(suite notNil and: [suite code ~= serverHello cipherSuite]) ifTrue: [
		^TLSError signal: 'the ServerHello''s cipher suite is not the HelloRetryRequest''s' alert: #illegalParameter].
	suite := TLSCipherSuite withCode: serverHello cipherSuite.
	share := serverHello keyShare.
	share isNil ifTrue: [^TLSError signal: 'the ServerHello has no key share' alert: #missingExtension].
	key := privateKeys at: share first ifAbsent: [
		^TLSError signal: 'the server''s key share is for the group ', share first printString, ', which has none of ours' alert: #illegalParameter].
	self addToTranscript: bytes.
	handshakeBuffer isEmpty ifFalse: [^TLSError signal: 'a message after ServerHello in its record' alert: #unexpectedMessage].
	schedule := TLSKeySchedule suite: suite.
	schedule startWithSharedSecret: (self sharedSecretFor: share first private: key peer: share last) transcriptHash: self transcriptHash.
	privateKeys := nil.
	readCipher := schedule cipherFor: schedule serverHandshakeSecret.
	writeCipher := schedule cipherFor: schedule clientHandshakeSecret
!
checkServerHello: serverHello allowing: types
	"What a ServerHello and a HelloRetryRequest must both be: TLS 1.3, our session id, a suite we offered."
	serverHello selectedVersion isNil ifTrue: [
		^TLSError signal: 'the server does not speak TLS 1.3 (it chose ', (self class versionName: serverHello version), ')' alert: #protocolVersion].
	serverHello selectedVersion = 16r0304 ifFalse: [^TLSError signal: 'the server chose the version ', serverHello selectedVersion printString, ', not TLS 1.3' alert: #illegalParameter].
	serverHello version = 16r0303 ifFalse: [^TLSError signal: 'a ServerHello with the legacy version ', serverHello version printString alert: #illegalParameter].
	serverHello sessionId = hello sessionId ifFalse: [^TLSError signal: 'the server did not echo the session id' alert: #illegalParameter].
	serverHello compression = 0 ifFalse: [^TLSError signal: 'the server chose compression' alert: #illegalParameter].
	(suites anySatisfy: [:each | each code = serverHello cipherSuite]) ifFalse: [
		^TLSError signal: 'the server chose the cipher suite ', serverHello cipherSuite printString, ', not offered' alert: #illegalParameter].
	serverHello extensions keysDo: [:each |
		(types includes: each) ifFalse: [
			^(hello extensionTypes includes: each)
				ifTrue: [TLSError signal: 'the extension ', each printString, ' in a ServerHello' alert: #illegalParameter]
				ifFalse: [TLSError signal: 'the extension ', each printString, ', not offered' alert: #unsupportedExtension]]]
!
acceptEncryptedExtensions: body
	| r extensions list name |
	r := TLSReader on: body.
	extensions := r extensions.
	r expectEnd.
	extensions keysDo: [:each |
		(hello extensionTypes includes: each) ifFalse: [^TLSError signal: 'the extension ', each printString, ', not offered' alert: #unsupportedExtension].
		(#(13 41 43 44 45 51) includes: each) ifTrue: [^TLSError signal: 'the extension ', each printString, ' in EncryptedExtensions' alert: #illegalParameter]].
	(extensions at: 0 ifAbsent: [#()]) isEmpty ifFalse: [^TLSError signal: 'decode error: server_name not empty' alert: #decodeError].
	(extensions at: 16 ifAbsent: [nil]) ifNotNil: [:data |
		r := TLSReader on: data.
		list := r reader16.
		r expectEnd.
		name := list vector8 asString.
		list expectEnd.
		(protocols includes: name) ifFalse: [^TLSError signal: 'the server chose the protocol ', name printString, ', not offered' alert: #illegalParameter].
		protocol := name]
!
acceptCertificateRequest: body
	| r |
	r := TLSReader on: body.
	certificateRequest := r vector8.
	r extensions.
	r expectEnd
!
acceptCertificate: body
	| r list ders |
	r := TLSReader on: body.
	r vector8 isEmpty ifFalse: [^TLSError signal: 'a Certificate with a request context' alert: #illegalParameter].
	list := r reader24.
	r expectEnd.
	ders := OrderedCollection new.
	[list atEnd] whileFalse: [| der extensions |
		der := list vector24.
		der isEmpty ifTrue: [^TLSError signal: 'decode error: an empty certificate' alert: #decodeError].
		extensions := (TLSReader on: (TLSWriter new vector16: list vector16; contents)) extensions.
		extensions isEmpty ifFalse: [^TLSError signal: 'a certificate extension, not offered' alert: #unsupportedExtension].
		ders add: der].
	ders isEmpty ifTrue: [^TLSError signal: 'the server sent no certificate' alert: #decodeError].
	certificates := ders asArray collect: [:each |
		[X509Certificate fromDer: each] on: Error do: [:e |
			^TLSError signal: 'a certificate does not parse: ', e messageText alert: #badCertificate]].
	[self validator validate: certificates host: host at: self class now] on: TLSError do: [:e |
		e alert isNil ifTrue: [e alert: #badCertificate].
		e pass]
!
acceptCertificateVerify: body
	"The server's signature of the transcript up to its Certificate (section 4.4.3)."
	| r scheme signature content |
	r := TLSReader on: body.
	scheme := r u16.
	signature := r vector16.
	r expectEnd.
	((schemes includes: scheme) and: [(self class certificateOnlySchemes includes: scheme) not]) ifFalse: [
		^TLSError signal: 'the server signed with the scheme ', scheme printString, ', not offered' alert: #illegalParameter].
	content := (ByteArray new: 64) atAllPut: 32; yourself.
	content := content, 'TLS 1.3, server CertificateVerify' asByteArray, #[0], self transcriptHash.
	(self verify: signature scheme: scheme content: content) ifFalse: [
		^TLSError signal: 'the server''s CertificateVerify does not verify' alert: #decryptError]
!
verify: signature scheme: scheme content: content
	| key |
	key := certificates first publicKey.
	(scheme = 16r0804 or: [scheme = 16r0805]) ifTrue: [
		(key isKindOf: RsaPublicKey) ifFalse: [^TLSError signal: 'an RSA signature but no RSA key' alert: #illegalParameter].
		^key verifyPss: signature message: content hash: (scheme = 16r0804 ifTrue: [SHA256] ifFalse: [SHA384])].
	(scheme = 16r0403 or: [scheme = 16r0503]) ifTrue: [
		((key isKindOf: EcPublicKey) and: [key curve name = (scheme = 16r0403 ifTrue: [#p256] ifFalse: [#p384])]) ifFalse: [
			^TLSError signal: 'an ECDSA signature but no key on its curve' alert: #illegalParameter].
		^key verify: signature message: content hash: (scheme = 16r0403 ifTrue: [SHA256] ifFalse: [SHA384])].
	^false
!
acceptFinished: body
	(body constantTimeEquals: (schedule verifyData: schedule serverHandshakeSecret transcriptHash: self transcriptHash)) ifFalse: [
		^TLSError signal: 'the server''s Finished does not verify' alert: #decryptError]
!
sendFinished
	"The second flight: an empty Certificate if the server asked for one, Finished; then the application keys."
	| certificate finished |
	schedule deriveApplicationSecrets: self transcriptHash.
	self sendChangeCipherSpec.
	certificateRequest isNil ifFalse: [
		certificate := TLSWriter new u8: 11; vector24Do: [:w | w vector8: certificateRequest; vector24: #[]]; contents.
		self addToTranscript: certificate.
		self sendRecord: certificate type: 22].
	finished := TLSWriter new u8: 20; vector24: (schedule verifyData: schedule clientHandshakeSecret transcriptHash: self transcriptHash); contents.
	self addToTranscript: finished.
	self sendRecord: finished type: 22.
	readCipher := schedule cipherFor: schedule serverApplicationSecret.
	writeCipher := schedule cipherFor: schedule clientApplicationSecret
! !

!TLSClientConnection methodsFor: 'application data'!
receiveInto: aByteArray
	^self receiveInto: aByteArray timeout: nil
!
receiveInto: aByteArray timeout: milliseconds
	"Wait for application data; answer the number of bytes stored at the start of aByteArray, 0 at the end of the stream (or once closed), nil if none came within milliseconds (nil: wait forever)."
	| deadline count |
	deadline := milliseconds isNil ifFalse: [Time millisecondClockValue + milliseconds].
	[data notNil and: [dataStart <= data size]] whileFalse: [
		(state == #connected and: [inputClosed not]) ifFalse: [^0].
		([self readApplicationDataUntil: deadline] on: TLSError do: [:e |
			self abort: e.
			e pass]) ifFalse: [^nil]].
	count := aByteArray size min: data size - dataStart + 1.
	aByteArray replaceFrom: 1 to: count with: data startingAt: dataStart.
	dataStart := dataStart + count.
	^count
!
sendAll: bytes
	"Send bytes (a ByteArray or ByteString) in records of at most 2^14 bytes. Answer false if the connection is gone."
	| all |
	state == #connected ifFalse: [^false].
	all := bytes asByteArray.
	^sendLock critical: [| start count ok |
		start := 1.
		ok := true.
		[ok and: [start <= all size]] whileTrue: [
			count := 16384 min: all size - start + 1.
			ok := socket sendAll: (writeCipher seal: (all copyFrom: start to: start + count - 1) type: 23 padding: (self paddingFor: count)).
			start := start + count].
		ok]
!
updateKeys
	"Send a KeyUpdate that asks the server to update its keys too."
	state == #connected ifFalse: [^self].
	self sendKeyUpdate: 1
!
close
	"Send close_notify, then close the socket."
	state == #closed ifTrue: [^self].
	state == #connected ifTrue: [
		sendLock critical: [[socket sendAll: (writeCipher seal: #[1 0] type: 21 padding: 0)] on: Error do: [:e | e return: nil]] ifLocked: []].
	state := #closed.
	socket close
!
forget
	"In an image resumed from a snapshot: the socket belonged to the VM that saved it."
	state := #closed.
	socket forget
! !

!TLSClientConnection methodsFor: 'records'!
readApplicationDataUntil: deadline
	"Read a record: application data goes to data, post-handshake messages are handled. Answer false if deadline passed first."
	| record message |
	record := self readRecordUntil: deadline.
	record isNil ifTrue: [^false].
	record == #end ifTrue: [
		inputClosed := true.
		^true].
	record first = 23 ifTrue: [
		handshakeBuffer isEmpty ifFalse: [^TLSError signal: 'application data inside a handshake message' alert: #unexpectedMessage].
		data := record last.
		dataStart := 1.
		^true].
	record first = 22 ifFalse: [^TLSError signal: 'an unexpected record of type ', record first printString alert: #unexpectedMessage].
	handshakeBuffer := handshakeBuffer, record last.
	[(message := self takeHandshakeMessage) notNil] whileTrue: [self acceptPostHandshake: message].
	^true
!
acceptPostHandshake: message
	| request |
	message first = 4 ifTrue: [^self].
	message first = 24 ifFalse: [^TLSError signal: 'an unexpected handshake message of type ', message first printString alert: #unexpectedMessage].
	(message at: 2) size = 1 ifFalse: [^TLSError signal: 'decode error: KeyUpdate' alert: #decodeError].
	request := (message at: 2) first.
	request > 1 ifTrue: [^TLSError signal: 'a KeyUpdate with request ', request printString alert: #illegalParameter].
	handshakeBuffer isEmpty ifFalse: [^TLSError signal: 'a message after KeyUpdate in its record' alert: #unexpectedMessage].
	schedule updateServerApplicationSecret.
	readCipher := schedule cipherFor: schedule serverApplicationSecret.
	request = 1 ifTrue: [self sendKeyUpdate: 0]
!
sendKeyUpdate: request
	sendLock critical: [
		(socket sendAll: (writeCipher seal: (ByteArray with: 24 with: 0 with: 0 with: 1), (ByteArray with: request) type: 22 padding: 0))
			ifFalse: [^TLSError signal: 'connection closed' alert: nil].
		schedule updateClientApplicationSecret.
		writeCipher := schedule cipherFor: schedule clientApplicationSecret]
!
expect: type until: deadline
	| message |
	message := self nextHandshakeMessageUntil: deadline.
	self check: message is: type.
	^message
!
check: message is: type
	message first = type ifFalse: [
		^TLSError signal: 'expected ', (self class messageName: type), ', got ', (self class messageName: message first) alert: #unexpectedMessage]
!
nextHandshakeMessageUntil: deadline
	"Answer the next handshake message: {type. body. whole message}."
	| record message |
	[(message := self takeHandshakeMessage) isNil] whileTrue: [
		record := self readRecordUntil: deadline.
		record isNil ifTrue: [^TLSError signal: 'timed out' alert: nil].
		record == #end ifTrue: [^TLSError signal: 'the server closed the connection' alert: nil].
		record first = 22 ifFalse: [^TLSError signal: 'unexpected ', (record first = 23 ifTrue: ['application data'] ifFalse: [record first printString]), ' during the handshake' alert: #unexpectedMessage].
		handshakeBuffer := handshakeBuffer, record last].
	^message
!
takeHandshakeMessage
	"The next whole handshake message in handshakeBuffer, or nil."
	| length message |
	handshakeBuffer size < 4 ifTrue: [^nil].
	length := ((handshakeBuffer at: 2) bitShift: 16) + ((handshakeBuffer at: 3) bitShift: 8) + (handshakeBuffer at: 4).
	length > self class maxHandshakeMessage ifTrue: [^TLSError signal: 'a handshake message of ', length printString, ' bytes' alert: #decodeError].
	handshakeBuffer size < (length + 4) ifTrue: [^nil].
	message := handshakeBuffer copyFrom: 1 to: length + 4.
	handshakeBuffer := handshakeBuffer copyFrom: length + 5 to: handshakeBuffer size.
	^{message first. message copyFrom: 5 to: message size. message}
!
readRecordUntil: deadline
	"The next record that is not a change_cipher_spec, decrypted: {content type. content}; #end at the end of the stream or after close_notify; nil if deadline passed."
	| available type length record header |
	[available := self fill: 5 until: deadline.
	 available == true ifFalse: [^available ifNil: [nil] ifNotNil: [#end]].
	 type := input at: inStart.
	 (type between: 20 and: 23) ifFalse: [^TLSError signal: 'not a TLS record (content type ', type printString, ')' alert: #unexpectedMessage].
	 (input at: inStart + 1) = 3 ifFalse: [^TLSError signal: 'not a TLS record (version ', (input at: inStart + 1) printString, ')' alert: #decodeError].
	 length := ((input at: inStart + 3) bitShift: 8) + (input at: inStart + 4).
	 length > (readCipher isNil ifTrue: [16384] ifFalse: [16384 + 256]) ifTrue: [
		^TLSError signal: 'a record of ', length printString, ' bytes' alert: #recordOverflow].
	 available := self fill: 5 + length until: deadline.
	 available == true ifFalse: [^available ifNil: [nil] ifNotNil: [#end]].
	 header := input copyFrom: inStart to: inStart + 4.
	 record := self unprotect: (input copyFrom: inStart + 5 to: inStart + 4 + length) type: type header: header.
	 inStart := inStart + 5 + length.
	 record isNil] whileTrue.
	^record
!
unprotect: body type: type header: header
	"{content type. content} of a record; nil for one to skip."
	| record |
	type = 20 ifTrue: [
		(state == #handshake and: [body = #[1]]) ifTrue: [^nil].
		^TLSError signal: 'an unexpected change_cipher_spec' alert: #unexpectedMessage].
	(readCipher isNil or: [type = 21]) ifTrue: [
		type = 23 ifTrue: [^TLSError signal: 'application data before the keys' alert: #unexpectedMessage].
		^self content: body type: type].
	type = 23 ifFalse: [^TLSError signal: 'an unprotected record after the keys changed' alert: #unexpectedMessage].
	record := readCipher open: body header: header.
	^self content: record last type: record first
!
content: bytes type: type
	type = 21 ifTrue: [^self receiveAlert: bytes].
	(bytes isEmpty and: [type ~= 23]) ifTrue: [^TLSError signal: 'an empty record' alert: #unexpectedMessage].
	(type = 22 or: [type = 23]) ifFalse: [^TLSError signal: 'a record of content type ', type printString alert: #unexpectedMessage].
	^{type. bytes}
!
receiveAlert: bytes
	bytes size = 2 ifFalse: [^TLSError signal: 'decode error: an alert of ', bytes size printString, ' bytes' alert: #decodeError].
	(bytes at: 2) = 0 ifTrue: [^#end].
	(bytes at: 2) = 90 ifTrue: [^nil].
	^TLSError peerAlert: (bytes at: 2)
!
fill: count until: deadline
	"Have count unread bytes in input: answer true, nil if deadline passed first, false at the end of the stream."
	| received |
	[input size - inStart + 1 >= count] whileFalse: [
		received := socket receiveInto: scratch timeout: (deadline isNil ifFalse: [deadline - Time millisecondClockValue max: 0]).
		received isNil ifTrue: [^nil].
		received = 0 ifTrue: [^false].
		input := (input copyFrom: inStart to: input size), (scratch copyFrom: 1 to: received).
		inStart := 1].
	^true
!
sendPlaintext: bytes type: type version: version
	(socket sendAll: (TLSWriter new u8: type; u16: version; vector16: bytes; contents)) ifFalse: [
		^TLSError signal: 'the server closed the connection' alert: nil]
!
sendRecord: bytes type: type
	(socket sendAll: (writeCipher seal: bytes type: type padding: (self paddingFor: bytes size))) ifFalse: [
		^TLSError signal: 'the server closed the connection' alert: nil]
!
sendChangeCipherSpec
	"Middlebox compatibility (section D.4): once, before the second flight or the second ClientHello."
	(sentChangeCipherSpec or: [hello sessionId isEmpty]) ifTrue: [^self].
	sentChangeCipherSpec := true.
	self sendPlaintext: #[1] type: 20 version: 16r0303
!
paddingFor: count
	padding <= 1 ifTrue: [^0].
	^(count + padding - 1) // padding * padding - count min: 16384 - count
!
abort: aTLSError
	"Send the alert that says why (unless the server sent one), then close."
	state == #closed ifTrue: [^self].
	failure := aTLSError messageText.
	(aTLSError alert notNil and: [aTLSError isFromPeer not]) ifTrue: [
		sendLock critical: [
			[socket sendAll: (self alertRecord: aTLSError alertCode)] on: Error do: [:e | e return: nil]] ifLocked: []].
	state := #closed.
	socket close
!
alertRecord: code
	| content |
	content := ByteArray with: 2 with: code.
	^writeCipher isNil
		ifTrue: [TLSWriter new u8: 21; u16: 16r0303; vector16: content; contents]
		ifFalse: [writeCipher seal: content type: 21 padding: 0]
! !

!TLSClientConnection methodsFor: 'transcript'!
addToTranscript: bytes
	transcript nextPutAll: bytes
!
transcriptHash
	^suite hashClass hash: transcript contents
! !

!TLSClientConnection methodsFor: 'key exchange'!
keySharesFor: someGroups
	^someGroups asArray collect: [:each | {each. self publicKeyFor: each private: (privateKeys at: each)}]
!
newPrivateKeyFor: group
	group = 16r1D ifTrue: [^X25519 newPrivateKey].
	group = 16r17 ifTrue: [^EcPrivateKey newOn: #p256].
	^TLSError signal: 'no key exchange for the group ', group printString alert: #internalError
!
publicKeyFor: group private: key
	group = 16r1D ifTrue: [^X25519 publicKeyFor: key].
	group = 16r17 ifTrue: [^key publicKeyBytes].
	^TLSError signal: 'no key exchange for the group ', group printString alert: #internalError
!
sharedSecretFor: group private: key peer: peerKey
	group = 16r1D ifTrue: [
		peerKey size = 32 ifFalse: [^TLSError signal: 'an X25519 key share of ', peerKey size printString, ' bytes' alert: #illegalParameter].
		^[X25519 sharedSecret: key peer: peerKey] on: CryptoError do: [:e | TLSError signal: e messageText alert: #illegalParameter]].
	group = 16r17 ifTrue: [
		(peerKey size = 65 and: [peerKey first = 4]) ifFalse: [^TLSError signal: 'a secp256r1 key share that is not an uncompressed point' alert: #illegalParameter].
		^[key sharedSecret: peerKey] on: CryptoError do: [:e | TLSError signal: e messageText alert: #illegalParameter]].
	^TLSError signal: 'no key exchange for the group ', group printString alert: #internalError
!
validator
	validator isNil ifTrue: [validator := CertificateValidator new trustStore: TrustStore default].
	^validator
! !

!TLSClientConnection methodsFor: 'testing'!
replayClientHello: bytes privateKey: x25519PrivateKey
	"Send the ClientHello bytes (with an X25519 key share of x25519PrivateKey) instead of a new one: for tests that replay a recorded handshake (RFC 8448)."
	hello := TLSClientHello fromBytes: bytes.
	privateKeys := Dictionary new.
	privateKeys at: 16r1D put: x25519PrivateKey
! !

!TLSClientConnection class methodsFor: 'instance creation'!
on: aSocket host: hostName
	"A connection over the connected socket aSocket to the server hostName, before the handshake."
	^self new setSocket: aSocket host: hostName
! !

!TLSClientConnection class methodsFor: 'constants'!
supportedGroups
	"x25519, secp256r1."
	^#(16r1D 16r17)
!
signatureSchemes
	"rsa_pss_rsae_sha256, rsa_pss_rsae_sha384, ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384, rsa_pkcs1_sha256, rsa_pkcs1_sha384 (the last two for certificates only)."
	^#(16r0804 16r0805 16r0403 16r0503 16r0401 16r0501)
!
certificateOnlySchemes
	^#(16r0401 16r0501)
!
maxHandshakeMessage
	"The longest handshake message accepted: certificate chains run to a few kilobytes."
	^262144
!
messageName: type
	| pairs |
	pairs := #(1 'ClientHello' 2 'ServerHello' 4 'NewSessionTicket' 5 'EndOfEarlyData' 8 'EncryptedExtensions' 11 'Certificate'
		13 'CertificateRequest' 15 'CertificateVerify' 20 'Finished' 24 'KeyUpdate' 254 'message_hash').
	1 to: pairs size by: 2 do: [:i | (pairs at: i) = type ifTrue: [^pairs at: i + 1]].
	^'handshake message ', type printString
!
versionName: code
	code = 16r0303 ifTrue: [^'TLS 1.2'].
	code = 16r0302 ifTrue: [^'TLS 1.1'].
	code = 16r0301 ifTrue: [^'TLS 1.0'].
	^code printString
!
serverNameFor: hostName
	"The server_name to send for hostName: nil for an IP address; no trailing dot."
	(hostName includes: $:) ifTrue: [^nil].
	(hostName allSatisfy: [:c | c isDigit or: [c = $.]]) ifTrue: [^nil].
	^(hostName notEmpty and: [hostName last = $.])
		ifTrue: [hostName copyFrom: 1 to: hostName size - 1]
		ifFalse: [hostName]
!
now
	"The time certificates must be valid at: seconds since 1970 UTC."
	^Time utcMicroseconds // 1000000
! !
