Object subclass: #NetworkStack
	instanceVariableNames: 'interface mac address netmask gateway nameServers clock now wakeup process ticker running arp ipId random nextPort connections sockets dhcp resolver rxBuffer loopback counters arpCheck'
	classVariableNames: 'Default LastError ProbeLock Probed'
	package: 'System-Network'!

NetworkStack comment: 'I am a TCP/IP stack (IPv4) in the image, over a NetworkInterface''s Ethernet frames: where there are no sockets of an operating system (UEFI: the image''s driver of the NIC, or the VM''s nic primitives), RemoteSocket''s sockets are mine (active), so ControlServer, HTTPClient and the rest work unchanged. I do Ethernet, ARP (a cache with aging; the last packet for an address being resolved waits for the answer; a gratuitous request when an address is bound), IPv4 (to the gateway unless for the subnet; fragments dropped, none sent; 127/8 and my own address loop back), ICMP (echo answered; a port unreachable fails a connection being made) and UDP; DhcpClient configures me, DnsResolver looks names up, TcpConnection is TCP, NetSocket the handles RemoteSocket knows.

My Process (priority 55: above user Processes and the remote-control service, below input and the compositor) waits for frames (the interface signals) and for my timer Process, which wakes it every 10 ms; each wakeup handles what arrived and runs every timer (pollAt:). Sockets work from their own Processes, under my lock (critical:), and wait on their Semaphores. Times are milliseconds of my clock (a block; tests give their own and drive me with pollAt:).'!

!NetworkStack class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self
! !

!NetworkStack class methodsFor: 'the image''s stack'!
active
	"The stack RemoteSocket's sockets use: when the machine has a network interface instead of the platform's sockets (UEFI: NetworkInterface open), started on first use; else nil (the platform's sockets). Processes that ask while the first one opens the interface wait for it (they used to get nil: the platform's sockets, which UEFI has not)."
	Probed == true ifTrue: [^Default].
	ProbeLock isNil ifTrue: [ProbeLock := Semaphore forMutualExclusion].
	^ProbeLock critical: [
		Probed == true ifFalse: [
			Default := NetworkInterface open ifNotNil: [:nic | (self on: nic) start; startDhcp; yourself].
			Probed := true].
		Default]
!
active: aStackOrNil
	"Let RemoteSocket use aStackOrNil (tests); nil: whatever the VM has, asked again."
	Default := aStackOrNil.
	Probed := aStackOrNil notNil
!
startUp: resuming
	"In an image resumed from a snapshot the stack's NIC, connections and Processes belonged to the VM that saved it."
	resuming ifFalse: [^self].
	Default isNil ifFalse: [Default abandon].
	Default := nil.
	Probed := false.
	NetSocket forgetAll
!
priority
	^55
!
tickMs
	^10
!
lockPriority
	"Above input, the compositor and everything else that may use a socket; below the timer."
	^79
! !

!NetworkStack class methodsFor: 'instance creation'!
on: aNetworkInterface
	^self new setInterface: aNetworkInterface
! !

!NetworkStack class methodsFor: 'errors'!
noteError: aString
	LastError := aString
!
takeLastError
	"The reason the last socket operation of a stack failed (once), or nil."
	| e |
	e := LastError.
	LastError := nil.
	^e
! !

!NetworkStack class methodsFor: 'addresses'!
addressFrom: aString
	"The IPv4 address (an Integer) of a dotted string, or nil."
	| parts |
	parts := aString subStrings: '.'.
	(parts size = 4 and: [(aString occurrencesOf: $.) = 3]) ifFalse: [^nil].
	^parts inject: 0 into: [:a :each |
		(each notEmpty and: [each size <= 3 and: [each allSatisfy: [:c | c isDigit]]]) ifFalse: [^nil].
		each asNumber > 255 ifTrue: [^nil].
		(a bitShift: 8) + each asNumber]
!
dotted: anInteger
	^String streamContents: [:s |
		24 to: 0 by: -8 do: [:k |
			s print: ((anInteger bitShift: k negated) bitAnd: 255).
			k > 0 ifTrue: [s nextPut: $.]]]
! !

!NetworkStack methodsFor: 'initialization'!
setInterface: aNetworkInterface
	interface := aNetworkInterface.
	mac := aNetworkInterface macAddress.
	address := netmask := gateway := 0.
	nameServers := OrderedCollection new.
	clock := [Time millisecondClockValue].
	now := clock value.
	arp := Dictionary new.
	ipId := 0.
	random := Random new.
	nextPort := 49152 + (random nextInt: 16000).
	connections := OrderedCollection new.
	sockets := OrderedCollection new.
	loopback := OrderedCollection new.
	rxBuffer := ByteArray new: 1536.
	counters := IdentityDictionary new.
	arpCheck := 0.
	running := false.
	dhcp := DhcpClient on: self.
	resolver := DnsResolver on: self
! !

!NetworkStack methodsFor: 'running'!
start
	"Run my Processes."
	running ifTrue: [^self].
	running := true.
	wakeup := Semaphore new.
	interface semaphore: wakeup.
	process := [self run] forkAt: self class priority named: 'network'.
	ticker := [[running] whileTrue: [
		(Delay forMilliseconds: self class tickMs) wait.
		wakeup signal]] forkAt: self class priority named: 'network timers'
!
startDhcp
	"Get an address (and the rest) by DHCP."
	self critical: [
		now := clock value.
		dhcp start]
!
run
	[running] whileTrue: [
		wakeup wait.
		running ifTrue: [self poll]]
!
poll
	self critical: [self pollAt: clock value]
!
pollAt: milliseconds
	"Take what arrived, run every timer, signal the sockets that became ready. My lock held."
	| n count looped |
	now := milliseconds.
	count := 0.
	[count < 256 and: [(n := interface receiveInto: rxBuffer) notNil]] whileTrue: [
		self frame: rxBuffer count: n.
		count := count + 1.
		self runLoopback].
	(count >= 256 and: [wakeup notNil]) ifTrue: [wakeup signal].
	self runLoopback.
	self arpTimers.
	dhcp tick.
	resolver tick.
	1 to: connections size do: [:i | (connections at: i) timers].
	(connections anySatisfy: [:each | each isDone]) ifTrue: [
		connections removeAll: (connections select: [:each | each isDone])].
	self runLoopback.
	sockets do: [:each | each update]
!
runLoopback
	| f k |
	k := 0.
	[loopback notEmpty and: [k < 1000]] whileTrue: [
		f := loopback removeFirst.
		self frame: f count: f size.
		k := k + 1]
!
stop
	"Stop: my connections are reset, my Processes end, my interface is let go."
	self critical: [
		connections copy do: [:each | each abort].
		connections removeAll: connections copy].
	self endProcesses.
	interface close
!
abandon
	"In an image resumed from a snapshot: my NIC, connections and Processes belonged to the VM that saved it."
	self endProcesses.
	interface forget
!
endProcesses
	running := false.
	{process. ticker} do: [:each | (each notNil and: [each isActiveProcess not]) ifTrue: [each terminate]]
!
critical: aBlock
	"Evaluate aBlock with nothing else that uses me in between: at a priority above every Process that might (none of my critical sections waits, so a Process terminated in one leaves nothing locked, as one waiting on a Semaphore's critical: may). What became ready above my caller's priority meanwhile runs once it waits."
	| active old |
	active := Processor activeProcess.
	old := active priority.
	old >= self class lockPriority ifTrue: [^aBlock value].
	active priority: self class lockPriority.
	^[aBlock value] ensure: [active priority: old]
!
wake
	wakeup isNil ifFalse: [wakeup signal]
! !

!NetworkStack methodsFor: 'accessing'!
interface
	^interface
!
macAddress
	^mac
!
address
	^address
!
netmask
	^netmask
!
gateway
	^gateway
!
nameServers
	^nameServers
!
now
	^now
!
clock: aBlock
	"Where my time comes from (milliseconds)."
	clock := aBlock.
	now := clock value
!
random
	^random
!
dhcp
	^dhcp
!
resolver
	^resolver
!
connections
	^connections
!
isConfigured
	^address ~= 0
!
isRunning
	^running
!
counters
	^counters
!
count: aSymbol
	counters at: aSymbol put: (counters at: aSymbol ifAbsent: [0]) + 1
!
printOn: aStream
	aStream nextPutAll: 'a NetworkStack ('; nextPutAll: (self class dotted: address); nextPut: $)
! !

!NetworkStack methodsFor: 'configuring'!
bind: anAddress mask: aMask gateway: aGateway
	"An address (from DHCP), announced with a gratuitous ARP request; connections that waited for it go ahead."
	address := anAddress.
	netmask := aMask.
	gateway := aGateway.
	self arpRequest: address.
	connections do: [:each | each addressCame]
!
unbind
	address := netmask := gateway := 0.
	nameServers := OrderedCollection new.
	arp := Dictionary new
!
nameServers: aCollection
	nameServers := aCollection asOrderedCollection
! !

!NetworkStack methodsFor: 'Ethernet'!
newFrame: payloadSize
	"A frame with room for payloadSize bytes of IP payload (from 35: after the Ethernet and IP headers)."
	^ByteArray new: 34 + payloadSize
!
frame: f count: n
	"A frame received: for my MAC address (or broadcast), IP or ARP."
	| type |
	self count: #framesIn.
	n < 14 ifTrue: [^self drop].
	((self isMine: f) or: [self isBroadcastMac: f]) ifFalse: [^self drop].
	type := f netUint16At: 13.
	type = 16r0800 ifTrue: [^self ip: f count: n].
	type = 16r0806 ifTrue: [^self arp: f count: n].
	self drop
!
isBroadcastMac: f
	^(f at: 1) = 255 and: [(f at: 2) = 255 and: [(f at: 3) = 255 and: [(f at: 4) = 255 and: [(f at: 5) = 255 and: [(f at: 6) = 255]]]]]
!
isMine: f
	^(f at: 6) = (mac at: 6) and: [(f at: 5) = (mac at: 5) and: [(f at: 4) = (mac at: 4) and: [(f at: 3) = (mac at: 3) and: [(f at: 2) = (mac at: 2) and: [(f at: 1) = (mac at: 1)]]]]]
!
drop
	self count: #dropped
!
transmit: f type: type length: n
	"The frame f, to the MAC address already in it."
	f replaceFrom: 7 to: 12 with: mac startingAt: 1.
	f netUint16At: 13 put: type.
	self count: #framesOut.
	^interface send: f count: n
! !

!NetworkStack methodsFor: 'ARP'!
arp: f count: n
	"Learn the sender (if we know it already, or it asks for us); answer a request for our address."
	| op spa tpa sha e |
	n < 42 ifTrue: [^self drop].
	((f netUint16At: 15) = 1 and: [(f netUint16At: 17) = 16r0800 and: [(f at: 19) = 6 and: [(f at: 20) = 4]]]) ifFalse: [^self drop].
	op := f netUint16At: 21.
	sha := f copyFrom: 23 to: 28.
	spa := f netUint32At: 29.
	tpa := f netUint32At: 39.
	spa = 0 ifTrue: [^self].
	e := arp at: spa ifAbsent: [nil].
	(e isNil and: [address ~= 0 and: [tpa = address]]) ifTrue: [e := self arpEntryFor: spa].
	e isNil ifFalse: [self arp: e resolved: sha].
	(op = 1 and: [address ~= 0 and: [tpa = address]]) ifTrue: [self arpSend: 2 to: sha ip: spa]
!
arpEntryFor: ip
	"A new entry for ip; the one that expires first goes when there are 64."
	| e |
	arp size >= 64 ifTrue: [
		arp do: [:each | (e isNil or: [each deadline < e deadline]) ifTrue: [e := each]].
		arp removeKey: e ip].
	e := ArpEntry ip: ip.
	arp at: ip put: e.
	^e
!
arp: e resolved: hw
	"e's MAC address is hw: send what waited for it."
	| f |
	e mac: hw; state: #resolved; deadline: now + 120000; tries: 0.
	f := e pending.
	f isNil ifTrue: [^self].
	e pending: nil.
	f replaceFrom: 1 to: 6 with: hw startingAt: 1.
	self transmit: f type: 16r0800 length: f size
!
arpRequest: ip
	"Who has ip? (Our own address: a gratuitous request.)"
	self arpSend: 1 to: nil ip: ip
!
arpSend: op to: hw ip: ip
	"A request (op 1, broadcast) or a reply (op 2, to hw) about ip."
	| f |
	f := ByteArray new: 42.
	f replaceFrom: 1 to: 6 with: (hw ifNil: [#[255 255 255 255 255 255]]) startingAt: 1.
	f netUint16At: 15 put: 1.
	f netUint16At: 17 put: 16r0800.
	f at: 19 put: 6.
	f at: 20 put: 4.
	f netUint16At: 21 put: op.
	f replaceFrom: 23 to: 28 with: mac startingAt: 1.
	f netUint32At: 29 put: address.
	hw isNil ifFalse: [f replaceFrom: 33 to: 38 with: hw startingAt: 1].
	f netUint32At: 39 put: ip.
	self transmit: f type: 16r0806 length: 42
!
arpTimers
	"Ask again for addresses not answered yet, and for those about to expire; forget them after three requests. Every 100 ms."
	now < arpCheck ifTrue: [^self].
	arpCheck := now + 100.
	arp copy keysAndValuesDo: [:ip :e |
		now >= e deadline ifTrue: [
			e state == #resolved ifTrue: [e state: #refreshing; tries: 0].
			e tries >= 3
				ifTrue: [arp removeKey: ip]
				ifFalse: [
					e tries: e tries + 1; deadline: now + 1000.
					self arpRequest: ip]]]
!
arpCache
	^arp
! !

!NetworkStack methodsFor: 'IP'!
isLocal: anAddress
	^(anAddress bitShift: -24) = 127 or: [address ~= 0 and: [anAddress = address]]
!
sourceFor: anAddress
	"The address I send to anAddress from."
	^(anAddress bitShift: -24) = 127 ifTrue: [16r7F000001] ifFalse: [address]
!
ip: f count: n
	"An IPv4 packet for us (or broadcast, or anything for UDP while we have no address: DHCP's answer)."
	| ihl total src dst proto broadcast |
	n < 34 ifTrue: [^self drop].
	((f at: 15) bitShift: -4) = 4 ifFalse: [^self drop].
	ihl := ((f at: 15) bitAnd: 15) * 4.
	total := f netUint16At: 17.
	(ihl < 20 or: [total < ihl or: [total > (n - 14)]]) ifTrue: [^self drop].
	(f internetSumFrom: 15 count: ihl) = 16rFFFF ifFalse: [^self drop].
	((f netUint16At: 21) bitAnd: 16r3FFF) = 0 ifFalse: [^self drop].
	src := f netUint32At: 27.
	dst := f netUint32At: 31.
	proto := f at: 24.
	broadcast := dst = 16rFFFFFFFF or: [address ~= 0 and: [dst = (address bitOr: (netmask bitXor: 16rFFFFFFFF))]].
	((self isLocal: dst) or: [broadcast or: [address = 0 and: [proto = 17]]]) ifFalse: [^self drop].
	(proto = 1 and: [broadcast not]) ifTrue: [^self icmp: f at: 15 + ihl count: total - ihl from: src to: dst].
	(proto = 6 and: [broadcast not]) ifTrue: [^self tcp: f at: 15 + ihl count: total - ihl from: src to: dst].
	proto = 17 ifTrue: [^self udp: f at: 15 + ihl count: total - ihl from: src to: dst].
	self drop
!
sendIp: proto from: src to: dst frame: f length: n
	"The n bytes of payload in f (from 35) under an IP header; false if they cannot go (no address yet, no route)."
	| hop |
	(src = 0 and: [dst ~= 16rFFFFFFFF]) ifTrue: [^false].
	f at: 15 put: 16r45.
	f at: 16 put: 0.
	f netUint16At: 17 put: n + 20.
	f netUint16At: 19 put: ipId.
	ipId := ipId + 1 bitAnd: 16rFFFF.
	f netUint16At: 21 put: 16r4000.
	f at: 23 put: 64.
	f at: 24 put: proto.
	f netUint16At: 25 put: 0.
	f netUint32At: 27 put: src.
	f netUint32At: 31 put: dst.
	f netUint16At: 25 put: ((f internetSumFrom: 15 count: 20) bitXor: 16rFFFF).
	(self isLocal: dst) ifTrue: [
		f replaceFrom: 1 to: 6 with: mac startingAt: 1.
		f replaceFrom: 7 to: 12 with: mac startingAt: 1.
		f netUint16At: 13 put: 16r0800.
		loopback addLast: (f copyFrom: 1 to: n + 34).
		self wake.
		^true].
	hop := self nextHop: dst.
	hop = 0 ifTrue: [^false].
	^self sendFrame: f to: hop length: n + 34
!
nextHop: dst
	"dst itself on our subnet (or a broadcast), else the gateway; 0 if there is none."
	dst = 16rFFFFFFFF ifTrue: [^dst].
	dst = (address bitOr: (netmask bitXor: 16rFFFFFFFF)) ifTrue: [^16rFFFFFFFF].
	(dst bitAnd: netmask) = (address bitAnd: netmask) ifTrue: [^dst].
	^gateway
!
sendFrame: f to: hop length: n
	"At once if hop's MAC address is known; else the frame waits for ARP's answer (instead of the one waiting)."
	| e |
	hop = 16rFFFFFFFF ifTrue: [
		f replaceFrom: 1 to: 6 with: #[255 255 255 255 255 255] startingAt: 1.
		^self transmit: f type: 16r0800 length: n].
	e := arp at: hop ifAbsent: [nil].
	(e notNil and: [e hasMac]) ifTrue: [
		f replaceFrom: 1 to: 6 with: e mac startingAt: 1.
		^self transmit: f type: 16r0800 length: n].
	e isNil ifTrue: [
		e := self arpEntryFor: hop.
		e state: #pending; tries: 1; deadline: now + 1000.
		e pending: (f copyFrom: 1 to: n).
		self arpRequest: hop.
		^true].
	e pending: (f copyFrom: 1 to: n).
	^true
!
pseudo: src dst: dst proto: proto length: n
	"The sum of the pseudo-header of TCP and UDP checksums."
	^(src bitShift: -16) + (src bitAnd: 16rFFFF) + (dst bitShift: -16) + (dst bitAnd: 16rFFFF) + proto + n
!
sum: f at: start count: n plus: aSum
	"The folded ones' complement sum of n bytes of f from start and aSum: 16rFFFF over a correct segment and its pseudo-header."
	| sum |
	sum := (f internetSumFrom: start count: n) + aSum.
	[sum > 16rFFFF] whileTrue: [sum := (sum bitAnd: 16rFFFF) + (sum bitShift: -16)].
	^sum
! !

!NetworkStack methodsFor: 'ICMP'!
icmp: f at: start count: n from: src to: dst
	"Echo requests answered; a port or protocol unreachable told to TCP."
	| r inner ihl |
	n < 8 ifTrue: [^self drop].
	(f internetSumFrom: start count: n) = 16rFFFF ifFalse: [^self drop].
	((f at: start) = 8 and: [n <= 1480]) ifTrue: [
		r := self newFrame: n.
		r replaceFrom: 35 to: 34 + n with: f startingAt: start.
		r at: 35 put: 0.
		r netUint16At: 37 put: 0.
		r netUint16At: 37 put: ((r internetSumFrom: 35 count: n) bitXor: 16rFFFF).
		^self sendIp: 1 from: dst to: src frame: r length: n].
	((f at: start) = 3 and: [n >= 36]) ifTrue: [
		inner := start + 8.
		ihl := ((f at: inner) bitAnd: 15) * 4.
		((f at: inner + 9) = 6 and: [n >= (8 + ihl + 4)]) ifTrue: [
			self unreachable: (f netUint32At: inner + 16) port: (f netUint16At: inner + ihl + 2)
				from: (f netUint16At: inner + ihl) code: (f at: start + 1)]]
! !

!NetworkStack methodsFor: 'UDP'!
udp: f at: start count: n from: src to: dst
	| len port |
	n < 8 ifTrue: [^self drop].
	len := f netUint16At: start + 4.
	(len < 8 or: [len > n]) ifTrue: [^self drop].
	((f netUint16At: start + 6) ~= 0 and: [(self sum: f at: start count: len plus: (self pseudo: src dst: dst proto: 17 length: len)) ~= 16rFFFF])
		ifTrue: [^self drop].
	port := f netUint16At: start + 2.
	port = 68 ifTrue: [^dhcp datagram: f at: start + 8 count: len - 8].
	resolver datagram: f at: start + 8 count: len - 8 port: port from: src port: (f netUint16At: start)
!
sendUdpFrom: sport to: dst port: dport frame: f length: n
	"The n bytes in f from 43 in a datagram."
	| src sum |
	src := self sourceFor: dst.
	f netUint16At: 35 put: sport.
	f netUint16At: 37 put: dport.
	f netUint16At: 39 put: n + 8.
	f netUint16At: 41 put: 0.
	sum := (self sum: f at: 35 count: n + 8 plus: (self pseudo: src dst: dst proto: 17 length: n + 8)) bitXor: 16rFFFF.
	f netUint16At: 41 put: (sum = 0 ifTrue: [16rFFFF] ifFalse: [sum]).
	^self sendIp: 17 from: src to: dst frame: f length: n + 8
!
freeUdpPort
	nextPort := nextPort >= 65535 ifTrue: [49152] ifFalse: [nextPort + 1].
	^nextPort
! !

!NetworkStack methodsFor: 'TCP'!
tcp: f at: start count: n from: src to: dst
	| seg c |
	n < 20 ifTrue: [^self drop].
	(self sum: f at: start count: n plus: (self pseudo: src dst: dst proto: 6 length: n)) = 16rFFFF ifFalse: [^self drop].
	seg := TcpSegment frame: f at: start count: n from: src to: dst.
	seg isNil ifTrue: [^self drop].
	self count: #segmentsIn.
	c := self connectionFor: seg.
	c isNil ifTrue: [^self reset: seg].
	c input: seg
!
connectionFor: seg
	"The connection seg is for, else the listener on its port, else nil."
	| listener |
	connections do: [:each |
		each localPort = seg dstPort ifTrue: [
			each isListening
				ifTrue: [listener := each]
				ifFalse: [(each isClosed not and: [each remotePort = seg srcPort and: [each remoteIp = seg src]]) ifTrue: [^each]]]].
	^listener
!
reset: seg
	"Answer a segment for no connection with a RST (unless it is one)."
	| f ack |
	seg isReset ifTrue: [^self].
	f := self newFrame: 20.
	f netUint16At: 35 put: seg dstPort.
	f netUint16At: 37 put: seg srcPort.
	seg hasAck
		ifTrue: [
			f netUint32At: 39 put: seg ack.
			f at: 48 put: TcpConnection rst]
		ifFalse: [
			ack := seg seq + seg length + (seg isSyn ifTrue: [1] ifFalse: [0]) + (seg isFin ifTrue: [1] ifFalse: [0]).
			f netUint32At: 43 put: (ack bitAnd: 16rFFFFFFFF).
			f at: 48 put: (TcpConnection rst bitOr: TcpConnection ack)].
	f at: 47 put: 80.
	f netUint16At: 51 put: ((self sum: f at: 35 count: 20 plus: (self pseudo: seg dst dst: seg src proto: 6 length: 20)) bitXor: 16rFFFF).
	self count: #segmentsOut.
	self sendIp: 6 from: seg dst to: seg src frame: f length: 20
!
unreachable: anAddress port: port from: localPort code: code
	"ICMP: a protocol or port unreachable fails a connection being made."
	(code = 2 or: [code = 3]) ifFalse: [^self].
	connections do: [:each |
		(each isSynSent and: [each remoteIp = anAddress and: [each remotePort = port and: [each localPort = localPort]]])
			ifTrue: [each fail: #unreachable]]
!
freePort
	"An ephemeral port no connection has."
	[nextPort := nextPort >= 65535 ifTrue: [49152] ifFalse: [nextPort + 1].
	 connections anySatisfy: [:each | each localPort = nextPort and: [each isClosed not]]] whileTrue.
	^nextPort
!
isListening: port
	^connections anySatisfy: [:each | each isListening and: [each localPort = port]]
!
initialSequence
	^random nextInt: 16rFFFFFFFF
!
addConnection: aTcpConnection
	connections add: aTcpConnection
! !

!NetworkStack methodsFor: 'sockets'!
listen: host port: port backlog: backlog
	"The handle of a socket listening on port (0: an ephemeral one) of every address (host: 0.0.0.0, 127.0.0.1 or ours); nil if it cannot."
	^self critical: [| a c |
		a := self class addressFrom: host.
		a isNil
			ifTrue: [self fail: 'not a numeric IPv4 address']
			ifFalse: [
				(port ~= 0 and: [self isListening: port])
					ifTrue: [self fail: 'address already in use']
					ifFalse: [
						c := TcpConnection listenerOn: self port: (port = 0 ifTrue: [self freePort] ifFalse: [port]) backlog: backlog.
						connections add: c.
						(NetSocket on: self connection: c) handle]]]
!
connect: host port: port
	"The handle of a socket connecting to the numeric address host and port (NetSocket>>connected tells when it is); nil if it cannot."
	^self critical: [| a c |
		a := self class addressFrom: host.
		a isNil
			ifTrue: [self fail: 'not a numeric IPv4 address']
			ifFalse: [
				c := TcpConnection on: self to: a port: port from: self freePort.
				connections add: c.
				c open.
				(NetSocket on: self connection: c) handle]]
!
resolve: hostName
	"The handle of a socket that reads as the addresses of hostName, a line each, or as one line of !! and the error, then ends."
	^self critical: [(NetSocket on: self lookup: (resolver lookup: hostName)) handle]
!
fail: aString
	"A socket operation failed: why, for RemoteSocket's lastError; answer nil."
	self class noteError: aString.
	^nil
!
addSocket: aNetSocket
	sockets add: aNetSocket
!
removeSocket: aNetSocket
	sockets remove: aNetSocket ifAbsent: []
! !

Object subclass: #ArpEntry
	instanceVariableNames: 'ip mac state deadline tries pending'
	classVariableNames: ''
	package: 'System-Network'!

ArpEntry comment: 'An address in a NetworkStack''s ARP cache: its MAC address once known; its state (#pending, #resolved, #refreshing: still used while asked again), the requests sent and when to act next; the frame waiting for it.'!

!ArpEntry class methodsFor: 'instance creation'!
ip: anInteger
	^self new setIp: anInteger
! !

!ArpEntry methodsFor: 'accessing'!
setIp: anInteger
	ip := anInteger.
	tries := 0.
	deadline := 0
!
ip
	^ip
!
mac
	^mac
!
mac: aByteArray
	mac := aByteArray
!
hasMac
	^mac notNil and: [state ~~ #pending]
!
state
	^state
!
state: aSymbol
	state := aSymbol
!
deadline
	^deadline
!
deadline: milliseconds
	deadline := milliseconds
!
tries
	^tries
!
tries: anInteger
	tries := anInteger
!
pending
	^pending
!
pending: aFrame
	pending := aFrame
! !
