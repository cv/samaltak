!Object methodsFor: '*UI-Windows-testing'!
isView
	^false
!
isWindow
	^false
!
isUIEvent
	^false
! !

!Object methodsFor: '*UI-Windows-animation'!
interpolateTo: anObject at: e
	"Animation: the value e (0..1) of the way from me to anObject. Objects that cannot be tweened stay until the end."
	^e < 1 ifTrue: [self] ifFalse: [anObject]
! !
