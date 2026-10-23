Widget subclass: #ProgressStripe
	instanceVariableNames: 'active fraction phase animation'
	classVariableNames: ''
	package: 'UI-Widgets'!

ProgressStripe comment: 'I am the Blue Book busy bar: ultramarine diagonal bands moving to the right while active (a barber pole, 400 ms per band), or, with fraction: set, a determinate bar filled to the fraction. Typically 2 to 4 points high. active: starts and stops the animation (it runs on the window''s frame clock).'!

!ProgressStripe methodsFor: 'initialization'!
initialize
	super initialize.
	active := false.
	phase := 0
! !

!ProgressStripe methodsFor: 'accessing'!
isActive
	^active
!
active: aBoolean
	active = aBoolean ifTrue: [^self].
	active := aBoolean.
	animation isNil ifFalse: [animation stop. animation := nil].
	(active and: [self window notNil]) ifTrue: [
		animation := self window requestAnimationFrames: [:ms |
			phase := ms / 400.0 \\ 1.
			self invalidate.
			active]].
	self invalidate
!
fraction
	^fraction
!
fraction: aNumberOrNil
	fraction := aNumberOrNil.
	self invalidate
!
phase
	^phase
!
phase: aNumber
	phase := aNumber.
	self invalidate
! !

!ProgressStripe methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| band r |
	r := self localBounds.
	fraction isNil ifFalse: [
		aCanvas strokeRect: r color: self theme ultramarine width: 1.
		^aCanvas fillRect: (r origin extent: (r width * ((fraction max: 0) min: 1)) @ r height) color: self theme ultramarine].
	active ifFalse: [^self].
	band := 8.
	aCanvas clip: r during: [
		aCanvas pattern: #diagonalStripes in: ((r left - band + (phase * band)) @ r top corner: r corner) color: self theme ultramarine]
! !

!ProgressStripe methodsFor: 'remote control'!
remoteRole
	^#progress
!
remoteState
	fraction isNil ifFalse: [^Array with: 'value=', (fraction * 100) rounded printString, '%'].
	^active ifTrue: [#(#busy)] ifFalse: [#()]
! !
