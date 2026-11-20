Object subclass: #NetSocket
	instanceVariableNames: 'handle stack connection lookup text position readIndex writeIndex readArmed writeArmed'
	classVariableNames: 'NextHandle Sockets'
	package: 'System-Network'!

NetSocket comment: 'A socket of a NetworkStack as RemoteSocket knows the platform''s: a handle (negative, so it is never the platform''s), a TcpConnection (listening or not) or a DnsLookup (it reads as the lookup''s text), and the external Semaphores RemoteSocket registered, signaled as the platform does: a socket with a read (write) semaphore is armed until it becomes readable or acceptable (writable), then its semaphore is signaled once; an operation that would block re-arms it. The stack signals (update) after each of its polls. Every operation holds the stack''s lock.

Answers as the socket primitives'' (docs/platform.md): connected true, nil (being made), false (failed); accept a handle, nil (none pending); receive a count, 0 at the end, nil (would block), -1 (failed); send a count, nil (would block), -1 (failed). Why something failed: NetworkStack takeLastError.'!

!NetSocket class methodsFor: 'handles'!
at: aHandle
	"The socket of aHandle, or nil."
	^(Sockets ifNil: [^nil]) at: aHandle ifAbsent: [nil]
!
register: aSocket
	Sockets isNil ifTrue: [Sockets := Dictionary new].
	NextHandle := (NextHandle ifNil: [0]) - 1.
	Sockets at: NextHandle put: aSocket.
	^NextHandle
!
unregister: aHandle
	Sockets isNil ifFalse: [Sockets removeKey: aHandle ifAbsent: []]
!
forgetAll
	"In an image resumed from a snapshot: the sockets died with the stacks of the VM that saved it."
	Sockets := nil
! !

!NetSocket class methodsFor: 'instance creation'!
on: aStack connection: aTcpConnection
	^self new setStack: aStack connection: aTcpConnection lookup: nil
!
on: aStack lookup: aDnsLookup
	^self new setStack: aStack connection: nil lookup: aDnsLookup
! !

!NetSocket methodsFor: 'initialization'!
setStack: aStack connection: aTcpConnection lookup: aDnsLookup
	stack := aStack.
	connection := aTcpConnection.
	lookup := aDnsLookup.
	readArmed := writeArmed := false.
	position := 0.
	handle := self class register: self.
	stack addSocket: self
! !

!NetSocket methodsFor: 'accessing'!
handle
	^handle
!
connection
	^connection
!
lookup
	^lookup
!
localPort
	^connection isNil ifTrue: [nil] ifFalse: [connection localPort]
! !

!NetSocket methodsFor: 'operations'!
connected
	"true once connected, nil while connecting (the write semaphore armed), false if it failed."
	^stack critical: [| r |
		connection isNil
			ifTrue: [false]
			ifFalse: [
				r := connection isConnected.
				r isNil ifTrue: [writeArmed := true].
				r == false ifTrue: [NetworkStack noteError: 'connect: ', connection failureText].
				r]]
!
accept
	"The handle of a connection established on a listening socket, nil if none is pending."
	^stack critical: [| c |
		readArmed := true.
		c := (connection notNil and: [connection isListening]) ifTrue: [connection accept].
		c isNil ifTrue: [nil] ifFalse: [(self class on: stack connection: c) handle]]
!
receiveInto: bytes start: start count: count
	^stack critical: [| r |
		readArmed := true.
		lookup notNil
			ifTrue: [self readLookupInto: bytes start: start count: count]
			ifFalse: [
				r := connection readInto: bytes start: start count: count.
				r = -2 ifTrue: [NetworkStack noteError: 'recv: ', connection failureText. -1] ifFalse: [
					r = -1 ifTrue: [nil] ifFalse: [r]]]]
!
readLookupInto: bytes start: start count: count
	| k |
	lookup isDone ifFalse: [^nil].
	text isNil ifTrue: [text := lookup text asByteArray].
	k := text size - position min: count.
	bytes replaceFrom: start to: start + k - 1 with: text startingAt: position + 1.
	position := position + k.
	^k
!
send: bytes start: start count: count
	^stack critical: [| r |
		connection isNil
			ifTrue: [-1]
			ifFalse: [
				r := connection write: bytes start: start count: count.
				(r = -1 or: [r >= 0 and: [r < count]]) ifTrue: [writeArmed := true].
				r = -2
					ifTrue: [
						NetworkStack noteError: 'send: ', connection failureText.
						-1]
					ifFalse: [r = -1 ifTrue: [nil] ifFalse: [r]]]]
!
close
	stack critical: [
		connection isNil ifFalse: [connection close].
		lookup isNil ifFalse: [stack resolver free: lookup].
		stack removeSocket: self].
	self class unregister: handle
!
semaphoresRead: r write: w
	stack critical: [
		readIndex := r.
		writeIndex := w.
		readArmed := true.
		writeArmed := false].
	stack wake
! !

!NetSocket methodsFor: 'readiness'!
isReadable
	lookup notNil ifTrue: [^lookup isDone].
	^connection isReadable
!
isWritable
	lookup notNil ifTrue: [^false].
	^connection isWritable
!
update
	"Signal what became ready (my stack's lock held)."
	(readArmed and: [readIndex notNil and: [readIndex ~= 0 and: [self isReadable]]]) ifTrue: [
		readArmed := false.
		self signal: readIndex].
	(writeArmed and: [writeIndex notNil and: [writeIndex ~= 0 and: [self isWritable]]]) ifTrue: [
		writeArmed := false.
		self signal: writeIndex]
!
signal: anIndex
	| table s |
	table := Smalltalk vm externalObjects.
	anIndex <= table size ifFalse: [^self].
	s := table at: anIndex.
	s isNil ifFalse: [s signal]
! !
