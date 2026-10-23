PositionableStream subclass: #ReadStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Streams'!

ReadStream comment: 'I read the elements of a SequenceableCollection one after another.'!

!ReadStream methodsFor: 'accessing'!
nextPut: anObject
	^self shouldNotImplement
! !
