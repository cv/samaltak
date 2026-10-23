!Rectangle methodsFor: '*UI-Windows-animation'!
interpolateTo: aRectangle at: e
	^Rectangle
		origin: (origin interpolateTo: aRectangle origin at: e)
		corner: (corner interpolateTo: aRectangle corner at: e)
! !
