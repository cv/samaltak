Container subclass: #Stack
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

Stack comment: 'I give each visible child my inner bounds, so they are drawn on top of each other (the last on top). Use me for overlays and for switching between alternative contents (show one child, hide the others).'!

!Stack methodsFor: 'layout'!
layout
	| inner |
	inner := self innerBounds.
	self visibleChildren do: [:each | each bounds: inner]
! !

!Stack class methodsFor: 'instance creation'!
with: aCollection
	^self new addAll: aCollection; yourself
! !
