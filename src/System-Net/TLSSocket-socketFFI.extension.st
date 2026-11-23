!TLSSocket class methodsFor: 'candidate FFI'!
ffiCandidatePrimStart: h host: name
	| binding result text |
	text := PlatformFFI textBytes: name.
	text isNil ifTrue: [^self primStart: h host: name].
	binding := TLSStartCall ifNil: [
		TLSStartCall := PlatformFFI bind: #(call 'platform' 'platform_tls_start' (i64 bytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {text. 1. text size}].
	result == false ifTrue: [^self primStart: h host: name].
	^result <= 0 ifTrue: [nil] ifFalse: [result]
!
ffiCandidatePrimRecv: h into: bytes start: start count: count
	| binding result |
	bytes class == ByteArray ifFalse: [^self primRecv: h into: bytes start: start count: count].
	(count isInteger and: [count > 16r7FFFFFFF]) ifTrue: [^self primRecv: h into: bytes start: start count: count].
	binding := TLSRecvCall ifNil: [
		TLSRecvCall := PlatformFFI bind: #(call 'platform' 'platform_tls_recv' (i64 writableBytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^self primRecv: h into: bytes start: start count: count].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [-1] ifFalse: [result]]
!
ffiCandidatePrimSend: h from: bytes start: start count: count
	| binding result |
	bytes class == ByteArray ifFalse: [^self primSend: h from: bytes start: start count: count].
	(count isInteger and: [count > 16r7FFFFFFF]) ifTrue: [^self primSend: h from: bytes start: start count: count].
	binding := TLSSendCall ifNil: [
		TLSSendCall := PlatformFFI bind: #(call 'platform' 'platform_tls_send' (i64 bytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^self primSend: h from: bytes start: start count: count].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [-1] ifFalse: [result]]
!
ffiCandidatePrimClose: h
	| binding result |
	binding := TLSCloseCall ifNil: [
		TLSCloseCall := PlatformFFI bind: #(call 'platform' 'platform_tls_close' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^self primClose: h].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
ffiCandidatePrimSemaphore: h read: r write: w
	| binding result |
	binding := TLSSemaphoreCall ifNil: [
		TLSSemaphoreCall := PlatformFFI bind: #(call 'platform' 'platform_tls_semaphore' (i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke3: h with: r with: w].
	result == false ifTrue: [^self primSemaphore: h read: r write: w].
	^result = 0 ifTrue: [RemoteError signal: 'tlsSemaphore failed: ', self lastError] ifFalse: [self]
!
ffiCandidatePrimHandshake: h
	| binding result |
	binding := TLSHandshakeCall ifNil: [
		TLSHandshakeCall := PlatformFFI bind: #(call 'platform' 'platform_tls_handshake' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: h].
	result == false ifTrue: [^self primHandshake: h].
	^result = 0 ifTrue: [nil] ifFalse: [result > 0]
! !
