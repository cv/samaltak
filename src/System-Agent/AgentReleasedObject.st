Object subclass: #AgentReleasedObject
	instanceVariableNames: 'box'
	classVariableNames: ''
	package: 'System-Agent'!

AgentReleasedObject comment: 'I hold an object of an AgentConversation''s object table weakly: a picture older than the newest ones the conversation keeps (AgentConversation>>releasePictures). value is the object while something else keeps it alive, then nil.'!

!AgentReleasedObject methodsFor: 'accessing'!
value
	^box first
!
setValue: anObject
	box := WeakArray new: 1.
	box at: 1 put: anObject
! !

!AgentReleasedObject class methodsFor: 'instance creation'!
on: anObject
	^self new setValue: anObject
! !
