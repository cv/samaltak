LinearBox subclass: #Column
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

Column comment: 'I lay out my children top to bottom (see LinearBox).

	Column with: {PaneHeader new title: ''Packages''; fixed: 20. list}'!

!Column methodsFor: 'axis'!
isHorizontal
	^false
! !
