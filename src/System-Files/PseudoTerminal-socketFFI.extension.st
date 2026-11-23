!PseudoTerminal class methodsFor: 'candidate FFI'!
ffiCandidatePrimRead: h into: bytes start: start count: count
	| binding result |
	bytes class == ByteArray ifFalse: [^self primRead: h into: bytes start: start count: count].
	(count isInteger and: [count > 16r7FFFFFFF]) ifTrue: [^self primRead: h into: bytes start: start count: count].
	binding := PtyReadCall ifNil: [
		PtyReadCall := PlatformFFI bind: #(call 'platform' 'pty_read' (i64 writableBytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^self primRead: h into: bytes start: start count: count].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [false] ifFalse: [result]]
!
ffiCandidatePrimWrite: h from: bytes start: start count: count
	| binding result |
	bytes class == ByteArray ifFalse: [^self primWrite: h from: bytes start: start count: count].
	(count isInteger and: [count > 16r7FFFFFFF]) ifTrue: [^self primWrite: h from: bytes start: start count: count].
	binding := PtyWriteCall ifNil: [
		PtyWriteCall := PlatformFFI bind: #(call 'platform' 'pty_write' (i64 bytesWithLength) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: {bytes. start. count}].
	result == false ifTrue: [^self primWrite: h from: bytes start: start count: count].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [false] ifFalse: [result]]
!
ffiCandidatePrimSemaphore: h read: r write: w
	| binding result |
	binding := PtySemaphoreCall ifNil: [
		PtySemaphoreCall := PlatformFFI bind: #(call 'platform' 'pty_semaphore' (i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke3: h with: r with: w].
	result == false ifTrue: [^self primSemaphore: h read: r write: w].
	^result = 0 ifTrue: [FileError signal: 'ptySemaphore: ', File lastError path: nil] ifFalse: [self]
!
ffiCandidatePrimWait: h blocking: block
	| binding result |
	(block == true or: [block == false]) ifFalse: [^self primWait: h blocking: block].
	binding := PtyWaitCall ifNil: [
		PtyWaitCall := PlatformFFI bind: #(call 'platform' 'pty_wait' (i64 i32) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: h with: (block ifTrue: [1] ifFalse: [0])].
	result == false ifTrue: [^self primWait: h blocking: block].
	^result = -1 ifTrue: [nil] ifFalse: [result < 0 ifTrue: [false] ifFalse: [result]]
! !
