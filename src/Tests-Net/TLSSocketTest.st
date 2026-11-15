TestCase subclass: #TLSSocketTest
	instanceVariableNames: 'listener accepted ticks'
	classVariableNames: ''
	package: 'Tests-Net'!

TLSSocketTest comment: 'I check that a TLS handshake never blocks the VM: against a local server that accepts and never speaks it times out while other Processes keep running, terminating the connecting Process cancels it, and a server that does not speak TLS fails it. Handles are not left open.'!

!TLSSocketTest methodsFor: 'running'!
setUp
	accepted := OrderedCollection new.
	listener := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 4
!
tearDown
	listener close.
	accepted do: [:each | each close]
! !

!TLSSocketTest methodsFor: 'support'!
socketCount
	^Smalltalk vm platformHandleCounts at: #sockets
!
acceptSilently
	"Accept connections and never speak."
	self fork: [| s | [(s := listener accept) notNil] whileTrue: [accepted add: s]]
!
startTicking
	ticks := 0.
	self fork: [[(Delay forMilliseconds: 10) wait. ticks := ticks + 1] repeat] at: Processor activePriority + 1
! !

!TLSSocketTest methodsFor: 'tests'!
testStalledHandshakeTimesOut
	| before start elapsed |
	self acceptSilently.
	before := self socketCount.
	self startTicking.
	start := Time millisecondClockValue.
	self should: [TLSSocket connectTo: '127.0.0.1' port: listener localPort timeout: 500] raise: RemoteError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'timed out')].
	elapsed := Time millisecondClockValue - start.
	self assert: elapsed >= 500.
	self assert: elapsed < 3000.
	"the VM went on running other Processes meanwhile"
	self assert: ticks > 20.
	self assert: accepted size equals: 1.
	self assert: self socketCount equals: before + 1
!
testTerminatingTheConnectingProcess
	| before outcome process |
	self acceptSilently.
	before := self socketCount.
	process := self fork: [
		outcome := [TLSSocket connectTo: '127.0.0.1' port: listener localPort timeout: 10000] on: RemoteError do: [:e | e messageText]].
	self assert: (self waitFor: [accepted size = 1]).
	(Delay forMilliseconds: 50) wait.
	self assert: process isTerminated not.
	process terminate.
	self assert: process isTerminated.
	self assert: outcome isNil.
	self assert: (self waitFor: [self socketCount = (before + 1)])
!
testHandshakeWithAPlainHTTPServer
	| server |
	server := HTTPTestServer on: [:request | HTTPTestServer response: 200 body: 'hi'].
	[self should: [TLSSocket connectTo: '127.0.0.1' port: (server url copyAfterLast: $:) asInteger timeout: 1000] raise: RemoteError]
		ensure: [server stop]
!
testHandshakeWithAServerThatAnswersPlainText
	| start |
	self fork: [| s |
		s := listener accept.
		accepted add: s.
		s sendAll: 'HTTP/1.1 400 Bad Request', String crlf, String crlf].
	start := Time millisecondClockValue.
	self should: [TLSSocket connectTo: '127.0.0.1' port: listener localPort timeout: 5000] raise: RemoteError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'cannot connect to 127.0.0.1:', listener localPort printString, ': TLS handshake: ').
		self deny: (e messageText includesSubstring: 'timed out')].
	self assert: Time millisecondClockValue - start < 3000
! !
