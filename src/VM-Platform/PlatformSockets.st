VMPlatformModule subclass: #PlatformSockets
	instanceVariableNames: 'table sems armedCount'
	classVariableNames: 'MAX_FDS MAX_POLLED'
	package: 'VM-Platform'!

PlatformSockets comment: 'Non-blocking TCP sockets, and the table they share with pseudo-terminal masters (kinds PF_FD_SOCKET and PF_FD_PTY, i = the descriptor), so both are polled the same way.

A descriptor with a read (write) semaphore is armed until it becomes readable or acceptable (writable); then the semaphore is signaled once. Read is re-armed by every recv/accept/read; write is armed by a send that would block or was partial.'!

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
	<c: 'int socket_wrap(int fd)'>
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
	"The addresses of host (any if NULL or empty) and port; NULL (and the error set) if there are none."
	<c: 'struct addrinfo *socket_resolve(const char *host, int port, bool passive)'>
	| hints ai ps r |
	hints := self local: 'struct addrinfo'.
	ai := self local: 'struct addrinfo *'.
	ps := self local: 'char[16]'.
	hints ai_family: posixSockets AF_UNSPEC.
	hints ai_socktype: posixSockets SOCK_STREAM.
	hints ai_flags: (passive ifTrue: [posixSockets AI_PASSIVE] ifFalse: [0]).
	libc snprintf: ps size: 16 format: '%d' with: port.
	r := posixSockets getaddrinfo: ((host notNull and: [(host at: 0) ~= 0]) ifTrue: [host] ifFalse: [self null]) service: ps hints: hints result: ai.
	r ~= 0 ifTrue: [
		common setError: 'getaddrinfo %s: %s' with: (host notNull ifTrue: [host] ifFalse: ['']) with: (posixSockets gaiStrerror: r).
		^self null].
	^ai value
!
eventsOf: h
	"The poll events handle h waits for."
	<c: 'short events_of(int h)'>
	| s |
	s := sems + h.
	^(((s readSem ~= 0 and: [s readArmed]) ifTrue: [posixIO POLLIN] ifFalse: [0])
		bitOr: ((s writeSem ~= 0 and: [s writeArmed]) ifTrue: [posixIO POLLOUT] ifFalse: [0])) asInt16
! !

!PlatformSockets methodsFor: 'descriptor table'!
fdGet: h kind: kind
	<c: 'pf_obj *pf_fd_get(int h, int kind)'>
	<export>
	| o |
	o := common table: table at: h kind: kind.
	o isNull ifTrue: [common setError: 'bad %s handle %d' with: (kind = PF_FD_PTY ifTrue: ['pty'] ifFalse: ['socket']) with: h].
	^o
!
fdOf: h kind: kind
	"The descriptor of handle h, -1 (and the error set) if it is none."
	<c: 'int fd_of_kind(int h, int kind)'>
	| o |
	o := self fdGet: h kind: kind.
	o isNull ifTrue: [^-1].
	^o i asInt32
!
add: fd kind: kind pointer: ptr
	"Make fd non-blocking and close-on-exec; its handle, 0 when the table is full (fd left open)."
	<c: 'int pf_fd_add(int fd, int kind, void *ptr)'>
	<export>
	| h |
	posixIO fcntl: fd command: posixIO F_SETFL value: ((posixIO fcntl: fd command: posixIO F_GETFL) bitOr: posixIO O_NONBLOCK).
	posixIO fcntl: fd command: posixIO F_SETFD value: posixIO FD_CLOEXEC.
	h := common table: table add: kind pointer: ptr.
	h >= MAX_FDS ifTrue: [
		common table: table remove: h.
		common setError: 'too many sockets and ptys'.
		^0].
	(table v + h) i: fd.
	libc memset: sems + h value: 0 size: (self sizeof: 'sock_sems').
	^h
!
close: h kind: kind
	<c: 'bool pf_fd_close(int h, int kind)'>
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
	<c: 'int64_t fd_read(int h, int kind, void *buf, size_t n)'>
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
	<c: 'int64_t fd_write(int h, int kind, const void *buf, size_t n)'>
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
semaphores: h kind: kind read: readIndex write: writeIndex
	<c: 'bool fd_semaphores(int h, int kind, int read_index, int write_index)'>
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
	<c: 'int pf_socket_listen(const char *host, int port, int backlog)'>
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
	"Blocking connect (meant for localhost), then non-blocking."
	<c: 'int pf_socket_connect(const char *host, int port)'>
	<export>
	<var: #fd type: 'int'>
	| ai a fd connected |
	platform init.
	ai := self resolve: host port: port passive: false.
	ai isNull ifTrue: [^0].
	fd := -1.
	a := ai.
	connected := false.
	[connected not and: [a notNull]] whileTrue: [
		fd := posixSockets socket: a ai_family type: posixSockets SOCK_STREAM protocol: 0.
		(fd >= 0 and: [(posixSockets connect: fd address: a ai_addr length: a ai_addrlen) = 0])
			ifTrue: [connected := true]
			ifFalse: [
				fd >= 0 ifTrue: [posixIO close: fd].
				fd := -1.
				a := a ai_next]].
	fd < 0 ifTrue: [self failOS: 'connect'].
	posixSockets freeaddrinfo: ai.
	fd < 0 ifTrue: [^0].
	self noDelay: fd.
	^self wrap: fd
!
accept: s wouldBlock: wouldBlock
	"0 and wouldBlock: none pending."
	<c: 'int pf_socket_accept(int s, bool *would_block)'>
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
	<c: 'int64_t pf_socket_recv(int s, void *buf, size_t n)'>
	<export>
	^self read: s kind: PF_FD_SOCKET into: buf count: n
!
send: s bytes: buf count: n
	"-1 would block, -2 error."
	<c: 'int64_t pf_socket_send(int s, const void *buf, size_t n)'>
	<export>
	^self write: s kind: PF_FD_SOCKET bytes: buf count: n
!
close: s
	<c: 'bool pf_socket_close(int s)'>
	<export>
	^self close: s kind: PF_FD_SOCKET
!
semaphores: s read: readIndex write: writeIndex
	<c: 'bool pf_socket_semaphores(int s, int read_index, int write_index)'>
	<export>
	^self semaphores: s kind: PF_FD_SOCKET read: readIndex write: writeIndex
!
localPort: s
	<c: 'int pf_socket_local_port(int s)'>
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
	<c: 'int pf_socket_handle_count(void)'>
	<export>
	^common table: table count: PF_FD_SOCKET
! !

!PlatformSockets methodsFor: 'pseudo-terminals'!
ptyRead: p into: buf count: n
	"0 at EOF (the child side closed), -1 would block, -2 error."
	<c: 'int64_t pf_pty_read(int p, void *buf, size_t n)'>
	<export>
	^self read: p kind: PF_FD_PTY into: buf count: n
!
ptyWrite: p bytes: buf count: n
	"-1 would block, -2 error."
	<c: 'int64_t pf_pty_write(int p, const void *buf, size_t n)'>
	<export>
	^self write: p kind: PF_FD_PTY bytes: buf count: n
!
ptySemaphores: p read: readIndex write: writeIndex
	<c: 'bool pf_pty_semaphores(int p, int read_index, int write_index)'>
	<export>
	^self semaphores: p kind: PF_FD_PTY read: readIndex write: writeIndex
!
ptyHandleCount
	<c: 'int pf_pty_handle_count(void)'>
	<export>
	^common table: table count: PF_FD_PTY
! !

!PlatformSockets methodsFor: 'polling'!
anyArmed
	<c: 'bool pf_socket_any_armed(void)'>
	<export>
	^armedCount > 0
!
pollFds: pollfds max: max
	"Fill pollfds (struct pollfd[max]) with the armed descriptors; answer their count."
	<c: 'int pf_socket_poll_fds(void *pollfds, int max)'>
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
	<c: 'void pf_socket_poll(int timeout_ms)'>
	<export>
	<var: #n type: 'int'>
	| p hs n ev r s |
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
		r ~= 0 ifTrue: [
			((r bitAnd: ((posixIO POLLIN bitOr: posixIO POLLHUP) bitOr: posixIO POLLERR)) ~= 0 and: [((p at: i) events bitAnd: posixIO POLLIN) ~= 0]) ifTrue: [
				s readArmed: false.
				scheduler signalExternalSemaphore: s readSem].
			((r bitAnd: ((posixIO POLLOUT bitOr: posixIO POLLHUP) bitOr: posixIO POLLERR)) ~= 0 and: [((p at: i) events bitAnd: posixIO POLLOUT) ~= 0]) ifTrue: [
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
