TestCase subclass: #RemoteSocketConnectTest
	instanceVariableNames: 'listener sockets'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteSocketConnectTest comment: 'I check looking up host names and connecting, neither of which blocks the VM: a lookup answers numeric addresses or a RemoteError, a connection to a closed port fails at once, and no handle is left open.'!

!RemoteSocketConnectTest methodsFor: 'running'!
tearDown
	listener isNil ifFalse: [listener close]
! !

!RemoteSocketConnectTest methodsFor: 'support'!
socketCount
	^Smalltalk vm platformHandleCounts at: #sockets
!
closedPort
	"A local port nobody listens on."
	| s port |
	s := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 1.
	port := s localPort.
	s close.
	^port
! !

!RemoteSocketConnectTest methodsFor: 'tests'!
testResolveLocalhost
	| before addresses |
	before := self socketCount.
	addresses := RemoteSocket resolve: 'localhost'.
	self deny: addresses isEmpty.
	self assert: (addresses allSatisfy: [:each | each = '::1' or: [each beginsWith: '127.']]).
	self assert: self socketCount equals: before
!
testResolveNumericAddress
	self assert: (RemoteSocket resolve: '127.0.0.1') equals: #('127.0.0.1')
!
testResolveInvalidName
	| before |
	before := self socketCount.
	self should: [RemoteSocket resolve: 'no-such-host.invalid'] raise: RemoteError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'cannot resolve no-such-host.invalid: ')].
	self assert: self socketCount equals: before
!
testConnectPrimitiveTakesNumericAddressesOnly
	self assert: (RemoteSocket primConnect: 'localhost' port: self closedPort) isNil
!
testConnectToAClosedPortFailsPromptly
	| port before start |
	port := self closedPort.
	before := self socketCount.
	start := Time millisecondClockValue.
	self should: [RemoteSocket connectTo: '127.0.0.1' port: port] raise: RemoteError withExceptionDo: [:e |
		self assert: (e messageText beginsWith: 'cannot connect to 127.0.0.1:', port printString, ': ')].
	self should: [RemoteSocket connectTo: 'localhost' port: port] raise: RemoteError.
	self assert: Time millisecondClockValue - start < 2000.
	self assert: self socketCount equals: before
!
testConnectByName
	| client server bytes |
	listener := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 1.
	client := RemoteSocket connectTo: 'localhost' port: listener localPort.
	[server := listener accept.
	 self assert: (client sendAll: 'ping').
	 bytes := ByteArray new: 4.
	 self assert: (server receiveInto: bytes timeout: 2000) equals: 4.
	 self assert: bytes asString equals: 'ping'] ensure: [
		client close.
		server isNil ifFalse: [server close]]
! !
