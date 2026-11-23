!RemoteSocket class methodsFor: 'candidate FFI'!
ffiCandidatePlatformListen: name port: p backlog: backlog
	| binding result text |
	text := PlatformFFI textBytes: name.
	text isNil ifTrue: [^self platformListen: name port: p backlog: backlog].
	binding := SocketListenCall ifNil: [
		SocketListenCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_listen' (bytesWithLength i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke3: {text. 1. text size} with: p with: backlog].
	result == false ifTrue: [^self platformListen: name port: p backlog: backlog].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidatePlatformConnect: name port: p
	| binding result text |
	text := PlatformFFI textBytes: name.
	text isNil ifTrue: [^self platformConnect: name port: p].
	binding := SocketConnectCall ifNil: [
		SocketConnectCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_connect' (bytesWithLength i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: {text. 1. text size} with: p].
	result == false ifTrue: [^self platformConnect: name port: p].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidatePlatformAccept: h
	| binding result |
	binding := SocketAcceptCall ifNil: [
		SocketAcceptCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_accept' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^self platformAccept: h].
	^result < 0 ifTrue: [false] ifFalse: [result = 0 ifTrue: [nil] ifFalse: [result]]
!
ffiCandidatePlatformRecv: h into: bytes start: start count: count
	| binding result |
	bytes class == ByteArray ifFalse: [^self platformRecv: h into: bytes start: start count: count].
	(count isInteger and: [count > 16r7FFFFFFF]) ifTrue: [^self platformRecv: h into: bytes start: start count: count].
	binding := SocketRecvCall ifNil: [
		SocketRecvCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_recv' (i64 writableBytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^self platformRecv: h into: bytes start: start count: count].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [-1] ifFalse: [result]]
!
ffiCandidatePlatformSend: h from: bytes start: start count: count
	| binding result |
	bytes class == ByteArray ifFalse: [^self platformSend: h from: bytes start: start count: count].
	(count isInteger and: [count > 16r7FFFFFFF]) ifTrue: [^self platformSend: h from: bytes start: start count: count].
	binding := SocketSendCall ifNil: [
		SocketSendCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_send' (i64 bytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^self platformSend: h from: bytes start: start count: count].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [-1] ifFalse: [result]]
!
ffiCandidatePlatformClose: h
	| binding result |
	binding := SocketCloseCall ifNil: [
		SocketCloseCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_close' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^self platformClose: h].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
ffiCandidatePlatformSemaphore: h read: r write: w
	| binding result |
	binding := SocketSemaphoreCall ifNil: [
		SocketSemaphoreCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_semaphore' (i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke3: h with: r with: w].
	result == false ifTrue: [^self platformSemaphore: h read: r write: w].
	^result = 0 ifTrue: [RemoteError signal: 'socketSemaphore failed: ', self lastError] ifFalse: [self]
!
ffiCandidatePlatformLocalPort: h
	| binding result |
	binding := SocketLocalPortCall ifNil: [
		SocketLocalPortCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_local_port' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^self platformLocalPort: h].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidatePlatformResolve: name
	| binding result text |
	text := PlatformFFI textBytes: name.
	text isNil ifTrue: [^self platformResolve: name].
	binding := SocketLookupCall ifNil: [
		SocketLookupCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_lookup' (bytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: {text. 1. text size}].
	result == false ifTrue: [^self platformResolve: name].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidatePlatformConnected: h
	| binding result |
	binding := SocketConnectedCall ifNil: [
		SocketConnectedCall := PlatformFFI bind: #(call 'platform' 'platform_sockets_connected' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^self platformConnected: h].
	^result = 0 ifTrue: [nil] ifFalse: [result > 0]
! !
