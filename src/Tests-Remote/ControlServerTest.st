TestCase subclass: #ControlServerTest
	instanceVariableNames: 'server clients'
	classVariableNames: ''
	package: 'Tests-Remote'!

ControlServerTest comment: 'Tests ControlServer over real TCP sockets on 127.0.0.1 (a free port): per-request authentication, JSON lines and concurrent clients.'!

!ControlServerTest methodsFor: 'running'!
setUp
	clients := OrderedCollection new.
	server := ControlServer startOn: 0 token: self fixtureToken
!
tearDown
	[clients do: [:c | c close]] ensure: [ControlServer stop]
!
fixtureToken
	"Fixed fixture for disposable loopback tests only."
	^'0123456789abcdef0123456789abcdef'
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
authenticated: aDictionary
	^aDictionary at: 'auth' put: self fixtureToken; yourself
!
request: aDictionary on: aSocket
	^self rawRequest: (self authenticated: aDictionary) on: aSocket
!
rawRequest: aDictionary on: aSocket
	self sendLine: (JSON render: aDictionary) on: aSocket.
	^JSON parse: (self readLineFrom: aSocket)
!
eval: aString
	^Dictionary new at: 'cmd' put: 'eval'; at: 'source' put: aString; yourself
!
assertRefused: aResponse
	self deny: (aResponse at: 'ok').
	self assert: (aResponse at: 'code') equals: 4.
	self deny: (aResponse includesKey: 'controlAuth')
! !

!ControlServerTest methodsFor: 'tests'!
testPortAndPing
	| r |
	self assert: server port > 0.
	self assert: server isRunning.
	r := self request: (Dictionary new at: 'cmd' put: 'ping'; at: 'id' put: 'a1'; yourself) on: self connect.
	self assert: (r at: 'ok').
	self assert: (r at: 'id') equals: 'a1'.
	self assert: (r at: 'controlAuth') equals: 1
!
testAuthenticationOnEveryRequest
	| c ping r |
	c := self connect.
	ping := Dictionary new at: 'id' put: 1; at: 'cmd' put: 'ping'; yourself.
	r := self rawRequest: ping on: c.
	self assertRefused: r.
	self assert: (r at: 'id') equals: 1.
	self assert: ((self request: ping copy on: c) at: 'ok').
	ping at: 'id' put: 2.
	r := self rawRequest: ping on: c.
	self assertRefused: r.
	self assert: (r at: 'id') equals: 2.
	ping at: 'auth' put: '1123456789abcdef0123456789abcdef'.
	self assertRefused: (self rawRequest: ping on: c).
	r := self request: ping on: c.
	self assert: (r at: 'ok').
	self assert: (r at: 'controlAuth') equals: 1
!
testTokenNormalization
	| c ping r |
	c := self connect.
	ping := Dictionary new at: 'cmd' put: 'ping'; yourself.
	#('0123456789ABCDEF0123456789ABCDEF' '01234567-89AbCdEf-01234567-89ABCDEF') do: [:token |
		ping at: 'auth' put: token.
		r := self rawRequest: ping on: c.
		self assert: (r at: 'ok').
		self assert: (r at: 'controlAuth') equals: 1]
!
testInvalidTokenFormats
	| c ping |
	c := self connect.
	ping := Dictionary new at: 'cmd' put: 'ping'; yourself.
	{nil. 42. ''. '0123456789abcdef0123456789abcde'. self fixtureToken, '0'.
		'0123456-789abcdef-01234567-89abcdef'. '01234567--89abcdef-01234567-89abcdef'.
		'01234567 89abcdef 01234567 89abcdef'. ' ', self fixtureToken.
		(String with: (Character value: 16rFF10)), (self fixtureToken copyFrom: 2 to: 32)} do: [:token |
		ping at: 'auth' put: token.
		self assertRefused: (self rawRequest: ping on: c)]
!
testRefusedEvalHasNoSideEffect
	| c request |
	c := self connect.
	request := self eval: 'Smalltalk at: #ControlServerTestEffect put: 42'.
	Smalltalk at: #ControlServerTestEffect put: 0.
	[self assertRefused: (self rawRequest: request on: c).
	 self assert: (Smalltalk at: #ControlServerTestEffect) equals: 0.
	 request at: 'auth' put: '1123456789abcdef0123456789abcdef'.
	 self assertRefused: (self rawRequest: request on: c).
	 self assert: (Smalltalk at: #ControlServerTestEffect) equals: 0.
	 self assert: ((self request: request on: c) at: 'ok').
	 self assert: (Smalltalk at: #ControlServerTestEffect) equals: 42]
		ensure: [Smalltalk removeKey: #ControlServerTestEffect ifAbsent: []]
!
testHandlerNeverSeesAuth
	| r |
	RemoteControl registerCommand: 'controlServerTestArguments' handler: [:request |
		Dictionary new at: 'received' put: request arguments; yourself].
	[r := self request: (Dictionary new at: 'cmd' put: 'controlServerTestArguments'; at: 'value' put: 42; yourself) on: self connect.
	 self assert: (r at: 'ok').
	 self assert: ((r at: 'received') at: 'value') equals: 42.
	 self deny: ((r at: 'received') includesKey: 'auth')]
		ensure: [RemoteControl unregisterCommand: 'controlServerTestArguments']
!
testNothingIsServedWhileTheImageStartsUp
	"A request that arrives while the image runs its startup list is answered once the list is done."
	| c r |
	SystemDictionary classPool at: #StartingUp put: true.
	[c := self connect.
	 self sendLine: (JSON render: (self authenticated: (Dictionary new at: 'cmd' put: 'ping'; at: 'id' put: 'b1'; yourself))) on: c.
	 self assert: (c receiveInto: (ByteArray new: 1) timeout: 300) isNil description: 'answered while starting up']
		ensure: [SystemDictionary classPool at: #StartingUp put: false].
	r := JSON parse: (self readLineFrom: c).
	self assert: (r at: 'ok').
	self assert: (r at: 'id') equals: 'b1'
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
	| c r1 r2 first second lf |
	c := self connect.
	first := self authenticated: ((self eval: '1+1') at: 'id' put: 1; yourself).
	second := self authenticated: ((self eval: '2+2') at: 'id' put: 2; yourself).
	lf := String with: Character lf.
	c sendAll: ((JSON render: first), lf, (JSON render: second), lf) utf8Encoded.
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
	 self sendLine: (JSON render: (self authenticated: (self eval: '(Smalltalk at: #ControlServerTestGate) wait. #slow'))) on: slow.
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
