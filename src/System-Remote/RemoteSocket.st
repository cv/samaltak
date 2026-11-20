Object subclass: #RemoteSocket
	instanceVariableNames: 'handle readSemaphore writeSemaphore readIndex writeIndex sharesRead'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteSocket comment: 'I am a TCP socket over the platform''s socket primitives (docs/platform.md), or over the image''s TCP/IP stack where the VM gives raw frames instead (NetworkStack active: UEFI; its handles are negative), with blocking connect, accept, receive and send that wait on my read and write Semaphores instead of spinning: the platform signals a Semaphore once when the socket becomes ready and re-arms it when a primitive answers "would block". No primitive blocks the VM: host names are looked up by a thread of the platform (resolve:), connecting tries each address in turn, and the whole connect gives up after connectTimeout. Terminating the Process that connects cancels it.

My Semaphores occupy two slots of the VM''s external objects (Smalltalk vm registerExternalSemaphore:), freed by close. A socket that is garbage collected unclosed is closed by the finalization process (WeakRegistry).'!

!RemoteSocket methodsFor: 'initialization'!
setHandle: anInteger
	handle := anInteger.
	readSemaphore := Semaphore new.
	writeSemaphore := Semaphore new.
	readIndex := Smalltalk vm registerExternalSemaphore: readSemaphore.
	writeIndex := Smalltalk vm registerExternalSemaphore: writeSemaphore.
	self class primSemaphore: handle read: readIndex write: writeIndex.
	self registerForFinalization
!
setHandle: anInteger readSemaphore: aSemaphore index: anIndex
	"Signal aSemaphore (registered at anIndex by my owner, possibly shared with other sockets) when I become readable."
	handle := anInteger.
	readSemaphore := aSemaphore.
	readIndex := anIndex.
	sharesRead := true.
	writeSemaphore := Semaphore new.
	writeIndex := Smalltalk vm registerExternalSemaphore: writeSemaphore.
	self class primSemaphore: handle read: readIndex write: writeIndex.
	self registerForFinalization
!
registerForFinalization
	"If I am collected unclosed, a copy of me (same handle and Semaphores) closes the socket."
	WeakRegistry default add: self executor: self shallowCopy
! !

!RemoteSocket methodsFor: 'accessing'!
handle
	^handle
!
isOpen
	^handle notNil
!
localPort
	^self class primLocalPort: handle
! !

!RemoteSocket methodsFor: 'operations'!
accept
	"Wait for the next connection on a listening socket; answer a new RemoteSocket, or nil once I am closed."
	| client |
	[handle isNil ifTrue: [^nil].
	 client := self class primAccept: handle.
	 client == false ifTrue: [^nil].
	 client isNil] whileTrue: [readSemaphore wait].
	^self class onHandle: client
!
readSemaphore: aSemaphore index: anIndex
	"Signal aSemaphore (registered at anIndex by my owner, possibly shared) from now on when I become readable."
	handle isNil ifTrue: [^self].
	sharesRead == true ifFalse: [self class unregister: readSemaphore at: readIndex].
	readSemaphore := aSemaphore.
	readIndex := anIndex.
	sharesRead := true.
	self class primSemaphore: handle read: readIndex write: writeIndex
!
acceptNow
	"A listening socket: answer the handle of a pending connection, or nil (none pending, or I am closed). Never waits."
	| client |
	handle isNil ifTrue: [^nil].
	client := self class primAccept: handle.
	(client isNil or: [client == false]) ifTrue: [^nil].
	^client
!
receiveNowInto: aByteArray
	"Answer the number of bytes stored at the start of aByteArray, 0 at end of stream or once I am closed, or nil if nothing arrived (never waits)."
	| count |
	handle isNil ifTrue: [^0].
	count := self class primRecv: handle into: aByteArray start: 1 count: aByteArray size.
	count isNil ifTrue: [^nil].
	^count max: 0
!
receiveInto: aByteArray
	"Wait for data; answer the number of bytes stored at the start of aByteArray, 0 at end of stream or once I am closed."
	^self receiveInto: aByteArray timeout: nil
!
receiveInto: aByteArray timeout: milliseconds
	"Like receiveInto:, but answer nil if nothing arrived within milliseconds (nil: wait forever)."
	| count |
	[handle isNil ifTrue: [^0].
	 count := self class primRecv: handle into: aByteArray start: 1 count: aByteArray size.
	 count isNil] whileTrue: [
		milliseconds isNil
			ifTrue: [readSemaphore wait]
			ifFalse: [(readSemaphore waitTimeoutMSecs: milliseconds) ifTrue: [^nil]]].
	^count max: 0
!
sendAll: bytes
	"Send all of bytes (a ByteArray or ByteString), waiting while the socket is full. Answer false if the connection is gone."
	| start sent |
	start := 1.
	[start <= bytes size] whileTrue: [
		handle isNil ifTrue: [^false].
		sent := self class primSend: handle from: bytes start: start count: bytes size - start + 1.
		sent isNil
			ifTrue: [writeSemaphore wait]
			ifFalse: [
				sent < 0 ifTrue: [^false].
				start := start + sent]].
	^true
!
close
	"Close the socket and wake any process waiting on it."
	| h |
	h := handle.
	h isNil ifTrue: [^self].
	handle := nil.
	WeakRegistry default remove: self.
	self class primClose: h.
	sharesRead == true ifFalse: [self class unregister: readSemaphore at: readIndex].
	self class unregister: writeSemaphore at: writeIndex.
	readSemaphore signal.
	writeSemaphore signal
!
forget
	"In an image resumed from a snapshot: my handle belonged to the VM that saved it (it may name a new socket now), so drop it without closing and free my Semaphore slots."
	handle isNil ifTrue: [^self].
	handle := nil.
	WeakRegistry default remove: self.
	sharesRead == true ifFalse: [self class unregister: readSemaphore at: readIndex].
	self class unregister: writeSemaphore at: writeIndex
!
finalize
	"I am the executor of a collected socket."
	self close
! !

!RemoteSocket methodsFor: 'private'!
awaitConnectionUntil: deadline
	"Wait until my connect is done or deadline (a millisecondClockValue) passes; answer nil once connected, else why not."
	| connected |
	[handle isNil ifTrue: [^'closed'].
	 connected := self class primConnected: handle.
	 connected == false ifTrue: [^self class lastError].
	 connected isNil] whileTrue: [
		(writeSemaphore waitTimeoutMSecs: deadline - Time millisecondClockValue) ifTrue: [^'timed out']].
	^nil
! !

!RemoteSocket methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a RemoteSocket'.
	handle isNil ifTrue: [^aStream nextPutAll: ' (closed)'].
	aStream nextPutAll: ' #'; print: handle
! !

!RemoteSocket class methodsFor: 'instance creation'!
onHandle: anInteger
	^self new setHandle: anInteger
!
onHandle: anInteger readSemaphore: aSemaphore index: anIndex
	^self new setHandle: anInteger readSemaphore: aSemaphore index: anIndex
!
listenOn: port host: hostString backlog: anInteger readSemaphore: aSemaphore index: anIndex
	"Like listenOn:host:backlog:, signalling aSemaphore (registered at anIndex) when a connection is pending."
	| h |
	h := self primListen: hostString port: port backlog: anInteger.
	h isNil ifTrue: [^RemoteError signal: 'cannot listen on ', hostString, ':', port printString, ': ', self lastError].
	^self onHandle: h readSemaphore: aSemaphore index: anIndex
!
listenOn: port host: hostString backlog: anInteger
	"Answer a socket listening on hostString:port (port 0 picks a free port; see localPort)."
	| h |
	h := self primListen: hostString port: port backlog: anInteger.
	h isNil ifTrue: [^RemoteError signal: 'cannot listen on ', hostString, ':', port printString, ': ', self lastError].
	^self onHandle: h
!
connectTo: hostString port: port
	^self connectTo: hostString port: port timeout: self connectTimeout
!
connectTo: hostString port: port timeout: milliseconds
	"Connect to port of the host named (or numbered) hostString, trying its addresses in turn; answer or fail within milliseconds."
	^self connectTo: hostString port: port until: Time millisecondClockValue + milliseconds
!
connectTo: hostString port: port until: deadline
	"Look up, then try each address with an equal share of the time left before deadline (a millisecondClockValue); the last gets all of it."
	| addresses reason h socket now |
	addresses := self resolve: hostString until: deadline.
	addresses withIndexDo: [:each :i |
		h := self primConnect: each port: port.
		h isNil
			ifTrue: [reason := self lastError]
			ifFalse: [
				socket := self onHandle: h.
				now := Time millisecondClockValue.
				reason := [socket awaitConnectionUntil: now + ((deadline - now max: 0) // (addresses size - i + 1))] ifCurtailed: [socket close].
				reason isNil ifTrue: [^socket].
				socket close]].
	^RemoteError signal: 'cannot connect to ', hostString, ':', port printString, ': ', reason
!
connectTimeout
	"Milliseconds a whole connect (the lookup, the connect, a TLS handshake) may take."
	^10000
! !

!RemoteSocket class methodsFor: 'host names'!
resolve: hostString
	^self resolve: hostString timeout: self connectTimeout
!
resolve: hostString timeout: milliseconds
	"Answer the numeric addresses (Strings) of the host named hostString, looked up by the platform without blocking the VM."
	^self resolve: hostString until: Time millisecondClockValue + milliseconds
!
resolve: hostString until: deadline
	| h socket out buffer n lines |
	h := self primResolve: hostString.
	h isNil ifTrue: [^RemoteError signal: 'cannot resolve ', hostString, ': ', self lastError].
	socket := RemoteSocket onHandle: h.
	out := WriteStream on: (String new: 64).
	buffer := ByteArray new: 1024.
	[[(n := socket receiveInto: buffer timeout: (deadline - Time millisecondClockValue max: 0)) = 0] whileFalse: [
		n isNil ifTrue: [^RemoteError signal: 'cannot resolve ', hostString, ': timed out'].
		out nextPutAll: (buffer copyFrom: 1 to: n) asString]] ensure: [socket close].
	lines := out contents lines reject: [:each | each isEmpty].
	(lines notEmpty and: [lines first beginsWith: '!!']) ifTrue: [
		^RemoteError signal: 'cannot resolve ', hostString, ': ', (lines first allButFirst)].
	lines isEmpty ifTrue: [^RemoteError signal: 'cannot resolve ', hostString, ': no address'].
	^lines asArray
! !

!RemoteSocket class methodsFor: 'external semaphores'!
unregister: aSemaphore at: index
	"Free the external semaphore slot index unless it holds another Semaphore by now (an executor's copy of me may hold a stale index)."
	(index notNil and: [(Smalltalk vm externalObjects at: index) == aSemaphore])
		ifTrue: [Smalltalk vm unregisterExternalSemaphore: index]
! !

!RemoteSocket class methodsFor: 'sockets'!
lastError
	^NetworkStack takeLastError ifNil: [self platformLastError]
!
primListen: host port: port backlog: backlog
	^NetworkStack active
		ifNil: [self platformListen: host port: port backlog: backlog]
		ifNotNil: [:stack | stack listen: host port: port backlog: backlog]
!
primConnect: address port: port
	"Start connecting to the numeric address; answer the handle at once (see primConnected:), nil on failure."
	^NetworkStack active
		ifNil: [self platformConnect: address port: port]
		ifNotNil: [:stack | stack connect: address port: port]
!
primResolve: hostName
	"Answer a handle that reads as the numeric addresses of hostName, a line each, or as one line of !! and the error; nil on failure."
	^NetworkStack active
		ifNil: [self platformResolve: hostName]
		ifNotNil: [:stack | stack resolve: hostName]
!
primConnected: aHandle
	"Answer true once connected, nil while connecting (the write Semaphore is armed), false on failure."
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNil: [false] ifNotNil: [:s | s connected]].
	^self platformConnected: aHandle
!
primAccept: aHandle
	"Answer a handle, nil if none is pending, false on failure."
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNil: [false] ifNotNil: [:s | s accept]].
	^self platformAccept: aHandle
!
primRecv: aHandle into: bytes start: start count: count
	"Answer the byte count, 0 at end of stream, nil if it would block, -1 on failure."
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNil: [-1] ifNotNil: [:s | s receiveInto: bytes start: start count: count]].
	^self platformRecv: aHandle into: bytes start: start count: count
!
primSend: aHandle from: bytes start: start count: count
	"Answer the byte count sent, nil if it would block, -1 on failure."
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNil: [-1] ifNotNil: [:s | s send: bytes start: start count: count]].
	^self platformSend: aHandle from: bytes start: start count: count
!
primClose: aHandle
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNotNil: [:s | s close]].
	^self platformClose: aHandle
!
primSemaphore: aHandle read: readIndex write: writeIndex
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNotNil: [:s | s semaphoresRead: readIndex write: writeIndex]].
	^self platformSemaphore: aHandle read: readIndex write: writeIndex
!
primLocalPort: aHandle
	aHandle < 0 ifTrue: [^(NetSocket at: aHandle) ifNotNil: [:s | s localPort]].
	^self platformLocalPort: aHandle
! !

!RemoteSocket class methodsFor: 'primitives'!
platformLastError
	<primitive: 'platformLastError'>
	^'unknown error'
!
platformListen: host port: port backlog: backlog
	<primitive: 'socketListen'>
	^nil
!
platformConnect: address port: port
	<primitive: 'socketConnect'>
	^nil
!
platformConnected: aHandle
	<primitive: 'socketConnected'>
	^false
!
platformResolve: hostName
	<primitive: 'socketResolve'>
	^nil
!
platformAccept: aHandle
	<primitive: 'socketAccept'>
	^false
!
platformRecv: aHandle into: bytes start: start count: count
	<primitive: 'socketRecv'>
	^-1
!
platformSend: aHandle from: bytes start: start count: count
	<primitive: 'socketSend'>
	^-1
!
platformClose: aHandle
	<primitive: 'socketClose'>
	^nil
!
platformSemaphore: aHandle read: readIndex write: writeIndex
	<primitive: 'socketSemaphore'>
	^RemoteError signal: 'socketSemaphore failed: ', self lastError
!
platformLocalPort: aHandle
	<primitive: 'socketLocalPort'>
	^nil
! !
