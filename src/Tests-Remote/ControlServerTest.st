TestCase subclass: #ControlServerTest
	instanceVariableNames: 'server clients'
	classVariableNames: ''
	package: 'Tests-Remote'!

ControlServerTest comment: 'Tests ControlServer over real TCP sockets on 127.0.0.1 (a free port): JSON-lines requests and responses, the token every request carries, malformed lines, and concurrent clients.'!

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
	"With the server's token unless aDictionary has an auth of its own."
	^self unauthenticated: (self authorized: aDictionary) on: aSocket
!
unauthenticated: aDictionary on: aSocket
	self sendLine: (JSON render: aDictionary) on: aSocket.
	^JSON parse: (self readLineFrom: aSocket)
!
authorized: aDictionary
	^(aDictionary includesKey: 'auth')
		ifTrue: [aDictionary]
		ifFalse: [aDictionary copy at: 'auth' put: server token; yourself]
!
ping: anId
	^self authorized: (Dictionary new at: 'cmd' put: 'ping'; at: 'id' put: anId; yourself)
!
eval: aString
	^self authorized: (Dictionary new at: 'cmd' put: 'eval'; at: 'source' put: aString; yourself)
!
assertUnauthorized: aResponse
	self deny: (aResponse at: 'ok').
	self assert: (aResponse at: 'code') equals: 4.
	self assert: ((aResponse at: 'error') includesSubstring: 'unauthorized')
! !

!ControlServerTest methodsFor: 'tests'!
testPortAndPing
	| r |
	self assert: server port > 0.
	self assert: server isRunning.
	r := self request: (self ping: 'a1') on: self connect.
	self assert: (r at: 'ok').
	self assert: (r at: 'id') equals: 'a1'
!
testNothingIsServedWhileTheImageStartsUp
	"A request that arrives while the image runs its startup list is answered once the list is done."
	| c |
	SystemDictionary classPool at: #StartingUp put: true.
	[c := self connect.
	 self sendLine: (JSON render: (self ping: 'b1')) on: c.
	 self assert: (c receiveInto: (ByteArray new: 1) timeout: 300) isNil description: 'answered while starting up']
		ensure: [SystemDictionary classPool at: #StartingUp put: false].
	self assert: ((JSON parse: (self readLineFrom: c)) at: 'id') equals: 'b1'
!
testWakeupAfterAHostTakesOverIsNotLost
	"A wakeup due on the server's own Semaphore when a host takes over its sockets: the next one goes to the host's."
	| sem index |
	sem := Semaphore new.
	index := Smalltalk vm registerExternalSemaphore: sem.
	[server wakeIn: 100.
	 server hostOn: sem index: index by: self.
	 self deny: (sem waitTimeoutMSecs: 1000) description: 'hosting did not signal'.
	 server wakeIn: 300.
	 self deny: (sem waitTimeoutMSecs: 1000) description: 'the wakeup went to the old Semaphore']
		ensure: [server unhost. Smalltalk vm unregisterExternalSemaphore: index]
!
testRequestWithoutTheTokenIsRejected
	"Without auth, with another token, a prefix of it or not a String: code 4, nothing runs; the same connection then works with it."
	| c r |
	c := self connect.
	Smalltalk at: #ControlServerTestRan put: false.
	[r := self unauthenticated: (Dictionary new at: 'cmd' put: 'eval'; at: 'source' put: 'Smalltalk at: #ControlServerTestRan put: true'; at: 'id' put: 7; yourself) on: c.
	 self assertUnauthorized: r.
	 self assert: (r at: 'id') equals: 7.
	 {server token reverse. server token allButLast. server token, 'x'. ''. 'x'. 42. nil} do: [:wrong |
		r := self request: ((self eval: 'Smalltalk at: #ControlServerTestRan put: true') at: 'auth' put: wrong; yourself) on: c.
		self assertUnauthorized: r].
	 self deny: (Smalltalk at: #ControlServerTestRan) description: 'an unauthorized request ran'.
	 r := self request: (self eval: '3 + 4') on: c.
	 self assert: (r at: 'printString') equals: '7']
		ensure: [Smalltalk removeKey: #ControlServerTestRan ifAbsent: [nil]]
!
testCommandsNeverSeeTheToken
	| r |
	RemoteControl registerCommand: 'test-keys' handler: [:q | Dictionary new at: 'keys' put: q arguments keys asSortedCollection asArray; at: 'printed' put: q printString; yourself].
	[r := self request: (Dictionary new at: 'cmd' put: 'test-keys'; yourself) on: self connect.
	 self assert: (r at: 'keys') equals: #('cmd').
	 self deny: ((r at: 'printed') includesSubstring: server token)]
		ensure: [RemoteControl unregisterCommand: 'test-keys']
!
testAuthorizes
	| t |
	t := server token.
	self assert: t size equals: 32.
	self assert: (t allSatisfy: [:c | '0123456789abcdef' includes: c]).
	self deny: t = ControlServer newToken.
	self assert: (server authorizes: t).
	self assert: (server authorizes: (ControlServer grouped: t)) description: 'grouped as on the screen'.
	self assert: (server authorizes: ' ', t, (String with: Character lf)).
	self deny: (server authorizes: t asUppercase).
	self deny: (server authorizes: (t allButFirst copyWith: (t last = $0 ifTrue: [$1] ifFalse: [$0]))).
	self deny: (server authorizes: (t first: 16)).
	self deny: (server authorizes: t, t).
	self deny: (server authorizes: '').
	self deny: (server authorizes: nil).
	self deny: (server authorizes: 12345)
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
	r := self request: (self ping: 'c1') on: c.
	self assert: (r at: 'ok')
!
testPipelinedRequests
	| c r1 r2 |
	c := self connect.
	c sendAll: ('{"id":1,"cmd":"eval","source":"1+1","auth":"', server token, '"}', (String with: Character lf), '{"id":2,"cmd":"eval","source":"2+2","auth":"', server token, '"}', (String with: Character lf)) utf8Encoded.
	r1 := JSON parse: (self readLineFrom: c).
	r2 := JSON parse: (self readLineFrom: c).
	self assert: (r1 at: 'id') equals: 1.
	self assert: (r1 at: 'printString') equals: '2'.
	self assert: (r2 at: 'id') equals: 2.
	self assert: (r2 at: 'printString') equals: '4'
!
testConcurrentClients
	"A client gets its answer while another client's request is still being evaluated: that one's goes on only once this one has it."
	| slow fast gate r |
	gate := Semaphore new.
	Smalltalk at: #ControlServerTestGate put: gate.
	[slow := self connect.
	 fast := self connect.
	 self sendLine: (JSON render: (self eval: '(Smalltalk at: #ControlServerTestGate) wait. #slow')) on: slow.
	 r := self request: (self eval: '#fast') on: fast.
	 self assert: (r at: 'printString') equals: '#fast'.
	 gate signal.
	 r := JSON parse: (self readLineFrom: slow).
	 self assert: (r at: 'printString') equals: '#slow']
		ensure: [
			gate signal.
			Smalltalk removeKey: #ControlServerTestGate ifAbsent: [nil]]
!
testClientDisconnect
	| c |
	c := self connect.
	self request: (self ping: 'd1') on: c.
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
