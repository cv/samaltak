Object subclass: #RfbTestInput
	instanceVariableNames: 'events'
	classVariableNames: ''
	package: 'Tests-Remote'!

RfbTestInput comment: 'I record what an RFB connection gives its input handler, for RfbTest.'!

!RfbTestInput methodsFor: 'accessing'!
events: aCollection
	events := aCollection
! !

!RfbTestInput methodsFor: 'input'!
key: keysym down: aBoolean
	events add: (Array with: #key with: keysym with: aBoolean)
!
pointer: mask at: aPoint
	events add: (Array with: #pointer with: mask with: aPoint)
!
cutText: aString
	events add: (Array with: #cut with: aString)
!
connectionClosed
	events add: #(#closed)
! !
