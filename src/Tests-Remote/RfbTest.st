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
	"Collect the damage (a polled or diffing source) and send the update now and decode it."
	server source collectFor: connection.
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
	"macOS Screen Sharing asks for depth 32 and decodes 3-byte CPIXELs, as TigerVNC, libvncserver and QEMU do."
	self assert: ((RfbPixelFormat bitsPerPixel: 32 depth: 32 bigEndian: false maxes: #(255 255 255) shifts: #(16 8 0)) cpixelSize) equals: 3.
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

!RfbTest methodsFor: 'tests: changed blocks'!
paragraphOn: aSource
	"Lines of dark glyphs, 6x9 every 8 pixels, on white: a paragraph from 10@10 to 310@100."
	aSource fill: aSource bounds red: 255 green: 255 blue: 255.
	0 to: 5 do: [:line |
		0 to: 36 do: [:i |
			(i * 7 + line) \\ 5 = 0 ifFalse: [
				aSource fill: (10 + (i * 8) @ (10 + (line * 15)) extent: 6 @ 9) red: 20 green: 20 blue: 20]]]
!
diffed
	"The screen through an RfbDiffSource, connected, the client's first update taken."
	server source: (RfbDiffSource on: source).
	self connected.
	self fullUpdate: #(16 1 -223).
	self assert: client framebuffer equals: source bytes.
	^server source
!
another
	"A second client of the same server: {connection. socket. client}, its first update taken."
	| s c k |
	s := RfbTestSocket new.
	s deliver: 'RFB 003.008' asByteArray, #[10 1 1].
	c := RfbConnection server: server socket: s.
	self assert: c handshake.
	s clearSent.
	c beServing.
	k := RfbTestClient new extent: source extent; yourself.
	s deliver: (RfbTestClient setEncodings: #(16 1 -223)), (RfbTestClient updateRequest: false rect: (0 @ 0 extent: source extent)).
	self process: c.
	self update: c socket: s client: k.
	^Array with: c with: s with: k
!
process: aConnection
	[[true] whileTrue: [aConnection processMessage]] on: RfbError do: [:e | e return: nil]
!
update: aConnection socket: aSocket client: aClient
	server source collectFor: aConnection.
	aConnection sendUpdate.
	aClient feed: aSocket takeSent.
	^aClient readUpdate
!
testStreamedParagraphSendsOnlyChangedBlocks
	"Text streamed into a paragraph that is re-laid out (all of it damaged) each time: only the 16x16 blocks of the words that came are sent."
	| diff |
	source := RfbBufferSource extent: 320 @ 200.
	self paragraphOn: source.
	diff := self diffed.
	0 to: 3 do: [:i | | word blocks r |
		word := 30 + (i * 64) @ 87 extent: 40 @ 9.
		source fill: word red: 200 green: 0 blue: 0.
		source redraw: (10 @ 10 extent: 300 @ 90).
		self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
		r := self update.
		self assert: client framebuffer equals: source bytes.
		blocks := (word left // 16 * 16) @ (word top // 16 * 16) corner: (word right + 15 // 16 * 16) @ (word bottom + 15 // 16 * 16).
		self assert: r notEmpty.
		self assert: (r allSatisfy: [:each | blocks containsRect: each last]).
		self assert: (r inject: 0 into: [:sum :each | sum + each last area]) <= blocks area].
	self assert: (diff statistics at: 'comparedArea') >= (4 * 300 * 90).
	self assert: (diff statistics at: 'changedArea') < ((diff statistics at: 'comparedArea') // 10)
!
testRedrawnTheSameSendsNothing
	self diffed.
	source redraw: (0 @ 0 extent: 60 @ 50).
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	server source collectFor: connection.
	self deny: connection hasUpdate
!
testChangedBlocksAreClippedAndJoined
	"Two pixels 40 rows apart in one column of blocks, and one far right: the damage is the blocks that hold them, clipped to what was damaged."
	| r |
	source := RfbBufferSource extent: 200 @ 140.
	source fillWith: [:x :y | Array with: x with: y * 2 \\ 256 with: x + y \\ 256].
	self diffed.
	source at: 17 @ 3 put: #(1 2 3).
	source at: 18 @ 45 put: #(1 2 3).
	source at: 90 @ 60 put: #(4 5 6).
	source redraw: (5 @ 0 extent: 90 @ 65).
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	r := (self update collect: [:each | each last]) asArray.
	self assert: client framebuffer equals: source bytes.
	self assert: (r includes: (80 @ 48 corner: 95 @ 64)).
	self assert: (r anySatisfy: [:each | (each containsPoint: 17 @ 3) and: [each containsPoint: 18 @ 45]]) not.
	self assert: (r anySatisfy: [:each | each containsPoint: 17 @ 3]).
	self assert: (r anySatisfy: [:each | each containsPoint: 18 @ 45]).
	self assert: (r inject: 0 into: [:sum :each | sum + each area]) <= (3 * 256)
!
testSlowViewerOfChangedBlocks
	"Two clients of one copy: one takes each change, the other only after several, merged; both end up with the screen."
	| b |
	self diffed.
	b := self another.
	self assert: (b at: 3) framebuffer equals: source bytes.
	1 to: 3 do: [:i |
		source fill: (i * 20 @ (i * 10) extent: 9 @ 7) red: i * 50 green: 0 blue: 0.
		source redraw: (0 @ 0 extent: 90 @ 60).
		self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
		self update.
		self assert: client framebuffer equals: source bytes].
	(b at: 2) deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	self process: (b at: 1).
	self assert: (b at: 1) hasUpdate.
	self update: (b at: 1) socket: (b at: 2) client: (b at: 3).
	self assert: (b at: 3) framebuffer equals: source bytes.
	(b at: 1) close.
	self assert: server source hasCopy.
	connection close.
	connection := nil.
	self deny: server source hasCopy
!
testCopyRectThroughChangedBlocks
	"A move is a CopyRect, and the copy moves too: what changed at its origin before is still sent, at both places."
	| r |
	self diffed.
	source move: (0 @ 0 extent: 20 @ 10) to: 30 @ 40.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	r := self update.
	self assert: r size equals: 1.
	self assert: r first equals: (Array with: 1 with: (30 @ 40 extent: 20 @ 10)).
	self assert: client framebuffer equals: source bytes.
	source fill: (2 @ 2 extent: 5 @ 5) red: 9 green: 99 blue: 199.
	source move: (0 @ 0 extent: 20 @ 10) to: 50 @ 20.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	r := self update.
	self assert: r first first equals: 1.
	self assert: client framebuffer equals: source bytes
!
testScrollIsACopyRect
	"A list scrolled up by 7 rows inside a window (all of it damaged): its rows are found again 7 rows lower in the copy, a CopyRect moves them, and only the rows it uncovered (and what did not scroll) are sent."
	| r region bytes w pixels |
	source := RfbBufferSource extent: 200 @ 150.
	source fillWith: [:x :y | Array with: x * 5 + y \\ 256 with: y * 3 \\ 256 with: x * y \\ 251].
	self diffed.
	region := 30 @ 20 extent: 140 @ 100.
	bytes := source bytes.
	w := 200 * 4.
	region top to: region bottom - 8 do: [:y |
		bytes replaceFrom: y * w + (region left * 4) + 1 to: y * w + (region right * 4) with: bytes startingAt: (y + 7) * w + (region left * 4) + 1].
	source fill: (region left @ (region bottom - 7) extent: region width @ 7) red: 250 green: 250 blue: 250.
	source redraw: region.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	r := self update.
	self assert: client framebuffer equals: source bytes.
	self assert: r first first equals: 1.
	self assert: (server source statistics at: 'scrolls') equals: 1.
	pixels := (r reject: [:each | each first = 1]) inject: 0 into: [:sum :each | sum + each last area].
	self assert: pixels < (region area // 3)
!
testMoveUnderAWindowStillMakesTheScreen
	"A move is a hint: where a window over the moved one hides it, the screen did not change (and was not damaged); the destination is compared again and those pixels sent."
	| r |
	self diffed.
	source notify: [:each | each moved: (0 @ 0 extent: 40 @ 30) to: 50 @ 35].
	source move: (0 @ 0 extent: 10 @ 10) to: 60 @ 40.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: source extent)).
	r := self update.
	self assert: (r collect: [:each | each first]) asArray first equals: 1.
	self assert: client framebuffer equals: source bytes
!
testDesktopSizeThroughChangedBlocks
	self diffed.
	source extent: 40 @ 30.
	source fillWith: [:x :y | #(1 2 3)].
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: 100 @ 70)).
	self assert: (self update collect: [:each | each first]) asArray equals: #(-223 16).
	self assert: client extent equals: 40 @ 30.
	self assert: client framebuffer equals: source bytes.
	source fill: (3 @ 3 extent: 2 @ 2) red: 0 green: 0 blue: 0.
	self deliver: (RfbTestClient updateRequest: true rect: (0 @ 0 extent: 40 @ 30)).
	self assert: (self update collect: [:each | each last]) asArray equals: (Array with: (3 @ 3 extent: 2 @ 2)).
	self assert: client framebuffer equals: source bytes
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
testScreenSharingGetsTheAppleKeys
	"A viewer's SetEncodings with Apple's encodings makes its input's profile #apple: Alt_L is cmd; the server can force a profile."
	| input |
	self connected.
	input := RfbInput queue: (InputQueue new extent: 100 @ 70; yourself).
	connection input: input.
	self deliver: (RfbTestClient setEncodings: #(1011 1002 6 16 -239 1104 1100 -223)), (RfbTestClient key: 16rFFE9 down: true).
	self assert: connection keyProfile equals: #apple.
	self assert: input modifiers equals: 8.
	self deliver: (RfbTestClient key: 16rFFE9 down: false), (RfbTestClient setEncodings: #(16 -239)), (RfbTestClient key: 16rFFE9 down: true).
	self assert: connection keyProfile equals: #standard.
	self assert: input modifiers equals: 4.
	input keyProfile: #apple.
	self deliver: (RfbTestClient setEncodings: #(16 -239)).
	self assert: connection keyProfile equals: #apple.
	self should: [server keyProfile: #pc] raise: Error.
	input close
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
	"the backoff runs from the failure: timed from its answer, not from the next connection (on a loaded machine connecting takes a while)"
	t0 := Time millisecondClockValue.
	c := RfbTestClient new socket: (s := RemoteSocket connectTo: '127.0.0.1' port: server port).
	result := c handshakeVersion: 'RFB 003.003' security: 2 password: 'secret12'.
	self assert: result isNil.
	self assert: Time millisecondClockValue - t0 >= 250 description: [(Time millisecondClockValue - t0) printString, ' ms from the failure to the screen'].
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

!RfbTest methodsFor: 'tests: primitives'!
zrleFormats
	"ZRLE's kinds of pixel formats: native BGRX (3-byte CPIXELs from byte 0), big-endian (from byte 1), 32 bits with channels in all four bytes (4-byte CPIXELs), 16 and 8 bits."
	^{RfbPixelFormat native.
		RfbPixelFormat bitsPerPixel: 32 depth: 24 bigEndian: true maxes: #(255 255 255) shifts: #(16 8 0).
		RfbPixelFormat bitsPerPixel: 32 depth: 32 bigEndian: false maxes: #(255 255 255) shifts: #(20 12 4).
		RfbPixelFormat bitsPerPixel: 16 depth: 16 bigEndian: false maxes: #(31 63 31) shifts: #(11 5 0).
		RfbPixelFormat bitsPerPixel: 8 depth: 8 bigEndian: false maxes: #(7 7 3) shifts: #(0 3 6)}
!
assertZrleOf: bgra width: w height: h
	"The zrleTiles primitive's tiles of the BGRA8 pixels are the Smalltalk's, in each kind of format."
	self zrleFormats do: [:f | | px e off |
		px := f convertBgra: bgra count: w * h.
		off := f cpixelOffset ifNil: [0].
		e := RfbZrleEncoder new.
		self assert: (e primTiles: px width: w height: h bytesPerPixel: f bytesPerPixel cpixelSize: f cpixelSize offset: off scratch: e scratch into: (ByteArray new: w * h * f cpixelSize + (w + 63 // 64 * (h + 63 // 64)))) notNil.
		self
			assert: (e tiles: px width: w height: h format: f)
			equals: (RfbZrleEncoder new tilesInSmalltalk: px width: w height: h bytesPerPixel: f bytesPerPixel cpixelSize: f cpixelSize offset: off)]
!
randomBgra: n mode: mode random: random
	"n BGRA8 pixels: one colour (0), two (1), four (2), a dozen (3) or 200 (4) in runs of random lengths, noise (5); alpha mostly 255, sometimes not."
	| colours out i |
	colours := (1 to: (#(1 2 4 12 200 1) at: mode + 1)) collect: [:k | ((1 to: 3) collect: [:b | (random nextInt: 256) - 1]) asByteArray].
	out := ByteArray new: n * 4.
	i := 0.
	[i < n] whileTrue: [| c len |
		c := colours at: (random nextInt: colours size).
		len := mode = 5 ifTrue: [1] ifFalse: [#(1 1 2 3 7 64 300) at: (random nextInt: 7)].
		(len min: n - i) timesRepeat: [
			mode = 5 ifTrue: [c := ((1 to: 3) collect: [:b | (random nextInt: 256) - 1]) asByteArray].
			out replaceFrom: i * 4 + 1 to: i * 4 + 3 with: c startingAt: 1.
			out at: i * 4 + 4 put: ((random nextInt: 10) = 1 ifTrue: [random nextInt: 2] ifFalse: [255]).
			i := i + 1]].
	^out
!
testZrlePrimitiveIsTheSmalltalk
	"Rectangles of 1 to 200 pixels across, one tile to several, partial ones at the edges, every kind of tile."
	| random |
	random := Random seed: 97531.
	#(#(1 1) #(3 2) #(64 64) #(65 65) #(130 70) #(200 3) #(7 130)) do: [:size |
		0 to: 5 do: [:mode |
			self assertZrleOf: (self randomBgra: size first * size last mode: mode random: random) width: size first height: size last]]
!
testZrlePrimitiveOnScreenshots
	"Screenshots of the World's themes (prototypes/screenshots: text, gradients, pictures), the middle of each: the primitive's tiles are the Smalltalk's. Where the files are not there (UEFI), there is nothing to compare."
	#('theme-swiss.png' 'theme-phosphor.png' 'proto-4-morphic.png') do: [:name | | form w h all bgra |
		form := [(Smalltalk at: #PNGReader) formFromFile: 'prototypes/screenshots/', name] on: Error do: [:e | e return: nil].
		form isNil ifFalse: [
			w := form width min: 600.
			h := form height min: 360.
			all := ByteArray new: form width * form height * 4.
			all replaceFrom: 1 to: all size withRawBytesOf: form bits startingAt: 1.
			bgra := ByteArray new: w * h * 4.
			0 to: h - 1 do: [:y | bgra replaceFrom: y * w * 4 + 1 to: y + 1 * w * 4 with: all startingAt: (form height - h // 2 + y) * form width + (form width - w // 2) * 4 + 1].
			self assertZrleOf: bgra width: w height: h]]
!
testZrlePrimitiveRefuses
	"Pixel sizes and CPIXELs ZRLE has not, buffers too small or the same, a scratch of the wrong size."
	| e px ok |
	e := RfbZrleEncoder new.
	px := ByteArray new: 4 * 4 * 4.
	ok := [:pixels :bpp :cp :off :scratch :out | e primTiles: pixels width: 4 height: 4 bytesPerPixel: bpp cpixelSize: cp offset: off scratch: scratch into: out].
	self assert: (ok valueWithArguments: {px. 4. 3. 0. e scratch. ByteArray new: 49}) notNil.
	self assert: (ok valueWithArguments: {px. 4. 3. 0. e scratch. ByteArray new: 48}) isNil.
	self assert: (ok valueWithArguments: {px. 3. 3. 0. e scratch. ByteArray new: 100}) isNil.
	self assert: (ok valueWithArguments: {px. 4. 3. 2. e scratch. ByteArray new: 100}) isNil.
	self assert: (ok valueWithArguments: {px. 4. 4. 1. e scratch. ByteArray new: 100}) isNil.
	self assert: (ok valueWithArguments: {px. 2. 3. 0. e scratch. ByteArray new: 100}) isNil.
	self assert: (ok valueWithArguments: {px. 4. 3. 0. ByteArray new: 100. ByteArray new: 100}) isNil.
	self assert: (ok valueWithArguments: {px. 4. 3. 0. e scratch. px}) isNil.
	self assert: (ok valueWithArguments: {ByteArray new: 63. 4. 3. 0. e scratch. ByteArray new: 100}) isNil.
	self assert: (ok valueWithArguments: {px. 4. 3. 0. e scratch. #[1 2 3]}) isNil
!
diffSource: ext copy: bytes
	"A diffing source whose copy is bytes."
	^(RfbDiffSource on: source)
		instVarNamed: 'extent' put: ext;
		instVarNamed: 'copy' put: bytes;
		yourself
!
testChangedBlocksPrimitiveIsTheSmalltalk
	"The pixelBlocksDiff primitive finds the blocks and makes the copy that the Smalltalk does: rectangles anywhere, of any size, with a few bytes changed or many."
	| random ext base |
	random := Random seed: 8642.
	ext := 203 @ 117.
	base := ((1 to: ext x * ext y * 4) collect: [:i | random nextInt: 3]) asByteArray.
	1 to: 200 do: [:t | | x y w h rect bytes a b ca cb marks |
		x := (random nextInt: ext x) - 1.
		y := (random nextInt: ext y) - 1.
		w := random nextInt: ext x - x.
		h := random nextInt: ext y - y.
		rect := x @ y extent: w @ h.
		bytes := ByteArray new: w * h * 4.
		0 to: h - 1 do: [:j | bytes replaceFrom: j * w * 4 + 1 to: j + 1 * w * 4 with: base startingAt: (y + j) * ext x + x * 4 + 1].
		(#(0 1 5 50 5000) at: t \\ 5 + 1) timesRepeat: [| i |
			i := random nextInt: bytes size.
			bytes at: i put: 255 - (bytes at: i)].
		a := self diffSource: ext copy: base copy.
		b := self diffSource: ext copy: base copy.
		marks := ByteArray new: w + 31 // 16 * (h + 31 // 16).
		self assert: (a primBlocks: bytes width: w height: h into: base copy stride: ext x * 4 left: x top: y block: 16 marks: marks) notNil.
		ca := OrderedCollection new.
		cb := OrderedCollection new.
		a compare: rect with: bytes into: ca.
		b compareInSmalltalk: rect with: bytes into: cb.
		self assert: ca asArray equals: cb asArray.
		self assert: (a instVarNamed: 'copy') equals: (b instVarNamed: 'copy')]
!
testChangedBlocksPrimitiveRefuses
	"Rectangles outside the copy, marks too few, the same object twice."
	| d copy px marks ok |
	d := self diffSource: 32 @ 32 copy: nil.
	copy := ByteArray new: 32 * 32 * 4.
	px := ByteArray new: 16 * 16 * 4.
	marks := ByteArray new: 4.
	ok := [:pixels :c :left :top :m | d primBlocks: pixels width: 16 height: 16 into: c stride: 128 left: left top: top block: 16 marks: m].
	self assert: (ok valueWithArguments: {px. copy. 16. 16. marks}) equals: 0.
	self assert: (ok valueWithArguments: {px. copy. 8. 8. marks}) equals: 0.
	self assert: (ok valueWithArguments: {px. copy. 8. 8. ByteArray new: 3}) isNil.
	self assert: (ok valueWithArguments: {px. copy. 17. 0. marks}) isNil.
	self assert: (ok valueWithArguments: {px. copy. 0. 17. marks}) isNil.
	self assert: (ok valueWithArguments: {ByteArray new: 1023. copy. 0. 0. marks}) isNil.
	self assert: (ok valueWithArguments: {px. px. 0. 0. marks}) isNil.
	self assert: (ok valueWithArguments: {px. copy. 0. 0. copy}) isNil.
	self assert: (ok valueWithArguments: {px. copy. -1. 0. marks}) isNil
! !
