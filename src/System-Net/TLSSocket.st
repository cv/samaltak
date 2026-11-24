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
primStart: h host: name
	"Make the connected socket aHandle a TLS connection to hostName; answer its handle (see primHandshake:), nil on failure."
	| binding result text |
	text := PlatformFFI osTextBytes: name.
	text isNil ifTrue: [^nil].
	binding := TLSStartCall ifNil: [
		TLSStartCall := PlatformFFI bind: #(call 'platform' 'platform_tls_start' (i64 bytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {text. 1. text size}].
	result == false ifTrue: [^nil].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
primHandshake: h
	"Answer true once the handshake is done, nil while it waits (a Semaphore is armed), false on failure."
	| binding result |
	binding := TLSHandshakeCall ifNil: [
		TLSHandshakeCall := PlatformFFI bind: #(call 'platform' 'platform_tls_handshake' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^false].
	^result = 0 ifTrue: [nil] ifFalse: [result > 0]
!
primRecv: h into: bytes start: start count: count
	"Answer the byte count, 0 at end of stream, nil if it would block, -1 on failure."
	| binding result |
	bytes class == ByteArray ifFalse: [
		^PlatformIOBuffer readInto: bytes start: start count: count failure: -1
			using: [:slice | self primRecv: h into: slice start: 1 count: count]].
	binding := TLSRecvCall ifNil: [
		TLSRecvCall := PlatformFFI bind: #(call 'platform' 'platform_tls_recv' (i64 writableBytesWithLength) i64)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^-1].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [-1] ifFalse: [result]]
!
primSend: h from: bytes start: start count: count
	"Answer the byte count sent, nil if it would block, -1 on failure."
	| binding result |
	bytes class == ByteArray ifFalse: [
		| slice |
		slice := PlatformIOBuffer writeSliceFrom: bytes start: start count: count.
		slice isNil ifTrue: [^-1].
		^self primSend: h from: slice start: 1 count: count].
	binding := TLSSendCall ifNil: [
		TLSSendCall := PlatformFFI bind: #(call 'platform' 'platform_tls_send' (i64 bytesWithLength) i64)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^-1].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [-1] ifFalse: [result]]
!
primClose: h
	| binding result |
	binding := TLSCloseCall ifNil: [
		TLSCloseCall := PlatformFFI bind: #(call 'platform' 'platform_tls_close' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^nil].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primSemaphore: h read: r write: w
	| binding result |
	binding := TLSSemaphoreCall ifNil: [
		TLSSemaphoreCall := PlatformFFI bind: #(call 'platform' 'platform_tls_semaphore' (i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke3: h with: r with: w].
	result == false ifTrue: [^RemoteError signal: 'tlsSemaphore failed: ', self lastError].
	^result = 0 ifTrue: [RemoteError signal: 'tlsSemaphore failed: ', self lastError] ifFalse: [self]
! !
