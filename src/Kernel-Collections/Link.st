Object subclass: #Link
	instanceVariableNames: 'nextLink'
	classVariableNames: ''
	package: 'Kernel-Collections'!

Link comment: 'I am an element of a LinkedList; I know the next element. Process is my most important subclass: the VM links runnable and waiting processes through nextLink.'!

!Link methodsFor: 'accessing'!
nextLink
	^nextLink
!
nextLink: aLink
	nextLink := aLink
! !
