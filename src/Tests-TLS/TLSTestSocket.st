Object subclass: #TLSTestSocket
	instanceVariableNames: 'incoming sent open chunkSize responder stalls'
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSTestSocket comment: 'I am a connected socket for TLS tests, without a network: what I receive is what deliver: gave me (or what my responder, a block given each send and me, delivers), in pieces of at most chunkSize bytes if that is set; sent answers everything sent. Once all is received, receiving answers 0, the end of the stream, unless I stall: then it waits out its timeout and answers nil.'!

!TLSTestSocket methodsFor: 'initialization'!
initialize
	incoming := ByteArray new.
	sent := WriteStream on: (ByteArray new: 1024).
	open := true.
	stalls := false
! !

!TLSTestSocket methodsFor: 'scripting'!
deliver: bytes
	incoming := incoming, bytes asByteArray
!
chunkSize: anInteger
	chunkSize := anInteger
!
responder: aBlock
	"aBlock value: bytesSent value: self, after each send."
	responder := aBlock
!
stall
	stalls := true
!
sent
	^sent contents
!
clearSent
	sent := WriteStream on: (ByteArray new: 1024)
! !

!TLSTestSocket methodsFor: 'socket'!
sendAll: bytes
	open ifFalse: [^false].
	sent nextPutAll: bytes asByteArray.
	responder isNil ifFalse: [responder value: bytes asByteArray value: self].
	^true
!
receiveInto: aByteArray
	^self receiveInto: aByteArray timeout: nil
!
receiveInto: aByteArray timeout: milliseconds
	| count |
	open ifFalse: [^0].
	incoming isEmpty ifTrue: [
		stalls ifFalse: [^0].
		(Delay forMilliseconds: (milliseconds ifNil: [60000])) wait.
		^nil].
	count := aByteArray size min: incoming size.
	chunkSize isNil ifFalse: [count := count min: chunkSize].
	aByteArray replaceFrom: 1 to: count with: incoming startingAt: 1.
	incoming := incoming copyFrom: count + 1 to: incoming size.
	^count
!
isOpen
	^open
!
close
	open := false
!
forget
	open := false
! !
