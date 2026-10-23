Error subclass: #JSONError
	instanceVariableNames: 'position'
	classVariableNames: ''
	package: 'System-Remote'!

JSONError comment: 'I am signaled by JSONReader for malformed input (position: 1-based index where it went wrong) and by JSONWriter for values it cannot represent.'!

!JSONError methodsFor: 'accessing'!
position
	^position
!
position: anInteger
	position := anInteger
! !
