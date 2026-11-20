Object subclass: #TcpSegment
	instanceVariableNames: 'src dst srcPort dstPort seq ack flags window mss frame dataStart length'
	classVariableNames: ''
	package: 'System-Network'!

TcpSegment comment: 'A TCP segment received: its header fields (mss: its MSS option, nil if none), its data (length bytes of frame from dataStart), the addresses it came from and went to.'!

!TcpSegment class methodsFor: 'instance creation'!
frame: f at: start count: n from: src to: dst
	"The segment of n bytes in f from start; nil if its header is malformed."
	^self new setFrame: f at: start count: n from: src to: dst
! !

!TcpSegment methodsFor: 'initialization'!
setFrame: f at: start count: n from: source to: destination
	| hl i kind len |
	hl := ((f at: start + 12) bitShift: -4) * 4.
	(hl < 20 or: [hl > n]) ifTrue: [^nil].
	src := source.
	dst := destination.
	frame := f.
	srcPort := f netUint16At: start.
	dstPort := f netUint16At: start + 2.
	seq := f netUint32At: start + 4.
	ack := f netUint32At: start + 8.
	flags := (f at: start + 13) bitAnd: 16r3F.
	window := f netUint16At: start + 14.
	dataStart := start + hl.
	length := n - hl.
	i := 20.
	[i < hl] whileTrue: [
		kind := f at: start + i.
		kind = 0
			ifTrue: [i := hl]
			ifFalse: [
				kind = 1
					ifTrue: [i := i + 1]
					ifFalse: [
						len := i + 1 < hl ifTrue: [f at: start + i + 1] ifFalse: [0].
						(len < 2 or: [i + len > hl])
							ifTrue: [i := hl]
							ifFalse: [
								(kind = 2 and: [len = 4]) ifTrue: [mss := f netUint16At: start + i + 2].
								i := i + len]]]]
! !

!TcpSegment methodsFor: 'accessing'!
src
	^src
!
dst
	^dst
!
srcPort
	^srcPort
!
dstPort
	^dstPort
!
seq
	^seq
!
ack
	^ack
!
flags
	^flags
!
window
	^window
!
mss
	^mss
!
frame
	^frame
!
dataStart
	^dataStart
!
length
	^length
!
isSyn
	^(flags bitAnd: 2) ~= 0
!
isFin
	^(flags bitAnd: 1) ~= 0
!
isReset
	^(flags bitAnd: 4) ~= 0
!
hasAck
	^(flags bitAnd: 16) ~= 0
! !

Object subclass: #TcpConnection
	instanceVariableNames: 'stack state localIp localPort remoteIp remotePort parent acceptQueue backlog detached failure iss sndUna sndNxt sndMax sndWnd sndWl1 sndWl2 mss sndBuf sndHead sndLen sndSeq finQueued irs rcvNxt rcvAdv rcvBuf rcvHead rcvLen ooo finReceived cwnd ssthresh dupAcks recover inRecovery srtt rttvar rto timing rttSeq rttStart rtxAt retries persistAt persistBackoff ackAt unacked ackNow closeAt'
	classVariableNames: 'ACK BUFFER DEFAULT_MSS DELACK_MS FIN FIN_WAIT_MS MAX_WINDOW MSS OOO PSH RETRIES RST RTO_INITIAL RTO_MAX RTO_MIN SYN SYN_RETRIES TIME_WAIT_MS'
	package: 'System-Network'!

TcpConnection comment: 'A TCP connection of a NetworkStack (RFC 9293): its state (#listen, #synSent, #synReceived, #established, #finWait1, #finWait2, #closeWait, #closing, #lastAck, #timeWait, #closed), endpoints and sequence numbers (modulo 2^32: seq:lt: and its siblings), a send and a receive buffer of BUFFER bytes (rings). The window offered is the receive buffer''s free space (at most 64 KB: no window scaling), its right edge never moving left, nor right by less than an MSS (receiver SWS avoidance); segments are at most the MSS the peer announced (MSS ours). Out-of-order data within the window goes straight into the receive buffer where it belongs, OOO ranges of it remembered, until the gap fills.

Sending: as much as the smaller of the peer''s window and the congestion window allows (no Nagle). Retransmission: one timer, its RTO from the RTT as RFC 6298 estimates it (one segment timed at a time, none retransmitted: Karn), at least RTO_MIN, doubled at each timeout, which goes back to the first unacknowledged byte with a congestion window of one segment. Congestion control (RFC 5681): slow start, congestion avoidance, fast retransmit on the third duplicate ACK, NewReno recovery (RFC 6582: a partial ACK retransmits the next hole; nothing sent before a timeout starts one). A zero window is probed (a segment one byte to the left of it, which the peer answers with its window) at the RTO, backed off. ACKs are delayed DELACK_MS, but every second segment and anything out of order is acknowledged at once.

Opening: actively (open: a SYN retransmitted SYN_RETRIES times) or passively (a listener makes a #synReceived connection per SYN up to its backlog, queued on it once established until accepted). Closing (close) is graceful: the socket lets go of me (detached); I send what remains, then my FIN, and am done once #closed; #finWait2 lasts FIN_WAIT_MS at most, #timeWait TIME_WAIT_MS. A RST resets me only at exactly rcvNxt (RFC 5961; else it is answered with an ACK). After RETRIES timeouts I fail. failure: why I failed (#refused, #reset, #timedOut, #unreachable) or nil.'!

!TcpConnection class methodsFor: 'class initialization'!
initialize
	FIN := 1.
	SYN := 2.
	RST := 4.
	PSH := 8.
	ACK := 16.
	BUFFER := 65536.
	MAX_WINDOW := 65535.
	MSS := 1460.
	DEFAULT_MSS := 536.
	OOO := 4.
	RTO_INITIAL := 1000.
	RTO_MIN := 200.
	RTO_MAX := 60000.
	DELACK_MS := 40.
	SYN_RETRIES := 6.
	RETRIES := 10.
	FIN_WAIT_MS := 60000.
	TIME_WAIT_MS := 2000
!
rst
	^RST
!
ack
	^ACK
! !

!TcpConnection class methodsFor: 'instance creation'!
on: aStack to: anAddress port: aPort from: aLocalPort
	"A connection to be opened (open)."
	^self new setStack: aStack state: #synSent; setRemote: anAddress port: aPort local: (aStack sourceFor: anAddress) port: aLocalPort
!
listenerOn: aStack port: aPort backlog: anInteger
	^self new setStack: aStack state: #listen; setListening: aPort backlog: anInteger
! !

!TcpConnection methodsFor: 'initialization'!
setStack: aStack state: aSymbol
	stack := aStack.
	state := aSymbol.
	detached := false.
	mss := DEFAULT_MSS.
	rto := RTO_INITIAL.
	cwnd := DEFAULT_MSS.
	ssthresh := 16r3FFFFFFF.
	dupAcks := 0.
	inRecovery := false.
	timing := false.
	retries := 0.
	persistBackoff := 0.
	unacked := 0.
	ackNow := false.
	finQueued := false.
	finReceived := false.
	rtxAt := persistAt := ackAt := closeAt := nil.
	sndWnd := sndWl1 := sndWl2 := 0.
	irs := rcvNxt := rcvAdv := 0.
	ooo := OrderedCollection new.
	aSymbol == #listen ifFalse: [
		sndBuf := ByteArray new: BUFFER.
		rcvBuf := ByteArray new: BUFFER.
		sndHead := sndLen := rcvHead := rcvLen := 0]
!
setRemote: anAddress port: aPort local: aLocalAddress port: aLocalPort
	remoteIp := anAddress.
	remotePort := aPort.
	localIp := aLocalAddress.
	localPort := aLocalPort
!
setListening: aPort backlog: anInteger
	localPort := aPort.
	backlog := anInteger max: 1.
	acceptQueue := OrderedCollection new
!
openIss: anInteger
	iss := sndUna := sndNxt := sndMax := recover := anInteger.
	sndSeq := self seq: anInteger plus: 1
!
open
	"Send the SYN (or as soon as there is an address)."
	self openIss: stack initialSequence.
	self output
! !

!TcpConnection methodsFor: 'sequence numbers'!
seq: a lt: b
	^(a - b bitAnd: 16rFFFFFFFF) >= 16r80000000
!
seq: a le: b
	^a = b or: [self seq: a lt: b]
!
seq: a gt: b
	^self seq: b lt: a
!
seq: a ge: b
	^a = b or: [self seq: b lt: a]
!
seq: a plus: n
	^a + n bitAnd: 16rFFFFFFFF
!
seq: a minus: b
	"The distance from b up to a."
	^a - b bitAnd: 16rFFFFFFFF
! !

!TcpConnection methodsFor: 'accessing'!
state
	^state
!
localIp
	^localIp
!
localPort
	^localPort
!
localPort: aPort
	localPort := aPort
!
remoteIp
	^remoteIp
!
remotePort
	^remotePort
!
parent
	^parent
!
failure
	^failure
!
mss
	^mss
!
rto
	^rto
!
cwnd
	^cwnd
!
cwnd: anInteger
	cwnd := anInteger
!
ssthresh
	^ssthresh
!
inRecovery
	^inRecovery
!
retries
	^retries
!
sndUna
	^sndUna
!
sndLen
	^sndLen
!
isListening
	^state == #listen
!
isClosed
	^state == #closed
!
isSynSent
	^state == #synSent
!
isDone
	"Closed, and nobody's: no socket holds me, nor a listener's queue."
	^state == #closed and: [detached or: [parent notNil]]
!
failureText
	failure == #refused ifTrue: [^'connection refused'].
	failure == #reset ifTrue: [^'connection reset by peer'].
	failure == #timedOut ifTrue: [^'connection timed out'].
	failure == #unreachable ifTrue: [^'host or port unreachable'].
	^'connection closed'
!
printOn: aStream
	aStream nextPutAll: 'a TcpConnection ('; print: state; nextPutAll: ' :'; print: localPort.
	remoteIp isNil ifFalse: [aStream nextPutAll: ' to '; nextPutAll: (NetworkStack dotted: remoteIp); nextPut: $:; print: remotePort].
	aStream nextPut: $)
! !

!TcpConnection methodsFor: 'states'!
established
	"Synchronized: the initial congestion window (RFC 5681); queued on my listener if I have one."
	state := #established.
	cwnd := mss > 2190 ifTrue: [2 * mss] ifFalse: [mss > 1095 ifTrue: [3 * mss] ifFalse: [4 * mss]].
	retries := 0.
	parent isNil ifFalse: [parent enqueue: self]
!
fail: aSymbol
	"CLOSED, failed for aSymbol (nil: just closed)."
	failure isNil ifTrue: [failure := aSymbol].
	state := #closed.
	self stopTimers.
	parent isNil ifFalse: [parent dequeue: self]
!
stopTimers
	rtxAt := persistAt := ackAt := closeAt := nil
!
abort
	"Reset the peer (if synchronized), and close."
	(#(#listen #synSent #closed) includes: state) ifFalse: [self send: sndNxt flags: (RST bitOr: ACK) offset: 0 length: 0].
	state := #closed.
	self stopTimers
!
timeWait
	state := #timeWait.
	rtxAt := persistAt := nil.
	closeAt := stack now + TIME_WAIT_MS
!
addressCame
	"The stack has an address now: a SYN that waited for it goes."
	state == #synSent ifFalse: [^self].
	localIp = 0 ifTrue: [localIp := stack sourceFor: remoteIp].
	sndNxt := iss.
	rtxAt := nil.
	self output
! !

!TcpConnection methodsFor: 'listening'!
enqueue: aConnection
	acceptQueue addLast: aConnection
!
dequeue: aConnection
	acceptQueue isNil ifFalse: [acceptQueue remove: aConnection ifAbsent: []]
!
accept
	"The next connection established on me, or nil."
	| c |
	acceptQueue isEmpty ifTrue: [^nil].
	c := acceptQueue removeFirst.
	c orphan.
	^c
!
orphan
	parent := nil
!
pending
	"How many connections are being made on me or wait to be accepted."
	^stack connections count: [:each | each parent == self and: [each isClosed not]]
!
hasPending
	^acceptQueue notEmpty
! !

!TcpConnection methodsFor: 'sending'!
window
	"The window to offer: the receive buffer's free space, its right edge never moving left nor right by less than an MSS."
	| free right held |
	free := BUFFER - rcvLen min: MAX_WINDOW.
	right := self seq: rcvNxt plus: free.
	held := (self seq: rcvAdv gt: rcvNxt) ifTrue: [self seq: rcvAdv minus: rcvNxt] ifFalse: [0].
	((self seq: right le: rcvAdv) or: [(self seq: right minus: rcvAdv) < mss]) ifTrue: [^held].
	rcvAdv := right.
	^free
!
send: seq flags: flags offset: off length: len
	"A segment: flags, len bytes of the send buffer from off (bytes past its first), the MSS option on a SYN; the ACK of all received and our window if ACK."
	| hl f start first |
	hl := (flags bitAnd: SYN) ~= 0 ifTrue: [24] ifFalse: [20].
	f := stack newFrame: hl + len.
	f netUint16At: 35 put: localPort.
	f netUint16At: 37 put: remotePort.
	f netUint32At: 39 put: seq.
	f netUint32At: 43 put: ((flags bitAnd: ACK) ~= 0 ifTrue: [rcvNxt] ifFalse: [0]).
	f at: 47 put: hl * 4.
	f at: 48 put: flags.
	f netUint16At: 49 put: ((flags bitAnd: RST) ~= 0 ifTrue: [0] ifFalse: [self window]).
	hl = 24 ifTrue: [
		f at: 55 put: 2.
		f at: 56 put: 4.
		f netUint16At: 57 put: MSS].
	len > 0 ifTrue: [
		start := sndHead + off \\ BUFFER.
		first := BUFFER - start min: len.
		f replaceFrom: 35 + hl to: 34 + hl + first with: sndBuf startingAt: start + 1.
		len > first ifTrue: [f replaceFrom: 35 + hl + first to: 34 + hl + len with: sndBuf startingAt: 1]].
	f netUint16At: 51 put: ((stack sum: f at: 35 count: hl + len plus: (stack pseudo: localIp dst: remoteIp proto: 6 length: hl + len)) bitXor: 16rFFFF).
	(flags bitAnd: ACK) ~= 0 ifTrue: [
		ackAt := nil.
		unacked := 0.
		ackNow := false].
	stack count: #segmentsOut.
	stack sendIp: 6 from: localIp to: remoteIp frame: f length: hl + len
!
sendAck
	self send: sndNxt flags: ACK offset: 0 length: 0
!
canSend
	^#(#established #closeWait #finWait1 #closing #lastAck) includes: state
!
output
	"Send what I may: my SYN; then data from sndNxt, as the peer's window and the congestion window allow, and my FIN after the last byte. Answer whether anything went."
	| off avail flight wnd usable len fin flags sent more |
	(state == #synSent or: [state == #synReceived]) ifTrue: [
		sndNxt = iss ifFalse: [^false].
		(retries = 0 and: [timing not]) ifTrue: [
			timing := true.
			rttSeq := sndSeq.
			rttStart := stack now].
		self send: iss flags: (state == #synSent ifTrue: [SYN] ifFalse: [SYN bitOr: ACK]) offset: 0 length: 0.
		sndNxt := sndSeq.
		(self seq: sndNxt gt: sndMax) ifTrue: [sndMax := sndNxt].
		rtxAt isNil ifTrue: [rtxAt := stack now + rto].
		^true].
	self canSend ifFalse: [^false].
	sent := false.
	more := true.
	avail := 0.
	[more] whileTrue: [
		off := self seq: sndNxt minus: sndSeq.
		avail := off >= sndLen ifTrue: [0] ifFalse: [sndLen - off].
		flight := self seq: sndNxt minus: sndUna.
		wnd := sndWnd min: cwnd.
		usable := wnd > flight ifTrue: [wnd - flight] ifFalse: [0].
		len := (avail min: usable) min: mss.
		fin := finQueued and: [off <= sndLen and: [off + len = sndLen]].
		(len = 0 and: [fin not])
			ifTrue: [more := false]
			ifFalse: [
				flags := ACK.
				(len > 0 and: [off + len = sndLen]) ifTrue: [flags := flags bitOr: PSH].
				fin ifTrue: [flags := flags bitOr: FIN].
				(timing not and: [len > 0 and: [self seq: sndNxt ge: sndMax]]) ifTrue: [
					timing := true.
					rttSeq := self seq: sndNxt plus: len.
					rttStart := stack now].
				self send: sndNxt flags: flags offset: off length: len.
				sndNxt := self seq: sndNxt plus: len + (fin ifTrue: [1] ifFalse: [0]).
				(self seq: sndNxt gt: sndMax) ifTrue: [sndMax := sndNxt].
				rtxAt isNil ifTrue: [rtxAt := stack now + rto].
				sent := true]].
	"a zero window: probe it (nothing in flight that a timeout would send again)"
	(sndWnd = 0 and: [avail > 0 and: [sndNxt = sndUna and: [rtxAt isNil and: [persistAt isNil]]]]) ifTrue: [
		persistAt := stack now + rto].
	^sent
!
retransmitFirst
	"Send the first unacknowledged segment again (fast retransmit, a partial ACK)."
	| len fin |
	len := sndLen min: mss.
	fin := finQueued and: [len = sndLen and: [self seq: sndMax gt: (self seq: sndSeq plus: sndLen)]].
	(len = 0 and: [fin not]) ifTrue: [^self].
	timing := false.
	stack count: #retransmits.
	self send: sndUna flags: (fin ifTrue: [ACK bitOr: FIN] ifFalse: [ACK]) offset: 0 length: len
! !

!TcpConnection methodsFor: 'receiving'!
input: seg
	state == #listen ifTrue: [^self listenInput: seg].
	state == #synSent ifTrue: [^self synSentInput: seg].
	self process: seg
!
synchronize: seg
	"The peer's SYN: its initial sequence number, MSS and window."
	irs := seg seq.
	rcvNxt := rcvAdv := self seq: irs plus: 1.
	mss := ((seg mss ifNil: [DEFAULT_MSS]) min: MSS) max: 64.
	sndWnd := seg window.
	sndWl1 := seg seq.
	sndWl2 := seg ack
!
listenInput: seg
	"A SYN: a connection in #synReceived, its SYN-ACK sent; unless the backlog is full (the peer will try again)."
	| c |
	(seg isReset or: [seg isSyn not]) ifTrue: [^self].
	seg hasAck ifTrue: [^stack reset: seg].
	self pending >= backlog ifTrue: [^self].
	c := self class new setStack: stack state: #synReceived.
	c setRemote: seg src port: seg srcPort local: seg dst port: localPort.
	c setParent: self.
	stack addConnection: c.
	c synchronize: seg.
	c openIss: stack initialSequence.
	c output
!
setParent: aListener
	parent := aListener
!
synSentInput: seg
	"The answer to our SYN: a SYN-ACK (established), a SYN (simultaneous open), a RST (refused)."
	| ack |
	ack := seg hasAck.
	(ack and: [(self seq: seg ack le: iss) or: [self seq: seg ack gt: sndMax]]) ifTrue: [^stack reset: seg].
	seg isReset ifTrue: [
		ack ifTrue: [self fail: #refused].
		^self].
	seg isSyn ifFalse: [^self].
	self synchronize: seg.
	ack ifFalse: [
		state := #synReceived.
		sndNxt := iss.
		^self output].
	self newAck: seg ack.
	self established.
	self sendAck.
	self output
!
inWindow: x size: wnd
	^(self seq: x ge: rcvNxt) and: [self seq: x lt: (self seq: rcvNxt plus: wnd)]
!
process: seg
	"A segment for a synchronized connection (RFC 9293, 3.10.7.4)."
	| seq len start fin syn wnd segLen ok d |
	seq := seg seq.
	len := seg length.
	start := seg dataStart.
	fin := seg isFin.
	syn := seg isSyn.
	wnd := (self seq: rcvAdv gt: rcvNxt) ifTrue: [self seq: rcvAdv minus: rcvNxt] ifFalse: [0].
	(state == #synReceived and: [syn and: [seq = irs and: [(seg flags bitAnd: (ACK bitOr: RST)) = 0]]]) ifTrue: [
		"the peer did not hear our SYN-ACK"
		sndNxt := iss.
		^self output].
	"1. is it in the window?"
	segLen := len + (syn ifTrue: [1] ifFalse: [0]) + (fin ifTrue: [1] ifFalse: [0]).
	ok := segLen = 0
		ifTrue: [wnd = 0 ifTrue: [seq = rcvNxt] ifFalse: [self inWindow: seq size: wnd]]
		ifFalse: [wnd > 0 and: [(self inWindow: seq size: wnd) or: [self inWindow: (self seq: seq plus: segLen - 1) size: wnd]]].
	(ok not and: [wnd = 0 and: [seq = rcvNxt]]) ifTrue: [
		"a zero window takes no data (a probe: answered), but the ACK and RST"
		ok := true.
		len := 0.
		fin := syn := false.
		ackNow := true].
	ok ifFalse: [
		seg isReset ifFalse: [self sendAck].
		^self].
	"trim what was received already, and what is beyond the window"
	(self seq: seq lt: rcvNxt) ifTrue: [
		d := self seq: rcvNxt minus: seq.
		syn ifTrue: [
			syn := false.
			d := d - 1].
		d <= len
			ifTrue: [
				start := start + d.
				len := len - d]
			ifFalse: [
				len := 0.
				fin := false].
		seq := rcvNxt].
	(self seq: seq minus: rcvNxt) + len > wnd ifTrue: [
		len := wnd - (self seq: seq minus: rcvNxt).
		fin := false].
	"2. RST: only at exactly rcvNxt, else challenged (RFC 5961)"
	seg isReset ifTrue: [
		seg seq = rcvNxt ifFalse: [^self sendAck].
		^self fail: ((state == #synReceived and: [parent isNil]) ifTrue: [#refused] ifFalse: [#reset])].
	"4. a SYN in the window: challenged"
	syn ifTrue: [^self sendAck].
	"5. the ACK"
	seg hasAck ifFalse: [^self].
	state == #synReceived ifTrue: [
		((self seq: seg ack gt: sndUna) and: [self seq: seg ack le: sndMax]) ifFalse: [^stack reset: seg].
		self established.
		sndWnd := seg window.
		sndWl1 := seg seq.
		sndWl2 := seg ack].
	(self ack: seg) ifFalse: [^self sendAck].
	state == #closed ifTrue: [^self].
	"7. data"
	(len > 0 and: [#(#established #finWait1 #finWait2) includes: state]) ifTrue: [
		self receive: seg frame from: start length: len seq: seq].
	"8. FIN, if all before it is here"
	(fin and: [(self seq: seq plus: len) = rcvNxt]) ifTrue: [
		rcvNxt := self seq: rcvNxt plus: 1.
		finReceived := true.
		ackNow := true.
		(state == #established or: [state == #synReceived]) ifTrue: [state := #closeWait].
		state == #finWait1 ifTrue: [self finAcked ifTrue: [self timeWait] ifFalse: [state := #closing]].
		(state == #finWait2 or: [state == #timeWait]) ifTrue: [self timeWait]].
	self output.
	ackNow ifTrue: [^self sendAck].
	(unacked > 0 and: [ackAt isNil]) ifTrue: [ackAt := stack now + DELACK_MS]
!
finAcked
	^finQueued and: [sndUna = (self seq: sndSeq plus: sndLen + 1)]
!
ack: seg
	"The ACK of seg: duplicate, or new; the peer's window; our FIN acknowledged. False if it acknowledges what we did not send."
	| ack |
	ack := seg ack.
	(self seq: ack gt: sndMax) ifTrue: [^false].
	(self seq: ack le: sndUna)
		ifTrue: [
			(seg length = 0 and: [(seg flags bitAnd: (SYN bitOr: FIN)) = 0 and: [seg window = sndWnd and: [sndMax ~= sndUna and: [ack = sndUna]]]])
				ifTrue: [self duplicateAck]]
		ifFalse: [self newAck: ack].
	((self seq: sndWl1 lt: seg seq) or: [sndWl1 = seg seq and: [self seq: sndWl2 le: ack]]) ifTrue: [
		sndWnd := seg window.
		sndWl1 := seg seq.
		sndWl2 := ack.
		sndWnd > 0 ifTrue: [
			persistAt := nil.
			persistBackoff := 0]].
	self finAcked ifFalse: [^true].
	state == #finWait1 ifTrue: [
		state := #finWait2.
		closeAt := stack now + FIN_WAIT_MS].
	state == #closing ifTrue: [self timeWait].
	state == #lastAck ifTrue: [self fail: nil].
	^true
!
acknowledge: ack
	"Bytes up to ack are acknowledged: out of the send buffer."
	| d |
	(self seq: ack gt: sndSeq) ifTrue: [
		d := (self seq: ack minus: sndSeq) min: sndLen.
		sndHead := sndHead + d \\ BUFFER.
		sndLen := sndLen - d.
		sndSeq := self seq: sndSeq plus: d].
	sndUna := ack.
	(self seq: sndNxt lt: ack) ifTrue: [sndNxt := ack].
	(self seq: sndMax lt: ack) ifTrue: [sndMax := ack]
!
newAck: ack
	"An ACK of something new: an RTT sample, the congestion window, the retransmission timer."
	| acked |
	acked := self seq: ack minus: sndUna.
	(timing and: [self seq: ack ge: rttSeq]) ifTrue: [
		timing := false.
		self rttSample: stack now - rttStart].
	self acknowledge: ack.
	retries := 0.
	inRecovery
		ifTrue: [
			(self seq: ack ge: recover)
				ifTrue: [
					cwnd := ssthresh.
					inRecovery := false.
					dupAcks := 0]
				ifFalse: [
					self retransmitFirst.
					cwnd := (cwnd - acked max: 0) + mss]]
		ifFalse: [
			dupAcks := 0.
			cwnd := cwnd < ssthresh
				ifTrue: [cwnd + (acked min: mss)]
				ifFalse: [cwnd + (mss * mss // cwnd max: 1)]].
	cwnd := cwnd min: 16r100000.
	rtxAt := sndUna = sndMax ifTrue: [nil] ifFalse: [stack now + rto]
!
duplicateAck
	"A third duplicate ACK: retransmit, halve the congestion window, recover; more inflate it."
	dupAcks := dupAcks + 1.
	inRecovery ifTrue: [
		cwnd := cwnd + mss.
		^self].
	dupAcks = 3 ifFalse: [^self].
	"not for what was sent before a timeout (RFC 6582)"
	(self seq: sndUna gt: recover) ifFalse: [^self].
	ssthresh := (self seq: sndMax minus: sndUna) // 2 max: 2 * mss.
	recover := sndMax.
	inRecovery := true.
	stack count: #fastRetransmits.
	self retransmitFirst.
	cwnd := ssthresh + (3 * mss).
	rtxAt := stack now + rto
!
rttSample: milliseconds
	"RFC 6298: SRTT, RTTVAR (in microseconds), RTO = SRTT + 4 RTTVAR, between RTO_MIN and RTO_MAX ms."
	| r delta |
	r := (milliseconds max: 0) * 1000.
	srtt isNil
		ifTrue: [
			srtt := r.
			rttvar := r // 2]
		ifFalse: [
			delta := r - srtt.
			rttvar := rttvar + (delta abs - rttvar quo: 4).
			srtt := srtt + (delta quo: 8)].
	rto := ((srtt + (4 * rttvar max: 1000)) // 1000 max: RTO_MIN) min: RTO_MAX
!
receive: f from: start length: len seq: seq
	"Data in the window: at rcvNxt it is received (and what was out of order behind it); beyond, it waits in the buffer."
	| off filled |
	detached ifTrue: [
		"nobody reads it any more"
		seq = rcvNxt ifTrue: [rcvNxt := self seq: rcvNxt plus: len].
		ackNow := true.
		^self].
	off := self seq: seq minus: rcvNxt.
	self store: f from: start length: len at: rcvLen + off.
	off > 0 ifTrue: [
		self remember: seq to: (self seq: seq plus: len).
		ackNow := true.
		^self].
	filled := ooo notEmpty.
	rcvLen := rcvLen + len.
	rcvNxt := self seq: rcvNxt plus: len.
	self advance.
	(filled or: [unacked >= 1]) ifTrue: [ackNow := true] ifFalse: [unacked := unacked + 1]
!
store: f from: start length: len at: off
	"len bytes into the receive buffer, off bytes past its first unread one."
	| at first |
	at := rcvHead + off \\ BUFFER.
	first := BUFFER - at min: len.
	rcvBuf replaceFrom: at + 1 to: at + first with: f startingAt: start.
	len > first ifTrue: [rcvBuf replaceFrom: 1 to: len - first with: f startingAt: start + first]
!
remember: from to: to
	"Out-of-order data [from, to) is in the buffer: merged into the ranges kept (if there is no room for another, it is as if it never came)."
	| s e merged |
	s := from.
	e := to.
	merged := true.
	[merged] whileTrue: [
		merged := false.
		ooo copy do: [:r |
			((self seq: r first le: e) and: [self seq: s le: r last]) ifTrue: [
				(self seq: r first lt: s) ifTrue: [s := r first].
				(self seq: r last gt: e) ifTrue: [e := r last].
				ooo remove: r.
				merged := true]]].
	ooo size < OOO ifTrue: [ooo add: (Array with: s with: e)]
!
advance
	"rcvNxt moved: out-of-order ranges it reached are received too."
	| moved |
	moved := true.
	[moved] whileTrue: [
		moved := false.
		ooo copy do: [:r |
			(self seq: r first le: rcvNxt) ifTrue: [
				(self seq: r last gt: rcvNxt) ifTrue: [
					rcvLen := rcvLen + (self seq: r last minus: rcvNxt).
					rcvNxt := r last.
					moved := true].
				ooo remove: r]]]
! !

!TcpConnection methodsFor: 'timers'!
timers
	"Delayed ACK, retransmission, zero-window probe, TIME_WAIT and FIN_WAIT_2."
	| t |
	(state == #closed or: [state == #listen]) ifTrue: [^self].
	t := stack now.
	(ackAt notNil and: [t >= ackAt]) ifTrue: [self sendAck].
	(rtxAt notNil and: [t >= rtxAt]) ifTrue: [self timeout].
	(persistAt notNil and: [t >= persistAt]) ifTrue: [self probe].
	(closeAt notNil and: [t >= closeAt]) ifTrue: [self fail: nil]
!
timeout
	"Back off, go back to the first unacknowledged byte with a congestion window of one segment; fail after too many."
	| syn |
	rtxAt := nil.
	(state == #synSent and: [stack isConfigured not and: [(remoteIp bitShift: -24) ~= 127]]) ifTrue: [
		"no address yet: the SYN waits for DHCP"
		rtxAt := stack now + RTO_INITIAL.
		^self].
	syn := state == #synSent or: [state == #synReceived].
	retries := retries + 1.
	retries > (syn ifTrue: [SYN_RETRIES] ifFalse: [RETRIES]) ifTrue: [^self fail: #timedOut].
	rto := rto * 2 min: RTO_MAX.
	timing := false.
	stack count: #retransmits.
	syn ifTrue: [
		sndNxt := iss.
		^self output].
	retries = 1 ifTrue: [ssthresh := (self seq: sndMax minus: sndUna) // 2 max: 2 * mss].
	cwnd := mss.
	inRecovery := false.
	dupAcks := 0.
	recover := sndMax.
	sndNxt := sndUna.
	self output
!
probe
	"Ask a peer with a zero window for its window: a segment just left of it; again later, backed off."
	persistAt := nil.
	sndWnd > 0 ifTrue: [^self output].
	self send: (self seq: sndUna minus: 1) flags: ACK offset: 0 length: 0.
	persistBackoff := persistBackoff + 1 min: 6.
	persistAt := stack now + ((rto bitShift: persistBackoff) min: RTO_MAX)
! !

!TcpConnection methodsFor: 'sockets'!
readInto: bytes start: start count: n
	"Bytes received: their count, 0 at the end, -1 if none yet, -2 if I failed."
	| k first right |
	(rcvLen notNil and: [rcvLen > 0]) ifTrue: [
		k := rcvLen min: n.
		first := BUFFER - rcvHead min: k.
		bytes replaceFrom: start to: start + first - 1 with: rcvBuf startingAt: rcvHead + 1.
		k > first ifTrue: [bytes replaceFrom: start + first to: start + k - 1 with: rcvBuf startingAt: 1].
		rcvHead := rcvHead + k \\ BUFFER.
		rcvLen := rcvLen - k.
		"a window update if the window opened by enough"
		right := self seq: rcvNxt plus: (BUFFER - rcvLen min: MAX_WINDOW).
		((#(#established #finWait1 #finWait2) includes: state)
			and: [(self seq: right gt: rcvAdv) and: [(self seq: right minus: rcvAdv) >= (2 * mss)]]) ifTrue: [self sendAck].
		^k].
	failure notNil ifTrue: [^-2].
	finReceived ifTrue: [^0].
	state == #closed ifTrue: [^-2].
	^-1
!
write: bytes start: start count: n
	"Bytes into the send buffer, and on their way: their count, -1 if there is no room (or I am being made), -2 if I failed or am closing."
	| k at first |
	(failure notNil or: [state == #closed]) ifTrue: [^-2].
	(state == #synSent or: [state == #synReceived]) ifTrue: [^-1].
	(state == #established or: [state == #closeWait]) ifFalse: [^-2].
	n = 0 ifTrue: [^0].
	k := BUFFER - sndLen min: n.
	k = 0 ifTrue: [^-1].
	at := sndHead + sndLen \\ BUFFER.
	first := BUFFER - at min: k.
	sndBuf replaceFrom: at + 1 to: at + first with: bytes startingAt: start.
	k > first ifTrue: [sndBuf replaceFrom: 1 to: k - first with: bytes startingAt: start + first].
	sndLen := sndLen + k.
	self output.
	^k
!
isReadable
	"Bytes to read, the end, a failure, or (a listener) a connection to accept."
	state == #listen ifTrue: [^acceptQueue notEmpty].
	^rcvLen > 0 or: [finReceived or: [failure notNil or: [state == #closed]]]
!
isWritable
	(failure notNil or: [state == #closed]) ifTrue: [^true].
	^(state == #established or: [state == #closeWait]) and: [sndLen < BUFFER]
!
isConnected
	"true made, nil being made, false failed."
	(failure notNil or: [state == #closed]) ifTrue: [^false].
	(state == #synSent or: [state == #synReceived]) ifTrue: [^nil].
	^true
!
close
	"The socket lets go of me: a listener goes (resetting what it has not accepted), a connection sends what remains and its FIN, and is done once #closed. Unread data is dropped, and what comes later."
	detached := true.
	rcvLen isNil ifFalse: [rcvLen := 0].
	state == #listen ifTrue: [
		stack connections do: [:each |
			each parent == self ifTrue: [
				each orphan; detach; abort]].
		acceptQueue removeAll: acceptQueue copy.
		state := #closed.
		^self].
	(state == #synSent or: [state == #synReceived]) ifTrue: [^self abort].
	(state == #established or: [state == #closeWait]) ifTrue: [
		finQueued := true.
		state := state == #established ifTrue: [#finWait1] ifFalse: [#lastAck].
		self output]
!
detach
	detached := true
! !
