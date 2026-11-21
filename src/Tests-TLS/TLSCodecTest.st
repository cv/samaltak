TestCase subclass: #TLSCodecTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSCodecTest comment: 'I check TLS''s presentation language (TLSReader, TLSWriter), the ServerHello decoder, the alert names and the cipher suites.'!

!TLSCodecTest methodsFor: 'tests'!
testWriter
	self assert: (TLSWriter new u8: 1; u16: 16r0203; u24: 16r040506; contents) equals: #[1 2 3 4 5 6].
	self assert: (TLSWriter new vector8: #[9 9]; vector16: #[7]; vector24: #[]; contents) equals: #[2 9 9 0 1 7 0 0 0].
	self assert: (TLSWriter new vector16Do: [:w | w u16: 16r1301; vector8Do: [:v | v u8: 5]]; contents) equals: #[0 4 16r13 1 1 5].
	self should: [TLSWriter new vector8: (ByteArray new: 256)] raise: TLSError
!
testReader
	| r sub |
	r := TLSReader on: #[1 2 3 4 5 6 7 8 9 10 2 11 12].
	self assert: r u8 equals: 1.
	self assert: r u16 equals: 16r0203.
	self assert: r u24 equals: 16r040506.
	self assert: r u32 equals: 16r0708090A.
	sub := r reader8.
	self assert: sub u16 equals: 16r0B0C.
	self assert: sub atEnd.
	self assert: r atEnd.
	r expectEnd
!
testReaderBounds
	self should: [(TLSReader on: #[1]) u16] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #decodeError].
	self should: [(TLSReader on: #[0 5 1 2]) vector16] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #decodeError].
	self should: [(TLSReader on: #[3 1 2 3 4]) vector8; expectEnd] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #decodeError].
	"a vector's reader stops at its end even when bytes follow"
	self should: [(TLSReader on: #[1 7 8]) reader8 u16] raise: TLSError
!
testExtensions
	| extensions |
	extensions := (TLSReader on: #[0 10 0 43 0 2 3 4 0 0 0 0]) extensions.
	self assert: (extensions at: 43) equals: #[3 4].
	self assert: (extensions at: 0) equals: #[].
	self should: [(TLSReader on: #[0 8 0 1 0 0 0 1 0 0]) extensions] raise: TLSError withExceptionDo: [:e | self assert: e alert equals: #illegalParameter]
!
testServerHello
	| body sh |
	body := TLSWriter new u16: 16r0303; bytes: (ByteArray new: 32 withAll: 1); vector8: #[5 6]; u16: 16r1302; u8: 0;
		vector16Do: [:w | w u16: 43; vector16: #[3 4]; u16: 51; vector16: #[0 16r1D 0 2 9 9]]; contents.
	sh := TLSServerHello fromBody: body.
	self deny: sh isHelloRetryRequest.
	self assert: sh sessionId equals: #[5 6].
	self assert: sh cipherSuite equals: 16r1302.
	self assert: sh selectedVersion equals: 16r0304.
	self assert: sh keyShare equals: {16r1D. #[9 9]}.
	self assert: sh cookie isNil.
	self should: [TLSServerHello fromBody: (body copyFrom: 1 to: body size - 1)] raise: TLSError
!
testHelloRetryRandom
	self assert: TLSServerHello helloRetryRandom equals: (SHA256 hash: 'HelloRetryRequest' asByteArray)
!
testAlerts
	self assert: (TLSError codeOf: #decodeError) equals: 50.
	self assert: (TLSError nameOf: 40) equals: #handshakeFailure.
	self assert: (TLSError nameOf: 200) equals: 200.
	self assert: (TLSError wireNameOf: #badRecordMac) equals: 'bad_record_mac'.
	self should: [TLSError peerAlert: 48] raise: TLSError withExceptionDo: [:e |
		self assert: e isFromPeer.
		self assert: e messageText equals: 'the server sent the alert unknown_ca']
!
testCipherSuites
	self assert: (TLSCipherSuite all collect: [:each | each code]) equals: #(16r1301 16r1303 16r1302).
	self assert: (TLSCipherSuite withCode: 16r1302) hashSize equals: 48.
	self assert: (TLSCipherSuite withCode: 16r1302) keySize equals: 32.
	self assert: (TLSCipherSuite withCode: 16r1304) isNil
! !
