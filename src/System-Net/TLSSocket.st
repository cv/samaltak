RemoteSocket subclass: #TLSSocket
	instanceVariableNames: 'connection'
	classVariableNames: 'Roots Engine TLSStartCall TLSRecvCall TLSSendCall TLSCloseCall TLSSemaphoreCall TLSHandshakeCall'
	package: 'System-Net'!

TLSSocket comment: 'I am a TLS client connection: over the platform''s TLS primitives (OpenSSL, docs/platform.md), or over the VM''s TLS engine (mbedTLS: an MbedTLSConnection on a RemoteSocket; docs/tls.md) where those fail, as on UEFI, where the socket is the image''s own TCP (NetworkStack), or when forced (TLSSocket engine: #mbedtls). Connecting is a RemoteSocket''s connect, then the handshake, which verifies the server''s certificate for the host name: against the system''s trust store with OpenSSL, against trustStore (TrustStore default''s roots unless set) with the engine. Each waits on Semaphores, and the whole connect gives up after connectTimeout, so the VM never blocks and terminating the connecting Process cancels it. Receiving and sending wait on Semaphores like a RemoteSocket''s; a connection that fails reads as ended (receiving answers 0, sending false).

	(TLSSocket connectTo: ''example.com'' port: 443) sendAll: ...
	TLSSocket trustStore: (TrustStore new add: testCA; yourself).	"for tests: the engine trusts just that"'!

!TLSSocket methodsFor: 'initialization'!
setConnection: anMbedTLSConnection
	connection := anMbedTLSConnection
! !

!TLSSocket methodsFor: 'accessing'!
connection
	"The MbedTLSConnection under me, or nil over OpenSSL."
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
		aStream nextPutAll: ' (mbedTLS'.
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
	(self engine == #platform and: [plain handle >= 0]) ifTrue: [
		h := [self primStart: plain handle host: hostString] ifCurtailed: [plain close]].
	h isNil ifTrue: [^self engineOver: plain host: hostString port: port until: deadline].
	"the handle passes from plain to me"
	[plain forget.
	 socket := self onHandle: h] ifCurtailed: [
		socket isNil ifTrue: [self primClose: h]].
	reason := [socket handshakeUntil: deadline] ifCurtailed: [socket close].
	reason isNil ifTrue: [^socket].
	socket close.
	^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': ', reason
!
engineOver: plain host: hostString port: port until: deadline
	"The VM's TLS engine over the connected RemoteSocket plain."
	| connection reason |
	MbedTLSConnection isAvailable ifFalse: [
		plain close.
		^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': TLS handshake: this VM has no TLS here'].
	connection := MbedTLSConnection on: plain host: hostString.
	Roots isNil ifFalse: [connection trustStore: Roots].
	reason := [[connection handshakeUntil: deadline. nil] on: TLSError do: [:e | e return: e messageText]]
		ifCurtailed: [connection close].
	reason isNil ifTrue: [^self new setConnection: connection].
	connection close.
	^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': TLS handshake: ', reason
! !

!TLSSocket class methodsFor: 'configuring'!
engine
	"What makes my connections: #platform (OpenSSL's primitives where they work, else the VM's engine) or #mbedtls (the VM's engine, mbedTLS, even where the platform's works)."
	^Engine ifNil: [#platform]
!
engine: aSymbol
	Engine := aSymbol
!
trustStore
	"The roots the engine trusts."
	^Roots ifNil: [TrustStore default]
!
trustStore: aTrustStoreOrNil
	"Trust just these roots with the engine (nil: TrustStore default's again)."
	Roots := aTrustStoreOrNil
!
trustStoreSetting
	"What trustStore: set: a TrustStore, or nil for TrustStore default (tests put it back)."
	^Roots
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
