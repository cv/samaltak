VMPlatformModule subclass: #UefiSockets
	instanceVariableNames: 'tcp table armedCount'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiSockets comment: 'TCP sockets on UEFI (in place of PlatformSockets): handles of kind PF_FD_SOCKET for UefiTcp''s connections, armed and signaled as PlatformSockets does it: a socket with a read (write) semaphore is armed until it becomes readable or acceptable (writable), then its semaphore is signaled once; recv and accept re-arm the read side, a send that would block or was partial the write side. poll: steps every connection. There is no loopback: listening on 127.0.0.1 fails (listen on 0.0.0.0: everyone on the network may connect). No pseudo-terminals.'!

!UefiSockets class methodsFor: 'declaring'!
declarations
	^#((tcp UefiTcp) (table 'pf_table[1]') (armedCount int32_t))
!
targetOS
	^#uefi
!
replaces
	^PlatformSockets
!
isSimulated
	^false
! !

!UefiSockets methodsFor: 'private'!
connOf: s
	"The connection of socket handle s, or null."
	<function>
	<var: #s type: 'int32_t'>
	<returns: 'UefiTcpConn *'>
	| o |
	o := common table: table at: s kind: PF_FD_SOCKET.
	o isNull ifTrue: [^self null].
	^self cCoerce: o ptr to: 'UefiTcpConn *'
!
wrap: c
	"A handle for c; 0 (and the error set) if c failed or is none."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'int32_t'>
	| h |
	c isNull ifTrue: [
		common setError: 'out of memory'.
		^0].
	c failed ifTrue: [
		tcp close: c.
		common setError: 'the network refused'.
		^0].
	h := common table: table add: PF_FD_SOCKET pointer: c.
	h = 0 ifTrue: [tcp close: c].
	^h
!
address: host into: bytes
	"The dotted IPv4 address host as 4 bytes; false (the error set) if it is none, or a loopback address."
	<function>
	<var: #host type: 'const char *'>
	<var: #bytes type: 'uint8_t *'>
	<returns: 'bool'>
	| i part v |
	i := 0.
	0 to: 3 do: [:k |
		v := 0.
		part := 0.
		[(host at: i) >= $0 value and: [(host at: i) <= $9 value]] whileTrue: [
			v := (v * 10) + ((host at: i) - $0 value).
			part := part + 1.
			i := i + 1].
		(part = 0 or: [v > 255 or: [(k < 3 and: [(host at: i) ~= $. value]) or: [k = 3 and: [(host at: i) ~= 0]]]]) ifTrue: [
			common setError: 'not a numeric IPv4 address (UEFI has no IPv6)'.
			^false].
		bytes at: k put: v.
		i := i + 1].
	(bytes at: 0) = 127 ifTrue: [
		common setError: 'no loopback on UEFI'.
		^false].
	^true
!
network
	"Whether there is a NIC with TCP (the error set if not)."
	<function>
	<returns: 'bool'>
	tcp start ifTrue: [^true].
	common setError: 'no network'.
	^false
! !

!UefiSockets methodsFor: 'sockets'!
listen: host port: port backlog: backlog
	"Listen on every address of the machine (host: 0.0.0.0, or its own)."
	<function>
	<var: #host type: 'char *'>
	<var: #port type: 'int32_t'>
	<var: #backlog type: 'int32_t'>
	<returns: 'int32_t'>
	| a |
	a := self local: 'uint8_t[4]'.
	(self address: host into: a) ifFalse: [^0].
	self network ifFalse: [^0].
	^self wrap: (tcp listen: port)
!
connect: host port: port
	"A connection to the numeric address host and port, being made (connected: tells when it is)."
	<function>
	<var: #host type: 'char *'>
	<var: #port type: 'int32_t'>
	<returns: 'int32_t'>
	| a |
	a := self local: 'uint8_t[4]'.
	(self address: host into: a) ifFalse: [^0].
	self network ifFalse: [^0].
	^self wrap: (tcp connect: a port: port)
!
connected: s
	"1 made, 0 being made (the write semaphore armed), -1 failed (the error set)."
	<function>
	<var: #s type: 'int32_t'>
	<returns: 'int'>
	| c r |
	c := self connOf: s.
	c isNull ifTrue: [^-1].
	r := tcp isConnected: c.
	r = 0 ifTrue: [c writeArmed: true].
	r < 0 ifTrue: [common setError: 'connect: the connection failed'].
	^r
!
lookup: hostName
	"A socket that reads as the numeric addresses of hostName, a line each, or as one line of !! and the error, then ends."
	<function>
	<var: #hostName type: 'char *'>
	<returns: 'int32_t'>
	tcp start.
	^self wrap: (tcp lookup: hostName)
!
accept: s wouldBlock: wouldBlock
	"0 and wouldBlock: none pending."
	<function>
	<var: #s type: 'int32_t'>
	<var: #wouldBlock type: 'bool *'>
	<returns: 'int32_t'>
	| c a |
	wouldBlock value: false.
	c := self connOf: s.
	c isNull ifTrue: [^0].
	c readArmed: true.
	a := tcp accept: c.
	a isNull ifTrue: [
		wouldBlock value: true.
		common setError: ''.
		^0].
	^self wrap: a
!
recv: s into: buf count: n
	"0 at EOF, -1 would block, -2 error."
	<function>
	<var: #s type: 'int32_t'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| c r |
	c := self connOf: s.
	c isNull ifTrue: [^-2].
	c readArmed: true.
	r := (tcp isLookup: c)
		ifTrue: [tcp readLookup: c into: buf count: n]
		ifFalse: [tcp read: c into: buf count: n].
	r = -2 ifTrue: [common setError: 'recv: the connection failed'].
	^r
!
send: s bytes: buf count: n
	"-1 would block, -2 error."
	<function>
	<var: #s type: 'int32_t'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| c r |
	c := self connOf: s.
	c isNull ifTrue: [^-2].
	r := tcp write: c bytes: buf count: n.
	(r = -1 or: [r >= 0 and: [r asUInt64 < n]]) ifTrue: [c writeArmed: true].
	r = -2 ifTrue: [common setError: 'send: the connection failed'].
	^r
!
close: s
	<function>
	<var: #s type: 'int32_t'>
	<returns: 'bool'>
	| c |
	c := self connOf: s.
	c isNull ifTrue: [^false].
	(c readSem ~= 0 or: [c writeSem ~= 0]) ifTrue: [armedCount := armedCount - 1].
	tcp close: c.
	common table: table remove: s.
	^true
!
semaphores: s read: readIndex write: writeIndex
	<function>
	<var: #s type: 'int32_t'>
	<var: #readIndex type: 'int32_t'>
	<var: #writeIndex type: 'int32_t'>
	<returns: 'bool'>
	| c had |
	c := self connOf: s.
	c isNull ifTrue: [^false].
	had := c readSem ~= 0 or: [c writeSem ~= 0].
	c readSem: readIndex.
	c writeSem: writeIndex.
	c readArmed: true.
	c writeArmed: false.
	armedCount := armedCount + ((readIndex ~= 0 or: [writeIndex ~= 0]) ifTrue: [1] ifFalse: [0]) - (had ifTrue: [1] ifFalse: [0]).
	events updatePollInterval.
	^true
!
localPort: s
	<function>
	<var: #s type: 'int32_t'>
	<returns: 'int'>
	| c |
	c := self connOf: s.
	c isNull ifTrue: [^0].
	^c port asInt32
!
handleCount
	<function>
	<returns: 'int32_t'>
	^common table: table count: PF_FD_SOCKET
! !

!UefiSockets methodsFor: 'polling'!
anyArmed
	<function>
	<returns: 'bool'>
	^armedCount > 0
!
poll: timeoutMs
	"Step every connection; signal the semaphores of the ready ones."
	<function>
	<var: #timeoutMs type: 'int'>
	| o c |
	1 to: table n - 1 do: [:h |
		o := table v + h.
		o kind = PF_FD_SOCKET ifTrue: [
			c := self cCoerce: o ptr to: 'UefiTcpConn *'.
			tcp step: c.
			(c readSem ~= 0 and: [c readArmed and: [tcp isReadable: c]]) ifTrue: [
				c readArmed: false.
				scheduler signalExternalSemaphore: c readSem].
			(c writeSem ~= 0 and: [c writeArmed and: [tcp isWritable: c]]) ifTrue: [
				c writeArmed: false.
				scheduler signalExternalSemaphore: c writeSem]]]
! !

!UefiSockets methodsFor: 'pseudo-terminals'!
ptyRead: p into: buf count: n
	<function>
	<var: #p type: 'int32_t'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-2
!
ptyWrite: p bytes: buf count: n
	<function>
	<var: #p type: 'int32_t'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-2
!
ptySemaphores: p read: readIndex write: writeIndex
	<function>
	<var: #p type: 'int32_t'>
	<var: #readIndex type: 'int32_t'>
	<var: #writeIndex type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
ptyHandleCount
	<function>
	<returns: 'int32_t'>
	^0
! !
