VMPlatformModule subclass: #PlatformSockets
	instanceVariableNames: 'table sems armedCount'
	classVariableNames: 'MAX_FDS MAX_POLLED'
	package: 'VM-Platform'!

PlatformSockets comment: 'Non-blocking TCP sockets, and the table they share with pseudo-terminal masters and TLS connections (kinds PF_FD_SOCKET, PF_FD_PTY and PF_FD_TLS, i = the descriptor), so all are polled the same way.

A descriptor with a read (write) semaphore is armed until it becomes readable or acceptable (writable); then the semaphore is signaled once (a TLS connection''s both: OpenSSL may read to write and write to read). Read is re-armed by every recv/accept/read; write is armed by a send that would block or was partial, and by a connect in progress.

Nothing here blocks the VM thread: connect and listen take numeric addresses only, a connect completes in the background (connected:), and a host name is looked up by a thread of its own (lookup:) that writes its answer to a socket.'!

!PlatformSockets class methodsFor: 'declaring'!
declarations
	^#((table 'pf_table[1]') (sems 'sock_sems[MAX_FDS]') (armedCount int32_t))
!
initialize
	MAX_FDS := 1024.
	MAX_POLLED := 256
! !

!PlatformSockets methodsFor: 'private'!
failOS: what
	common failOS: what code: posixIO errno
!
socketFd: s
	^self fdOf: s kind: PF_FD_SOCKET
!
wouldBlock
	^posixIO errno = posixIO EAGAIN or: [posixIO errno = posixIO EWOULDBLOCK]
!
wrap: fd
	"A socket handle for fd (closed if the table is full)."
	<function>
	| h |
	host socketOpened: fd.
	h := self add: fd kind: PF_FD_SOCKET pointer: self null.
	h = 0 ifTrue: [posixIO close: fd].
	^h
!
noDelay: fd
	| one |
	one := self local: 'int'.
	one value: 1.
	posixSockets setsockopt: fd level: posixSockets IPPROTO_TCP option: posixSockets TCP_NODELAY value: one length: (self sizeof: 'int') asUInt32
!
resolve: host port: port passive: passive
	"The address of the numeric address host (any if NULL or empty) and port; NULL (and the error set) if it is none."
	<function>
	| hints ai ps r |
	hints := self local: 'struct addrinfo'.
	ai := self local: 'struct addrinfo *'.
	ps := self local: 'char[16]'.
	hints ai_family: posixSockets AF_UNSPEC.
	hints ai_socktype: posixSockets SOCK_STREAM.
	hints ai_flags: ((passive ifTrue: [posixSockets AI_PASSIVE] ifFalse: [0]) bitOr: (posixSockets AI_NUMERICHOST bitOr: posixSockets AI_NUMERICSERV)).
	libc snprintf: ps size: 16 format: '%d' with: port.
	r := posixSockets getaddrinfo: ((host notNull and: [(host at: 0) ~= 0]) ifTrue: [host] ifFalse: [self null]) service: ps hints: hints result: ai.
	r ~= 0 ifTrue: [
		common setError: 'getaddrinfo %s: %s' with: (host notNull ifTrue: [host] ifFalse: ['']) with: (posixSockets gaiStrerror: r).
		^self null].
	^ai value
!
eventsOf: h
	"The poll events handle h waits for."
	<function>
	| s |
	s := sems + h.
	^(((s readSem ~= 0 and: [s readArmed]) ifTrue: [posixIO POLLIN] ifFalse: [0])
		bitOr: ((s writeSem ~= 0 and: [s writeArmed]) ifTrue: [posixIO POLLOUT] ifFalse: [0])) asInt16
! !

!PlatformSockets methodsFor: 'descriptor table'!
fdGet: h kind: kind
	<export>
	| o |
	o := common table: table at: h kind: kind.
	o isNull ifTrue: [common setError: 'bad %s handle %d' with: (kind = PF_FD_PTY ifTrue: ['pty'] ifFalse: [kind = PF_FD_TLS ifTrue: ['TLS'] ifFalse: ['socket']]) with: h].
	^o
!
fdOf: h kind: kind
	"The descriptor of handle h, -1 (and the error set) if it is none."
	<function>
	| o |
	o := self fdGet: h kind: kind.
	o isNull ifTrue: [^-1].
	^o i asInt32
!
add: fd kind: kind pointer: ptr
	"Make fd non-blocking and close-on-exec; its handle, 0 on failure (fd left open)."
	<var: #ptr type: 'void *'>
	<export>
	| h |
	h := self reserveDescriptor: kind pointer: ptr.
	h ~= 0 ifTrue: [self installDescriptor: fd at: h].
	^h
!
reserveDescriptor: kind pointer: ptr
	"Reserve a handle before acquiring a descriptor. Install or cancel before returning to the VM."
	<var: #ptr type: 'void *'>
	<export>
	| h |
	h := common table: table add: kind pointer: ptr.
	h = 0 ifTrue: [common setError: 'out of memory'. ^0].
	h >= MAX_FDS ifTrue: [
		self cancelDescriptor: h.
		common setError: 'too many sockets and ptys'.
		^0].
	^h
!
installDescriptor: fd at: h
	<export>
	posixIO fcntl: fd command: posixIO F_SETFL value: ((posixIO fcntl: fd command: posixIO F_GETFL) bitOr: posixIO O_NONBLOCK).
	posixIO fcntl: fd command: posixIO F_SETFD value: posixIO FD_CLOEXEC.
	(table v + h) i: fd.
	libc memset: sems + h value: 0 size: (self sizeof: 'sock_sems')
!
cancelDescriptor: h
	<export>
	common table: table remove: h
!
close: h kind: kind
	<export>
	| fd |
	fd := self fdOf: h kind: kind.
	fd < 0 ifTrue: [^false].
	self semaphores: h kind: kind read: 0 write: 0.
	common table: table remove: h.
	(posixIO close: fd) = 0 ifTrue: [^true].
	self failOS: 'close'.
	^false
!
read: h kind: kind into: buf count: n
	"0 at EOF, -1 would block, -2 error."
	<function>
	<var: #buf type: 'void *'>
	| fd r |
	fd := self fdOf: h kind: kind.
	fd < 0 ifTrue: [^-2].
	(sems + h) readArmed: true.
	[r := kind = PF_FD_PTY
		ifTrue: [posixIO read: fd into: buf count: n]
		ifFalse: [posixSockets recv: fd into: buf count: n flags: 0].
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r >= 0 ifTrue: [^r].
	self wouldBlock ifTrue: [^-1].
	"a pty's slave side is closed"
	(kind = PF_FD_PTY and: [posixIO errno = posixIO EIO]) ifTrue: [^0].
	self failOS: (kind = PF_FD_PTY ifTrue: ['read'] ifFalse: ['recv']).
	^-2
!
write: h kind: kind bytes: buf count: n
	"-1 would block, -2 error."
	<function>
	<var: #buf type: 'const void *'>
	| fd r |
	fd := self fdOf: h kind: kind.
	fd < 0 ifTrue: [^-2].
	[r := kind = PF_FD_PTY
		ifTrue: [posixIO write: fd bytes: buf count: n]
		ifFalse: [posixSockets send: fd bytes: buf count: n flags: 0].
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	(sems + h) writeArmed: ((r >= 0 and: [r asUInt64 < n]) or: [r < 0 and: [self wouldBlock]]).
	r >= 0 ifTrue: [^r].
	self wouldBlock ifTrue: [^-1].
	self failOS: (kind = PF_FD_PTY ifTrue: ['write'] ifFalse: ['send']).
	^-2
!
armRead: h
	"Wait for h to become readable (TLS: OpenSSL needs more bytes)."
	<function>
	(sems + h) readArmed: true
!
armWrite: h when: armed
	"Wait for h to become writable, or not."
	<function>
	(sems + h) writeArmed: armed
!
semaphores: h kind: kind read: readIndex write: writeIndex
	<function>
	| s had |
	(self fdOf: h kind: kind) < 0 ifTrue: [^false].
	s := sems + h.
	had := s readSem ~= 0 or: [s writeSem ~= 0].
	s readSem: readIndex.
	s writeSem: writeIndex.
	s readArmed: true.
	s writeArmed: false.
	armedCount := armedCount + ((readIndex ~= 0 or: [writeIndex ~= 0]) ifTrue: [1] ifFalse: [0]) - (had ifTrue: [1] ifFalse: [0]).
	events updatePollInterval.
	^true
! !

!PlatformSockets methodsFor: 'sockets'!
listen: host port: port backlog: backlog
	<export>
	| ai fd one |
	platform init.
	ai := self resolve: host port: port passive: true.
	ai isNull ifTrue: [^0].
	fd := posixSockets socket: ai ai_family type: posixSockets SOCK_STREAM protocol: 0.
	fd < 0 ifTrue: [
		posixSockets freeaddrinfo: ai.
		self failOS: 'socket'.
		^0].
	one := self local: 'int'.
	one value: 1.
	posixSockets setsockopt: fd level: posixSockets SOL_SOCKET option: posixSockets SO_REUSEADDR value: one length: (self sizeof: 'int') asUInt32.
	((posixSockets bind: fd address: ai ai_addr length: ai ai_addrlen) ~= 0 or: [(posixSockets listen: fd backlog: backlog) ~= 0]) ifTrue: [
		self failOS: 'bind/listen'.
		posixIO close: fd.
		posixSockets freeaddrinfo: ai.
		^0].
	posixSockets freeaddrinfo: ai.
	^self wrap: fd
!
connect: host port: port
	"Start a TCP connection (TCP_NODELAY) to the numeric address host and port; its handle at once (connected: tells when it is made), 0 (and the error set) on failure."
	<export>
	<var: #h type: 'int32_t'>
	| ai fd h e |
	platform init.
	ai := self resolve: host port: port passive: false.
	ai isNull ifTrue: [^0].
	fd := posixSockets socket: ai ai_family type: posixSockets SOCK_STREAM protocol: 0.
	h := fd < 0 ifTrue: [0] ifFalse: [self wrap: fd].
	fd < 0 ifTrue: [self failOS: 'socket'].
	(h ~= 0 and: [(posixSockets connect: fd address: ai ai_addr length: ai ai_addrlen) ~= 0]) ifTrue: [
		e := posixIO errno.
		(e = posixIO EINPROGRESS or: [e = posixIO EINTR]) ifFalse: [
			self close: h kind: PF_FD_SOCKET.
			common failOS: 'connect' code: e.
			h := 0]].
	posixSockets freeaddrinfo: ai.
	h ~= 0 ifTrue: [self noDelay: fd].
	^h
!
connected: s
	"1 once the connection socket s started is made, 0 while it is in progress (arming the write semaphore), -1 (and the error set) if it failed."
	<export>
	| fd p err len |
	fd := self socketFd: s.
	fd < 0 ifTrue: [^-1].
	p := self local: 'struct pollfd'.
	p fd: fd.
	p events: posixIO POLLOUT.
	(posixIO poll: p count: 1 timeout: 0) <= 0 ifTrue: [
		(sems + s) writeArmed: true.
		^0].
	err := self local: 'int'.
	len := self local: 'socklen_t'.
	len value: (self sizeof: 'int') asUInt32.
	(posixSockets getsockopt: fd level: posixSockets SOL_SOCKET option: posixSockets SO_ERROR value: err length: len) ~= 0 ifTrue: [
		self failOS: 'getsockopt'.
		^-1].
	err value = 0 ifTrue: [^1].
	common failOS: 'connect' code: err value.
	^-1
!
lookup: hostName
	"A socket that reads as the numeric addresses of hostName, a line each, or as one line of !! and the error, then ends; written by a thread of its own (lookupRun:). 0 (and the error set) if the lookup cannot be started."
	<export>
	<var: #h type: 'int32_t'>
	| fds req h t |
	platform init.
	fds := self local: 'int[2]'.
	(posixSockets socketpair: posixSockets AF_UNIX type: posixSockets SOCK_STREAM protocol: 0 pair: fds) ~= 0 ifTrue: [
		self failOS: 'socketpair'.
		^0].
	"the thread's end: no SIGPIPE once the handle is closed, not inherited by children"
	host socketOpened: (fds at: 1).
	posixIO fcntl: (fds at: 1) command: posixIO F_SETFD value: posixIO FD_CLOEXEC.
	req := self cCoerce: (libc calloc: 1 size: (self sizeof: 'lookup_request')) to: 'lookup_request *'.
	req notNull ifTrue: [req host: (libc strdup: hostName)].
	h := 0.
	(req notNull and: [req host notNull])
		ifTrue: [h := self wrap: (fds at: 0)]
		ifFalse: [
			common setError: 'out of memory'.
			posixIO close: (fds at: 0)].
	h ~= 0 ifTrue: [
		req fd: (fds at: 1).
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #lookupRun:) argument: req) = 0 ifTrue: [
			posix pthreadDetach: t value.
			^h].
		common setError: 'cannot start a lookup thread'.
		self close: h kind: PF_FD_SOCKET].
	posixIO close: (fds at: 1).
	req notNull ifTrue: [libc free: req host].
	libc free: req.
	^0
!
lookupRun: arg
	"A lookup's thread: getaddrinfo, the answer written to its end of the socket pair, then the end closed and its request (arg) freed. It touches nothing else."
	<function>
	| req hints ai a r name |
	req := self cCoerce: arg to: 'lookup_request *'.
	hints := self local: 'struct addrinfo'.
	ai := self local: 'struct addrinfo *'.
	name := self local: 'char[128]'.
	hints ai_family: posixSockets AF_UNSPEC.
	hints ai_socktype: posixSockets SOCK_STREAM.
	r := posixSockets getaddrinfo: req host service: self null hints: hints result: ai.
	r ~= 0
		ifTrue: [self lookupWrite: req fd prefix: '!!' text: (posixSockets gaiStrerror: r)]
		ifFalse: [
			a := ai value.
			[a notNull] whileTrue: [
				(posixSockets getnameinfo: a ai_addr length: a ai_addrlen host: name size: 128 service: self null size: 0 flags: posixSockets NI_NUMERICHOST) = 0 ifTrue: [
					self lookupWrite: req fd prefix: '' text: name].
				a := a ai_next].
			posixSockets freeaddrinfo: ai value].
	posixIO close: req fd.
	libc free: req host.
	libc free: req.
	^self null
!
lookupWrite: fd prefix: prefix text: text
	"A line of prefix and text to fd (blocking: the lookup's thread)."
	<function>
	<var: #done type: 'size_t'>
	| line n done r |
	line := self local: 'char[256]'.
	libc snprintf: line size: 255 format: '%s%s' with: prefix with: text.
	n := libc strlen: line.
	line at: n put: 10.
	n := n + 1.
	done := 0.
	[done < n] whileTrue: [
		r := posixIO write: fd bytes: line + done count: n - done.
		r < 0
			ifTrue: [posixIO errno = posixIO EINTR ifFalse: [^self]]
			ifFalse: [done := done + r asUInt64]]
!
accept: s wouldBlock: wouldBlock
	"0 and wouldBlock: none pending."
	<export>
	| fd c e |
	fd := self socketFd: s.
	wouldBlock value: false.
	fd < 0 ifTrue: [^0].
	(sems + s) readArmed: true.
	c := posixSockets accept: fd address: self null length: self null.
	c < 0 ifTrue: [
		e := posixIO errno.
		(e = posixIO EAGAIN or: [e = posixIO EWOULDBLOCK or: [e = posixIO ECONNABORTED or: [e = posixIO EINTR]]]) ifTrue: [
			wouldBlock value: true.
			common setError: ''.
			^0].
		self failOS: 'accept'.
		^0].
	self noDelay: c.
	^self wrap: c
!
recv: s into: buf count: n
	"0 at EOF, -1 would block, -2 error."
	<var: #buf type: 'void *'>
	<export>
	^self read: s kind: PF_FD_SOCKET into: buf count: n
!
send: s bytes: buf count: n
	"-1 would block, -2 error."
	<var: #buf type: 'const void *'>
	<export>
	^self write: s kind: PF_FD_SOCKET bytes: buf count: n
!
close: s
	<export>
	^self close: s kind: PF_FD_SOCKET
!
semaphores: s read: readIndex write: writeIndex
	<export>
	^self semaphores: s kind: PF_FD_SOCKET read: readIndex write: writeIndex
!
localPort: s
	<export>
	| fd ss len |
	fd := self socketFd: s.
	ss := self local: 'struct sockaddr_storage'.
	len := self local: 'socklen_t'.
	len value: (self sizeof: 'struct sockaddr_storage') asUInt32.
	fd < 0 ifTrue: [^0].
	(posixSockets getsockname: fd address: (self cCoerce: ss to: 'struct sockaddr *') length: len) ~= 0 ifTrue: [
		self failOS: 'getsockname'.
		^0].
	^ss ss_family = posixSockets AF_INET6
		ifTrue: [posixSockets ntohs: (self cCoerce: ss to: 'struct sockaddr_in6 *') sin6_port]
		ifFalse: [posixSockets ntohs: (self cCoerce: ss to: 'struct sockaddr_in *') sin_port]
!
handleCount
	"Sockets and TLS connections."
	<export>
	^(common table: table count: PF_FD_SOCKET) + (common table: table count: PF_FD_TLS)
! !

!PlatformSockets methodsFor: 'pseudo-terminals'!
ptyRead: p into: buf count: n
	"0 at EOF (the child side closed), -1 would block, -2 error."
	<var: #buf type: 'void *'>
	<export>
	^self read: p kind: PF_FD_PTY into: buf count: n
!
ptyWrite: p bytes: buf count: n
	"-1 would block, -2 error."
	<var: #buf type: 'const void *'>
	<export>
	^self write: p kind: PF_FD_PTY bytes: buf count: n
!
ptySemaphores: p read: readIndex write: writeIndex
	<export>
	^self semaphores: p kind: PF_FD_PTY read: readIndex write: writeIndex
!
ptyHandleCount
	<export>
	^common table: table count: PF_FD_PTY
! !

!PlatformSockets methodsFor: 'polling'!
anyArmed
	<export>
	^armedCount > 0
!
pollFds: pollfds max: max
	"Fill pollfds (struct pollfd[max]) with the armed descriptors; answer their count."
	<var: #pollfds type: 'void *'>
	<export>
	<var: #n type: 'int'>
	| p n ev |
	p := self cCoerce: pollfds to: 'struct pollfd *'.
	n := 0.
	1 to: table n - 1 do: [:h |
		(n < max and: [(table v + h) kind ~= 0]) ifTrue: [
			ev := self eventsOf: h.
			ev ~= 0 ifTrue: [
				(p at: n) fd: (table v + h) i.
				(p at: n) events: ev.
				(p at: n) revents: 0.
				n := n + 1]]].
	^n
!
poll: timeoutMs
	"Signal the semaphores of the ready descriptors."
	<export>
	<var: #n type: 'int'>
	| p hs n ev r s both |
	p := self local: 'struct pollfd[MAX_POLLED]'.
	hs := self local: 'int[MAX_POLLED]'.
	n := 0.
	1 to: table n - 1 do: [:h |
		(n < MAX_POLLED and: [(table v + h) kind ~= 0]) ifTrue: [
			ev := self eventsOf: h.
			ev ~= 0 ifTrue: [
				(p at: n) fd: (table v + h) i.
				(p at: n) events: ev.
				hs at: n put: h.
				n := n + 1]]].
	n = 0 ifTrue: [
		timeoutMs > 0 ifTrue: [posixIO poll: self null count: 0 timeout: timeoutMs].
		^self].
	(posixIO poll: p count: n asUInt32 timeout: timeoutMs) <= 0 ifTrue: [^self].
	0 to: n - 1 do: [:i |
		s := sems + (hs at: i).
		r := (p at: i) revents.
		both := r ~= 0 and: [(table v + (hs at: i)) kind = PF_FD_TLS].
		r ~= 0 ifTrue: [
			(both
				ifTrue: [s readSem ~= 0]
				ifFalse: [(r bitAnd: ((posixIO POLLIN bitOr: posixIO POLLHUP) bitOr: posixIO POLLERR)) ~= 0 and: [((p at: i) events bitAnd: posixIO POLLIN) ~= 0]]) ifTrue: [
					s readArmed: false.
					scheduler signalExternalSemaphore: s readSem].
			(both
				ifTrue: [s writeSem ~= 0]
				ifFalse: [(r bitAnd: ((posixIO POLLOUT bitOr: posixIO POLLHUP) bitOr: posixIO POLLERR)) ~= 0 and: [((p at: i) events bitAnd: posixIO POLLOUT) ~= 0]]) ifTrue: [
					s writeArmed: false.
					scheduler signalExternalSemaphore: s writeSem]]]
! !

VMStruct subclass: #SockSems
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SockSems comment: 'The readiness semaphores of a socket or pty (external semaphore indices, 0 = none) and whether each is armed.'!

!SockSems class methodsFor: 'declaring'!
fields
	^#((readSem int32_t) (writeSem int32_t) (readArmed bool) (writeArmed bool))
! !

VMStruct subclass: #LookupRequest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

LookupRequest comment: 'A host name lookup''s thread''s own: the end of the socket pair it writes to, a copy of the name.'!

!LookupRequest class methodsFor: 'declaring'!
fields
	^#((fd int32_t) (host 'char *'))
! !
