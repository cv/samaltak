TestCase subclass: #NetworkStackTest
	instanceVariableNames: 'stack peer t stacks'
	classVariableNames: ''
	package: 'Tests-Network'!

NetworkStackTest comment: 'The image''s TCP/IP stack (System-Network) on virtual wires, in the test''s time (tick:): checksums, sequence numbers modulo 2^32, ARP, ping, DHCP and DNS against a peer scripted here; TCP against crafted segments (handshakes, RSTs, out-of-order data, wrap-around, windows both ways, retransmission, fast retransmit, the closing states); two stacks moving data through a wire that loses and reorders frames; RemoteSockets between two running stacks. We are 10.0.2.15, the peer 10.0.2.2 (the gateway), the DNS server 10.0.2.3, as on QEMU''s user network.'!

!NetworkStackTest methodsFor: 'running'!
setUp
	| pair |
	pair := VirtualNetworkInterface wire: #[16r52 16r54 0 16r12 16r34 16r56] to: self peerMac.
	t := 0.
	stack := NetworkStack on: pair first.
	stack clock: [t].
	peer := pair last.
	stacks := OrderedCollection new
!
tearDown
	stacks do: [:each | each stop].
	NetworkStack active: nil
!
bind
	"Our address as DHCP would give it; the peer and the DNS server known (they asked for us)."
	stack bind: self us mask: 16rFFFFFF00 gateway: self peer.
	stack nameServers: {self nameServer}.
	self inject: (self arp: 1 from: self peerMac ip: self peer to: #[0 0 0 0 0 0] ip: self us).
	self inject: (self arp: 1 from: #[16r52 16r55 16r0A 0 2 3] ip: self nameServer to: #[0 0 0 0 0 0] ip: self us).
	self tick: 0.
	peer inbox removeAll: peer inbox copy
!
tick: ms
	t := t + ms.
	stack poll
!
inject: aFrame
	stack interface deliver: aFrame
!
timeLimitMilliseconds
	^120000
! !

!NetworkStackTest methodsFor: 'addresses'!
us
	^16r0A00020F
!
peer
	^16r0A000202
!
nameServer
	^16r0A000203
!
peerMac
	^#[16r52 16r55 16r0A 0 2 2]
!
port
	"Our side of the connection the crafted segments are for."
	^49999
! !

!NetworkStackTest methodsFor: 'frames'!
sum: b
	"The ones' complement sum of b, as RFC 1071 has it (written here independently of internetSumFrom:count:)."
	| acc |
	acc := 0.
	1 to: b size by: 2 do: [:i | acc := acc + ((b at: i) bitShift: 8) + (i < b size ifTrue: [b at: i + 1] ifFalse: [0])].
	[acc > 16rFFFF] whileTrue: [acc := (acc bitAnd: 16rFFFF) + (acc bitShift: -16)].
	^acc
!
pseudo: src dst: dst proto: proto length: n
	| b |
	b := ByteArray new: 12.
	b netUint32At: 1 put: src.
	b netUint32At: 5 put: dst.
	b at: 10 put: proto.
	b netUint16At: 11 put: n.
	^b
!
ip: proto from: src to: dst payload: p
	| h |
	h := ByteArray new: 20.
	h at: 1 put: 16r45.
	h netUint16At: 3 put: 20 + p size.
	h at: 9 put: 64.
	h at: 10 put: proto.
	h netUint32At: 13 put: src.
	h netUint32At: 17 put: dst.
	h netUint16At: 11 put: ((self sum: h) bitXor: 16rFFFF).
	^stack macAddress , self peerMac , #[8 0] , h , p
!
arp: op from: sha ip: spa to: tha ip: tpa
	| a |
	a := ByteArray new: 28.
	a netUint16At: 1 put: 1.
	a netUint16At: 3 put: 16r0800.
	a at: 5 put: 6.
	a at: 6 put: 4.
	a netUint16At: 7 put: op.
	a replaceFrom: 9 to: 14 with: sha startingAt: 1.
	a netUint32At: 15 put: spa.
	a replaceFrom: 19 to: 24 with: tha startingAt: 1.
	a netUint32At: 25 put: tpa.
	^(op = 1 ifTrue: [#[255 255 255 255 255 255]] ifFalse: [stack macAddress]) , sha , #[8 6] , a
!
segmentFrom: sport to: dport seq: seq ack: ack flags: flags window: w data: d options: o
	| s |
	s := ByteArray new: 20 + o size.
	s netUint16At: 1 put: sport.
	s netUint16At: 3 put: dport.
	s netUint32At: 5 put: (seq bitAnd: 16rFFFFFFFF).
	s netUint32At: 9 put: (ack bitAnd: 16rFFFFFFFF).
	s at: 13 put: (20 + o size) * 4.
	s at: 14 put: flags.
	s netUint16At: 15 put: w.
	s replaceFrom: 21 to: 20 + o size with: o startingAt: 1.
	s := s , d.
	s netUint16At: 17 put: ((self sum: (self pseudo: self peer dst: self us proto: 6 length: s size) , s) bitXor: 16rFFFF).
	^self ip: 6 from: self peer to: self us payload: s
!
send: flags seq: seq ack: ack
	self send: flags seq: seq ack: ack data: #[] window: 65535
!
send: flags seq: seq ack: ack data: d window: w
	"From the peer's port 80 to our connection's port, delivered and polled."
	self inject: (self segmentFrom: 80 to: self port seq: seq ack: ack flags: flags window: w data: d options: #[]).
	self tick: 0
!
ipOf: f
	"The IP packet of a frame (its header checked), or nil."
	| ip |
	(f size >= 34 and: [(f netUint16At: 13) = 16r0800]) ifFalse: [^nil].
	ip := f copyFrom: 15 to: 14 + (f netUint16At: 17).
	self assert: (self sum: (ip copyFrom: 1 to: 20)) equals: 16rFFFF.
	^ip
!
tcpOf: f
	"The TCP segment of a frame as a Dictionary (its checksum checked), or nil."
	| ip s hl d |
	ip := self ipOf: f.
	(ip isNil or: [(ip at: 10) ~= 6]) ifTrue: [^nil].
	s := ip copyFrom: 21 to: ip size.
	self assert: (self sum: (self pseudo: (ip netUint32At: 13) dst: (ip netUint32At: 17) proto: 6 length: s size) , s) equals: 16rFFFF.
	hl := ((s at: 13) bitShift: -4) * 4.
	d := Dictionary new.
	d at: #srcPort put: (s netUint16At: 1); at: #dstPort put: (s netUint16At: 3); at: #seq put: (s netUint32At: 5);
		at: #ack put: (s netUint32At: 9); at: #flags put: (s at: 14); at: #window put: (s netUint16At: 15);
		at: #data put: (s copyFrom: hl + 1 to: s size).
	(hl >= 24 and: [(s at: 21) = 2]) ifTrue: [d at: #mss put: (s netUint16At: 23)].
	^d
!
sent
	"The frames sent since last asked."
	| all |
	all := peer inbox copy.
	peer inbox removeAll: all.
	^all
!
segments
	^((self sent collect: [:f | self tcpOf: f]) reject: [:s | s isNil]) asArray
!
segment
	| all |
	all := self segments.
	self assert: all size equals: 1.
	^all first
!
noSegments
	self assert: self segments isEmpty
! !

!NetworkStackTest methodsFor: 'connections'!
connectWithIss: peerIss
	"A connection to the peer's port 80 from our port, established (the peer's MSS 1460)."
	| c |
	c := self connection.
	self segment.
	self inject: (self segmentFrom: 80 to: self port seq: peerIss ack: 1001 flags: 16r12 window: 65535 data: #[] options: #[2 4 16r05 16rB4]).
	self tick: 0.
	self assert: c state equals: #established.
	self segment.
	^c
!
connection
	"A connection from our port to the peer's port 80, its SYN sent (sequence number 1000)."
	| c |
	c := TcpConnection on: stack to: self peer port: 80 from: self port.
	stack addConnection: c.
	c openIss: 1000; output.
	^c
!
read: c
	| buf n |
	buf := ByteArray new: 70000.
	n := c readInto: buf start: 1 count: buf size.
	n <= 0 ifTrue: [^n].
	^buf copyFrom: 1 to: n
!
write: aByteArray to: c
	^c write: aByteArray start: 1 count: aByteArray size
! !

!NetworkStackTest methodsFor: 'tests: IP'!
testChecksum
	"RFC 1071's example; odd lengths and offsets against the plain sum."
	| b |
	self assert: (#[16r00 16r01 16rF2 16r03 16rF4 16rF5 16rF6 16rF7] internetSumFrom: 1 count: 8) equals: 16rDDF2.
	self assert: (#[16r45 0 0 16r73 0 0 16r40 0 16r40 16r11 16rB8 16r61 16rC0 16rA8 0 1 16rC0 16rA8 0 16rC7] internetSumFrom: 1 count: 20) equals: 16rFFFF.
	b := ((1 to: 1503) collect: [:i | i * 7 \\ 256]) asByteArray.
	#(1 2 3 4 5 6 7 8 9 10) do: [:start |
		#(0 1 2 3 7 1460 1491) do: [:n |
			self assert: (b internetSumFrom: start count: n) equals: (self sum: (b copyFrom: start to: start + n - 1))]]
!
testAddressesAndSequenceNumbers
	| c |
	self assert: (NetworkStack addressFrom: '10.0.2.15') equals: self us.
	self assert: (NetworkStack addressFrom: '10.0.2') isNil.
	self assert: (NetworkStack addressFrom: '10.0.2.256') isNil.
	self assert: (NetworkStack addressFrom: 'example.com') isNil.
	self assert: (NetworkStack dotted: self us) equals: '10.0.2.15'.
	c := TcpConnection new.
	self assert: (c seq: 16rFFFFFFF0 lt: 16r10).
	self deny: (c seq: 16r10 lt: 16rFFFFFFF0).
	self assert: (c seq: 16r10 gt: 16rFFFFFFF0).
	self assert: (c seq: 5 le: 5).
	self assert: (c seq: 16r7FFFFFFF gt: 0).
	self assert: (c seq: 16r80000001 lt: 0).
	self assert: (c seq: 16rFFFFFFFF plus: 2) equals: 1.
	self assert: (c seq: 1 minus: 16rFFFFFFFF) equals: 2
!
testArp
	"A request for us is answered; a packet for an address not known yet waits for ARP's answer, then goes."
	| reply c |
	self bind.
	self inject: (self arp: 1 from: #[2 0 0 0 0 9] ip: 16r0A000209 to: #[0 0 0 0 0 0] ip: self us).
	self tick: 0.
	reply := self sent first.
	self assert: (reply copyFrom: 1 to: 6) equals: #[2 0 0 0 0 9].
	self assert: (reply netUint16At: 21) equals: 2.
	self assert: (reply copyFrom: 23 to: 28) equals: stack macAddress.
	self assert: (reply netUint32At: 29) equals: self us.
	c := TcpConnection on: stack to: 16r0A000207 port: 80 from: self port.
	stack addConnection: c.
	c open.
	self assert: (self sent collect: [:f | f netUint16At: 13]) asArray equals: #(16r0806).
	self tick: 1001.
	self assert: ((self sent select: [:f | (f netUint16At: 13) = 16r0806]) size) equals: 1.
	self inject: (self arp: 2 from: #[2 0 0 0 0 7] ip: 16r0A000207 to: stack macAddress ip: self us).
	self tick: 0.
	reply := self sent.
	self assert: reply size equals: 1.
	self assert: (reply first copyFrom: 1 to: 6) equals: #[2 0 0 0 0 7].
	self assert: ((self tcpOf: reply first) at: #flags) equals: 2
!
testPing
	| echo reply icmp |
	self bind.
	echo := #[8 0 0 0 16r12 16r34 0 1] , 'ping payload' asByteArray.
	echo netUint16At: 3 put: ((self sum: echo) bitXor: 16rFFFF).
	self inject: (self ip: 1 from: self peer to: self us payload: echo).
	self tick: 0.
	reply := self ipOf: self sent first.
	self assert: (reply at: 10) equals: 1.
	self assert: (reply netUint32At: 17) equals: self peer.
	icmp := reply copyFrom: 21 to: reply size.
	self assert: (icmp at: 1) equals: 0.
	self assert: (self sum: icmp) equals: 16rFFFF.
	self assert: (icmp copyFrom: 5 to: icmp size) equals: (echo copyFrom: 5 to: echo size)
!
testLoopback
	"127.0.0.1 and our own address loop back: a connection to ourselves, without a wire."
	| l c s |
	self bind.
	l := TcpConnection listenerOn: stack port: 7341 backlog: 2.
	stack addConnection: l.
	{16r7F000001. self us} do: [:address |
		c := TcpConnection on: stack to: address port: 7341 from: stack freePort.
		stack addConnection: c.
		c open.
		self tick: 0.
		self assert: c state equals: #established.
		s := l accept.
		self assert: s state equals: #established.
		self assert: s remoteIp equals: (address = self us ifTrue: [self us] ifFalse: [16r7F000001]).
		self write: 'hello' asByteArray to: c.
		self tick: 0.
		self assert: (self read: s) equals: 'hello' asByteArray].
	self assert: self sent isEmpty
! !

!NetworkStackTest methodsFor: 'tests: DHCP and DNS'!
testDhcp
	"DISCOVER, OFFER, REQUEST (for the offer, from its server), ACK: bound, a gratuitous ARP; renewal at T1, by unicast."
	| discover xid request options dhcp |
	stack startDhcp.
	discover := self ipOf: self sent last.
	self assert: (discover netUint32At: 17) equals: 16rFFFFFFFF.
	xid := discover netUint32At: 33.
	self assert: (discover copyFrom: 28 + 241 to: 28 + 243) equals: #[53 1 1].
	options := #[53 1 2 54 4 10 0 2 2 1 4 255 255 255 0 3 4 10 0 2 2 6 8 10 0 2 3 8 8 8 8 51 4 0 0 16r0E 16r10 255].
	self inject: (self dhcpReply: xid options: options).
	self tick: 0.
	request := self ipOf: self sent last.
	dhcp := request copyFrom: 29 to: request size.
	self assert: (dhcp copyFrom: 241 to: 243) equals: #[53 1 3].
	self assert: (dhcp indexOfSubCollection: #[50 4 10 0 2 15]) > 0.
	self assert: (dhcp indexOfSubCollection: #[54 4 10 0 2 2]) > 0.
	self inject: (self dhcpReply: xid options: (options copy at: 3 put: 5; yourself)).
	self tick: 0.
	self assert: stack address equals: self us.
	self assert: stack gateway equals: self peer.
	self assert: stack nameServers asArray equals: {self nameServer. 16r08080808}.
	self assert: ((self sent collect: [:f | f netUint16At: 13]) includes: 16r0806).
	self assert: stack dhcp state equals: #bound.
	"T1: half of the hour"
	self tick: 1800 * 1000.
	self inject: (self arp: 2 from: self peerMac ip: self peer to: stack macAddress ip: self us).
	self tick: 0.
	request := self ipOf: (self sent detect: [:f | (self ipOf: f) notNil]).
	self assert: (request netUint32At: 17) equals: self peer.
	self assert: (request netUint32At: 28 + 13) equals: self us.
	self assert: stack dhcp state equals: #renewing
!
dhcpReply: xid options: options
	| b udp |
	b := ByteArray new: 240.
	b at: 1 put: 2; at: 2 put: 1; at: 3 put: 6.
	b netUint32At: 5 put: xid.
	b netUint32At: 17 put: self us.
	b replaceFrom: 29 to: 34 with: stack macAddress startingAt: 1.
	b netUint32At: 237 put: 16r63825363.
	b := b , options.
	udp := ByteArray new: 8.
	udp netUint16At: 1 put: 67.
	udp netUint16At: 3 put: 68.
	udp netUint16At: 5 put: 8 + b size.
	^self ip: 17 from: self peer to: 16rFFFFFFFF payload: udp , b
!
testDns
	"A query to the server; an answer through a CNAME with two addresses; NXDOMAIN; no answer at all; a dotted address; localhost."
	| l q udp |
	self bind.
	l := stack resolver lookup: 'www.example.com'.
	self deny: l isDone.
	q := self ipOf: self sent last.
	self assert: (q netUint32At: 17) equals: self nameServer.
	udp := q copyFrom: 21 to: q size.
	self assert: (udp netUint16At: 3) equals: 53.
	self assert: (udp copyFrom: 21 to: udp size) equals: #[3] , 'www' asByteArray , #[7] , 'example' asByteArray , #[3] , 'com' asByteArray , #[0 0 1 0 1].
	self inject: (self dnsAnswer: udp rcode: 0 count: 3 answers: #[16rC0 12 0 5 0 1 0 0 0 60 0 6 3] , 'web' asByteArray , #[16rC0 16] ,
		#[16rC0 16r29 0 1 0 1 0 0 0 60 0 4 93 184 216 34] , #[16rC0 16r29 0 1 0 1 0 0 0 60 0 4 1 2 3 4]).
	self tick: 0.
	self assert: l text equals: '93.184.216.34
1.2.3.4
'.
	l := stack resolver lookup: 'nowhere.invalid'.
	q := self ipOf: self sent last.
	self inject: (self dnsAnswer: (q copyFrom: 21 to: q size) rcode: 3 count: 0 answers: #[]).
	self tick: 0.
	self assert: l text equals: '!!no such host
'.
	l := stack resolver lookup: 'slow.example'.
	20 timesRepeat: [self tick: 1000].
	self assert: l text equals: '!!DNS timed out
'.
	self assert: (self sent count: [:f | (self ipOf: f) notNil]) equals: 6.
	self assert: (stack resolver lookup: '10.1.2.3') text equals: '10.1.2.3
'.
	self assert: (stack resolver lookup: 'localhost') text equals: '127.0.0.1
'
!
dnsAnswer: query rcode: rcode count: n answers: answers
	"The server's answer to the UDP datagram query: its question, then the answer records."
	| m udp |
	m := query copyFrom: 9 to: query size.
	m at: 3 put: 16r81.
	m at: 4 put: 16r80 + rcode.
	m netUint16At: 7 put: n.
	m := m , answers.
	udp := ByteArray new: 8.
	udp netUint16At: 1 put: 53.
	udp netUint16At: 3 put: (query netUint16At: 1).
	udp netUint16At: 5 put: 8 + m size.
	^self ip: 17 from: self nameServer to: self us payload: udp , m
! !

!NetworkStackTest methodsFor: 'tests: TCP'!
testResetForAClosedPort
	| rst |
	self bind.
	self inject: (self segmentFrom: 1234 to: 81 seq: 5000 ack: 0 flags: 2 window: 1000 data: #[] options: #[]).
	self tick: 0.
	rst := self segment.
	self assert: (rst at: #flags) equals: 16r14.
	self assert: (rst at: #seq) equals: 0.
	self assert: (rst at: #ack) equals: 5001.
	self inject: (self segmentFrom: 1234 to: 81 seq: 5000 ack: 0 flags: 4 window: 1000 data: #[] options: #[]).
	self tick: 0.
	self noSegments
!
testActiveOpenAndPassiveClose
	"SYN with our MSS, SYN-ACK, ACK; data both ways; the peer's FIN (CLOSE_WAIT, the end); our FIN (LAST_ACK); its ACK: closed and gone."
	| c syn s |
	self bind.
	c := self connection.
	syn := self segment.
	self assert: (syn at: #flags) equals: 2.
	self assert: (syn at: #seq) equals: 1000.
	self assert: (syn at: #mss) equals: 1460.
	self assert: c isConnected isNil.
	self send: 16r12 seq: 7000 ack: 1001 data: #[] window: 8192.
	self assert: c isConnected.
	s := self segment.
	self assert: (s at: #flags) equals: 16r10.
	self assert: (s at: #ack) equals: 7001.
	self assert: (self write: 'GET /' asByteArray to: c) equals: 5.
	s := self segment.
	self assert: (s at: #data) equals: 'GET /' asByteArray.
	self assert: (s at: #flags) equals: 16r18.
	self send: 16r18 seq: 7001 ack: 1006 data: 'hello' asByteArray window: 8192.
	self assert: (self read: c) equals: 'hello' asByteArray.
	self assert: (self read: c) equals: -1.
	self send: 16r11 seq: 7006 ack: 1006.
	self assert: c state equals: #closeWait.
	self assert: (self read: c) equals: 0.
	self assert: (self segment at: #ack) equals: 7007.
	c close.
	s := self segment.
	self assert: (s at: #flags) equals: 16r11.
	self assert: c state equals: #lastAck.
	self send: 16r10 seq: 7007 ack: 1007.
	self assert: stack connections isEmpty
!
testPassiveOpenBacklogAndActiveClose
	"listen with a backlog of 1: one SYN-ACK, a second SYN dropped; accept; our FIN first: FIN_WAIT_1, _2, TIME_WAIT, then gone."
	| l s c |
	self bind.
	l := TcpConnection listenerOn: stack port: 7341 backlog: 1.
	stack addConnection: l.
	self inject: (self segmentFrom: 40000 to: 7341 seq: 9000 ack: 0 flags: 2 window: 30000 data: #[] options: #[2 4 16r05 16rB4]).
	self tick: 0.
	s := self segment.
	self assert: (s at: #flags) equals: 16r12.
	self assert: (s at: #ack) equals: 9001.
	"a retransmitted SYN: the SYN-ACK again"
	self inject: (self segmentFrom: 40000 to: 7341 seq: 9000 ack: 0 flags: 2 window: 30000 data: #[] options: #[2 4 16r05 16rB4]).
	self tick: 0.
	self assert: (self segment at: #seq) equals: (s at: #seq).
	self inject: (self segmentFrom: 40001 to: 7341 seq: 3000 ack: 0 flags: 2 window: 30000 data: #[] options: #[]).
	self tick: 0.
	self noSegments.
	self assert: l accept isNil.
	self inject: (self segmentFrom: 40000 to: 7341 seq: 9001 ack: (s at: #seq) + 1 flags: 16r10 window: 30000 data: #[] options: #[]).
	self tick: 0.
	self assert: l isReadable.
	c := l accept.
	self assert: c state equals: #established.
	self assert: c mss equals: 1460.
	self deny: l isReadable.
	c close.
	self assert: (self segment at: #flags) equals: 16r11.
	self assert: c state equals: #finWait1.
	self inject: (self segmentFrom: 40000 to: 7341 seq: 9001 ack: (s at: #seq) + 2 flags: 16r10 window: 30000 data: #[] options: #[]).
	self tick: 0.
	self assert: c state equals: #finWait2.
	self inject: (self segmentFrom: 40000 to: 7341 seq: 9001 ack: (s at: #seq) + 2 flags: 16r11 window: 30000 data: #[] options: #[]).
	self tick: 0.
	self assert: c state equals: #timeWait.
	self assert: (self segment at: #ack) equals: 9002.
	self tick: 2001.
	self assert: stack connections asArray equals: {l}
!
testOutOfOrderDataWaitsForTheGap
	| c |
	self bind.
	c := self connectWithIss: 100.
	self send: 16r10 seq: 106 ack: 1001 data: 'world' asByteArray window: 65535.
	self assert: (self segment at: #ack) equals: 101.
	self assert: (self read: c) equals: -1.
	self send: 16r10 seq: 111 ack: 1001 data: '!!' asByteArray window: 65535.
	self assert: (self segment at: #ack) equals: 101.
	self send: 16r10 seq: 101 ack: 1001 data: 'hello' asByteArray window: 65535.
	self assert: (self segment at: #ack) equals: 112.
	self assert: (self read: c) equals: 'helloworld!!' asByteArray.
	"old data again: acknowledged, not received twice"
	self send: 16r10 seq: 101 ack: 1001 data: 'hello' asByteArray window: 65535.
	self assert: (self segment at: #ack) equals: 112.
	self assert: (self read: c) equals: -1
!
testSequenceNumbersWrapAround
	| c s data |
	self bind.
	c := TcpConnection on: stack to: self peer port: 80 from: self port.
	stack addConnection: c.
	c openIss: 16rFFFFFF00; output.
	self segment.
	self send: 16r12 seq: 16rFFFFFFF0 ack: 16rFFFFFF01 data: #[] window: 65535.
	self segment.
	data := ((1 to: 300) collect: [:i | i \\ 256]) asByteArray.
	self assert: (self write: data to: c) equals: 300.
	s := self segment.
	self assert: (s at: #seq) equals: 16rFFFFFF01.
	self send: 16r10 seq: 16rFFFFFFF1 ack: 16r2D data: (data copyFrom: 1 to: 100) window: 65535.
	self assert: c sndUna equals: 16r2D.
	self assert: c sndLen equals: 0.
	self assert: (self read: c) equals: (data copyFrom: 1 to: 100).
	self tick: 50.
	self assert: (self segment at: #ack) equals: 16r55
!
testZeroWindowIsProbed
	| c s |
	self bind.
	c := self connectWithIss: 100.
	self send: 16r10 seq: 101 ack: 1001 data: #[] window: 0.
	self assert: (self write: #[1 2 3] to: c) equals: 3.
	self noSegments.
	self tick: c rto + 1.
	s := self segment.
	self assert: (s at: #seq) equals: 1000.
	self assert: (s at: #data) isEmpty.
	self send: 16r10 seq: 101 ack: 1001 data: #[] window: 0.
	self tick: c rto + 1.
	self noSegments.
	self tick: c rto.
	self assert: (self segment at: #seq) equals: 1000.
	self send: 16r10 seq: 101 ack: 1001 data: #[] window: 1000.
	s := self segment.
	self assert: (s at: #data) equals: #[1 2 3].
	self assert: (s at: #seq) equals: 1001
!
testOurWindowClosesAndOpens
	"Data nobody reads fills the 64 KB buffer: the window offered shrinks to 0; a probe with a byte is answered, the byte not taken; reading opens the window at once."
	| c seq s rest |
	self bind.
	c := self connectWithIss: 100.
	seq := 101.
	[seq - 101 + 1460 <= 65535] whileTrue: [
		self send: 16r10 seq: seq ack: 1001 data: (ByteArray new: 1460 withAll: 3) window: 65535.
		seq := seq + 1460].
	rest := 65535 - (seq - 101).
	self send: 16r10 seq: seq ack: 1001 data: (ByteArray new: rest withAll: 4) window: 65535.
	seq := seq + rest.
	self tick: 40.
	s := self segments last.
	self assert: (s at: #ack) equals: seq.
	self assert: (s at: #window) equals: 0.
	self send: 16r10 seq: seq ack: 1001 data: #[9] window: 65535.
	s := self segment.
	self assert: (s at: #ack) equals: seq.
	self assert: (s at: #window) equals: 0.
	self assert: (self read: c) size equals: 65535.
	s := self segment.
	self assert: (s at: #ack) equals: seq.
	self assert: (s at: #window) equals: 65535
!
testRetransmissionBacksOff
	"The RTO from the SYN's RTT (at least 200 ms), doubled at each timeout; go back to the first byte not acknowledged; failure after 10."
	| c s |
	self bind.
	c := self connectWithIss: 100.
	self assert: c rto equals: 200.
	self write: (ByteArray new: 100 withAll: 7) to: c.
	self segment.
	self tick: 199.
	self noSegments.
	self tick: 1.
	s := self segment.
	self assert: (s at: #seq) equals: 1001.
	self assert: (s at: #data) size equals: 100.
	self assert: c rto equals: 400.
	self assert: c cwnd equals: c mss.
	self tick: 400.
	self assert: self segments size equals: 1.
	self assert: c rto equals: 800.
	20 timesRepeat: [self tick: 60000].
	self assert: c state equals: #closed.
	self assert: (self read: c) equals: -2.
	self assert: c failureText equals: 'connection timed out'
!
testFastRetransmit
	"Four segments out; three duplicate ACKs: the first again at once, the window halved and inflated."
	| c s |
	self bind.
	c := self connectWithIss: 100.
	c cwnd: 10 * 1460.
	self write: (ByteArray new: 4 * 1460 withAll: 1) to: c.
	self assert: self segments size equals: 4.
	self send: 16r10 seq: 101 ack: 1001 + 1460 data: #[] window: 65535.
	self noSegments.
	3 timesRepeat: [self send: 16r10 seq: 101 ack: 1001 + 1460 data: #[] window: 65535].
	s := self segment.
	self assert: (s at: #seq) equals: 1001 + 1460.
	self assert: c inRecovery.
	self assert: c ssthresh equals: 2 * 1460.
	self send: 16r10 seq: 101 ack: 1001 + (4 * 1460) data: #[] window: 65535.
	self deny: c inRecovery.
	self assert: c cwnd equals: 2 * 1460.
	self assert: (stack counters at: #fastRetransmits) equals: 1
!
testResetOnlyAtTheExactSequenceNumber
	| c |
	self bind.
	c := self connectWithIss: 100.
	self send: 4 seq: 150 ack: 0.
	self assert: c state equals: #established.
	self assert: (self segment at: #ack) equals: 101.
	self send: 4 seq: 101 ack: 0.
	self assert: c state equals: #closed.
	self assert: (self read: c) equals: -2.
	self assert: c failureText equals: 'connection reset by peer'
!
testRefused
	| c |
	self bind.
	c := self connection.
	self segment.
	self send: 16r14 seq: 0 ack: 1001.
	self assert: c isConnected equals: false.
	self assert: c failureText equals: 'connection refused'
!
testSynWaitsForAnAddress
	"connect before DHCP has answered: the SYN goes when the address comes."
	| c |
	c := TcpConnection on: stack to: self peer port: 80 from: self port.
	stack addConnection: c.
	c open.
	self tick: 3000.
	self noSegments.
	self assert: c retries equals: 0.
	stack bind: self us mask: 16rFFFFFF00 gateway: self peer.
	self inject: (self arp: 2 from: self peerMac ip: self peer to: stack macAddress ip: self us).
	self tick: 0.
	self assert: (self segments anySatisfy: [:s | (s at: #flags) = 2])
! !

!NetworkStackTest methodsFor: 'tests: two stacks'!
testTwoStacksOverALossyWire
	"Two stacks, every 9th frame lost each way, some reordered: 300 KB each way, intact; both close and are gone."
	| pair a b l ca cb dataA dataB sentA sentB gotA gotB k n closedA closedB step w buf |
	pair := VirtualNetworkInterface wire: #[2 0 0 0 0 1] to: #[2 0 0 0 0 2].
	a := NetworkStack on: pair first.
	b := NetworkStack on: pair last.
	a clock: [t].
	b clock: [t].
	a bind: 16r0A000001 mask: 16rFFFFFF00 gateway: 0.
	b bind: 16r0A000002 mask: 16rFFFFFF00 gateway: 0.
	k := n := 0.
	pair first drop: [:f | (k := k + 1) \\ 9 = 0].
	pair last drop: [:f | (n := n + 1) \\ 9 = 4].
	l := TcpConnection listenerOn: b port: 80 backlog: 4.
	b addConnection: l.
	ca := TcpConnection on: a to: 16r0A000002 port: 80 from: a freePort.
	a addConnection: ca.
	ca open.
	dataA := ((1 to: 300000) collect: [:i | i * 31 \\ 256]) asByteArray.
	dataB := ((1 to: 300000) collect: [:i | i * 17 \\ 251]) asByteArray.
	sentA := sentB := 0.
	gotA := WriteStream on: (ByteArray new: dataB size).
	gotB := WriteStream on: (ByteArray new: dataA size).
	buf := ByteArray new: 70000.
	closedA := closedB := false.
	step := 0.
	[step < 40000 and: [(closedA and: [closedB and: [a connections isEmpty and: [b connections asArray = {l}]]]) not]] whileTrue: [
		step := step + 1.
		{pair first inbox. pair last inbox} do: [:inbox |
			(inbox size >= 2 and: [(inbox first size + step) \\ 5 = 0]) ifTrue: [inbox addLast: inbox removeFirst]].
		t := t + 1.
		a poll.
		b poll.
		cb isNil ifTrue: [cb := l accept].
		closedA ifFalse: [
			sentA < dataA size ifTrue: [
				w := ca write: dataA start: sentA + 1 count: (20000 min: dataA size - sentA).
				w > 0 ifTrue: [sentA := sentA + w]].
			[(w := ca readInto: buf start: 1 count: buf size) > 0] whileTrue: [gotA nextPutAll: (buf copyFrom: 1 to: w)].
			(sentA = dataA size and: [gotA size = dataB size]) ifTrue: [
				ca close.
				closedA := true]].
		(cb notNil and: [closedB not]) ifTrue: [
			sentB < dataB size ifTrue: [
				w := cb write: dataB start: sentB + 1 count: (20000 min: dataB size - sentB).
				w > 0 ifTrue: [sentB := sentB + w]].
			[(w := cb readInto: buf start: 1 count: buf size) > 0] whileTrue: [gotB nextPutAll: (buf copyFrom: 1 to: w)].
			(sentB = dataB size and: [gotB size = dataA size]) ifTrue: [
				cb close.
				closedB := true]]].
	self assert: gotB contents = dataA.
	self assert: gotA contents = dataB.
	self assert: closedA & closedB.
	self assert: a connections isEmpty.
	self assert: b connections asArray equals: {l}.
	self assert: (a counters at: #retransmits) > 0.
	Transcript show: 'two stacks: ', t printString, ' ms of the test''s time; counters ', a counters printString; cr
!
running: aStack
	"aStack, its Processes running (stopped after the test)."
	stacks add: aStack.
	^aStack start; yourself
!
testRemoteSocketsBetweenTwoRunningStacks
	"RemoteSocket on two stacks in their own Processes: listen on one, connect from the other, 1 MB each way, close."
	| pair a b server client accepted data got buf n reader |
	pair := VirtualNetworkInterface wire: #[2 0 0 0 0 1] to: #[2 0 0 0 0 2].
	a := NetworkStack on: pair first.
	b := NetworkStack on: pair last.
	a bind: 16r0A000001 mask: 16rFFFFFF00 gateway: 0.
	b bind: 16r0A000002 mask: 16rFFFFFF00 gateway: 0.
	self running: a; running: b.
	NetworkStack active: a.
	server := RemoteSocket listenOn: 0 host: '0.0.0.0' backlog: 2.
	self assert: server handle < 0.
	NetworkStack active: b.
	client := RemoteSocket connectTo: '10.0.0.1' port: server localPort timeout: 5000.
	accepted := server accept.
	data := ((1 to: 1000000) collect: [:i | i * 13 \\ 256]) asByteArray.
	got := WriteStream on: (ByteArray new: data size).
	reader := self fork: [
		buf := ByteArray new: 65536.
		[(n := accepted receiveInto: buf timeout: 5000) notNil and: [n > 0]] whileTrue: [got nextPutAll: (buf copyFrom: 1 to: n)].
		accepted sendAll: got contents reverse.
		accepted close].
	self assert: (client sendAll: data).
	self assert: (self waitFor: [got size = data size] timeout: 30000).
	client close.
	self assert: got contents = data.
	self assert: (self waitFor: [accepted isOpen not]).
	server close.
	self assert: (self waitFor: [a connections isEmpty and: [b connections isEmpty]] timeout: 10000)
! !

HTTPClientTest subclass: #HTTPClientOverNetworkStackTest
	instanceVariableNames: 'stack'
	classVariableNames: ''
	package: 'Tests-Network'!

HTTPClientOverNetworkStackTest comment: 'HTTPClientTest with RemoteSocket over the image''s TCP/IP stack (NetworkStack active), on 127.0.0.1: what the image has on UEFI. No TLS over it.'!

!HTTPClientOverNetworkStackTest methodsFor: 'running'!
setUp
	stack := NetworkStack on: (VirtualNetworkInterface mac: #[2 0 0 0 0 1]).
	stack start.
	NetworkStack active: stack.
	super setUp
!
tearDown
	super tearDown.
	NetworkStack active: nil.
	stack stop
! !

!HTTPClientOverNetworkStackTest methodsFor: 'tests'!
testCancelByCloseWhileConnecting
	"Over HTTPS, which the image's stack does not have: the connect fails at once."
	| outcome |
	self serve: [:request | nil].
	outcome := [client get: 'https://127.0.0.1:', (server url copyAfterLast: $:), '/' headers: nil. #completed]
		on: HTTPError do: [:e | e return: e messageText].
	self deny: outcome = #completed
! !

ControlServerTest subclass: #ControlServerOverNetworkStackTest
	instanceVariableNames: 'stack'
	classVariableNames: ''
	package: 'Tests-Network'!

ControlServerOverNetworkStackTest comment: 'ControlServerTest with RemoteSocket over the image''s TCP/IP stack (NetworkStack active), on 127.0.0.1.'!

!ControlServerOverNetworkStackTest methodsFor: 'running'!
setUp
	stack := NetworkStack on: (VirtualNetworkInterface mac: #[2 0 0 0 0 1]).
	stack start.
	NetworkStack active: stack.
	super setUp
!
tearDown
	super tearDown.
	NetworkStack active: nil.
	stack stop
! !

RemoteSocketConnectTest subclass: #RemoteSocketOverNetworkStackTest
	instanceVariableNames: 'stack'
	classVariableNames: ''
	package: 'Tests-Network'!

RemoteSocketOverNetworkStackTest comment: 'RemoteSocketConnectTest with RemoteSocket over the image''s TCP/IP stack (NetworkStack active), on 127.0.0.1; a stack without DHCP fails a lookup of a name at once.'!

!RemoteSocketOverNetworkStackTest methodsFor: 'running'!
setUp
	stack := NetworkStack on: (VirtualNetworkInterface mac: #[2 0 0 0 0 1]).
	stack start.
	NetworkStack active: stack
!
tearDown
	super tearDown.
	NetworkStack active: nil.
	stack stop
! !
