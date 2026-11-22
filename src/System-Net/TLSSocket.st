RemoteSocket subclass: #TLSSocket
	instanceVariableNames: 'connection'
	classVariableNames: 'Roots UseSmalltalkTLS'
	package: 'System-Net'!

TLSSocket comment: 'I am a TLS client connection: over the platform''s TLS primitives (OpenSSL, docs/platform.md), or over the Smalltalk TLS 1.3 client (a TLSClientConnection on a RemoteSocket; docs/tls.md) where those fail, as on UEFI, where the socket is the image''s own TCP (NetworkStack), or when forced (TLSSocket useSmalltalkTLS: true). Connecting is a RemoteSocket''s connect, then the handshake, which verifies the server''s certificate for the host name: against the system''s trust store with OpenSSL, against trustStore (TrustStore default unless set) with the Smalltalk TLS. Each waits on Semaphores, and the whole connect gives up after connectTimeout, so the VM never blocks and terminating the connecting Process cancels it. Receiving and sending wait on Semaphores like a RemoteSocket''s; a connection that fails reads as ended (receiving answers 0, sending false).

	(TLSSocket connectTo: ''example.com'' port: 443) sendAll: ...
	TLSSocket trustStore: (TrustStore new add: testCA; yourself).	"for tests: the Smalltalk TLS trusts just that"'!

!TLSSocket methodsFor: 'initialization'!
setConnection: aTLSClientConnection
	connection := aTLSClientConnection
! !

!TLSSocket methodsFor: 'accessing'!
connection
	"The TLSClientConnection under me, or nil over OpenSSL."
	^connection
!
isOpen
	connection isNil ifTrue: [^super isOpen].
	^connection isOpen
!
localPort
	connection isNil ifTrue: [^super localPort].
	^connection socket localPort
! !

!TLSSocket methodsFor: 'operations'!
receiveNowInto: aByteArray
	connection isNil ifTrue: [^super receiveNowInto: aByteArray].
	^[connection receiveInto: aByteArray timeout: 0] on: TLSError do: [:e | e return: 0]
!
receiveInto: aByteArray timeout: milliseconds
	connection isNil ifTrue: [^super receiveInto: aByteArray timeout: milliseconds].
	^[connection receiveInto: aByteArray timeout: milliseconds] on: TLSError do: [:e | e return: 0]
!
sendAll: bytes
	connection isNil ifTrue: [^super sendAll: bytes].
	^[connection sendAll: bytes] on: TLSError do: [:e | e return: false]
!
close
	connection isNil ifTrue: [^super close].
	connection close
!
forget
	connection isNil ifTrue: [^super forget].
	connection forget
! !

!TLSSocket methodsFor: 'private'!
handshakeUntil: deadline
	"Do the TLS handshake unless deadline (a millisecondClockValue) passes first; answer nil once it is done, else why not. The platform signals both my Semaphores when the connection is ready."
	| done |
	[handle isNil ifTrue: [^'closed'].
	 done := self class primHandshake: handle.
	 done == false ifTrue: [^self class lastError].
	 done isNil] whileTrue: [
		(readSemaphore waitTimeoutMSecs: deadline - Time millisecondClockValue) ifTrue: [^'TLS handshake: timed out']].
	^nil
! !

!TLSSocket methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a TLSSocket'.
	connection isNil ifFalse: [
		aStream nextPutAll: ' (Smalltalk TLS'.
		connection isOpen ifFalse: [aStream nextPutAll: ', closed'].
		^aStream nextPut: $)].
	handle isNil ifTrue: [^aStream nextPutAll: ' (closed)'].
	aStream nextPutAll: ' #'; print: handle
! !

!TLSSocket class methodsFor: 'instance creation'!
connectTo: hostString port: port until: deadline
	"A connection to port of the host named hostString, its certificate verified for hostString, by deadline (a millisecondClockValue)."
	| plain h socket reason |
	plain := RemoteSocket connectTo: hostString port: port until: deadline.
	(self useSmalltalkTLS or: [plain handle < 0]) ifFalse: [
		h := [self primStart: plain handle host: hostString] ifCurtailed: [plain close]].
	h isNil ifTrue: [^self smalltalkTLSOver: plain host: hostString port: port until: deadline].
	"the handle passes from plain to me"
	[plain forget.
	 socket := self onHandle: h] ifCurtailed: [
		socket isNil ifTrue: [self primClose: h]].
	reason := [socket handshakeUntil: deadline] ifCurtailed: [socket close].
	reason isNil ifTrue: [^socket].
	socket close.
	^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': ', reason
!
smalltalkTLSOver: plain host: hostString port: port until: deadline
	"The Smalltalk TLS client over the connected RemoteSocket plain."
	| connection reason |
	connection := TLSClientConnection on: plain host: hostString.
	Roots isNil ifFalse: [connection trustStore: Roots].
	reason := [[connection handshakeUntil: deadline. nil] on: TLSError do: [:e | e return: e messageText]]
		ifCurtailed: [connection close].
	reason isNil ifTrue: [^self new setConnection: connection].
	connection close.
	^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': TLS handshake: ', reason
! !

!TLSSocket class methodsFor: 'configuring'!
useSmalltalkTLS
	"Is the Smalltalk TLS forced, even where the platform's works?"
	^UseSmalltalkTLS == true
!
useSmalltalkTLS: aBoolean
	UseSmalltalkTLS := aBoolean
!
trustStore
	"The roots the Smalltalk TLS trusts."
	^Roots ifNil: [TrustStore default]
!
trustStore: aTrustStoreOrNil
	"Trust just these roots with the Smalltalk TLS (nil: TrustStore default again)."
	Roots := aTrustStoreOrNil
!
trustStoreSetting
	"What trustStore: set: a TrustStore, or nil for TrustStore default (tests put it back)."
	^Roots
! !

!TLSSocket class methodsFor: 'primitives'!
primStart: aHandle host: hostName
	"Make the connected socket aHandle a TLS connection to hostName; answer its handle (see primHandshake:), nil on failure."
	<primitive: 'tlsStart'>
	^nil
!
primHandshake: aHandle
	"Answer true once the handshake is done, nil while it waits (a Semaphore is armed), false on failure."
	<primitive: 'tlsHandshake'>
	^false
!
primRecv: aHandle into: bytes start: start count: count
	"Answer the byte count, 0 at end of stream, nil if it would block, -1 on failure."
	<primitive: 'tlsRecv'>
	^-1
!
primSend: aHandle from: bytes start: start count: count
	"Answer the byte count sent, nil if it would block, -1 on failure."
	<primitive: 'tlsSend'>
	^-1
!
primClose: aHandle
	<primitive: 'tlsClose'>
	^nil
!
primSemaphore: aHandle read: readIndex write: writeIndex
	<primitive: 'tlsSemaphore'>
	^RemoteError signal: 'tlsSemaphore failed: ', self lastError
! !
