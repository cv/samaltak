RemoteSocket subclass: #TLSSocket
	instanceVariableNames: ''
	classVariableNames: 'TLSStartCall TLSRecvCall TLSSendCall TLSCloseCall TLSSemaphoreCall TLSHandshakeCall'
	package: 'System-Net'!

TLSSocket comment: 'I am a TLS client connection over the platform''s TLS primitives (docs/platform.md). Connecting is a RemoteSocket''s connect, then the handshake, which verifies the server''s certificate against the system''s trust store and for the host name; each waits on Semaphores, and the whole connect gives up after connectTimeout, so the VM never blocks and terminating the connecting Process cancels it. Receiving and sending wait on Semaphores like a RemoteSocket''s.

	(TLSSocket connectTo: ''example.com'' port: 443) sendAll: ...'!

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
	handle isNil ifTrue: [^aStream nextPutAll: ' (closed)'].
	aStream nextPutAll: ' #'; print: handle
! !

!TLSSocket class methodsFor: 'instance creation'!
connectTo: hostString port: port until: deadline
	"A connection to port of the host named hostString, its certificate verified for hostString, by deadline (a millisecondClockValue)."
	| plain h socket reason |
	plain := RemoteSocket connectTo: hostString port: port until: deadline.
	"the handle passes from plain to me"
	[h := self primStart: plain handle host: hostString.
	 h isNil ifTrue: [^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': ', self lastError].
	 plain forget.
	 socket := self onHandle: h] ifCurtailed: [
		socket isNil ifTrue: [
			h isNil ifTrue: [plain close] ifFalse: [
				plain forget.
				self primClose: h]]].
	reason := [socket handshakeUntil: deadline] ifCurtailed: [socket close].
	reason isNil ifTrue: [^socket].
	socket close.
	^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': ', reason
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
