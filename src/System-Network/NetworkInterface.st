Object subclass: #NetworkInterface
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Network'!

NetworkInterface comment: 'I am the abstract class of the network interfaces a NetworkStack sends and receives Ethernet frames through: the VM''s raw NIC (VmNetworkInterface) or a virtual wire between two stacks (VirtualNetworkInterface).

	macAddress		6 bytes
	send: frame count: n	a whole frame (without its checksum); false if it could not go
	receiveInto: buffer	the length of the next frame received into buffer, nil if there is none
	semaphore: aSemaphore	aSemaphore is signaled when a frame is waiting (once, until receiveInto: has answered nil)
	close, forget (after a snapshot was resumed)'!

!NetworkInterface methodsFor: 'interface'!
macAddress
	^self subclassResponsibility
!
send: aFrame count: n
	^self subclassResponsibility
!
receiveInto: aByteArray
	^self subclassResponsibility
!
semaphore: aSemaphore
	^self subclassResponsibility
!
close
!
forget
	"In an image resumed from a snapshot: let go of what belonged to the VM that saved it."
!
status
	"Counters, or nil."
	^nil
! !

NetworkInterface subclass: #VmNetworkInterface
	instanceVariableNames: 'mac semaphore index'
	classVariableNames: ''
	package: 'System-Network'!

VmNetworkInterface comment: 'The VM''s raw network interface (the nic primitives, docs/platform.md): on UEFI the firmware''s NIC; a VM on an operating system has none (open answers nil). The VM signals my Semaphore, registered as an external one, from its polls.'!

!VmNetworkInterface class methodsFor: 'instance creation'!
open
	"The VM's NIC, or nil if it has none."
	| mac |
	mac := self primOpen: (ByteArray new: 6).
	mac isNil ifTrue: [^nil].
	^self new setMac: mac
! !

!VmNetworkInterface class methodsFor: 'primitives'!
primOpen: aByteArray
	<primitive: 'nicOpen'>
	^nil
!
primSend: aByteArray count: n
	<primitive: 'nicSend'>
	^false
!
primReceive: aByteArray
	<primitive: 'nicReceive'>
	^nil
!
primSemaphore: anIndex
	<primitive: 'nicSemaphore'>
	^nil
!
primStatus
	<primitive: 'nicStatus'>
	^nil
! !

!VmNetworkInterface methodsFor: 'interface'!
setMac: aByteArray
	mac := aByteArray
!
macAddress
	^mac
!
send: aFrame count: n
	^(self class primSend: aFrame count: n) == true
!
receiveInto: aByteArray
	^self class primReceive: aByteArray
!
semaphore: aSemaphore
	self close.
	semaphore := aSemaphore.
	index := Smalltalk vm registerExternalSemaphore: aSemaphore.
	self class primSemaphore: index
!
close
	index isNil ifTrue: [^self].
	self class primSemaphore: 0.
	(Smalltalk vm externalObjects at: index) == semaphore ifTrue: [Smalltalk vm unregisterExternalSemaphore: index].
	index := nil
!
forget
	"In an image resumed from a snapshot: the new VM has no semaphore of mine; free its slot."
	(index notNil and: [(Smalltalk vm externalObjects at: index) == semaphore]) ifTrue: [Smalltalk vm unregisterExternalSemaphore: index].
	index := nil
!
status
	"{frames received. sent. sends that failed. frames waiting}"
	^self class primStatus
! !

NetworkInterface subclass: #VirtualNetworkInterface
	instanceVariableNames: 'mac peer inbox semaphore drop'
	classVariableNames: ''
	package: 'System-Network'!

VirtualNetworkInterface comment: 'A network interface in the image: what I send goes to my peer (another of me, or anything that understands deliver:), unless drop (a block on the frame) says to lose it; what is delivered to me waits in my inbox. For tests, and for stacks that talk to each other.'!

!VirtualNetworkInterface class methodsFor: 'instance creation'!
mac: aByteArray
	^self new setMac: aByteArray
!
wire: aByteArray to: anotherByteArray
	"Two interfaces, each the other's peer."
	| a b |
	a := self mac: aByteArray.
	b := self mac: anotherByteArray.
	a peer: b.
	b peer: a.
	^Array with: a with: b
! !

!VirtualNetworkInterface methodsFor: 'accessing'!
setMac: aByteArray
	mac := aByteArray.
	inbox := OrderedCollection new
!
peer
	^peer
!
peer: anObject
	peer := anObject
!
drop: aBlock
	drop := aBlock
!
inbox
	^inbox
!
deliver: aFrame
	inbox addLast: aFrame.
	semaphore isNil ifFalse: [semaphore signal]
! !

!VirtualNetworkInterface methodsFor: 'interface'!
macAddress
	^mac
!
send: aFrame count: n
	| f |
	f := aFrame copyFrom: 1 to: n.
	(peer notNil and: [drop isNil or: [(drop value: f) not]]) ifTrue: [peer deliver: f].
	^true
!
receiveInto: aByteArray
	| f |
	inbox isEmpty ifTrue: [^nil].
	f := inbox removeFirst.
	aByteArray replaceFrom: 1 to: f size with: f startingAt: 1.
	^f size
!
semaphore: aSemaphore
	semaphore := aSemaphore
! !
