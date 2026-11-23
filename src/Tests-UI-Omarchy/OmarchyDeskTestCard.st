Application subclass: #OmarchyDeskTestCard
	instanceVariableNames: 'view height'
	classVariableNames: ''
	package: 'Tests-UI-Omarchy'!

OmarchyDeskTestCard comment: 'A desktop card for OmarchyDeskTest (card id samaltak-test): a white view 120 points tall that can grow.'!

!OmarchyDeskTestCard methodsFor: 'accessing'!
title
	^'Test card'
!
content
	view isNil ifTrue: [view := RecordingTestView new color: Color white; yourself].
	^view
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
