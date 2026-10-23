Widget subclass: #BusyIndicator
	instanceVariableNames: 'active angle animation'
	classVariableNames: ''
	package: 'UI-Widgets'!

BusyIndicator comment: 'I am the small Blue Book spinner (an open ultramarine ring turning, 700 ms per turn) shown while something runs; nothing when inactive. Typically 9 to 12 points square.'!

!BusyIndicator methodsFor: 'initialization'!
initialize
	super initialize.
	active := false.
	angle := 0
! !

!BusyIndicator methodsFor: 'accessing'!
isActive
	^active
!
active: aBoolean
	active = aBoolean ifTrue: [^self].
	active := aBoolean.
	animation isNil ifFalse: [animation stop. animation := nil].
	(active and: [self window notNil]) ifTrue: [
		animation := self window requestAnimationFrames: [:ms |
			angle := ms / 700.0 \\ 1 * 2 * Float pi.
			self invalidate.
			active]].
	self invalidate
!
preferredExtent
	^12 @ 12
! !

!BusyIndicator methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| c radius segments prev |
	active ifFalse: [^self].
	c := self localBounds center.
	radius := (self width min: self height) / 2 - 1.5.
	segments := 12.
	prev := nil.
	0 to: segments * 3 // 4 do: [:i |
		| a p |
		a := angle + (i * 2 * Float pi / segments).
		p := c + ((a cos * radius) @ (a sin * radius)).
		prev isNil ifFalse: [aCanvas line: prev to: p color: self theme ultramarine width: 1.5].
		prev := p]
! !

!BusyIndicator methodsFor: 'remote control'!
remoteRole
	^#busy
!
remoteState
	^active ifTrue: [#(#busy)] ifFalse: [#()]
! !
