Object subclass: #RfbTestClient
	instanceVariableNames: 'socket buffer pos extent framebuffer name zdata zcount cursor rects'
	classVariableNames: ''
	package: 'Tests-Remote'!

RfbTestClient comment: 'I am the client side of RFB for tests: I build client messages (class side) and decode what a server sent, from bytes fed to me (feed:) or read from a socket: the handshake''s ServerInit, and FramebufferUpdates in the native pixel format (BGRX) into my framebuffer: Raw, ZRLE (inflating the session''s one zlib stream with ZLib, all of it again each time: tests are small), CopyRect, Cursor, DesktopSize and LastRect. rects lists the last update''s rectangles as {encoding. rectangle}.'!

!RfbTestClient methodsFor: 'initialization'!
initialize
	buffer := ByteArray new.
	pos := 1.
	zdata := ByteArray new.
	zcount := 0.
	rects := OrderedCollection new
!
socket: aSocket
	socket := aSocket
!
extent: aPoint
	extent := aPoint.
	framebuffer := ByteArray new: aPoint x * aPoint y * 4
! !

!RfbTestClient methodsFor: 'accessing'!
extent
	^extent
!
framebuffer
	^framebuffer
!
name
	^name
!
cursor
	^cursor
!
rects
	^rects
!
encodingsSeen
	^rects collect: [:each | each first]
!
atEnd
	^pos > buffer size
! !

!RfbTestClient methodsFor: 'reading'!
feed: bytes
	buffer := (buffer copyFrom: pos to: buffer size), bytes.
	pos := 1
!
next: n
	| chunk got |
	[buffer size - pos + 1 < n] whileTrue: [
		socket isNil ifTrue: [^self error: 'RfbTestClient: wanted ', n printString, ' bytes, have ', (buffer size - pos + 1) printString].
		chunk := ByteArray new: 65536.
		got := socket receiveInto: chunk timeout: 10000.
		(got isNil or: [got = 0]) ifTrue: [^self error: 'RfbTestClient: the server sent nothing more'].
		self feed: (chunk copyFrom: 1 to: got)].
	pos := pos + n.
	^buffer copyFrom: pos - n to: pos - 1
!
u8
	^(self next: 1) first
!
u16
	^(self next: 2) uint16BigEndianAt: 1
!
u32
	^(self next: 4) uint32BigEndianAt: 1
!
s32
	| v |
	v := self u32.
	^v >= 16r80000000 ifTrue: [v - 16r100000000] ifFalse: [v]
!
send: bytes
	socket sendAll: bytes
! !

!RfbTestClient methodsFor: 'handshake'!
readServerInit
	| w h |
	w := self u16.
	h := self u16.
	self next: 16.
	name := (self next: self u32) asString.
	self extent: w @ h
!
handshakeVersion: aString security: aType password: aPassword
	"Over my socket: version aString (e.g. 'RFB 003.008'), then the security type the server picks (3.3) or aType from its list, the password (VNC) or token (VeNCrypt-Plain), ClientInit shared. Answer nil when in, else what went wrong."
	| v n types type r |
	v := self next: 12.
	self send: aString asByteArray, #[10].
	(aString = 'RFB 003.003')
		ifTrue: [
			type := self u32.
			type = 0 ifTrue: [^(self next: self u32) asString]]
		ifFalse: [
			n := self u8.
			n = 0 ifTrue: [^(self next: self u32) asString].
			types := (self next: n) asArray.
			(types includes: aType) ifFalse: [^'not offered: ', types printString].
			type := aType.
			self send: (ByteArray with: type)].
	type = 2 ifTrue: [self send: (Des vncResponseTo: (self next: 16) password: aPassword)].
	type = 19 ifTrue: [
		self next: 2.
		self send: #[0 2].
		self u8 = 0 ifFalse: [^'VeNCrypt version refused'].
		n := self u8.
		types := (1 to: n) collect: [:i | self u32].
		self send: (self class u32: 256), (self class u32: 4), (self class u32: aPassword size), 'user' asByteArray, aPassword asByteArray].
	(type ~= 1 or: [aString = 'RFB 003.008']) ifTrue: [
		r := self u32.
		r = 0 ifFalse: [^aString = 'RFB 003.008' ifTrue: [(self next: self u32) asString] ifFalse: ['failed']]].
	self send: #[1].
	self readServerInit.
	^nil
! !

!RfbTestClient methodsFor: 'updates'!
readUpdate
	"One FramebufferUpdate into my framebuffer."
	| count |
	self u8 = 0 ifFalse: [^self error: 'not a FramebufferUpdate'].
	self u8.
	count := self u16.
	rects := OrderedCollection new.
	count = 16rFFFF
		ifTrue: [[self readRect] whileTrue]
		ifFalse: [count timesRepeat: [self readRect]].
	^rects
!
readRect
	"Answer false after LastRect."
	| x y w h enc r |
	x := self u16.
	y := self u16.
	w := self u16.
	h := self u16.
	enc := self s32.
	r := x @ y extent: w @ h.
	rects add: (Array with: enc with: r).
	enc = -224 ifTrue: [^false].
	enc = 0 ifTrue: [self putRows: (self next: w * h * 4) in: r].
	enc = 1 ifTrue: [self copyFrom: self u16 @ self u16 to: r].
	enc = 16 ifTrue: [self readZrle: r].
	enc = -239 ifTrue: [cursor := Array with: x @ y with: (self next: w * h * 4) with: (self next: w + 7 // 8 * h) with: w @ h].
	enc = -223 ifTrue: [self extent: w @ h].
	^true
!
putRows: bgrx in: r
	0 to: r height - 1 do: [:y | | to |
		to := (r top + y) * extent x + r left * 4 + 1.
		framebuffer replaceFrom: to to: to + (r width * 4) - 1 with: bgrx startingAt: y * r width * 4 + 1]
!
copyFrom: aPoint to: r
	| copy |
	copy := ByteArray new: r width * r height * 4.
	0 to: r height - 1 do: [:y |
		copy replaceFrom: y * r width * 4 + 1 to: y + 1 * r width * 4 with: framebuffer startingAt: (aPoint y + y) * extent x + aPoint x * 4 + 1].
	self putRows: copy in: r
!
readZrle: r
	| data all in p pixel tile |
	data := self next: self u32.
	zdata := zdata, data.
	all := ZLib new inflate: zdata, #[1 0 0 255 255] from: 3.
	in := all copyFrom: zcount + 1 to: all size.
	zcount := all size.
	p := 1.
	pixel := [| px | px := (in copyFrom: p to: p + 2), #[255]. p := p + 3. px].
	0 to: r height - 1 by: 64 do: [:ty |
		0 to: r width - 1 by: 64 do: [:tx | | tw th sub out palette |
			tw := 64 min: r width - tx.
			th := 64 min: r height - ty.
			out := ByteArray new: tw * th * 4.
			sub := in at: p.
			p := p + 1.
			sub = 0 ifTrue: [0 to: tw * th - 1 do: [:i | out replaceFrom: i * 4 + 1 to: i * 4 + 4 with: pixel value startingAt: 1]].
			sub = 1 ifTrue: [| px | px := pixel value. 0 to: tw * th - 1 do: [:i | out replaceFrom: i * 4 + 1 to: i * 4 + 4 with: px startingAt: 1]].
			(sub between: 2 and: 16) ifTrue: [| bits |
				palette := (1 to: sub) collect: [:i | pixel value].
				bits := sub = 2 ifTrue: [1] ifFalse: [sub <= 4 ifTrue: [2] ifFalse: [4]].
				0 to: th - 1 do: [:y | | byte left |
					left := 0.
					0 to: tw - 1 do: [:x | | index |
						left = 0 ifTrue: [byte := in at: p. p := p + 1. left := 8].
						left := left - bits.
						index := ((byte bitShift: left negated) bitAnd: (1 bitShift: bits) - 1) + 1.
						out replaceFrom: y * tw + x * 4 + 1 to: y * tw + x * 4 + 4 with: (palette at: index) startingAt: 1]]].
			(sub = 128 or: [sub >= 130]) ifTrue: [| i |
				sub >= 130 ifTrue: [palette := (1 to: sub - 128) collect: [:k | pixel value]].
				i := 0.
				[i < (tw * th)] whileTrue: [| px length b |
					sub = 128
						ifTrue: [px := pixel value. length := self runLengthIn: in at: [:np | p := np] from: p]
						ifFalse: [
							b := in at: p.
							p := p + 1.
							px := palette at: (b bitAnd: 127) + 1.
							length := b < 128 ifTrue: [1] ifFalse: [self runLengthIn: in at: [:np | p := np] from: p]].
					length timesRepeat: [out replaceFrom: i * 4 + 1 to: i * 4 + 4 with: px startingAt: 1. i := i + 1]]].
			((sub between: 17 and: 127) or: [sub = 129]) ifTrue: [^self error: 'bad ZRLE subencoding ', sub printString].
			tile := (r left + tx) @ (r top + ty) extent: tw @ th.
			self putRows: out in: tile]].
	p = (in size + 1) ifFalse: [^self error: 'ZRLE: ', (in size + 1 - p) printString, ' bytes left over']
!
runLengthIn: bytes at: setBlock from: start
	| p length b |
	p := start.
	length := 1.
	[b := bytes at: p. p := p + 1. length := length + b. b = 255] whileTrue.
	setBlock value: p.
	^length
! !

!RfbTestClient class methodsFor: 'messages'!
u16: n
	^ByteArray with: (n bitShift: -8) with: (n bitAnd: 255)
!
u32: n
	^ByteArray with: ((n bitShift: -24) bitAnd: 255) with: ((n bitShift: -16) bitAnd: 255) with: ((n bitShift: -8) bitAnd: 255) with: (n bitAnd: 255)
!
setEncodings: anArray
	| out |
	out := WriteStream on: (ByteArray new: 64).
	out nextPutAll: #[2 0]; nextPutAll: (self u16: anArray size).
	anArray do: [:e | out nextPutAll: (self u32: (e < 0 ifTrue: [e + 16r100000000] ifFalse: [e]))].
	^out contents
!
updateRequest: incremental rect: r
	^(ByteArray with: 3 with: (incremental ifTrue: [1] ifFalse: [0])), (self u16: r left), (self u16: r top), (self u16: r width), (self u16: r height)
!
setPixelFormat: anRfbPixelFormat
	^#[0 0 0 0], anRfbPixelFormat asBytes
!
key: keysym down: aBoolean
	^(ByteArray with: 4 with: (aBoolean ifTrue: [1] ifFalse: [0]) with: 0 with: 0), (self u32: keysym)
!
pointer: mask at: aPoint
	^(ByteArray with: 5 with: mask), (self u16: aPoint x), (self u16: aPoint y)
!
cutText: aString
	^#[6 0 0 0], (self u32: aString size), aString asByteArray
! !
