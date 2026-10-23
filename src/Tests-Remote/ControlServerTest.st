TestCase subclass: #ControlServerTest
	instanceVariableNames: 'server clients'
	classVariableNames: ''
	package: 'Tests-Remote'!

ControlServerTest comment: 'Tests ControlServer over real TCP sockets on 127.0.0.1 (a free port): JSON-lines requests and responses, malformed lines, and concurrent clients.'!

!ControlServerTest methodsFor: 'running'!
setUp
	server := ControlServer new startOn: 0.
	clients := OrderedCollection new
!
tearDown
	clients do: [:c | c close].
	server stop
!
connect
	^clients add: (RemoteSocket connectTo: '127.0.0.1' port: server port)
!
sendLine: aString on: aSocket
	aSocket sendAll: (aString, (String with: Character lf)) utf8Encoded
!
readLineFrom: aSocket
	"Answer the next line (decoded), or nil after 5 s."
	| line buffer byte |
	line := WriteStream on: (ByteArray new: 100).
	buffer := ByteArray new: 1.
	[((aSocket receiveInto: buffer timeout: 5000) ifNil: [^nil]) = 0 ifTrue: [^nil].
	 (byte := buffer first) = 10] whileFalse: [line nextPut: byte].
	^String fromUTF8: line contents
!
request: aDictionary on: aSocket
	self sendLine: (JSON render: aDictionary) on: aSocket.
	^JSON parse: (self readLineFrom: aSocket)
!
eval: aString
	^Dictionary new at: 'cmd' put: 'eval'; at: 'source' put: aString; yourself
! !

!ControlServerTest methodsFor: 'tests'!
testPortAndPing
	| r |
	self assert: server port > 0.
	self assert: server isRunning.
	r := self request: (Dictionary new at: 'cmd' put: 'ping'; at: 'id' put: 'a1'; yourself) on: self connect.
	self assert: (r at: 'ok').
	self assert: (r at: 'id') equals: 'a1'
!
testEvalOverSocket
	| c r |
	c := self connect.
	r := self request: (self eval: '3 + 4') on: c.
	self assert: (r at: 'printString') equals: '7'.
	r := self request: (self eval: '1/0') on: c.
	self deny: (r at: 'ok').
	self assert: (r at: 'code') equals: 3.
	r := self request: (self eval: '''', (String with: (Character value: 955)), '''') on: c.
	self assert: (r at: 'printString') equals: '''', (String with: (Character value: 955)), ''''
!
testBadLines
	| c r |
	c := self connect.
	self sendLine: 'not json' on: c.
	r := JSON parse: (self readLineFrom: c).
	self deny: (r at: 'ok').
	self assert: ((r at: 'error') includesSubstring: 'bad request').
	self sendLine: '[1, 2]' on: c.
	r := JSON parse: (self readLineFrom: c).
	self deny: (r at: 'ok').
	"blank lines are ignored; the connection still works"
	self sendLine: '' on: c.
	r := self request: (Dictionary new at: 'cmd' put: 'ping'; yourself) on: c.
	self assert: (r at: 'ok')
!
testPipelinedRequests
	| c r1 r2 |
	c := self connect.
	c sendAll: ('{"id":1,"cmd":"eval","source":"1+1"}', (String with: Character lf), '{"id":2,"cmd":"eval","source":"2+2"}', (String with: Character lf)) utf8Encoded.
	r1 := JSON parse: (self readLineFrom: c).
	r2 := JSON parse: (self readLineFrom: c).
	self assert: (r1 at: 'id') equals: 1.
	self assert: (r1 at: 'printString') equals: '2'.
	self assert: (r2 at: 'id') equals: 2.
	self assert: (r2 at: 'printString') equals: '4'
!
testConcurrentClients
	| slow fast start r |
	slow := self connect.
	fast := self connect.
	start := Time millisecondClockValue.
	self sendLine: (JSON render: (self eval: '(Delay forMilliseconds: 600) wait. #slow')) on: slow.
	r := self request: (self eval: '#fast') on: fast.
	self assert: (r at: 'printString') equals: '#fast'.
	self assert: Time millisecondClockValue - start < 500.
	r := JSON parse: (self readLineFrom: slow).
	self assert: (r at: 'printString') equals: '#slow'.
	self assert: Time millisecondClockValue - start >= 600
!
testClientDisconnect
	| c |
	c := self connect.
	self request: (Dictionary new at: 'cmd' put: 'ping'; yourself) on: c.
	self assert: server connections size equals: 1.
	c close.
	self assert: (self waitFor: [server connections isEmpty])
!
testStopClosesListener
	| c |
	server stop.
	self deny: server isRunning.
	c := [RemoteSocket connectTo: '127.0.0.1' port: server port] on: RemoteError do: [:e | e return: nil].
	c isNil ifFalse: [
		clients add: c.
		self assert: (c receiveInto: (ByteArray new: 4) timeout: 2000) equals: 0]
! !
