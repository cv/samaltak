VMPlatformModule subclass: #PlatformTLS
	instanceVariableNames: 'sslContext openSSL retryHead'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformTLS comment: 'TLS client connections (OpenSSL 3) in the socket table (kind PF_FD_TLS, i = the descriptor, ptr = the SSL), polled and signaled like sockets (PlatformSockets). start:host: turns a connected socket into one; handshake: advances the handshake (SNI, the certificate verified against the default trust store (SSL_CTX_set_default_verify_paths) and for the host name) as far as it can without waiting. The handshake, reads and writes are non-blocking: one that would block arms the semaphore OpenSSL waits for. OpenSSL may hold decrypted bytes while the descriptor is not readable, so read until "would block" before waiting.'!

!PlatformTLS class methodsFor: 'declaring'!
declarations
	^#((sslContext 'SSL_CTX *') (openSSL OpenSSL) (retryHead 'tls_send_retry *'))
! !

!PlatformTLS methodsFor: 'private'!
failSSL: what
	"Set the error from OpenSSL's error queue, from errno if it is empty (0: the peer closed the connection)."
	<function>
	| e buf |
	e := openSSL getError.
	e = 0
		ifTrue: [posixIO errno = 0
			ifTrue: [common setError: '%s: connection closed by the peer' with: what]
			ifFalse: [common failOS: what code: posixIO errno]]
		ifFalse: [
			buf := self local: 'char[256]'.
			openSSL errorString: e into: buf size: 256.
			common setError: '%s: %s' with: what with: buf]
!
context
	"Make the client context on first use; false (and the error set) if it cannot be."
	<function>
	sslContext notNull ifTrue: [^true].
	openSSL clearError.
	sslContext := openSSL newContext: openSSL clientMethod.
	sslContext isNull ifTrue: [
		self failSSL: 'SSL_CTX_new'.
		^false].
	openSSL setDefaultVerifyPaths: sslContext.
	openSSL setVerify: sslContext mode: openSSL SSL_VERIFY_PEER callback: self null.
	openSSL setMode: sslContext mode: (openSSL SSL_MODE_ENABLE_PARTIAL_WRITE bitOr: openSSL SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER).
	openSSL setOptions: sslContext options: openSSL SSL_OP_IGNORE_UNEXPECTED_EOF.
	^true
!
sslOf: h
	"The SSL of handle h, NULL (and the error set) if it is none."
	<function>
	<returns: 'SSL *'>
	| o |
	o := sockets fdGet: h kind: PF_FD_TLS.
	o isNull ifTrue: [^self null].
	^o ptr
!
failed: ssl handle: h what: what
	"After a read or write that did nothing: 0 at EOF, -1 would block (arming the semaphore OpenSSL waits for), -2 error."
	<function>
	| e |
	e := openSSL error: ssl result: 0.
	e = openSSL SSL_ERROR_WANT_READ ifTrue: [
		sockets armRead: h.
		^-1].
	e = openSSL SSL_ERROR_WANT_WRITE ifTrue: [
		sockets armWrite: h when: true.
		^-1].
	e = openSSL SSL_ERROR_ZERO_RETURN ifTrue: [^0].
	self failSSL: what.
	^-2
! !

!PlatformTLS methodsFor: 'connections'!
start: s host: hostName
	"Make the connected socket s a TLS connection to hostName, the same handle (without semaphores); 0 (and the error set) on failure, s left a socket."
	<export>
	| o ssl |
	self context ifFalse: [^0].
	o := sockets fdGet: s kind: PF_FD_SOCKET.
	o isNull ifTrue: [^0].
	openSSL clearError.
	ssl := openSSL newSSL: sslContext.
	ssl isNull ifTrue: [
		self failSSL: 'SSL_new'.
		^0].
	((openSSL setFd: ssl fd: o i asInt32) ~= 1
		or: [(openSSL setServerName: ssl name: hostName) ~= 1
		or: [(openSSL setHost: ssl name: hostName) ~= 1]]) ifTrue: [
			self failSSL: 'TLS'.
			openSSL freeSSL: ssl.
			^0].
	openSSL setConnectState: ssl.
	sockets semaphores: s kind: PF_FD_SOCKET read: 0 write: 0.
	o kind: PF_FD_TLS.
	o ptr: ssl.
	^s
!
handshake: h
	"Go on with the handshake of h: 1 done, 0 it waits for the peer (arming the semaphore OpenSSL waits for), -1 (and the error set) it failed."
	<export>
	| ssl r e v |
	ssl := self sslOf: h.
	ssl isNull ifTrue: [^-1].
	openSSL clearError.
	r := openSSL connect: ssl.
	r = 1 ifTrue: [^1].
	e := openSSL error: ssl result: r.
	e = openSSL SSL_ERROR_WANT_READ ifTrue: [
		sockets armRead: h.
		^0].
	e = openSSL SSL_ERROR_WANT_WRITE ifTrue: [
		sockets armWrite: h when: true.
		^0].
	v := openSSL verifyResult: ssl.
	v ~= openSSL X509_V_OK
		ifTrue: [common setError: 'TLS %s: certificate verify failed: %s' with: (openSSL serverName: ssl type: openSSL TLSEXT_NAMETYPE_host_name) with: (openSSL verifyErrorString: v)]
		ifFalse: [self failSSL: 'TLS handshake'].
	^-1
!
recv: h into: buf count: n
	"0 at EOF, -1 would block, -2 error."
	<var: #buf type: 'void *'>
	<export>
	| ssl done |
	ssl := self sslOf: h.
	ssl isNull ifTrue: [^-2].
	sockets armRead: h.
	done := self local: 'size_t'.
	openSSL clearError.
	(openSSL read: ssl into: buf count: n done: done) = 1 ifTrue: [^done value asInt64].
	^self failed: ssl handle: h what: 'TLS recv'
!
recvBorrowed: h into: buf count: n
	"OpenSSL returns at most one application-data record per read. Keep the writable heap slice at the copy boundary, not in OpenSSL."
	<function>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| scratch count r |
	scratch := self local: 'uint8_t[16384]'.
	count := n < 16384 ifTrue: [n] ifFalse: [16384 asUInt64].
	r := self recv: h into: scratch count: count.
	r > 0 ifTrue: [libc memcpy: buf from: scratch size: r asUInt64].
	^r
!
sendOwned: h bytes: buf count: n
	"Never pass a heap borrow to OpenSSL. Allocate ownership before the write: on WANT_READ/WRITE keep the same bytes and length until completion or close."
	<function>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| ssl retry staged r |
	ssl := self sslOf: h.
	ssl isNull ifTrue: [^-2].
	retry := self sendRetryOf: h.
	retry notNull ifTrue: [^self retry: retry ssl: ssl bytes: buf count: n].
	retry := self cCoerce: (libc malloc: (self sizeof: 'tls_send_retry') + (n = 0 ifTrue: [1 asUInt64] ifFalse: [n])) to: 'tls_send_retry *'.
	retry isNull ifTrue: [
		common setError: 'out of memory staging TLS send'.
		^-2].
	staged := self cCoerce: retry + 1 to: 'uint8_t *'.
	n > 0 ifTrue: [libc memcpy: staged from: buf size: n].
	r := self write: ssl handle: h bytes: staged count: n.
	r = -1
		ifTrue: [
			retry handle: h.
			retry count: n.
			retry next: retryHead.
			retryHead := retry]
		ifFalse: [libc free: retry].
	^r
!
sendRetryOf: h
	"The list is empty outside candidate writes that returned WANT_*."
	<function>
	<var: #h type: 'int32_t'>
	<returns: 'tls_send_retry *'>
	| retry |
	retry := retryHead.
	[retry notNull and: [retry handle ~= h]] whileTrue: [retry := retry next].
	^retry
!
retry: pending ssl: ssl bytes: buf count: n
	<function>
	<var: #pending type: 'tls_send_retry *'>
	<var: #ssl type: 'SSL *'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| staged r |
	staged := self cCoerce: pending + 1 to: 'const uint8_t *'.
	(n ~= pending count or: [n > 0 and: [(libc memcmp: buf with: staged size: n) ~= 0]]) ifTrue: [
		common setError: 'TLS send retry requires the same bytes and count'.
		^-2].
	r := self write: ssl handle: pending handle bytes: staged count: n.
	r ~= -1 ifTrue: [self freeRetry: pending].
	^r
!
freeRetry: pending
	<function>
	<var: #pending type: 'tls_send_retry *'>
	| previous |
	pending = retryHead
		ifTrue: [retryHead := pending next]
		ifFalse: [
			previous := retryHead.
			[previous next ~= pending] whileTrue: [previous := previous next].
			previous next: pending next].
	libc free: pending
!
write: ssl handle: h bytes: buf count: n
	<function>
	<var: #ssl type: 'SSL *'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| done |
	done := self local: 'size_t'.
	openSSL clearError.
	(openSSL write: ssl bytes: buf count: n done: done) = 1 ifTrue: [
		sockets armWrite: h when: done value < n.
		^done value asInt64].
	^self failed: ssl handle: h what: 'TLS send'
!
close: h
	<export>
	| ssl ok retry |
	ssl := self sslOf: h.
	ssl isNull ifTrue: [^false].
	ok := sockets close: h kind: PF_FD_TLS.
	openSSL freeSSL: ssl.
	retry := self sendRetryOf: h.
	retry notNull ifTrue: [self freeRetry: retry].
	^ok
!
semaphores: h read: readIndex write: writeIndex
	<export>
	^sockets semaphores: h kind: PF_FD_TLS read: readIndex write: writeIndex
! !

VMStruct subclass: #TLSSendRetry
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

TLSSendRetry comment: 'Allocated together with the native bytes immediately after the header. Only linked while a candidate write waits for OpenSSL readiness; no heap borrow or TLS start allocation.'!

!TLSSendRetry class methodsFor: 'declaring'!
cName
	^'tls_send_retry'
!
fields
	^#((next 'tls_send_retry *') (handle int32_t) (count uint64_t))
! !
