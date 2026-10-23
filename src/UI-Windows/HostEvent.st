UIEvent subclass: #HostEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Windows'!

HostEvent comment: 'I am the abstract event about the host window rather than input for a View. My subclasses are decoded from the platform''s event Arrays (UIEvent fromPlatform:) and handled by the InputDispatcher (dispatchTo:); none reaches a Window''s queue.'!

!HostEvent methodsFor: 'initialization'!
setFrom: anArray
	"Read my own slots of the platform's event Array."
! !

!HostEvent class methodsFor: 'decoding'!
decode: anArray
	^self new
		setType: self eventType time: (self timeFrom: anArray) modifiers: (self modifiersFrom: anArray);
		setFrom: anArray;
		yourself
!
eventType
	self subclassResponsibility
! !
