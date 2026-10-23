Object subclass: #RemotePointer
	instanceVariableNames: 'position target lastSeen lastActivity lastStep opacity rings'
	classVariableNames: ''
	package: 'UI-Windows'!

RemotePointer comment: 'I am the software pointer the Compositor draws while remote input is active (RemoteInputDevice default injects events): a Blue Book arrow that follows the injected pointer positions smoothly (the device already interpolates moves; I ease between frames), a ring where an injected click lands, and a fade-out 4 s after the last remote input.'!

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
opacity
	^opacity
!
isVisible
	^opacity > 0 and: [position notNil]
!
isActiveAt: ms
	^ms - lastActivity < 4000
! !

!RemotePointer methodsFor: 'stepping'!
ignore: aPoint
	"Take aPoint as the device's current position without showing me (a position not set by remote input)."
	lastSeen := aPoint
!
pollAt: ms
	"Follow RemoteInputDevice default's pointer; answer whether I need another frame."
	| p dt k animating |
	p := RemoteInputDevice default pointer.
	(p notNil and: [p ~= lastSeen]) ifTrue: [
		lastSeen := p.
		target := p.
		position isNil ifTrue: [position := p].
		lastActivity := ms].
	dt := lastStep isNil ifTrue: [16] ifFalse: [(ms - lastStep) max: 0].
	lastStep := ms.
	animating := false.
	(position notNil and: [target notNil and: [position ~= target]]) ifTrue: [
		k := 1 - (dt / -30.0) exp.
		position := (position dist: target) < 0.3 ifTrue: [target] ifFalse: [position + (target - position * k)].
		animating := true].
	ms - lastActivity < 4000
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
