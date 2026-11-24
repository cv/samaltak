!FFIPairedBench class methodsFor: 'hosted socket and PTY workloads'!
socketLocalPort
	| socket listener port |
	socket := RemoteSocket.
	listener := socket platformListen: '127.0.0.1' port: 0 backlog: 2.
	listener isNil ifTrue: [self error: 'loopback listen failed'].
	[
		port := socket platformLocalPort: listener.
		self case: 'socket-local-port' repeat: nil
			run: [:n | | sum | sum := 0. n timesRepeat: [sum := sum + (socket platformLocalPort: listener)]. {sum. n}]
			reset: []
			expect: [:answer | answer first = (port * answer second)]
	] ensure: [socket platformClose: listener]
!
socketAcceptPending
	| socket listener |
	socket := RemoteSocket.
	listener := socket platformListen: '127.0.0.1' port: 0 backlog: 2.
	listener isNil ifTrue: [self error: 'loopback listen failed'].
	[
		self case: 'socket-accept-pending' repeat: nil
			run: [:n | | pending | pending := 0. n timesRepeat: [(socket platformAccept: listener) isNil ifTrue: [pending := pending + 1]]. {pending. n}]
			reset: []
			expect: [:answer | answer first = answer second]
	] ensure: [socket platformClose: listener]
!
socketSendSize: count label: label
	| socket listener client accepted payload received |
	socket := RemoteSocket.
	listener := socket listenOn: 0 host: '127.0.0.1' backlog: 2.
	[
		client := socket connectTo: '127.0.0.1' port: listener localPort.
		accepted := listener accept.
		payload := ByteArray new: count + 2.
		payload atAllPut: 65.
		received := ByteArray new: count.
		self case: label repeat: nil
			run: [:n |
				| ok |
				ok := 0.
				n timesRepeat: [
					(socket platformSend: client handle from: payload start: 2 count: count) = count
						ifFalse: [self error: 'unexpected transmit backpressure'].
					self socketDrain: accepted into: received.
					ok := ok + (received at: count)].
				{ok. n}]
			reset: []
			expect: [:answer | answer first = (65 * answer second)]
	] ensure: [
		accepted ifNotNil: [accepted close].
		client ifNotNil: [client close].
		listener close]
!
socketDrain: peer into: buffer
	| start got |
	start := 1.
	[start <= buffer size] whileTrue: [
		got := RemoteSocket platformRecv: peer handle into: buffer start: start count: buffer size - start + 1.
		got
			ifNil: [
				((peer instVarNamed: 'readSemaphore') waitTimeoutMSecs: 1000)
					ifTrue: [self error: 'loopback transport timed out']]
			ifNotNil: [
				got <= 0 ifTrue: [self error: 'loopback transport closed'].
				start := start + got]]
!
ptyReadPending
	| term terminal h ready deadline |
	term := PseudoTerminal.
	terminal := term spawn: #('/bin/sh' '-c' 'printf X; read line') environment: nil directory: nil rows: 24 columns: 80.
	[
		h := terminal instVarNamed: 'handle'.
		ready := ByteArray new: 1.
		deadline := Time millisecondClockValue + 3000.
		[(terminal readInto: ready) = 1 or: [Time millisecondClockValue > deadline]]
			whileFalse: [terminal semaphore waitTimeoutMSecs: 10].
		ready first = $X asciiValue ifFalse: [self error: 'PTY child not ready'].
		self case: 'pty-read-pending' repeat: nil
			run: [:n | | pending | pending := 0. n timesRepeat: [(term primRead: h into: ready start: 1 count: 1) isNil ifTrue: [pending := pending + 1]]. {pending. n}]
			reset: []
			expect: [:answer | answer first = answer second]
	] ensure: [terminal close]
! !
