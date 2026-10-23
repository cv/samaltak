TestCase subclass: #RemoteSocketFinalizationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteSocketFinalizationTest comment: 'I check that a RemoteSocket dropped unclosed is closed when it is garbage collected: its platform handle and its external Semaphore slots are freed.'!

!RemoteSocketFinalizationTest methodsFor: 'support'!
sockets
	^Smalltalk vm platformHandleCounts at: #sockets
!
usedSemaphoreSlots
	^Smalltalk vm externalObjects count: [:each | each notNil]
! !

!RemoteSocketFinalizationTest methodsFor: 'tests'!
testDroppedSocketIsClosed
	| sockets slots socket |
	sockets := self sockets.
	slots := self usedSemaphoreSlots.
	socket := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 1.
	self assert: self sockets equals: sockets + 1.
	self assert: self usedSemaphoreSlots equals: slots + 2.
	socket := nil.
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [self sockets = sockets]).
	self assert: self usedSemaphoreSlots equals: slots
!
testClosedSocketIsUnregistered
	| socket |
	socket := RemoteSocket listenOn: 0 host: '127.0.0.1' backlog: 1.
	self assert: (WeakRegistry default includes: socket).
	socket close.
	self deny: (WeakRegistry default includes: socket)
! !
