Object subclass: #RfbConnection
	instanceVariableNames: 'server socket source inBuffer inStart inEnd deadline version running closed reader writer lock sendLock wake format pendingFormat encodings encoding supports request damage moves resizePending cursorPending clientExtent lastSentAt lastCostMs firstDamageAt wakeAt input zrle shared lastError updates bytesSent rectsSent'
	classVariableNames: ''
	package: 'System-Remote'!

RfbConnection comment: 'I am one RFB client of an RfbServer (RFC 6143): the handshake, then the client''s messages and the updates it asks for.

Handshake: I offer RFB 3.8 and speak what the client answers: 3.3 (the server picks the security type, a 32-bit word: VNC authentication, as macOS Screen Sharing needs), 3.7 or 3.8 (a list: VeNCrypt-Plain with the session token, VNC authentication, never None unless the server offersNone). Then ClientInit (shared = 0 disconnects the others) and ServerInit: the screen''s size, the native pixel format (RfbPixelFormat native: BGRX, 32 bits little-endian, shifts 16/8/0) and the desktop''s name. The handshake must be done within handshakeTimeoutMs; nothing but it is accepted before authentication.

Client messages: SetPixelFormat (any true colour), SetEncodings (at most 1024 read, 256 kept), FramebufferUpdateRequest (incremental: what changed since; not: the whole rectangle), and KeyEvent, PointerEvent and ClientCutText (at most 1 MB), which go to my input (nil: ignored), an object understanding key: keysym down: aBoolean, pointer: buttonMask at: aPoint, cutText: aString (Latin-1) and connectionClosed: RfbInput forConnection: me if that class exists (D5). sendCutText: and sendBell go the other way.

Updates: my frame source tells me what changed (damaged:, damagedAll, moved:to:, resized:, cursorChanged, from the Process that presents, doing only O(rectangles) work: an RfbDamage under my lock and a signal) and my writer Process sends a FramebufferUpdate only when the client has asked for one, something changed and the socket takes it (sendAll: waits on the socket, never the World): at most server maxRate a second, at least as long apart as the last update took to make (so encoding takes at most about half the CPU), and coalesceMs after the first change so that a typed word is one update. A slow client so gets fewer, larger updates; frames are never queued. Rectangles go out in the client''s first choice of ZRLE (16, RfbZrleEncoder) or Raw (0); moves as CopyRect (1) if the client has it; pseudo-encodings DesktopSize (-223) when the screen changes size, Cursor (-239: the pointer''s shape, sent once and when it changes) and LastRect (-224: then rectangles are sent as they are encoded).

Processes: the reader (''rfb connection'') runs the handshake and reads messages; the writer (''rfb updates'') sends updates; both at the server''s priority (45). Either closing closes both.'!

!RfbConnection methodsFor: 'initialization'!
setServer: anRfbServer socket: aSocket
	server := anRfbServer.
	socket := aSocket.
	source := anRfbServer source.
	inBuffer := ByteArray new: 65536.
	inStart := 1.
	inEnd := 0.
	running := false.
	closed := false.
	lock := Semaphore forMutualExclusion.
	sendLock := Semaphore forMutualExclusion.
	wake := Semaphore new.
	format := RfbPixelFormat native.
	encodings := #().
	encoding := 0.
	supports := #().
	moves := OrderedCollection new.
	resizePending := false.
	cursorPending := false.
	lastCostMs := 0.
	zrle := RfbZrleEncoder new.
	updates := 0.
	bytesSent := 0.
	rectsSent := 0
! !

!RfbConnection methodsFor: 'running'!
start
	reader := [self run] forkAt: self priority named: 'rfb connection'
!
run
	[[self handshake ifTrue: [self serve]] on: Error do: [:e | lastError := e messageText. e return: nil]]
		ensure: [self close]
!
serve
	"After the handshake: watch the screen, start the writer and read messages until the client goes."
	running := true.
	input := self class newInputFor: self.
	source attach: self.
	writer := [self writeLoop] forkAt: self priority named: 'rfb updates'.
	[running] whileTrue: [self processMessage]
!
beServing
	"After the handshake, without my Processes: tests drive processMessage and sendUpdate."
	running := true.
	source attach: self
!
writeLoop
	[[running] whileTrue: [
		wake wait.
		running ifTrue: [self serviceUpdate]]] on: Error do: [:e |
			lastError := e messageText.
			e return: nil].
	self close
!
close
	"Close the socket; both Processes end (the reader''s receive and the writer''s send fail, the writer''s wait is signalled)."
	closed ifTrue: [^self].
	closed := true.
	running := false.
	source isNil ifFalse: [source detach: self].
	socket close.
	wake signal.
	server removeConnection: self.
	input isNil ifFalse: [[input connectionClosed] on: Error do: [:e | e return: nil]]
!
abandon
	closed ifTrue: [^self].
	closed := true.
	running := false.
	source isNil ifFalse: [source detach: self].
	socket forget.
	wake signal
!
priority
	^RfbServer priority
!
handshakeTimeoutMs
	^10000
!
coalesceMs
	"How long after the first change an update waits for more."
	^4
! !

!RfbConnection methodsFor: 'accessing'!
isRunning
	^running
!
isClosed
	^closed
!
version
	"3, 7 or 8 (RFB 3.x) once the client answered."
	^version
!
format
	^format
!
encoding
	^encoding
!
encodings
	^encodings
!
input
	^input
!
input: anObject
	input := anObject
!
isShared
	^shared
!
lastError
	^lastError
!
socket
	^socket
!
statistics
	"Updates, bytes and rectangles sent, and how long the last update took to make and send."
	^Dictionary new
		at: 'updates' put: updates;
		at: 'bytes' put: bytesSent;
		at: 'rects' put: rectsSent;
		at: 'lastMs' put: lastCostMs;
		yourself
! !

!RfbConnection methodsFor: 'handshake'!
handshake
	"Version, security, ClientInit and ServerInit; answer whether the client is in."
	deadline := Time millisecondClockValue + self handshakeTimeoutMs.
	self send: 'RFB 003.008' asByteArray, #[10].
	version := self parseVersion: (self next: 12).
	server isFull ifTrue: [^self refuse: 'too many clients (', server maxClients printString, ')'].
	self authenticate ifFalse: [^false].
	shared := self nextByte ~= 0.
	shared ifFalse: [server disconnectOthers: self].
	self sendServerInit.
	deadline := nil.
	^true
!
parseVersion: bytes
	"RFB 3.3 (and 3.4-3.6, Apple's 3.3 variants), 3.7, or 3.8 and later (Apple's 3.889)."
	| s minor |
	s := bytes asString.
	((s beginsWith: 'RFB 003.') and: [(s at: 12) = Character lf]) ifFalse: [^RfbError signal: 'not an RFB client'].
	minor := Integer readFrom: (s copyFrom: 9 to: 11) ifFail: [^RfbError signal: 'not an RFB version'].
	minor >= 8 ifTrue: [^8].
	minor = 7 ifTrue: [^7].
	^3
!
refuse: aReason
	"No security type: the connection fails with aReason."
	version = 3 ifTrue: [self send: (self u32: 0)] ifFalse: [self send: #[0]].
	self send: (self u32: aReason size), aReason asByteArray.
	lastError := aReason.
	^false
!
authenticate
	| type types choice |
	version = 3 ifTrue: [
		type := server securityTypeV3.
		type isNil ifTrue: [^self refuse: 'RFB 3.3 needs VNC authentication: start the display with --display-vnc-auth'].
		self send: (self u32: type).
		type = 1 ifTrue: [^true].
		^self vncAuthentication].
	types := server securityTypes.
	types isEmpty ifTrue: [^self refuse: 'no authentication is configured'].
	self send: (ByteArray with: types size), (ByteArray withAll: types).
	choice := self nextByte.
	(types includes: choice) ifFalse: [^self securityResult: false reason: 'security type ', choice printString, ' was not offered'].
	choice = 1 ifTrue: [
		version = 8 ifTrue: [self securityResult: true reason: nil].
		^true].
	choice = 2 ifTrue: [^self vncAuthentication].
	^self veNCrypt
!
vncAuthentication
	"VNC authentication (2): a random 16-byte challenge; the answer is it encrypted with DES under the password."
	| challenge response ok |
	challenge := (Smalltalk at: #SecureRandom) default nextBytes: 16.
	self send: challenge.
	response := self next: 16.
	ok := server authenticate: [server checkVncResponse: response challenge: challenge].
	^self securityResult: ok reason: 'authentication failed'
!
veNCrypt
	"VeNCrypt (19) version 0.2 with its Plain subtype (256) only: a user name (ignored) and the session token as the password, in clear (an SSH tunnel or a trusted network)."
	| v sub userSize passSize pass ok |
	self send: #[0 2].
	v := self next: 2.
	v = #[0 2] ifFalse: [
		self send: #[255].
		lastError := 'VeNCrypt version ', v printString.
		^false].
	self send: #[0].
	self send: #[1], (self u32: 256).
	sub := self nextU32.
	sub = 256 ifFalse: [^self securityResult: false reason: 'VeNCrypt subtype ', sub printString, ' was not offered'].
	userSize := self nextU32.
	passSize := self nextU32.
	(userSize > 1024 or: [passSize > 1024]) ifTrue: [^RfbError signal: 'VeNCrypt-Plain: credentials too long'].
	self next: userSize.
	pass := (self next: passSize) asString.
	ok := server authenticate: [server checkToken: pass].
	^self securityResult: ok reason: 'authentication failed'
!
securityResult: ok reason: aReason
	"SecurityResult: 0 OK, 1 failed (with the reason from RFB 3.8 on)."
	ok ifTrue: [self send: (self u32: 0). ^true].
	self send: (self u32: 1), (version = 8 ifTrue: [(self u32: aReason size), aReason asByteArray] ifFalse: [#[]]).
	lastError := aReason.
	^false
!
sendServerInit
	| e name out |
	e := source extent.
	e isNil ifTrue: [^RfbError signal: 'no screen to serve'].
	clientExtent := e.
	damage := RfbDamage extent: e.
	name := server desktopName asByteArray.
	out := WriteStream on: (ByteArray new: 64).
	self put16: e x on: out.
	self put16: e y on: out.
	out nextPutAll: format asBytes.
	self put32: name size on: out.
	out nextPutAll: name.
	self send: out contents
! !

!RfbConnection methodsFor: 'client messages'!
processMessage
	| type |
	type := self nextByte.
	type = 0 ifTrue: [^self readSetPixelFormat].
	type = 2 ifTrue: [^self readSetEncodings].
	type = 3 ifTrue: [^self readUpdateRequest].
	type = 4 ifTrue: [^self readKeyEvent].
	type = 5 ifTrue: [^self readPointerEvent].
	type = 6 ifTrue: [^self readCutText].
	^RfbError signal: 'unknown client message ', type printString
!
readSetPixelFormat
	| f |
	self next: 3.
	f := RfbPixelFormat fromBytes: (self next: 16).
	f problem ifNotNil: [:p | ^RfbError signal: 'SetPixelFormat: ', p].
	lock critical: [pendingFormat := f]
!
readSetEncodings
	| n list |
	self next: 1.
	n := self nextU16.
	n > 1024 ifTrue: [^RfbError signal: 'SetEncodings: too many'].
	list := (1 to: n) collect: [:i | self nextS32].
	lock critical: [self useEncodings: (list first: (n min: 256))]
!
useEncodings: aList
	"The first of ZRLE and Raw the client lists is its choice; the pseudo-encodings I speak that it lists are on."
	encodings := aList.
	encoding := aList detect: [:e | e = 0 or: [e = 16]] ifNone: [0].
	supports := (#(1 -239 -223 -224) select: [:e | aList includes: e]) asArray.
	(supports includes: -239) ifTrue: [cursorPending := true]
!
supports: anEncoding
	^supports includes: anEncoding
!
readUpdateRequest
	| incremental x y w h r |
	incremental := self nextByte ~= 0.
	x := self nextU16.
	y := self nextU16.
	w := self nextU16.
	h := self nextU16.
	r := (x @ y extent: w @ h) intersect: (0 @ 0 extent: clientExtent).
	lock critical: [
		request := request isNil ifTrue: [r] ifFalse: [request merge: r].
		incremental ifFalse: [
			damage add: r.
			firstDamageAt := 0]].
	wake signal
!
readKeyEvent
	| down keysym |
	down := self nextByte ~= 0.
	self next: 2.
	keysym := self nextU32.
	self toInput: [:i | i key: keysym down: down]
!
readPointerEvent
	| mask x y |
	mask := self nextByte.
	x := self nextU16.
	y := self nextU16.
	self toInput: [:i | i pointer: mask at: x @ y]
!
readCutText
	| size text |
	self next: 3.
	size := self nextU32.
	size > self maxCutText ifTrue: [^RfbError signal: 'ClientCutText: too long'].
	text := (self next: size) asString.
	self toInput: [:i | i cutText: text]
!
maxCutText
	^1048576
!
toInput: aBlock
	"An error of the input handler does not end the connection."
	input isNil ifTrue: [^self].
	[aBlock value: input] on: Error do: [:e | lastError := 'input: ', e messageText. e return: nil]
! !

!RfbConnection methodsFor: 'server messages'!
sendCutText: aString
	"ServerCutText (Latin-1: other characters become ?), to an authenticated client only."
	| bytes |
	running ifFalse: [^self].
	bytes := (aString collect: [:c | c codePoint < 256 ifTrue: [c] ifFalse: [$?]]) asByteArray.
	self send: #[3 0 0 0], (self u32: bytes size), bytes
!
sendBell
	running ifFalse: [^self].
	self send: #[2]
! !

!RfbConnection methodsFor: 'frame source events'!
damaged: aCollectionOfRectangles
	damage isNil ifTrue: [^self].
	lock critical: [
		aCollectionOfRectangles do: [:r | damage add: r].
		self noteDamage].
	wake signal
!
damagedAll
	damage isNil ifTrue: [^self].
	lock critical: [
		damage beFull.
		self noteDamage].
	wake signal
!
moved: aRectangle to: aPoint
	"A CopyRect if the client''s copy of aRectangle is up to date (no damage there waits), else damage."
	damage isNil ifTrue: [^self].
	lock critical: [
		((damage intersects: aRectangle) or: [moves size >= 8])
			ifTrue: [damage add: (aPoint extent: aRectangle extent)]
			ifFalse: [moves add: (Array with: aRectangle with: aPoint)].
		self noteDamage].
	wake signal
!
resized: anExtent
	damage isNil ifTrue: [^self].
	lock critical: [
		damage bounds: (0 @ 0 extent: anExtent).
		moves := OrderedCollection new.
		resizePending := true.
		self noteDamage].
	wake signal
!
cursorChanged
	lock critical: [(self supports: -239) ifTrue: [cursorPending := true]].
	wake signal
!
noteDamage
	firstDamageAt isNil ifTrue: [firstDamageAt := Time millisecondClockValue]
! !

!RfbConnection methodsFor: 'updates'!
hasUpdate
	"Whether the client asked and something is to be sent (under my lock)."
	^request notNil and: [damage notEmpty or: [moves notEmpty or: [resizePending or: [cursorPending]]]]
!
serviceUpdate
	"Send an update if one is due; else, if one will be, have the writer woken then."
	| now due |
	(lock critical: [self hasUpdate]) ifFalse: [^self].
	now := Time millisecondClockValue.
	due := self dueAt.
	now < due ifTrue: [^self wakeIn: due - now].
	self sendUpdate
!
dueAt
	| gap |
	gap := 1000 // (server maxRate max: 1) max: lastCostMs.
	^((lastSentAt ifNil: [-1000000]) + gap) max: (firstDamageAt ifNil: [0]) + self coalesceMs
!
wakeIn: milliseconds
	| now at |
	now := Time millisecondClockValue.
	at := now + milliseconds.
	(wakeAt notNil and: [wakeAt > now and: [wakeAt <= at]]) ifTrue: [^self].
	wakeAt := at.
	(Delay forMilliseconds: (milliseconds max: 1)) signal: wake
!
sendUpdate
	"One FramebufferUpdate of what changed inside the client's request: DesktopSize, Cursor, CopyRects, then the damaged rectangles."
	| start region rects mv resize cursorNow fmt enc streaming cursor out count |
	start := Time millisecondClockValue.
	lock critical: [
		pendingFormat isNil ifFalse: [format := pendingFormat. pendingFormat := nil].
		region := request ifNil: [0 @ 0 extent: clientExtent].
		request := nil.
		resize := resizePending and: [self supports: -223].
		resizePending := false.
		resize ifTrue: [
			clientExtent := damage bounds extent.
			damage beFull.
			region := 0 @ 0 extent: clientExtent].
		cursorNow := cursorPending and: [self supports: -239].
		cursorPending := false.
		region := region intersect: (0 @ 0 extent: clientExtent).
		mv := moves.
		moves := OrderedCollection new.
		((self supports: 1) and: [resize not]) ifFalse: [
			mv do: [:m | damage add: ((m at: 2) extent: (m at: 1) extent)].
			mv := #()].
		mv := mv reject: [:m |
			((region containsRect: (m at: 1)) and: [region containsRect: ((m at: 2) extent: (m at: 1) extent)])
				ifTrue: [false]
				ifFalse: [damage add: ((m at: 2) extent: (m at: 1) extent). true]].
		rects := damage takeWithin: region.
		firstDamageAt := damage isEmpty ifTrue: [nil] ifFalse: [Time millisecondClockValue].
		fmt := format.
		enc := encoding.
		streaming := self supports: -224].
	cursor := cursorNow ifTrue: [source cursor] ifFalse: [nil].
	count := (resize ifTrue: [1] ifFalse: [0]) + (cursor isNil ifTrue: [0] ifFalse: [1]) + mv size + rects size.
	out := WriteStream on: (ByteArray new: 4096).
	out nextPut: 0; nextPut: 0.
	self put16: (streaming ifTrue: [16rFFFF] ifFalse: [count]) on: out.
	resize ifTrue: [self putRect: (0 @ 0 extent: clientExtent) encoding: -223 on: out].
	cursor isNil ifFalse: [self putCursor: cursor format: fmt on: out].
	mv do: [:m |
		self putRect: ((m at: 2) extent: (m at: 1) extent) encoding: 1 on: out.
		self put16: (m at: 1) left on: out.
		self put16: (m at: 1) top on: out].
	rects do: [:r |
		self putPixelsOf: r format: fmt encoding: enc on: out.
		(streaming and: [out position > 65536]) ifTrue: [
			self send: out contents.
			out := WriteStream on: (ByteArray new: 4096)]].
	streaming ifTrue: [self putRect: (0 @ 0 extent: 0 @ 0) encoding: -224 on: out].
	self send: out contents.
	lastSentAt := Time millisecondClockValue.
	lastCostMs := lastSentAt - start.
	updates := updates + 1.
	rectsSent := rectsSent + count
!
putPixelsOf: aRectangle format: fmt encoding: enc on: out
	| r pixels |
	r := aRectangle intersect: source bounds.
	r isEmpty ifTrue: [^self putRect: (aRectangle origin extent: 0 @ 0) encoding: 0 on: out].
	pixels := fmt convertBgra: (source bgraOf: r) count: r width * r height.
	self putRect: r encoding: enc on: out.
	enc = 16
		ifTrue: [out nextPutAll: (zrle encode: pixels width: r width height: r height format: fmt)]
		ifFalse: [out nextPutAll: pixels]
!
putCursor: anRfbCursor format: fmt on: out
	self putRect: (anRfbCursor hotspot extent: anRfbCursor width @ anRfbCursor height) encoding: -239 on: out.
	out nextPutAll: (fmt convertBgra: anRfbCursor bgra count: anRfbCursor width * anRfbCursor height).
	out nextPutAll: anRfbCursor mask
!
putRect: aRectangle encoding: anInteger on: out
	self put16: aRectangle left on: out.
	self put16: aRectangle top on: out.
	self put16: aRectangle width on: out.
	self put16: aRectangle height on: out.
	self put32: (anInteger < 0 ifTrue: [anInteger + 16r100000000] ifFalse: [anInteger]) on: out
! !

!RfbConnection methodsFor: 'reading'!
fill
	| n |
	n := deadline isNil
		ifTrue: [socket receiveInto: inBuffer]
		ifFalse: [socket receiveInto: inBuffer timeout: (deadline - Time millisecondClockValue max: 1)].
	n isNil ifTrue: [^RfbError signal: 'the handshake timed out'].
	n = 0 ifTrue: [^RfbError signal: 'the client closed the connection'].
	inStart := 1.
	inEnd := n
!
next: n
	| out got k |
	out := ByteArray new: n.
	got := 0.
	[got < n] whileTrue: [
		inStart > inEnd ifTrue: [self fill].
		k := n - got min: inEnd - inStart + 1.
		out replaceFrom: got + 1 to: got + k with: inBuffer startingAt: inStart.
		got := got + k.
		inStart := inStart + k].
	^out
!
nextByte
	| b |
	inStart > inEnd ifTrue: [self fill].
	b := inBuffer at: inStart.
	inStart := inStart + 1.
	^b
!
nextU16
	^(self next: 2) uint16BigEndianAt: 1
!
nextU32
	^(self next: 4) uint32BigEndianAt: 1
!
nextS32
	| v |
	v := self nextU32.
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
! !

!RfbConnection methodsFor: 'writing'!
send: bytes
	| ok |
	ok := sendLock critical: [socket sendAll: bytes].
	ok ifFalse: [^RfbError signal: 'the client closed the connection'].
	bytesSent := bytesSent + bytes size
!
u32: anInteger
	^ByteArray with: ((anInteger bitShift: -24) bitAnd: 255) with: ((anInteger bitShift: -16) bitAnd: 255) with: ((anInteger bitShift: -8) bitAnd: 255) with: (anInteger bitAnd: 255)
!
put16: anInteger on: out
	out nextPut: ((anInteger bitShift: -8) bitAnd: 255); nextPut: (anInteger bitAnd: 255)
!
put32: anInteger on: out
	out nextPutAll: (self u32: anInteger)
! !

!RfbConnection methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an RfbConnection'.
	version isNil ifFalse: [aStream nextPutAll: ' 3.'; print: version].
	closed ifTrue: [aStream nextPutAll: ' (closed)']
! !

!RfbConnection class methodsFor: 'instance creation'!
server: anRfbServer socket: aSocket
	^self new setServer: anRfbServer socket: aSocket
!
newInputFor: aConnection
	"The input handler (D5's RfbInput, when it is in the image), or nil."
	^(Smalltalk at: #RfbInput ifAbsent: [nil]) ifNotNil: [:c | c forConnection: aConnection]
! !
