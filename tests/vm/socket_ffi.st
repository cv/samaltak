"Headless real TCP, verified local TLS, and PTY coverage. Invoked by socket_ffi_test.py."

Object subclass: #SocketFFISmoke
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'SocketFFISmoke'!

!SocketFFISmoke class methodsFor: 'support'!
check: condition because: description
	condition ifFalse: [self error: description]
!
await: operation on: sem
	| answer deadline |
	deadline := Time millisecondClockValue + 5000.
	[(answer := operation value) isNil] whileTrue: [
		(Time millisecondClockValue >= deadline) ifTrue: [self error: 'I/O timeout'].
		sem waitTimeoutMSecs: 10].
	^answer
!
run
	| sockets terminals |
	sockets := [Smalltalk vm platformHandleCounts at: #sockets].
	terminals := [Smalltalk vm platformHandleCounts at: #ptys].
	self check: (sockets value = 0 and: [terminals value = 0]) because: 'expected empty handle tables'.
	self tcp; lookup; tls; terminal; boundary.
	self check: (sockets value = 0 and: [terminals value = 0]) because: 'leaked native handle'.
	^'socket-ffi-ok'
! !

!SocketFFISmoke class methodsFor: 'TCP'!
tcp
	| socket listener client accepted port readable writable ri wi dst payload big sent partial pending total n |
	socket := RemoteSocket.
	listener := socket platformListen: '127.0.0.1' port: 0 backlog: 4.
	self check: listener notNil because: 'listen failed'.
	readable := Semaphore new.
	writable := Semaphore new.
	ri := Smalltalk vm registerExternalSemaphore: readable.
	wi := Smalltalk vm registerExternalSemaphore: writable.
	[
		self check: (socket platformSemaphore: listener read: ri write: 0) == socket because: 'arm accept'.
		self check: (socket platformAccept: listener) isNil because: 'accept must pend'.
		port := socket platformLocalPort: listener.
		self check: (port between: 1 and: 65535) because: 'actual bound port'.
		self check: (socket platformListen: #[49 0 50] port: 0 backlog: 1) isNil because: 'NUL host accepted'.
		client := socket platformConnect: #[49 50 55 46 48 46 48 46 49] port: port.
		self check: client notNil because: 'connect start'.
		socket platformSemaphore: client read: 0 write: wi.
		self check: (self await: [socket platformConnected: client] on: writable) == true because: 'connect completion'.
		self check: (readable waitTimeoutMSecs: 1000) not because: 'accept readiness not rearmed'.
		accepted := socket platformAccept: listener.
		self check: (accepted isInteger and: [accepted > 0]) because: 'accept completion'.
		socket platformSemaphore: accepted read: ri write: 0.
		[readable isSignaled] whileTrue: [readable wait].
		dst := #[9 9 9 9 9] copy.
		self check: (socket platformRecv: accepted into: dst start: 2 count: 3) isNil because: 'empty TCP recv must pend'.
		self check: dst = #[9 9 9 9 9] because: 'pending changed output'.
		payload := #[0 65 66 67 0].
		self check: (socket platformSend: client from: payload start: 2 count: 3) = 3 because: 'TCP send slice'.
		self check: (readable waitTimeoutMSecs: 1000) not because: 'TCP read readiness not rearmed'.
		self check: (self await: [socket platformRecv: accepted into: dst start: 2 count: 3] on: readable) = 3 because: 'TCP recv slice'.
		self check: dst = #[9 65 66 67 9] because: 'recv crossed slice'.
		big := ByteArray new: 8 * 1024 * 1024.
		[writable isSignaled] whileTrue: [writable wait].
		partial := false.
		pending := false.
		total := 0.
		1 to: 12 do: [:i |
			pending ifFalse: [
				sent := socket platformSend: client from: big start: 1 count: big size.
				sent isNil
					ifTrue: [pending := true]
					ifFalse: [
						self check: sent > 0 because: 'TCP flood failed'.
						partial := partial or: [sent < big size].
						total := total + sent]]].
		self check: (pending and: [partial]) because: 'TCP did not partially write then pend'.
		dst := ByteArray new: 65536.
		[total > 0] whileTrue: [
			n := self await: [socket platformRecv: accepted into: dst start: 1 count: dst size] on: readable.
			self check: (n between: 1 and: total) because: 'TCP drain count'.
			total := total - n].
		self check: (writable waitTimeoutMSecs: 1000) not because: 'TCP write readiness not rearmed'.
		socket platformClose: accepted.
		accepted := nil.
		self check: (self await: [socket platformRecv: client into: dst start: 1 count: 5] on: readable) = 0
			because: 'TCP graceful EOF'.
		self check: (socket platformAccept: -1) == false because: 'invalid handle is not pending'.
		self check: (socket platformRecv: -1 into: dst start: 1 count: 1) = -1 because: 'invalid TCP read status'.
		self check: (socket platformSend: -1 from: payload start: 1 count: 1) = -1 because: 'invalid TCP write status'.
		self check: (socket platformClose: -1) isNil because: 'invalid TCP close status'
	] ensure: [
		accepted ifNotNil: [socket platformClose: accepted].
		client ifNotNil: [socket platformClose: client].
		socket platformClose: listener.
		Smalltalk vm unregisterExternalSemaphore: ri.
		Smalltalk vm unregisterExternalSemaphore: wi]
!
lookup
	| socket h sem index dst n answer |
	socket := RemoteSocket.
	h := socket platformResolve: '127.0.0.1'.
	self check: h notNil because: 'lookup did not create reader handle'.
	sem := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: sem.
	[
		socket platformSemaphore: h read: index write: 0.
		dst := ByteArray new: 128.
		answer := WriteStream on: (String new: 40).
		[(n := self await: [socket platformRecv: h into: dst start: 1 count: dst size] on: sem) > 0]
			whileTrue: [answer nextPutAll: (dst first: n) asString].
		self check: n = 0 because: 'resolver did not report EOF'.
		self check: answer contents lines first = '127.0.0.1' because: 'bad numeric lookup'
	] ensure: [
		socket platformClose: h.
		Smalltalk vm unregisterExternalSemaphore: index]
! !

!SocketFFISmoke class methodsFor: 'TLS'!
tls
	| plain hostPort sem index dst h tls payload sent start pending partial n rejected mark send mixed |
	hostPort := (Smalltalk vm getenv: 'SAMALTAK_SOCKET_TEST_PORT') asInteger.
	mark := Smalltalk vm getenv: 'SAMALTAK_SOCKET_TEST_RESUME'.
	plain := RemoteSocket connectTo: '127.0.0.1' port: hostPort.
	tls := TLSSocket.
	sem := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: sem.
	[
		"Failed start must leave native ownership with the TCP socket."
		self check: (tls primStart: plain handle host: #[97 0 98]) isNil because: 'TLS accepted NUL peer name'.
		h := tls primStart: plain handle host: 'localhost'.
		self check: h = plain handle because: 'TLS must transfer the existing handle'.
		plain forget.
		tls primSemaphore: h read: index write: index.
		self check: (self await: [tls primHandshake: h] on: sem) == true because: tls lastError.
		dst := #[9 9 9] copy.
		self check: (tls primRecv: h into: dst start: 2 count: 1) isNil because: 'TLS read must pend before server reply'.
		self check: dst = #[9 9 9] because: 'pending TLS read touched slice'.
		payload := ByteArray new: 4 * 1024 * 1024 + 2.
		payload atAllPut: 65.
		payload at: 1 put: 88; at: payload size put: 88.
		start := 2.
		pending := false.
		partial := false.
		mixed := false.
		send := FFI bind: #(call 'platform' 'platform_tls_send' (i64 bytesWithLength) i64).
		[start < payload size] whileTrue: [
			sent := (pending and: [mixed not])
				ifTrue: [
					| status |
					mixed := true.
					status := send tryInvoke2: h with: {payload. start. payload size - start}.
					self check: status ~~ false because: 'typed TLS retry not admitted'.
					"Raw typed status -1 means pending; the public facade presents it as nil."
					status = -1 ifTrue: [nil] ifFalse: [status]]
				ifFalse: [tls primSend: h from: payload start: start count: payload size - start].
			sent isNil
				ifTrue: [
					pending ifFalse: [
						pending := true.
						payload at: start put: 90.
						rejected := tls primSend: h from: payload start: start count: payload size - start.
						self check: rejected = -1 because: 'changed TLS retry was not rejected'.
						payload at: start put: 65.
						Smalltalk vm garbageCollect.
						"Same bytes, different image object after GC, same in-flight native write."
						payload := payload copy.
						File writeText: 'resume' to: mark].
					sem waitTimeoutMSecs: 10]
				ifFalse: [
					self check: sent > 0 because: tls lastError.
					partial := partial or: [sent < (payload size - start)].
					start := start + sent]].
		self check: (pending and: [partial]) because: 'TLS fixture did not exercise partial write and WANT retry'.
		n := self await: [tls primRecv: h into: dst start: 2 count: 1] on: sem.
		self check: (n = 1 and: [dst = #[9 75 9]]) because: 'bad TLS reply or out-of-slice mutation'.
		self check: (self await: [tls primRecv: h into: dst start: 2 count: 1] on: sem) = 0 because: 'TLS EOF'.
		self check: (tls primHandshake: -1) == false because: 'invalid TLS handle'.
		self check: (tls primRecv: -1 into: dst start: 2 count: 1) = -1 because: 'invalid TLS recv status'
	] ensure: [
		h ifNotNil: [tls primClose: h].
		plain close.
		Smalltalk vm unregisterExternalSemaphore: index]
! !

!SocketFFISmoke class methodsFor: 'PTY'!
terminal
	| pty term h index dst n got |
	term := PseudoTerminal.
	pty := term spawn: #('/bin/sh' '-c' 'stty -echo; printf R; read line; [ "$line" = test ] || exit 3; printf K; exit 17')
		environment: nil directory: nil rows: 24 columns: 80.
	h := pty instVarNamed: 'handle'.
	index := Smalltalk vm registerExternalSemaphore: pty semaphore.
	[
		self check: (term primSemaphore: h read: index write: index) == term because: 'PTY registration'.
		self check: (term primWait: h blocking: false) isNil because: 'child should still be alive'.
		dst := #[9 9 9] copy.
		n := self await: [term primRead: h into: dst start: 2 count: 1] on: pty semaphore.
		self check: (n = 1 and: [dst = #[9 82 9]]) because: 'bad PTY ready bytes'.
		[pty semaphore isSignaled] whileTrue: [pty semaphore wait].
		self check: (term primRead: h into: dst start: 2 count: 1) isNil because: 'empty terminal read'.
		self check: (term primWrite: h from: #[88 116 101 115 116 10 88] start: 2 count: 5) = 5 because: 'PTY write slice'.
		self check: (pty semaphore waitTimeoutMSecs: 1000) not because: 'PTY read readiness not rearmed'.
		got := self await: [term primRead: h into: dst start: 2 count: 1] on: pty semaphore.
		self check: (got = 1 and: [dst = #[9 75 9]]) because: 'bad PTY reply'.
		self check: (self await: [term primRead: h into: dst start: 2 count: 1] on: pty semaphore) = 0 because: 'PTY EOF'.
		self check: (term primWait: h blocking: true) = 17 because: 'PTY exit status'.
		self check: (term primWait: h blocking: false) == false because: 'PTY wait error after reaping'.
		self check: (term primRead: -1 into: dst start: 2 count: 1) == false because: 'invalid PTY read status'
	] ensure: [
		pty close.
		Smalltalk vm unregisterExternalSemaphore: index]
! !

!SocketFFISmoke class methodsFor: 'bounds'!
boundary
	| socket listener client accepted port recv dst readonly |
	socket := RemoteSocket.
	listener := socket listenOn: 0 host: '127.0.0.1' backlog: 2.
	[
		port := listener localPort.
		client := socket connectTo: '127.0.0.1' port: port.
		accepted := listener accept.
		self check: (client sendAll: 'B') because: 'ByteString send'.
		recv := FFI bind: #(call 'platform' 'platform_sockets_recv' (i64 writableBytesWithLength) i64).
		readonly := #[9 9].
		dst := readonly copy.
		self check: (recv tryInvoke2: accepted handle with: {readonly. 1. 1}) == false because: 'immutable receive admitted'.
		self check: (recv tryInvoke2: accepted handle with: {dst. 2. 2}) == false because: 'out-of-range receive admitted'.
		self check: (recv tryInvoke2: accepted handle with: {dst. 0. 1}) == false because: 'zero-based receive admitted'.
		self check: (recv tryInvoke2: accepted handle with: {dst. 2. 16r3FFFFFFFFFFFFFFF}) == false because: 'overflowing receive admitted'.
		self check: dst = readonly because: 'rejected receive wrote output'.
		self check: (recv tryInvoke2: accepted handle with: {dst. 3. 0}) = 0 because: 'one-past-end empty range'.
		self check: (self await: [
			socket platformRecv: accepted handle into: dst start: 2 count: 1
		] on: (accepted instVarNamed: 'readSemaphore')) = 1 because: 'rejections consumed data'.
		self check: dst = #[9 66] because: 'ByteString send / canonical slice data'
	] ensure: [
		accepted ifNotNil: [accepted close].
		client ifNotNil: [client close].
		listener close]
! !
