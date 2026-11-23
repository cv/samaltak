!SDLPlatform methodsFor: 'socket, TLS and terminal FFI'!
ffiSocketListen: name count: n port: p backlog: backlog
	"Use counted text and the existing handle-based TCP backend."
	<function>
	<approvedFFI: 540 symbol: 'platform_sockets_listen' arguments: #(8 3 3) result: 1>
	<var: #name type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #p type: 'int64_t'>
	<var: #backlog type: 'int64_t'>
	<returns: 'int32_t'>
	| c result |
	c := nativeCountedText copyTerminated: name size: n.
	c isNull ifTrue: [^0].
	result := sockets listen: c port: p asInt32 backlog: backlog asInt32.
	libc free: c.
	^result
!
ffiSocketConnect: name count: n port: p
	<function>
	<approvedFFI: 541 symbol: 'platform_sockets_connect' arguments: #(8 3) result: 1>
	<var: #name type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #p type: 'int64_t'>
	<returns: 'int32_t'>
	| c result |
	c := nativeCountedText copyTerminated: name size: n.
	c isNull ifTrue: [^0].
	result := sockets connect: c port: p asInt32.
	libc free: c.
	^result
!
ffiSocketAccept: h
	"Positive handle, zero pending, negative failure."
	<function>
	<approvedFFI: 542 symbol: 'platform_sockets_accept' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	| pending hClient |
	pending := self local: 'bool'.
	hClient := sockets accept: h asInt32 wouldBlock: pending.
	hClient ~= 0 ifTrue: [^hClient].
	^pending value ifTrue: [0] ifFalse: [-1]
!
ffiSocketRecv: h bytes: buf count: n
	<function>
	<approvedFFI: 543 symbol: 'platform_sockets_recv' arguments: #(3 9) result: 1>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	n > 16r7FFFFFFF ifTrue: [^self ffiSocketCountOverflow].
	^(sockets recv: h asInt32 into: buf count: n) asInt32
!
ffiSocketSend: h bytes: buf count: n
	<function>
	<approvedFFI: 544 symbol: 'platform_sockets_send' arguments: #(3 8) result: 1>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	n > 16r7FFFFFFF ifTrue: [^self ffiSocketCountOverflow].
	^(sockets send: h asInt32 bytes: buf count: n) asInt32
!
ffiSocketClose: h
	<function>
	<approvedFFI: 545 symbol: 'platform_sockets_close' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^((sockets close: h asInt32) ifTrue: [1] ifFalse: [0]) asInt32
!
ffiSocketSemaphore: h read: r write: w
	<function>
	<approvedFFI: 546 symbol: 'platform_sockets_semaphore' arguments: #(3 3 3) result: 1>
	<var: #h type: 'int64_t'>
	<var: #r type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<returns: 'int32_t'>
	^((sockets semaphores: h asInt32 read: r asInt32 write: w asInt32) ifTrue: [1] ifFalse: [0]) asInt32
!
ffiSocketLocalPort: h
	<function>
	<approvedFFI: 547 symbol: 'platform_sockets_local_port' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^(sockets localPort: h asInt32) asInt32
!
ffiSocketLookup: name count: n
	<function>
	<approvedFFI: 548 symbol: 'platform_sockets_lookup' arguments: #(8) result: 1>
	<var: #name type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| c result |
	c := nativeCountedText copyTerminated: name size: n.
	c isNull ifTrue: [^0].
	result := sockets lookup: c.
	libc free: c.
	^result
!
ffiSocketConnected: h
	<function>
	<approvedFFI: 549 symbol: 'platform_sockets_connected' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^sockets connected: h asInt32
!
ffiTLSStart: h host: name count: n
	<function>
	<approvedFFI: 550 symbol: 'platform_tls_start' arguments: #(3 8) result: 1>
	<var: #h type: 'int64_t'>
	<var: #name type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	| c result |
	c := nativeCountedText copyTerminated: name size: n.
	c isNull ifTrue: [^0].
	result := tls start: h asInt32 host: c.
	libc free: c.
	^result
!
ffiTLSRecv: h bytes: buf count: n
	<function>
	<approvedFFI: 551 symbol: 'platform_tls_recv' arguments: #(3 9) result: 1>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	n > 16r7FFFFFFF ifTrue: [^self ffiSocketCountOverflow].
	^(tls recvBorrowed: h asInt32 into: buf count: n) asInt32
!
ffiTLSSend: h bytes: buf count: n
	<function>
	<approvedFFI: 552 symbol: 'platform_tls_send' arguments: #(3 8) result: 1>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	n > 16r7FFFFFFF ifTrue: [^self ffiSocketCountOverflow].
	^(tls sendOwned: h asInt32 bytes: buf count: n) asInt32
!
ffiTLSClose: h
	<function>
	<approvedFFI: 553 symbol: 'platform_tls_close' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^((tls close: h asInt32) ifTrue: [1] ifFalse: [0]) asInt32
!
ffiTLSSemaphore: h read: r write: w
	<function>
	<approvedFFI: 554 symbol: 'platform_tls_semaphore' arguments: #(3 3 3) result: 1>
	<var: #h type: 'int64_t'>
	<var: #r type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<returns: 'int32_t'>
	^((tls semaphores: h asInt32 read: r asInt32 write: w asInt32) ifTrue: [1] ifFalse: [0]) asInt32
!
ffiTLSHandshake: h
	<function>
	<approvedFFI: 555 symbol: 'platform_tls_handshake' arguments: #(3) result: 1>
	<var: #h type: 'int64_t'>
	<returns: 'int32_t'>
	^tls handshake: h asInt32
!
ffiPtyRead: h bytes: buf count: n
	<function>
	<approvedFFI: 561 symbol: 'pty_read' arguments: #(3 9) result: 1>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	n > 16r7FFFFFFF ifTrue: [^self ffiSocketCountOverflow].
	^(sockets ptyRead: h asInt32 into: buf count: n) asInt32
!
ffiPtyWrite: h bytes: buf count: n
	<function>
	<approvedFFI: 562 symbol: 'pty_write' arguments: #(3 8) result: 1>
	<var: #h type: 'int64_t'>
	<var: #buf type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int32_t'>
	n > 16r7FFFFFFF ifTrue: [^self ffiSocketCountOverflow].
	^(sockets ptyWrite: h asInt32 bytes: buf count: n) asInt32
!
ffiPtySemaphore: h read: r write: w
	<function>
	<approvedFFI: 564 symbol: 'pty_semaphore' arguments: #(3 3 3) result: 1>
	<var: #h type: 'int64_t'>
	<var: #r type: 'int64_t'>
	<var: #w type: 'int64_t'>
	<returns: 'int32_t'>
	^((sockets ptySemaphores: h asInt32 read: r asInt32 write: w asInt32) ifTrue: [1] ifFalse: [0]) asInt32
!
ffiPtyWait: h blocking: block
	"Exit status (or 128 + signal), -1 pending, -2 failure. Blocking uses the same VM thread as the original wait."
	<function>
	<approvedFFI: 565 symbol: 'pty_wait' arguments: #(3 1) result: 1>
	<var: #h type: 'int64_t'>
	<var: #block type: 'int32_t'>
	<returns: 'int32_t'>
	| status done |
	(block ~= 0 and: [block ~= 1]) ifTrue: [^self ffiSocketInvalidBlock].
	status := self local: 'int32_t'.
	done := self local: 'bool'.
	(ptys wait: h asInt32 block: block ~= 0 status: status done: done) ifFalse: [^-2].
	^done value ifTrue: [status value] ifFalse: [-1]
!
ffiSocketCountOverflow
	<function>
	<returns: 'int32_t'>
	common setError: 'socket or pty byte count exceeds INT32_MAX'.
	^-2
!
ffiSocketInvalidBlock
	<function>
	<returns: 'int32_t'>
	common setError: 'pty wait block flag must be 0 or 1'.
	^-2
! !
