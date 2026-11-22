Object subclass: #RfbTestSocket
	instanceVariableNames: 'incoming sent open responder'
	classVariableNames: ''
	package: 'Tests-Remote'!

RfbTestSocket comment: 'I am a connected socket for RFB tests, without a network: what I receive is what deliver: gave me (or what my responder, a block given each send and me, delivers); sent answers everything sent. Once all is received, receiving answers 0, the end of the stream.'!

!RfbTestSocket methodsFor: 'initialization'!
initialize
	incoming := ByteArray new.
	sent := WriteStream on: (ByteArray new: 1024).
	open := true
! !

!RfbTestSocket methodsFor: 'scripting'!
deliver: bytes
	incoming := incoming, bytes asByteArray
!
responder: aBlock
	responder := aBlock
!
sent
	^sent contents
!
clearSent
	sent := WriteStream on: (ByteArray new: 1024)
!
takeSent
	| s |
	s := self sent.
	self clearSent.
	^s
! !

!RfbTestSocket methodsFor: 'socket'!
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
	incoming isEmpty ifTrue: [^0].
	count := aByteArray size min: incoming size.
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
