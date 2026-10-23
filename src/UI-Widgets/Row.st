LinearBox subclass: #Row
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

Row comment: 'I lay out my children left to right (see LinearBox).

	Row with: {list1 flex: 1. list2 fixed: 120}'!

!Row methodsFor: 'axis'!
isHorizontal
	^true
! !
