ProtoObject subclass: #KernelTestProxy
	instanceVariableNames: 'target log'
	classVariableNames: ''
	package: 'Tests-Kernel'!

KernelTestProxy comment: 'I forward every message I do not understand to target and log its selector; used by MessageNotUnderstoodTest.'!

!KernelTestProxy methodsFor: 'accessing'!
setTarget: anObject
	target := anObject.
	log := OrderedCollection new
!
proxyLog
	^log
! !

!KernelTestProxy methodsFor: 'forwarding'!
doesNotUnderstand: aMessage
	log add: aMessage selector.
	^aMessage sendTo: target
! !

!KernelTestProxy class methodsFor: 'instance creation'!
on: anObject
	^self basicNew setTarget: anObject
! !
