!Object methodsFor: '*VM-Lowtalk'!
caseOf: anArrayOfAssociations
	"Lowtalk's switch: evaluate the value block of the first association whose key block answers something equal to me."
	^self caseOf: anArrayOfAssociations otherwise: [self error: 'no case for ' , self printString]
!
caseOf: anArrayOfAssociations otherwise: aBlock
	anArrayOfAssociations do: [:each | each key value = self ifTrue: [^each value value]].
	^aBlock value
! !
