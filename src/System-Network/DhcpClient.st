Object subclass: #DhcpClient
	instanceVariableNames: 'stack state xid server offered deadline tries interval leaseEnd renewAt rebindAt'
	classVariableNames: ''
	package: 'System-Network'!

DhcpClient comment: 'The DHCP client (RFC 2131) that configures a NetworkStack: DISCOVER, OFFER, REQUEST, ACK; the address, subnet mask, router, DNS servers and lease. An unanswered message is sent again after 1, 2, 4 ... 32 s (a REQUEST four times, then it starts over); the lease is renewed at T1 (by unicast to its server), rebound at T2 (broadcast), and given up when it ends. state: #idle, #selecting, #requesting, #bound, #renewing, #rebinding.'!

!DhcpClient class methodsFor: 'instance creation'!
on: aStack
	^self new setStack: aStack
! !

!DhcpClient methodsFor: 'running'!
setStack: aStack
	stack := aStack.
	state := #idle
!
state
	^state
!
start
	self discover
!
stop
	state := #idle
!
discover
	state := #selecting.
	xid := stack random nextInt: 16rFFFFFFFF.
	tries := 0.
	interval := 1000.
	self send: 1.
	deadline := stack now + interval
!
tick
	| t |
	t := stack now.
	(state == #idle or: [t < deadline]) ifTrue: [^self].
	(state == #selecting or: [state == #requesting]) ifTrue: [
		tries := tries + 1.
		(state == #requesting and: [tries >= 4]) ifTrue: [^self discover].
		interval := interval * 2 min: 32000.
		self send: (state == #selecting ifTrue: [1] ifFalse: [3]).
		deadline := t + interval + (stack random nextInt: 500).
		^self].
	t >= leaseEnd ifTrue: [
		stack unbind.
		^self discover].
	(state == #bound or: [state == #renewing]) ifTrue: [state := t >= rebindAt ifTrue: [#rebinding] ifFalse: [#renewing]].
	self send: 3.
	"again halfway to the next stage, at least a minute later"
	deadline := t + (((state == #renewing ifTrue: [rebindAt] ifFalse: [leaseEnd]) - t) // 2 max: 60000).
	state == #renewing ifTrue: [deadline := deadline min: rebindAt].
	deadline := deadline min: leaseEnd
!
send: type
	"A DHCP message (1 DISCOVER, 3 REQUEST): to our server while renewing, else broadcast."
	| f p o options |
	f := stack newFrame: 308.
	p := 43.
	f at: p put: 1.
	f at: p + 1 put: 1.
	f at: p + 2 put: 6.
	f netUint32At: p + 4 put: xid.
	(state == #renewing or: [state == #rebinding]) ifTrue: [f netUint32At: p + 12 put: stack address].
	f replaceFrom: p + 28 to: p + 33 with: stack macAddress startingAt: 1.
	f netUint32At: p + 236 put: 16r63825363.
	options := WriteStream on: (ByteArray new: 64).
	options nextPutAll: (ByteArray with: 53 with: 1 with: type).
	options nextPutAll: #[61 7 1]; nextPutAll: stack macAddress.
	(type = 3 and: [state == #requesting]) ifTrue: [
		options nextPutAll: #[50 4]; nextPutAll: (self bytesOf: offered).
		server ~= 0 ifTrue: [options nextPutAll: #[54 4]; nextPutAll: (self bytesOf: server)]].
	options nextPutAll: #[55 6 1 3 6 51 58 59]; nextPutAll: #[57 2 5 220]; nextPut: 255.
	o := options contents.
	f replaceFrom: p + 240 to: p + 239 + o size with: o startingAt: 1.
	stack sendUdpFrom: 68 to: (state == #renewing ifTrue: [server] ifFalse: [16rFFFFFFFF]) port: 67 frame: f length: 300
!
bytesOf: anAddress
	^ByteArray with: (anAddress bitShift: -24) with: ((anAddress bitShift: -16) bitAnd: 255) with: ((anAddress bitShift: -8) bitAnd: 255) with: (anAddress bitAnd: 255)
!
datagram: f at: start count: n
	"A message from a server: an OFFER (we ask for it), an ACK (bound) or a NAK (start over)."
	| o code len type serverId mask router lease t1 t2 dns yiaddr |
	(n < 240 or: [(f at: start) ~= 2 or: [(f netUint32At: start + 4) ~= xid or: [(f netUint32At: start + 236) ~= 16r63825363]]]) ifTrue: [^self].
	(f copyFrom: start + 28 to: start + 33) = stack macAddress ifFalse: [^self].
	type := serverId := mask := router := lease := t1 := t2 := 0.
	dns := OrderedCollection new.
	o := start + 240.
	[o < (start + n) and: [(code := f at: o) ~= 255]] whileTrue: [
		code = 0
			ifTrue: [o := o + 1]
			ifFalse: [
				len := o + 1 < (start + n) ifTrue: [f at: o + 1] ifFalse: [0].
				o + 2 + len > (start + n) ifTrue: [^self].
				(code = 53 and: [len = 1]) ifTrue: [type := f at: o + 2].
				(code = 54 and: [len = 4]) ifTrue: [serverId := f netUint32At: o + 2].
				(code = 1 and: [len = 4]) ifTrue: [mask := f netUint32At: o + 2].
				(code = 3 and: [len >= 4]) ifTrue: [router := f netUint32At: o + 2].
				(code = 51 and: [len = 4]) ifTrue: [lease := f netUint32At: o + 2].
				(code = 58 and: [len = 4]) ifTrue: [t1 := f netUint32At: o + 2].
				(code = 59 and: [len = 4]) ifTrue: [t2 := f netUint32At: o + 2].
				code = 6 ifTrue: [0 to: len // 4 - 1 do: [:i | dns add: (f netUint32At: o + 2 + (4 * i))]].
				o := o + 2 + len]].
	yiaddr := f netUint32At: start + 16.
	(type = 2 and: [state == #selecting and: [yiaddr ~= 0]]) ifTrue: [
		offered := yiaddr.
		server := serverId.
		state := #requesting.
		tries := 0.
		interval := 1000.
		self send: 3.
		deadline := stack now + interval.
		^self].
	(#(#requesting #renewing #rebinding) includes: state) ifFalse: [^self].
	type = 6 ifTrue: [
		stack unbind.
		^self discover].
	(type = 5 and: [yiaddr ~= 0]) ifTrue: [
		serverId ~= 0 ifTrue: [server := serverId].
		stack nameServers: dns.
		self bound: yiaddr mask: (mask = 0 ifTrue: [16rFFFFFF00] ifFalse: [mask]) router: router lease: lease t1: t1 t2: t2]
!
bound: yiaddr mask: mask router: router lease: lease t1: t1 t2: t2
	"Times in seconds (lease 0: an hour; 16rFFFFFFFF: forever)."
	| t secs |
	t := stack now.
	(stack address ~= yiaddr or: [state == #requesting]) ifTrue: [stack bind: yiaddr mask: mask gateway: router].
	state := #bound.
	lease = 16rFFFFFFFF ifTrue: [
		leaseEnd := renewAt := rebindAt := deadline := SmallInteger maxVal.
		^self].
	secs := lease = 0 ifTrue: [3600] ifFalse: [lease].
	leaseEnd := t + (secs * 1000).
	renewAt := t + ((t1 = 0 ifTrue: [secs // 2] ifFalse: [t1]) * 1000).
	rebindAt := t + ((t2 = 0 ifTrue: [secs * 7 // 8] ifFalse: [t2]) * 1000).
	deadline := renewAt
! !
