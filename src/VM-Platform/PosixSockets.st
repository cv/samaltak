CLibrary subclass: #PosixSockets
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PosixSockets comment: 'BSD sockets and name resolution for the platform layer''s TCP sockets. Not simulated.'!

!PosixSockets class methodsFor: 'declaring'!
headers
	^#('<sys/socket.h>' '<netdb.h>' '<netinet/in.h>' '<netinet/tcp.h>' '<arpa/inet.h>')
!
typedefs
	^#((socklen_t uint32_t) (sa_family_t uint8_t) (in_port_t uint16_t))
! !

!PosixSockets methodsFor: 'simulation'!
notSimulated
	^self error: 'sockets are not simulated'
! !

!PosixSockets methodsFor: 'sockets'!
socket: domain type: type protocol: protocol
	<c: 'int socket(int domain, int type, int protocol)'>
	^self notSimulated
!
bind: s address: address length: length
	<c: 'int bind(int s, const struct sockaddr *address, socklen_t length)'>
	^self notSimulated
!
listen: s backlog: backlog
	<c: 'int listen(int s, int backlog)'>
	^self notSimulated
!
accept: s address: address length: length
	<c: 'int accept(int s, struct sockaddr *address, socklen_t *length)'>
	^self notSimulated
!
connect: s address: address length: length
	<c: 'int connect(int s, const struct sockaddr *address, socklen_t length)'>
	^self notSimulated
!
recv: s into: buf count: n flags: flags
	<c: 'ssize_t recv(int s, void *buf, size_t n, int flags)'>
	^self notSimulated
!
send: s bytes: buf count: n flags: flags
	<c: 'ssize_t send(int s, const void *buf, size_t n, int flags)'>
	^self notSimulated
!
socketpair: domain type: type protocol: protocol pair: fds
	<c: 'int socketpair(int domain, int type, int protocol, int *fds)'>
	^self notSimulated
!
setsockopt: s level: level option: name value: value length: length
	<c: 'int setsockopt(int s, int level, int name, const void *value, socklen_t length)'>
	^self notSimulated
!
getsockopt: s level: level option: name value: value length: length
	<c: 'int getsockopt(int s, int level, int name, void *value, socklen_t *length)'>
	^self notSimulated
!
getsockname: s address: address length: length
	<c: 'int getsockname(int s, struct sockaddr *address, socklen_t *length)'>
	^self notSimulated
!
ntohs: n
	<c: 'uint16_t ntohs(uint16_t n)'>
	^self notSimulated
!
AF_UNSPEC
	<cMacro: 'int AF_UNSPEC'>
	^0
!
AF_UNIX
	<cMacro: 'int AF_UNIX'>
	^1
!
AF_INET6
	<cMacro: 'int AF_INET6'>
	^30
!
SOCK_STREAM
	<cMacro: 'int SOCK_STREAM'>
	^1
!
SOL_SOCKET
	<cMacro: 'int SOL_SOCKET'>
	^16rFFFF
!
SO_REUSEADDR
	<cMacro: 'int SO_REUSEADDR'>
	^4
!
SO_ERROR
	<cMacro: 'int SO_ERROR'>
	^16r1007
!
SO_NOSIGPIPE
	<cMacro: 'int SO_NOSIGPIPE'>
	^16r1022
!
IPPROTO_TCP
	<cMacro: 'int IPPROTO_TCP'>
	^6
!
TCP_NODELAY
	<cMacro: 'int TCP_NODELAY'>
	^1
! !

!PosixSockets methodsFor: 'names'!
getaddrinfo: host service: service hints: hints result: res
	<c: 'int getaddrinfo(const char *host, const char *service, const struct addrinfo *hints, struct addrinfo **res)'>
	^self notSimulated
!
freeaddrinfo: ai
	<c: 'void freeaddrinfo(struct addrinfo *ai)'>
	^self notSimulated
!
getnameinfo: address length: length host: host size: hostSize service: service size: serviceSize flags: flags
	<c: 'int getnameinfo(const struct sockaddr *address, socklen_t length, char *host, socklen_t hostSize, char *service, socklen_t serviceSize, int flags)'>
	^self notSimulated
!
gaiStrerror: code
	<c: 'const char *gai_strerror(int code)'>
	^self notSimulated
!
AI_PASSIVE
	<cMacro: 'int AI_PASSIVE'>
	^1
!
AI_NUMERICHOST
	<cMacro: 'int AI_NUMERICHOST'>
	^4
!
AI_NUMERICSERV
	<cMacro: 'int AI_NUMERICSERV'>
	^16r1000
!
NI_NUMERICHOST
	<cMacro: 'int NI_NUMERICHOST'>
	^2
! !

ExternStruct subclass: #AddrInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!AddrInfo class methodsFor: 'declaring'!
cName
	^'struct addrinfo'
!
fields
	^#((ai_flags int) (ai_family int) (ai_socktype int) (ai_protocol int) (ai_addrlen socklen_t)
		(ai_canonname 'char *') (ai_addr 'struct sockaddr *') (ai_next 'struct addrinfo *'))
! !

ExternStruct subclass: #SockAddrStorage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SockAddrStorage class methodsFor: 'declaring'!
cName
	^'struct sockaddr_storage'
!
fields
	^#((ss_len uint8_t) (ss_family sa_family_t) (ss_data 'char[126]'))
! !

ExternStruct subclass: #SockAddrIn
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SockAddrIn class methodsFor: 'declaring'!
cName
	^'struct sockaddr_in'
!
fields
	^#((sin_len uint8_t) (sin_family sa_family_t) (sin_port in_port_t))
! !

ExternStruct subclass: #SockAddrIn6
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SockAddrIn6 class methodsFor: 'declaring'!
cName
	^'struct sockaddr_in6'
!
fields
	^#((sin6_len uint8_t) (sin6_family sa_family_t) (sin6_port in_port_t))
! !
