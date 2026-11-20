UefiModule subclass: #UefiTcp
	instanceVariableNames: 'nic tcpBinding dnsBinding ipConfig nextPort started'
	classVariableNames: 'TCP_BUFFER TCP_DNS TCP_LISTEN TCP_STREAM'
	package: 'VM-UEFI'!

UefiTcp comment: 'TCP over IPv4 with the firmware''s network stack (edk2: TCP4, DNS4 and IP4 configuration over the NIC''s driver), for UefiSockets. A connection (UefiTcpConn, malloc''d) is a TCP4 child: listening (one Accept outstanding, the accepted child kept until taken), or a stream (one Receive into a buffer of its own and one Transmit from a copy outstanding), or a DNS4 lookup whose answer reads as lines of numeric addresses. Every operation is started and its completion token''s event checked later (step:): nothing waits. The NIC gets its address by DHCP; until it has one, configuring a child fails with no mapping and is tried again at every step.'!

!UefiTcp class methodsFor: 'declaring'!
declarations
	^#((nic 'void *') (tcpBinding 'EfiServiceBinding *') (dnsBinding 'EfiServiceBinding *') (ipConfig 'EfiIp4Config2 *')
		(nextPort uint32_t 49152) (started bool))
!
initialize
	"Connection kinds; a stream's receive and transmit buffers."
	TCP_LISTEN := 1.
	TCP_STREAM := 2.
	TCP_DNS := 3.
	TCP_BUFFER := 65536
! !

!UefiTcp methodsFor: 'starting'!
start
	"The first NIC with TCP4: DHCP for its address; answer whether there is one."
	<function>
	<returns: 'bool'>
	| guid count handles p policy |
	started ifTrue: [^tcpBinding notNull].
	started := true.
	guid := self local: 'EfiGuid'.
	count := self local: 'uint64_t'.
	handles := self local: 'void **'.
	firmware guid: guid data1: 16r00720665 data2: 16r67EB data3: 16r4A99 data4: 16rBAF7D3C33A1C7CC9.
	(self efiFailed: (self efi: self boot locateHandleBuffer with: 2 with: guid with: self null with: count with: handles)) ifTrue: [^false].
	count value = 0 ifTrue: [^false].
	nic := handles value at: 0.
	self efi: self boot freePool with: handles value.
	p := self local: 'void *'.
	(self efiFailed: (self efi: self boot handleProtocol with: nic with: guid with: p)) ifTrue: [^false].
	tcpBinding := self cCoerce: p value to: 'EfiServiceBinding *'.
	firmware guid: guid data1: 16rB625B186 data2: 16rE063 data3: 16r44F7 data4: 16r89056A74DC6F52B4.
	(self efiFailed: (self efi: self boot handleProtocol with: nic with: guid with: p))
		ifFalse: [dnsBinding := self cCoerce: p value to: 'EfiServiceBinding *'].
	firmware guid: guid data1: 16r5B446ED1 data2: 16rE30B data3: 16r4FAA data4: 16r871A3654ECA36080.
	(self efiFailed: (self efi: self boot handleProtocol with: nic with: guid with: p)) ifFalse: [
		ipConfig := self cCoerce: p value to: 'EfiIp4Config2 *'.
		policy := self local: 'uint32_t'.
		policy value: 1.
		self efi: ipConfig setData with: ipConfig with: 1 with: 4 with: policy].
	^true
! !

!UefiTcp methodsFor: 'connections'!
newConnection: kind
	"A zeroed connection with its events; null if out of memory."
	<function>
	<var: #kind type: 'int32_t'>
	<returns: 'UefiTcpConn *'>
	| c e |
	c := self cCoerce: (libc calloc: 1 size: (self sizeof: 'UefiTcpConn')) to: 'UefiTcpConn *'.
	c isNull ifTrue: [^c].
	c kind: kind.
	e := self local: 'void *'.
	0 to: 3 do: [:i |
		self efi: self boot createEvent with: 0 with: EFI_TPL_CALLBACK with: self null with: self null with: e.
		(self cCoerce: (c fieldAddress: #events) to: 'void **') at: i put: e value].
	(c fieldAddress: #openToken) event: ((self cCoerce: (c fieldAddress: #events) to: 'void **') at: 0).
	(c fieldAddress: #rxToken) event: ((self cCoerce: (c fieldAddress: #events) to: 'void **') at: 1).
	(c fieldAddress: #txToken) event: ((self cCoerce: (c fieldAddress: #events) to: 'void **') at: 2).
	(c fieldAddress: #closeToken) event: ((self cCoerce: (c fieldAddress: #events) to: 'void **') at: 3).
	kind = TCP_STREAM ifTrue: [self buffersOf: c].
	^c
!
buffersOf: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	c rxBuf: (self cCoerce: (libc malloc: TCP_BUFFER) to: 'uint8_t *').
	c txBuf: (self cCoerce: (libc malloc: TCP_BUFFER) to: 'uint8_t *').
	(c rxBuf isNull or: [c txBuf isNull]) ifTrue: [c failed: true]
!
childOf: c
	"A TCP4 child for c; false if there is none."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'bool'>
	| h guid p |
	tcpBinding isNull ifTrue: [^false].
	h := self local: 'void *'.
	(self efiFailed: (self efi: tcpBinding createChild with: tcpBinding with: h)) ifTrue: [^false].
	c child: h value.
	^self adopt: h value into: c
!
adopt: child into: c
	"c's TCP4 protocol is child's."
	<function>
	<var: #child type: 'void *'>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'bool'>
	| guid p |
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16r65530BC7 data2: 16rA359 data3: 16r410F data4: 16rB0105AADC7EC2B62.
	p := self local: 'void *'.
	c child: child.
	(self efiFailed: (self efi: self boot handleProtocol with: child with: guid with: p)) ifTrue: [^false].
	c tcp: (self cCoerce: p value to: 'EfiTcp4 *').
	^true
!
configure: c
	"c's TCP4 child as its fields say; answer the status (no mapping: DHCP has not answered yet)."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'uint64_t'>
	| cfg |
	cfg := self local: 'EfiTcp4Config'.
	cfg timeToLive: 64.
	cfg useDefaultAddress: 1.
	cfg stationPort: c port asUInt16.
	cfg activeFlag: (c kind = TCP_STREAM ifTrue: [1] ifFalse: [0]).
	c kind = TCP_STREAM ifTrue: [
		0 to: 3 do: [:i | (self cCoerce: (cfg fieldAddress: #remoteAddress) to: 'uint8_t *') at: i put: ((self cCoerce: (c fieldAddress: #remote) to: 'uint8_t *') at: i)].
		cfg remotePort: c remotePort asUInt16].
	^self efi: c tcp configure with: c tcp with: cfg
!
listen: port
	"A connection listening on port (0: one of ours); null (status in the answer's failure) if none."
	<function>
	<var: #port type: 'int32_t'>
	<returns: 'UefiTcpConn *'>
	| c |
	c := self newConnection: TCP_LISTEN.
	c isNull ifTrue: [^c].
	c port: (port = 0 ifTrue: [self freePort] ifFalse: [port asUInt32]).
	(self childOf: c) ifFalse: [c failed: true].
	c failed ifFalse: [self open: c].
	^c
!
connect: address port: port
	"A connection to the IPv4 address (4 bytes) and port, being made."
	<function>
	<var: #address type: 'const uint8_t *'>
	<var: #port type: 'int32_t'>
	<returns: 'UefiTcpConn *'>
	| c |
	c := self newConnection: TCP_STREAM.
	c isNull ifTrue: [^c].
	0 to: 3 do: [:i | (self cCoerce: (c fieldAddress: #remote) to: 'uint8_t *') at: i put: (address at: i)].
	c remotePort: port asUInt32.
	c port: self freePort.
	(self childOf: c) ifFalse: [c failed: true].
	c failed ifFalse: [self open: c].
	^c
!
freePort
	<function>
	<returns: 'uint32_t'>
	nextPort := nextPort + 1.
	nextPort > 65000 ifTrue: [nextPort := 49153].
	^nextPort
!
open: c
	"Configure c (again, while there is no address yet), then start its Accept or Connect."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	| status |
	status := self configure: c.
	status = EFI_NO_MAPPING ifTrue: [^self].
	(self efiFailed: status) ifTrue: [
		c failed: true.
		^self].
	c configured: true.
	c kind = TCP_LISTEN ifTrue: [^self startAccept: c].
	(self efiFailed: (self efi: c tcp connect with: c tcp with: (c fieldAddress: #openToken)))
		ifTrue: [c failed: true]
		ifFalse: [c openPending: true]
!
startAccept: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	(c fieldAddress: #openToken) extra: self null.
	(self efiFailed: (self efi: c tcp accept with: c tcp with: (c fieldAddress: #openToken)))
		ifTrue: [c failed: true]
		ifFalse: [c openPending: true]
!
isDone: event
	"Whether event was signaled (since asked last)."
	<function>
	<var: #event type: 'void *'>
	<returns: 'bool'>
	^(self efiFailed: (self efi: self boot checkEvent with: event)) not
!
step: c
	"Advance c: its open (configure, connect, accept), receive, transmit and close tokens."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	| status |
	c kind = TCP_DNS ifTrue: [^self stepLookup: c].
	c tcp notNull ifTrue: [self efi: c tcp poll with: c tcp].
	(c failed or: [c tcp isNull]) ifTrue: [^self].
	c configured ifFalse: [^self open: c].
	(c openPending and: [self isDone: (c fieldAddress: #openToken) event]) ifTrue: [
		c openPending: false.
		status := (c fieldAddress: #openToken) status.
		(self efiFailed: status)
			ifTrue: [c failed: true]
			ifFalse: [c kind = TCP_LISTEN
				ifTrue: [c accepted: (c fieldAddress: #openToken) extra]
				ifFalse: [c connected: true]]].
	(c kind = TCP_LISTEN and: [c openPending not and: [c accepted isNull and: [c failed not]]]) ifTrue: [self startAccept: c].
	(c rxPending and: [self isDone: (c fieldAddress: #rxToken) event]) ifTrue: [
		c rxPending: false.
		status := (c fieldAddress: #rxToken) status.
		status = 0
			ifTrue: [
				c rxLen: (c fieldAddress: #rxData) dataLength.
				c rxPos: 0]
			ifFalse: [c eof: true]].
	(c txPending and: [self isDone: (c fieldAddress: #txToken) event]) ifTrue: [
		c txPending: false.
		(self efiFailed: (c fieldAddress: #txToken) status) ifTrue: [c failed: true]].
	(c connected and: [c rxPending not and: [c rxPos >= c rxLen and: [c eof not]]]) ifTrue: [self startReceive: c]
!
startReceive: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	| d |
	d := c fieldAddress: #rxData.
	d dataLength: TCP_BUFFER.
	d fragmentCount: 1.
	d fragmentLength: TCP_BUFFER.
	d fragmentBuffer: c rxBuf.
	(c fieldAddress: #rxToken) packet: d.
	c rxLen: 0.
	c rxPos: 0.
	(self efiFailed: (self efi: c tcp receive with: c tcp with: (c fieldAddress: #rxToken)))
		ifTrue: [c eof: true]
		ifFalse: [c rxPending: true]
! !

!UefiTcp methodsFor: 'streams'!
isLookup: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'bool'>
	^c kind = TCP_DNS
!
isReadable: c
	"Bytes to read, the end, a failure, an accepted connection or a lookup's answer."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'bool'>
	c failed ifTrue: [^true].
	c kind = TCP_LISTEN ifTrue: [^c accepted notNull].
	c kind = TCP_DNS ifTrue: [^c answered].
	^c rxPos < c rxLen or: [c eof]
!
isWritable: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'bool'>
	^c failed or: [c kind = TCP_STREAM and: [c connected and: [c txPending not]]]
!
read: c into: buf count: n
	"Bytes into buf: their count, 0 at the end, -1 if none yet, -2 if the connection failed."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| k |
	self step: c.
	c rxPos < c rxLen ifTrue: [
		k := (c rxLen - c rxPos) asUInt64.
		k > n ifTrue: [k := n].
		libc memcpy: buf from: c rxBuf + c rxPos size: k.
		c rxPos: c rxPos + k asUInt32.
		c rxPos >= c rxLen ifTrue: [self step: c].
		^k asInt64].
	c failed ifTrue: [^-2].
	c eof ifTrue: [^0].
	^-1
!
write: c bytes: buf count: n
	"Bytes from buf on their way: their count, -1 if the last ones are still on theirs, -2 if the connection failed."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| k d |
	self step: c.
	c failed ifTrue: [^-2].
	(c connected not or: [c txPending]) ifTrue: [^-1].
	n = 0 ifTrue: [^0].
	k := n > TCP_BUFFER ifTrue: [TCP_BUFFER asUInt64] ifFalse: [n].
	libc memcpy: c txBuf from: buf size: k.
	d := c fieldAddress: #txData.
	d flags: 1.
	d dataLength: k asUInt32.
	d fragmentCount: 1.
	d fragmentLength: k asUInt32.
	d fragmentBuffer: c txBuf.
	(c fieldAddress: #txToken) packet: d.
	(self efiFailed: (self efi: c tcp transmit with: c tcp with: (c fieldAddress: #txToken))) ifTrue: [
		c failed: true.
		^-2].
	c txPending: true.
	^k asInt64
!
accept: c
	"The connection c accepted, or null (none yet)."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'UefiTcpConn *'>
	| a child |
	self step: c.
	c accepted isNull ifTrue: [^self null].
	child := c accepted.
	c accepted: self null.
	self startAccept: c.
	a := self newConnection: TCP_STREAM.
	a isNull ifTrue: [^a].
	a port: c port.
	(self adopt: child into: a) ifFalse: [a failed: true].
	a configured: true.
	a connected: true.
	self step: a.
	^a
!
isConnected: c
	"1 made, 0 being made, -1 failed."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<returns: 'int32_t'>
	self step: c.
	c failed ifTrue: [^-1].
	^c connected ifTrue: [1] ifFalse: [0]
!
close: c
	"Close gracefully, destroy the child, free c (the firmware has no use for it afterwards: it is not waited for)."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	c kind = TCP_DNS ifTrue: [^self freeLookup: c].
	c tcp notNull ifTrue: [
		self efi: c tcp close with: c tcp with: (c fieldAddress: #closeToken).
		self efi: c tcp configure with: c tcp with: self null].
	c child notNull ifTrue: [self efi: tcpBinding destroyChild with: tcpBinding with: c child].
	c accepted notNull ifTrue: [self efi: tcpBinding destroyChild with: tcpBinding with: c accepted].
	self free: c
!
free: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	0 to: 3 do: [:i | self efi: self boot closeEvent with: ((self cCoerce: (c fieldAddress: #events) to: 'void **') at: i)].
	libc free: c rxBuf.
	libc free: c txBuf.
	libc free: c
! !

!UefiTcp methodsFor: 'lookups'!
lookup: name
	"A connection that reads as the IPv4 addresses of name, a line each (or a line of !! and the error), then ends."
	<function>
	<var: #name type: 'const char *'>
	<returns: 'UefiTcpConn *'>
	| c h p guid cfg wide n |
	c := self newConnection: TCP_DNS.
	c isNull ifTrue: [^c].
	c rxBuf: (self cCoerce: (libc malloc: 4096) to: 'uint8_t *').
	c rxBuf isNull ifTrue: [^self failLookup: c error: 'out of memory'].
	(self numeric: name into: (self cCoerce: (c fieldAddress: #remote) to: 'uint8_t *')) ifTrue: [
		self answer: c address: (self cCoerce: (c fieldAddress: #remote) to: 'uint8_t *').
		c answered: true.
		c eof: true.
		^c].
	dnsBinding isNull ifTrue: [^self failLookup: c error: 'no DNS on this machine'].
	h := self local: 'void *'.
	(self efiFailed: (self efi: dnsBinding createChild with: dnsBinding with: h)) ifTrue: [^self failLookup: c error: 'cannot start a DNS lookup'].
	c child: h value.
	guid := self local: 'EfiGuid'.
	firmware guid: guid data1: 16rAE3D28CC data2: 16rE05B data3: 16r4FA1 data4: 16rA0117EB55A3F1401.
	p := self local: 'void *'.
	(self efiFailed: (self efi: self boot handleProtocol with: c child with: guid with: p)) ifTrue: [^self failLookup: c error: 'cannot start a DNS lookup'].
	c dns: (self cCoerce: p value to: 'EfiDns4 *').
	cfg := self local: 'EfiDns4Config'.
	cfg useDefaultSetting: 1.
	cfg enableDnsCache: 1.
	cfg protocol: 17.
	cfg retryCount: 3.
	cfg retryInterval: 2.
	c name: (libc strdup: name).
	c configured: false.
	^c
!
numeric: name into: bytes
	"Whether name is a dotted IPv4 address (into bytes)."
	<function>
	<var: #name type: 'const char *'>
	<var: #bytes type: 'uint8_t *'>
	<returns: 'bool'>
	| i v digits |
	i := 0.
	0 to: 3 do: [:k |
		v := 0.
		digits := 0.
		[(name at: i) >= $0 value and: [(name at: i) <= $9 value]] whileTrue: [
			v := (v * 10) + ((name at: i) - $0 value).
			digits := digits + 1.
			i := i + 1].
		(digits = 0 or: [digits > 3 or: [v > 255 or: [(k < 3 and: [(name at: i) ~= $. value]) or: [k = 3 and: [(name at: i) ~= 0]]]]]) ifTrue: [^false].
		bytes at: k put: v.
		i := i + 1].
	^true
!
stepLookup: c
	"Configure the DNS4 child (again while there is no address), start the lookup, take its answer."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	| cfg status wide n h2a list |
	(c answered or: [c dns isNull]) ifTrue: [^self].
	self efi: c dns pollDns with: c dns.
	c configured ifFalse: [
		cfg := self local: 'EfiDns4Config'.
		cfg useDefaultSetting: 1.
		cfg enableDnsCache: 1.
		cfg protocol: 17.
		cfg retryCount: 3.
		cfg retryInterval: 2.
		status := self efi: c dns configure with: c dns with: cfg.
		status = EFI_NO_MAPPING ifTrue: [^self].
		(self efiFailed: status) ifTrue: [^self answer: c error: 'cannot configure DNS'].
		c configured: true.
		wide := self local: 'uint16_t[256]'.
		n := libc strlen: c name.
		n > 255 ifTrue: [n := 255].
		0 to: n asInt64 - 1 do: [:i | wide at: i put: (c name at: i) asUInt8].
		wide at: n put: 0.
		(c fieldAddress: #dnsToken) event: ((self cCoerce: (c fieldAddress: #events) to: 'void **') at: 0).
		(self efiFailed: (self efi: c dns hostNameToIp with: c dns with: wide with: (c fieldAddress: #dnsToken))) ifTrue: [
			^self answer: c error: 'cannot look up'].
		c openPending: true.
		^self].
	(c openPending and: [self isDone: (c fieldAddress: #dnsToken) event]) ifFalse: [^self].
	c openPending: false.
	(self efiFailed: (c fieldAddress: #dnsToken) status) ifTrue: [^self answer: c error: 'no such host'].
	h2a := (c fieldAddress: #dnsToken) answer.
	c rxLen: 0.
	(h2a notNull and: [h2a ipCount > 0]) ifFalse: [^self answer: c error: 'no such host'].
	list := h2a ipList.
	0 to: h2a ipCount asInt64 - 1 do: [:i | self answer: c address: list + (4 * i)].
	c answered: true.
	c eof: true
!
answer: c address: bytes
	"The dotted address of 4 bytes and a line feed: into c's answer."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<var: #bytes type: 'const uint8_t *'>
	| p v |
	(c rxLen + 16) < 4096 ifFalse: [^self].
	p := c rxBuf + c rxLen.
	0 to: 3 do: [:k |
		v := (bytes at: k) asInt64.
		v >= 100 ifTrue: [
			p at: 0 put: $0 value + (v quo: 100).
			p := p + 1].
		v >= 10 ifTrue: [
			p at: 0 put: $0 value + ((v quo: 10) rem: 10).
			p := p + 1].
		p at: 0 put: $0 value + (v rem: 10).
		p := p + 1.
		p at: 0 put: (k < 3 ifTrue: [$. value] ifFalse: [10]).
		p := p + 1].
	c rxLen: (p - c rxBuf) asUInt32
!
failLookup: c error: message
	"c, answering !! and message."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<var: #message type: 'const char *'>
	<returns: 'UefiTcpConn *'>
	self answer: c error: message.
	^c
!
answer: c error: message
	"c answers !! and message, a line, then ends."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<var: #message type: 'const char *'>
	| k |
	c rxBuf isNull ifTrue: [
		c failed: true.
		^self].
	c rxBuf at: 0 put: $!! value.
	k := libc strlen: message.
	k > 4000 ifTrue: [k := 4000].
	libc memcpy: c rxBuf + 1 from: message size: k.
	c rxBuf at: k + 1 put: 10.
	c rxLen: (k + 2) asUInt32.
	c rxPos: 0.
	c answered: true.
	c eof: true
!
readLookup: c into: buf count: n
	"The answer's bytes: as read:into:count:."
	<function>
	<var: #c type: 'UefiTcpConn *'>
	<var: #buf type: 'void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'int64_t'>
	| k |
	self stepLookup: c.
	c answered ifFalse: [^-1].
	c rxPos >= c rxLen ifTrue: [^0].
	k := (c rxLen - c rxPos) asUInt64.
	k > n ifTrue: [k := n].
	libc memcpy: buf from: c rxBuf + c rxPos size: k.
	c rxPos: c rxPos + k asUInt32.
	^k asInt64
!
freeLookup: c
	<function>
	<var: #c type: 'UefiTcpConn *'>
	(c openPending and: [c dns notNull]) ifTrue: [self efi: c dns cancel with: c dns with: (c fieldAddress: #dnsToken)].
	c child notNull ifTrue: [self efi: dnsBinding destroyChild with: dnsBinding with: c child].
	libc free: c name.
	self free: c
! !

VMStruct subclass: #UefiTcpToken
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiTcpToken comment: 'EFI_TCP4_CONNECTION_TOKEN, _LISTEN_TOKEN (extra: NewChildHandle) and _CLOSE_TOKEN (extra''s first byte: AbortOnClose).'!

!UefiTcpToken class methodsFor: 'declaring'!
fields
	^#((event 'void *') (status uint64_t) (extra 'void *'))
! !

VMStruct subclass: #UefiTcpData
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiTcpData comment: 'EFI_TCP4_RECEIVE_DATA and _TRANSMIT_DATA with one fragment (flags: UrgentFlag, or Push and Urgent).'!

!UefiTcpData class methodsFor: 'declaring'!
fields
	^#((flags uint8_t) (urgent uint8_t) (dataLength uint32_t) (fragmentCount uint32_t) (padding uint32_t) (fragmentLength uint32_t) (fragmentBuffer 'void *'))
! !

VMStruct subclass: #UefiTcpIoToken
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiTcpIoToken comment: 'EFI_TCP4_IO_TOKEN.'!

!UefiTcpIoToken class methodsFor: 'declaring'!
fields
	^#((event 'void *') (status uint64_t) (packet 'UefiTcpData *'))
! !

VMStruct subclass: #UefiDnsToken
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiDnsToken comment: 'EFI_DNS4_COMPLETION_TOKEN (answer: the DNS_HOST_TO_ADDR_DATA of HostNameToIp).'!

!UefiDnsToken class methodsFor: 'declaring'!
fields
	^#((event 'void *') (status uint64_t) (retryCount uint32_t) (retryInterval uint32_t) (answer 'EfiDnsHostToAddr *'))
! !

VMStruct subclass: #EfiDnsHostToAddr
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiDnsHostToAddr class methodsFor: 'declaring'!
fields
	^#((ipCount uint32_t) (ipList 'uint8_t *'))
! !

VMStruct subclass: #UefiTcpConn
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiTcpConn comment: 'A connection of UefiTcp: its kind (listen, stream, lookup), its TCP4 or DNS4 child, its tokens and their events, its buffers, and the readiness semaphores UefiSockets keeps in it.'!

!UefiTcpConn class methodsFor: 'declaring'!
fields
	^#((kind int32_t) (port uint32_t) (remote 'uint8_t[4]') (remotePort uint32_t)
		(child 'void *') (tcp 'EfiTcp4 *') (dns 'EfiDns4 *') (name 'char *') (events 'void *[4]')
		(openToken UefiTcpToken) (closeToken UefiTcpToken) (rxToken UefiTcpIoToken) (txToken UefiTcpIoToken) (dnsToken UefiDnsToken)
		(rxData UefiTcpData) (txData UefiTcpData) (rxBuf 'uint8_t *') (txBuf 'uint8_t *') (rxLen uint32_t) (rxPos uint32_t)
		(accepted 'void *') (configured bool) (openPending bool) (connected bool) (rxPending bool) (txPending bool) (eof bool)
		(failed bool) (answered bool) (readSem int32_t) (writeSem int32_t) (readArmed bool) (writeArmed bool))
! !

VMStruct subclass: #EfiServiceBinding
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiServiceBinding comment: 'EFI_SERVICE_BINDING_PROTOCOL (UEFI 2.10, 11.6).'!

!EfiServiceBinding class methodsFor: 'declaring'!
fields
	^#((createChild 'void *') (destroyChild 'void *'))
! !

VMStruct subclass: #EfiTcp4
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiTcp4 comment: 'EFI_TCP4_PROTOCOL (UEFI 2.10, 28.1).'!

!EfiTcp4 class methodsFor: 'declaring'!
fields
	^#((getModeData 'void *') (configure 'void *') (routes 'void *') (connect 'void *') (accept 'void *') (transmit 'void *')
		(receive 'void *') (close 'void *') (cancel 'void *') (poll 'void *'))
! !

VMStruct subclass: #EfiTcp4Config
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiTcp4Config comment: 'EFI_TCP4_CONFIG_DATA with its EFI_TCP4_ACCESS_POINT inline.'!

!EfiTcp4Config class methodsFor: 'declaring'!
fields
	^#((typeOfService uint8_t) (timeToLive uint8_t) (useDefaultAddress uint8_t) (stationAddress 'uint8_t[4]') (subnetMask 'uint8_t[4]')
		(stationPort uint16_t) (remoteAddress 'uint8_t[4]') (remotePort uint16_t) (activeFlag uint8_t) (controlOption 'void *'))
! !

VMStruct subclass: #EfiDns4
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiDns4 comment: 'EFI_DNS4_PROTOCOL (UEFI 2.10, 29.4).'!

!EfiDns4 class methodsFor: 'declaring'!
fields
	^#((getModeData 'void *') (configure 'void *') (hostNameToIp 'void *') (ipToHostName 'void *') (generalLookUp 'void *')
		(updateDnsCache 'void *') (pollDns 'void *') (cancel 'void *'))
! !

VMStruct subclass: #EfiDns4Config
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiDns4Config comment: 'EFI_DNS4_CONFIG_DATA.'!

!EfiDns4Config class methodsFor: 'declaring'!
fields
	^#((dnsServerListCount uint64_t) (dnsServerList 'void *') (useDefaultSetting uint8_t) (enableDnsCache uint8_t) (protocol uint8_t)
		(stationIp 'uint8_t[4]') (subnetMask 'uint8_t[4]') (localPort uint16_t) (retryCount uint32_t) (retryInterval uint32_t))
! !

VMStruct subclass: #EfiIp4Config2
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiIp4Config2 comment: 'EFI_IP4_CONFIG2_PROTOCOL (UEFI 2.10, 28.5).'!

!EfiIp4Config2 class methodsFor: 'declaring'!
fields
	^#((setData 'void *') (getData 'void *') (registerDataNotify 'void *') (unregisterDataNotify 'void *'))
! !
