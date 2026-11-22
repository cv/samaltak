TestCase subclass: #RfbTest
	instanceVariableNames: 'source server socket connection client'
	classVariableNames: ''
	package: 'Tests-Remote'!

RfbTest comment: 'Tests the RFB server (RfbServer, RfbConnection) over a scripted socket (RfbTestSocket), against a screen in memory (RfbBufferSource), decoding what it sends with RfbTestClient: the handshakes of RFB 3.3, 3.7 and 3.8 with None, VNC authentication and VeNCrypt-Plain, updates in Raw and ZRLE equal to the screen, incremental updates of only the damage, pixel formats, the pseudo-encodings, CopyRect and input; and over real sockets on 127.0.0.1 the backoff after failures and the connection limit.'!

!RfbTest methodsFor: 'running'!
setUp
	source := RfbBufferSource extent: 100 @ 70.
	source fillWith: [:x :y | Array with: x * 2 with: y * 3 with: x + y \\ 256].
	server := RfbServer new.
	server source: source.
	socket := RfbTestSocket new.
	client := RfbTestClient new
!
tearDown
	connection isNil ifFalse: [connection close].
	server stop
!
connection
	^connection ifNil: [connection := RfbConnection server: server socket: socket]
!
connected
	"Through RFB 3.8 with None; the handshake's bytes taken, the screen known to the client."
	server allowNone: true.
	socket deliver: 'RFB 003.008' asByteArray, #[10 1 1].
	self assert: self connection handshake.
	socket clearSent.
	connection beServing.
	client extent: source extent.
	^connection
!
deliver: bytes
	"Client messages, processed until the socket has no more."
	socket deliver: bytes.
	[[true] whileTrue: [connection processMessage]] on: RfbError do: [:e |
		self assert: e messageText equals: 'the client closed the connection'.
		e return: nil]
!
update
	"Send the update now and decode it."
	connection sendUpdate.
	client feed: socket takeSent.
	^client readUpdate
!
fullUpdate: encodings
	self deliver: (RfbTestClient setEncodings: encodings), (RfbTestClient updateRequest: false rect: (0 @ 0 extent: source extent)).
	^self update
! !

!RfbTest methodsFor: 'tests: handshake'!
testVersion38None
	| sent |
	server allowNone: true.
	socket deliver: 'RFB 003.008' asByteArray, #[10 1 1].
	self assert: self connection handshake.
	sent := socket sent.
	self assert: (sent copyFrom: 1 to: 12) asString equals: 'RFB 003.008', (String with: Character lf).
	self assert: (sent copyFrom: 13 to: 14) equals: #[1 1].
	self assert: (sent copyFrom: 15 to: 18) equals: #[0 0 0 0].
	client feed: (sent copyFrom: 19 to: sent size).
	client readServerInit.
	self assert: client extent equals: 100 @ 70.
	self assert: client name equals: 'Samaltak'.
	self assert: (sent copyFrom: 23 to: 38) equals: RfbPixelFormat native asBytes.
	self assert: RfbPixelFormat native asBytes equals: #[32 24 0 1 0 255 0 255 0 255 16 8 0 0 0 0].
	self assert: connection isShared
!
testNoneOnlyWhenAllowedOnLoopback
	self assert: server securityTypes equals: #().
	server allowNone: true.
	self assert: server securityTypes equals: #(1).
	server host: '0.0.0.0'.
	self assert: server securityTypes equals: #().
	server token: '0123456789abcdef0123456789abcdef'; password: 'secret12'.
	self assert: server securityTypes equals: #(19 2).
	self assert: server securityTypeV3 equals: 2
!
testNothingConfiguredIsRefused
	| sent |
	socket deliver: 'RFB 003.008' asByteArray, #[10].
	self deny: self connection handshake.
	sent := socket sent.
	self assert: (sent at: 13) equals: 0.
	self assert: ((sent copyFrom: 18 to: sent size) asString includesSubstring: 'no authentication')
!
testVersion33VncAuth
	| sent |
	server password: 'secret12'.
	socket responder: [:bytes :s | bytes size = 16 ifTrue: [s deliver: (Des vncResponseTo: bytes password: 'secret12'), #[0]]].
	socket deliver: 'RFB 003.003' asByteArray, #[10].
	self assert: self connection handshake.
	self assert: connection version equals: 3.
	sent := socket sent.
	self assert: (sent copyFrom: 13 to: 16) equals: #[0 0 0 2].
	self assert: (sent copyFrom: 33 to: 36) equals: #[0 0 0 0].
	self deny: connection isShared
!
testVersion33WrongPassword
	| sent |
	server password: 'secret12'; backoffMs: 1.
	socket responder: [:bytes :s | bytes size = 16 ifTrue: [s deliver: (Des vncResponseTo: bytes password: 'secret13')]].
	socket deliver: 'RFB 003.003' asByteArray, #[10].
	self deny: self connection handshake.
	sent := socket sent.
	self assert: sent size equals: 36.
	self assert: (sent copyFrom: 33 to: 36) equals: #[0 0 0 1]
!
testVersion33WithoutPasswordRefused
	| sent |
	server token: '0123456789abcdef0123456789abcdef'.
	socket deliver: 'RFB 003.003' asByteArray, #[10].
	self deny: self connection handshake.
	sent := socket sent.
	self assert: (sent copyFrom: 13 to: 16) equals: #[0 0 0 0].
	self assert: ((sent copyFrom: 21 to: sent size) asString includesSubstring: 'VNC authentication')
!
testVersion38VncAuthFailureHasReason
	| sent |
	server password: 'secret12'; backoffMs: 1.
	socket responder: [:bytes :s | bytes size = 16 ifTrue: [s deliver: (ByteArray new: 16)]].
	socket deliver: 'RFB 003.008' asByteArray, #[10 2].
	self deny: self connection handshake.
	sent := socket sent.
	self assert: (sent copyFrom: 13 to: 14) equals: #[1 2].
	self assert: (sent copyFrom: 31 to: 34) equals: #[0 0 0 1].
	self assert: (sent copyFrom: 39 to: sent size) asString equals: 'authentication failed'
!
testVersion37None
	server allowNone: true.
	socket deliver: 'RFB 003.007' asByteArray, #[10 1 1].
	self assert: self connection handshake.
	self assert: connection version equals: 7.
	"no SecurityResult for None before 3.8: ServerInit follows the list"
	self assert: (socket sent copyFrom: 15 to: 16) equals: #[0 100]
!
testTypeNotOffered
	server password: 'secret12'.
	socket deliver: 'RFB 003.008' asByteArray, #[10 1].
	self deny: self connection handshake.
	self assert: ((socket sent copyFrom: 19 to: socket sent size) asString includesSubstring: 'not offered')
!
testVeNCryptPlain
	| sent |
	server token: '0123-4567-89ab-cdef-0123-4567-89ab-cdef'.
	socket deliver: 'RFB 003.008' asByteArray, #[10 19 0 2], (RfbTestClient u32: 256), (RfbTestClient u32: 1), (RfbTestClient u32: 32), 'u' asByteArray, '0123456789abcdef0123456789abcdef' asByteArray, #[1].
	self assert: self connection handshake.
	sent := socket sent.
	self assert: (sent copyFrom: 13 to: 14) equals: #[1 19].
	self assert: (sent copyFrom: 15 to: 22) equals: #[0 2 0 1 0 0 1 0].
	self assert: (sent copyFrom: 23 to: 26) equals: #[0 0 0 0]
!
testVeNCryptWrongToken
	server token: '0123456789abcdef0123456789abcdef'; backoffMs: 1.
	socket deliver: 'RFB 003.008' asByteArray, #[10 19 0 2], (RfbTestClient u32: 256), (RfbTestClient u32: 0), (RfbTestClient u32: 31), '0123456789abcdef0123456789abcde' asByteArray.
	self deny: self connection handshake.
	self assert: (socket sent copyFrom: 23 to: 26) equals: #[0 0 0 1]
!
testTooManyClients
	server allowNone: true; maxClients: 0.
	server newConnectionOn: RfbTestSocket new.
	socket deliver: 'RFB 003.008' asByteArray, #[10].
	self deny: self connection handshake.
	self assert: (socket sent at: 13) equals: 0.
	self assert: ((socket sent copyFrom: 18 to: socket sent size) asString includesSubstring: 'too many')
!
testNotRfb
	socket deliver: 'GET / HTTP/1.1' asByteArray.
	self should: [self connection handshake] raise: RfbError
! !

!RfbTest methodsFor: 'tests: updates'!
testRawFullUpdate
	self connected.
	self fullUpdate: #(0).
	self assert: client encodingsSeen asArray equals: #(0).
	self assert: client framebuffer equals: source bytes
!
testZrleFullUpdate
	self connected.
	self fullUpdate: #(16 0).
	self assert: client encodingsSeen asArray equals: #(16).
	self assert: client framebuffer equals: source bytes
!
testZrleTileKinds
	"Solid, two colours (packed, 1 bit), a few (packed, 4 bits), runs (palette RLE), many colours in runs (plain RLE), noise (raw)."
	source := RfbBufferSource extent: 64 * 6 @ 64.
	server source: source.
	source fillWith: [:x :y | | t |
		t := x // 64.
		t = 0 ifTrue: [#(10 20 30)] ifFalse: [
		t = 1 ifTrue: [(x + y) odd ifTrue: [#(0 0 0)] ifFalse: [#(255 255 255)]] ifFalse: [
		t = 2 ifTrue: [Array with: x \\ 7 * 30 with: 0 with: 0] ifFalse: [
		t = 3 ifTrue: [Array with: y // 8 * 10 with: 5 with: 5] ifFalse: [
		t = 4 ifTrue: [Array with: y * 2 with: x // 16 with: 200] ifFalse: [
		Array with: x * 7 + (y * 13) \\ 256 with: x * y \\ 256 with: x * 3 + y \\ 256]]]]]].
	self connected.
	self fullUpdate: #(16).
	self assert: client framebuffer equals: source bytes.
	self assert: (RfbZrleEncoder new tiles: (source bgraOf: (0 @ 0 extent: 64 @ 64)) width: 64 height: 64 format: RfbPixelFormat native) equals: #[1 30 20 10]
!
testZrleStreamAcrossUpdates
	self connected.
	self fullUpdate: #(16).
	source fill: (10 @ 10 extent: 30 @ 5) red: 1 green: 2 blue: 3.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self update.
	self assert: client framebuffer equals: source bytes
!
testIncrementalSendsOnlyDamage
	| r |
	self connected.
	self fullUpdate: #(0).
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self deny: connection hasUpdate.
	source fill: (5 @ 6 extent: 7 @ 8) red: 255 green: 0 blue: 0.
	self assert: connection hasUpdate.
	r := self update.
	self assert: r size equals: 1.
	self assert: r first last equals: (5 @ 6 extent: 7 @ 8).
	self assert: client framebuffer equals: source bytes.
	self deny: connection hasUpdate
!
testDamageWaitsForARequest
	self connected.
	self fullUpdate: #(0).
	source fill: (0 @ 0 extent: 4 @ 4) red: 1 green: 1 blue: 1.
	source fill: (50 @ 50 extent: 4 @ 4) red: 2 green: 2 blue: 2.
	self deny: connection hasUpdate.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self assert: self update size equals: 2.
	self assert: client framebuffer equals: source bytes
!
testRequestOfAPart
	"Damage outside the requested rectangle stays for a later request."
	self connected.
	self fullUpdate: #(0).
	source fill: (0 @ 0 extent: 20 @ 20) red: 9 green: 9 blue: 9.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: 10 @ 70)).
	self assert: self update first last equals: (0 @ 0 extent: 10 @ 20).
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self assert: self update first last equals: (10 @ 0 extent: 10 @ 20).
	self assert: client framebuffer equals: source bytes
!
testLastRect
	self connected.
	self fullUpdate: #(16 -224).
	self assert: client encodingsSeen asArray equals: #(16 -224).
	self assert: client framebuffer equals: source bytes
!
testCursorOnce
	| r |
	self connected.
	r := self fullUpdate: #(0 -239).
	self assert: client encodingsSeen asArray equals: #(-239 0).
	self assert: (client cursor at: 1) equals: 0 @ 0.
	self assert: (client cursor at: 4) equals: RfbCursor arrow width @ RfbCursor arrow height.
	self assert: (client cursor at: 3) equals: RfbCursor arrow mask.
	self assert: ((client cursor at: 3) first bitAnd: 128) equals: 128.
	source fill: (0 @ 0 extent: 1 @ 1) red: 0 green: 0 blue: 0.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self assert: (self update collect: [:each | each first]) asArray equals: #(0)
!
testDesktopSize
	self connected.
	self fullUpdate: #(0 -223).
	source extent: 40 @ 30.
	source fillWith: [:x :y | #(1 2 3)].
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: 100 @ 70)).
	self assert: (self update collect: [:each | each first]) asArray equals: #(-223 0).
	self assert: client extent equals: 40 @ 30.
	self assert: client framebuffer equals: source bytes
!
testCopyRect
	| r |
	self connected.
	self fullUpdate: #(1 0).
	source move: (0 @ 0 extent: 20 @ 10) to: 30 @ 40.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	r := self update.
	self assert: r size equals: 1.
	self assert: r first equals: (Array with: 1 with: (30 @ 40 extent: 20 @ 10)).
	self assert: client framebuffer equals: source bytes
!
testCopyRectAfterDamageThereIsPixels
	"The client's copy of the source is stale: the destination goes as pixels."
	self connected.
	self fullUpdate: #(1 0).
	source fill: (0 @ 0 extent: 5 @ 5) red: 7 green: 7 blue: 7.
	source move: (0 @ 0 extent: 20 @ 10) to: 30 @ 40.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self deny: (self update anySatisfy: [:each | each first = 1]).
	self assert: client framebuffer equals: source bytes
!
testCopyRectWithoutSupportIsPixels
	self connected.
	self fullUpdate: #(0).
	source move: (0 @ 0 extent: 20 @ 10) to: 30 @ 40.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self assert: (self update collect: [:each | each first]) asArray equals: #(0).
	self assert: client framebuffer equals: source bytes
!
testSetPixelFormat
	| sent rgb565 rgbx px |
	self connected.
	rgb565 := RfbPixelFormat bitsPerPixel: 16 depth: 16 bigEndian: true maxes: #(31 63 31) shifts: #(11 5 0).
	self deliver: (RfbTestClient setPixelFormat: rgb565), (RfbTestClient setEncodings: #(0)), (RfbTestClient updateRequest: false rect: (1 @ 0 extent: 1 @ 1)).
	connection sendUpdate.
	sent := socket takeSent.
	px := source bgraOf: (1 @ 0 extent: 1 @ 1).
	self assert: (sent copyFrom: 17 to: 18) equals: (RfbTestClient u16: (rgb565 pixelOfRed: (px at: 3) green: (px at: 2) blue: (px at: 1))).
	rgbx := RfbPixelFormat bitsPerPixel: 32 depth: 24 bigEndian: false maxes: #(255 255 255) shifts: #(0 8 16).
	self deliver: (RfbTestClient setPixelFormat: rgbx), (RfbTestClient updateRequest: false rect: (1 @ 0 extent: 1 @ 1)).
	connection sendUpdate.
	sent := socket takeSent.
	self assert: (sent copyFrom: 17 to: 19) equals: (ByteArray with: (px at: 3) with: (px at: 2) with: (px at: 1))
!
testPixelFormats
	| bgra |
	bgra := #[10 20 30 255 1 2 3 255].
	self assert: (RfbPixelFormat native convertBgra: bgra count: 2) == bgra.
	self assert: ((RfbPixelFormat bitsPerPixel: 32 depth: 24 bigEndian: true maxes: #(255 255 255) shifts: #(16 8 0)) convertBgra: bgra count: 2)
		equals: #[0 30 20 10 0 3 2 1].
	self assert: ((RfbPixelFormat bitsPerPixel: 32 depth: 24 bigEndian: true maxes: #(255 255 255) shifts: #(8 16 24)) isNative).
	self assert: ((RfbPixelFormat bitsPerPixel: 8 depth: 8 bigEndian: false maxes: #(7 7 3) shifts: #(0 3 6)) convertBgra: #[255 0 255 255] count: 1)
		equals: #[199].
	self assert: RfbPixelFormat native cpixelSize equals: 3.
	self assert: RfbPixelFormat native cpixelOffset equals: 0.
	self assert: ((RfbPixelFormat bitsPerPixel: 32 depth: 24 bigEndian: false maxes: #(255 255 255) shifts: #(24 16 8)) cpixelOffset) equals: 1.
	self assert: ((RfbPixelFormat bitsPerPixel: 16 depth: 16 bigEndian: false maxes: #(31 63 31) shifts: #(11 5 0)) cpixelSize) equals: 2.
	self assert: (RfbPixelFormat fromBytes: RfbPixelFormat native asBytes) equals: RfbPixelFormat native.
	self assert: (RfbPixelFormat fromBytes: #[8 8 0 0 0 0 0 0 0 0 0 0 0 0 0 0]) problem notNil
!
testZrleSmallFormats
	"ZRLE with 16-bit pixels: CPIXELs are whole pixels."
	| f |
	self connected.
	f := RfbPixelFormat bitsPerPixel: 16 depth: 16 bigEndian: false maxes: #(31 63 31) shifts: #(11 5 0).
	self deliver: (RfbTestClient setPixelFormat: f), (RfbTestClient setEncodings: #(16)), (RfbTestClient updateRequest: false rect: (0 @ 0 extent: 8 @ 1)).
	connection sendUpdate.
	self assert: socket sent size > 16
! !

!RfbTest methodsFor: 'tests: damage'!
testDamageMerges
	| d |
	d := RfbDamage extent: 1000 @ 1000.
	d add: (10 @ 10 extent: 8 @ 16); add: (20 @ 10 extent: 8 @ 16).
	self assert: d rects size equals: 1.
	d add: (500 @ 500 extent: 10 @ 10).
	self assert: d rects size equals: 2.
	d add: (-5 @ -5 extent: 10 @ 10).
	self assert: (d rects allSatisfy: [:r | d bounds containsRect: r]).
	d add: (0 @ 0 extent: 900 @ 900).
	self assert: d isFull.
	d := RfbDamage extent: 1000 @ 1000.
	d maxRects: 4.
	0 to: 9 do: [:i | d add: (i * 100 @ 0 extent: 2 @ 2)].
	self assert: d rects size equals: 4
!
testDamageTakeWithin
	| d inside |
	d := RfbDamage extent: 100 @ 100.
	d add: (0 @ 0 extent: 20 @ 20).
	inside := d takeWithin: (0 @ 0 extent: 10 @ 100).
	self assert: inside asArray equals: (Array with: (0 @ 0 extent: 10 @ 20)).
	self assert: d rects asArray equals: (Array with: (10 @ 0 extent: 10 @ 20))
! !

!RfbTest methodsFor: 'tests: input'!
testInputGoesToTheHandler
	| events |
	self connected.
	events := OrderedCollection new.
	connection input: (RfbTestInput new events: events).
	self deliver: (RfbTestClient key: 16rFFE7 down: true), (RfbTestClient pointer: 5 at: 12 @ 34), (RfbTestClient cutText: 'caf', (String with: (Character value: 233))).
	self assert: events asArray equals: (Array with: (Array with: #key with: 16rFFE7 with: true) with: (Array with: #pointer with: 5 with: 12 @ 34) with: (Array with: #cut with: 'caf', (String with: (Character value: 233))))
!
testCutTextLimit
	self connected.
	socket deliver: #[6 0 0 0], (RfbTestClient u32: 2000000).
	self should: [connection processMessage] raise: RfbError
!
testServerCutText
	self connected.
	connection sendCutText: 'hi', (String with: (Character value: 16r263A)).
	self assert: socket sent equals: #[3 0 0 0 0 0 0 3 104 105 63]
! !

!RfbTest methodsFor: 'tests: sockets'!
testOverTcpWithBackoff
	"Real sockets: a wrong password fails, the next attempt waits out the backoff, the right one gets the screen."
	| s t0 c result |
	server := RfbServer new.
	server password: 'secret12'; token: '0123456789abcdef0123456789abcdef'; backoffMs: 300.
	server startOn: 0 host: '127.0.0.1' source: source.
	c := RfbTestClient new socket: (RemoteSocket connectTo: '127.0.0.1' port: server port).
	self assert: (c handshakeVersion: 'RFB 003.008' security: 2 password: 'wrong') equals: 'authentication failed'.
	c := RfbTestClient new socket: (s := RemoteSocket connectTo: '127.0.0.1' port: server port).
	t0 := Time millisecondClockValue.
	result := c handshakeVersion: 'RFB 003.003' security: 2 password: 'secret12'.
	self assert: result isNil.
	self assert: Time millisecondClockValue - t0 >= 250.
	c send: (RfbTestClient setEncodings: #(16)), (RfbTestClient updateRequest: false rect: (0 @ 0 extent: source extent)).
	c readUpdate.
	self assert: c framebuffer equals: source bytes.
	source fill: (1 @ 2 extent: 3 @ 4) red: 0 green: 0 blue: 255.
	c send: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	c readUpdate.
	self assert: c framebuffer equals: source bytes.
	s close.
	c := RfbTestClient new socket: (s := RemoteSocket connectTo: '127.0.0.1' port: server port).
	self assert: (c handshakeVersion: 'RFB 003.008' security: 19 password: '0123-4567-89ab-cdef-0123-4567-89ab-cdef') isNil.
	s close
!
testOverTcpConnectionLimit
	| sockets c |
	server := RfbServer new.
	server allowNone: true; maxClients: 2.
	server startOn: 0 host: '127.0.0.1' source: source.
	sockets := (1 to: 2) collect: [:i | | sock |
		sock := RemoteSocket connectTo: '127.0.0.1' port: server port.
		self assert: ((RfbTestClient new socket: sock) handshakeVersion: 'RFB 003.008' security: 1 password: nil) isNil.
		sock].
	c := RfbTestClient new socket: (RemoteSocket connectTo: '127.0.0.1' port: server port).
	self assert: ((c handshakeVersion: 'RFB 003.008' security: 1 password: nil) includesSubstring: 'too many').
	sockets do: [:each | each close]
! !
