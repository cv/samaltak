Application subclass: #OmarchyDeskTestCard
	instanceVariableNames: 'view height clicks'
	classVariableNames: ''
	package: 'Tests-UI-Omarchy'!

OmarchyDeskTestCard comment: 'A desktop card for OmarchyDeskTest (card id samaltak-test): an OmarchyDeskTestView 300 points wide and 120 tall that can grow, counting its clicks.'!

!OmarchyDeskTestCard methodsFor: 'accessing'!
title
	^'Test card'
!
content
	view isNil ifTrue: [
		view := OmarchyDeskTestView new.
		view onActivate: [clicks := self clicks + 1]].
	^view
!
clicks
	^clicks ifNil: [0]
!
height
	^height ifNil: [120]
!
extent
	^300 @ self height
!
height: points
	height := points
! !

!OmarchyDeskTestCard class methodsFor: 'desktop'!
cardId
	^'samaltak-test'
! !
