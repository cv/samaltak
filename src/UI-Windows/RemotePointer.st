Object subclass: #RemotePointer
	instanceVariableNames: 'position lastSeen lastActivity lastStep opacity rings shown'
	classVariableNames: ''
	package: 'UI-Windows'!

RemotePointer comment: 'I am the software pointer the Compositor draws while remote input is active (RemoteInputDevice default injects events): a Blue Book arrow exactly where the input dispatcher last saw the pointer, the position hover and clicks go to (the device injects a travel as a series of moves: they are the animation), a ring where an injected click lands, and a fade-out 4 s after the last remote input. Remote input presses a button only once a frame showed me where it presses (hasShown:, RemoteInputDevice arrivalBlock:).'!

!RemotePointer methodsFor: 'initialization'!
initialize
	opacity := 0.
	lastActivity := -1.0e9.
	rings := #()
! !

!RemotePointer methodsFor: 'accessing'!
position
	^position
!
shown
	"Where the last frame drew me (nil: not drawn)."
	^shown
!
opacity
	^opacity
!
isVisible
	^opacity > 0 and: [position notNil]
!
isDrawn
	"Whether drawOn:time: draws anything: the arrow, or a click's ring."
	^rings notEmpty or: [self isVisible]
!
isActiveAt: ms
	^ms - lastActivity < 4000
!
hasShown: aPoint
	"Did the last frame drawn show me at aPoint (within half a point)?"
	^shown notNil and: [(shown dist: aPoint) <= 0.5]
! !

!RemotePointer methodsFor: 'stepping'!
ignore: aPoint
	"Take aPoint as the device's current position without showing me (a position not set by remote input)."
	lastSeen := aPoint
!
pollAt: ms pointer: aPointOrNil
	"Show the pointer where the input dispatcher last saw it (aPointOrNil, nil: no dispatcher), while RemoteInputDevice default moves it; answer whether I need another frame."
	| p dt animating |
	p := RemoteInputDevice default pointer.
	(p notNil and: [p ~= lastSeen]) ifTrue: [
		lastSeen := p.
		lastActivity := ms].
	dt := lastStep isNil ifTrue: [16] ifFalse: [(ms - lastStep) max: 0].
	lastStep := ms.
	animating := aPointOrNil notNil and: [aPointOrNil ~= position and: [opacity > 0 or: [self isActiveAt: ms]]].
	aPointOrNil isNil ifFalse: [position := aPointOrNil].
	(self isActiveAt: ms)
		ifTrue: [
			opacity < 1 ifTrue: [opacity := (opacity + (dt / 120.0)) min: 1. animating := true]]
		ifFalse: [
			opacity > 0 ifTrue: [opacity := (opacity - (dt / 500.0)) max: 0. animating := true]].
	rings isEmpty ifFalse: [
		rings := rings reject: [:r | ms - r last > 350].
		animating := true].
	^animating
!
ringAt: aPoint time: ms
	rings := rings copyWith: (Array with: aPoint with: ms).
	lastActivity := ms
! !

!RemotePointer methodsFor: 'drawing'!
drawOn: c time: ms
	| form |
	rings do: [:r |
		| t radius |
		t := (ms - r last) / 350.0 min: 1.
		radius := 8 * (0.3 + (1.2 * (Animation ease: #easeOutCubic at: t))).
		c alpha: 1 - t during: [self circle: r first radius: radius on: c]].
	self isVisible ifFalse: [^self].
	shown := position.
	form := UIIcons arrowPointerScale: c scale.
	c alpha: opacity during: [
		c image: form in: (position - (1 @ 1) extent: 13 @ 19)]
!
circle: center radius: r on: c
	| n |
	n := 20.
	0 to: n - 1 do: [:i |
		| a0 a1 |
		a0 := i * 2 * Float pi / n.
		a1 := (i + 1) * 2 * Float pi / n.
		c line: (center x + (r * a0 cos)) @ (center y + (r * a0 sin))
			to: (center x + (r * a1 cos)) @ (center y + (r * a1 sin))
			color: Color ultramarine width: 1.5]
! !
