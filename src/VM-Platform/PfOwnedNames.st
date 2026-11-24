VMStruct subclass: #PfOwnedNames
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfOwnedNames comment: 'One owned native name vector, identified by a nonrecycled process ticket, never by its address.'!

!PfOwnedNames class methodsFor: 'declaring'!
fields
	^#((ticket uint64_t) (names 'char **') (count uint32_t))
! !
