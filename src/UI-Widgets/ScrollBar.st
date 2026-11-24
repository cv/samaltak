Widget subclass: #ScrollBar
	instanceVariableNames: 'client horizontal dragOffset'
	classVariableNames: ''
	package: 'UI-Widgets'!

ScrollBar comment: 'I am a thin Blue Book scroll bar: a halftone track behind a 1-point rule, and a white thumb with a 1-point frame. My client answers scrollTotal (content length), scrollVisible (viewport length) and scrollOffset, and takes scrollOffset: (points). Drag the thumb, or click the track to page.'!

!ScrollBar methodsFor: 'accessing'!
client
	^client
!
client: anObject
	client := anObject
!
isHorizontal
	^horizontal == true
!
beHorizontal
	horizontal := true
!
isNeeded
	^client notNil and: [client scrollTotal > client scrollVisible]
!
trackLength
	^self isHorizontal ifTrue: [self width] ifFalse: [self height]
!
thumbRect
	"The thumb in my coordinates, or nil when everything is visible."
	| total visible length start size |
	self isNeeded ifFalse: [^nil].
	total := client scrollTotal.
	visible := client scrollVisible.
	length := self trackLength.
	size := (length * visible / total max: 16) min: length.
	start := (length - size) * (client scrollOffset / (total - visible)).
	start := (start max: 0) min: length - size.
	^self isHorizontal
		ifTrue: [start @ 0 extent: size @ self height]
		ifFalse: [0 @ start extent: self width @ size]
!
along: aPoint
	^self isHorizontal ifTrue: [aPoint x] ifFalse: [aPoint y]
! !

!ScrollBar methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| thumb r |
	self theme isBevelled ifTrue: [^self drawBevelledOn: aCanvas].
	r := self localBounds.
	aCanvas fillRect: r color: self theme paper.
	aCanvas pattern: #halftone in: r color: self theme ink.
	self isHorizontal
		ifTrue: [aCanvas fillRect: (0 @ 0 corner: self width @ 1) color: self theme rule]
		ifFalse: [aCanvas fillRect: (0 @ 0 corner: 1 @ self height) color: self theme rule].
	thumb := self thumbRect.
	thumb isNil ifTrue: [^self].
	aCanvas fillRect: thumb color: self theme paper.
	self isHorizontal
		ifTrue: [
			aCanvas fillRect: (thumb left @ 0 corner: thumb right @ (thumb bottom - 1)) color: self theme paper.
			aCanvas strokeRect: (thumb left @ 0 corner: thumb right @ (thumb bottom + 1)) color: self theme rule width: 1]
		ifFalse: [aCanvas strokeRect: (thumb left @ thumb top corner: (thumb right + 1) @ thumb bottom) color: self theme rule width: 1]
!
drawBevelledOn: aCanvas
	"Haiku's scroll bar: a sunken gray track and a raised thumb with grip lines."
	| t r thumb c |
	t := self theme.
	r := self localBounds.
	aCanvas fillRect: r color: (t panel mixed: 0.25 with: (t color: #bevelDark)).
	aCanvas fillRect: (r origin extent: (self isHorizontal ifTrue: [r width @ 1] ifFalse: [1 @ r height])) color: (t color: #bevelDark).
	thumb := self thumbRect.
	thumb isNil ifTrue: [^self].
	thumb := self isHorizontal
		ifTrue: [thumb left @ 1 corner: thumb right @ thumb bottom]
		ifFalse: [1 @ thumb top corner: thumb right @ thumb bottom].
	aCanvas strokeRect: thumb color: (t color: #bevelDark) width: 1.
	thumb := thumb insetBy: 1.
	t shade: thumb from: (t color: #buttonTop) to: (t color: #buttonBottom) on: aCanvas.
	aCanvas fillRect: (thumb origin extent: thumb width @ 1) color: (t color: #bevelLight).
	aCanvas fillRect: (thumb origin extent: 1 @ thumb height) color: (t color: #bevelLight).
	c := thumb center rounded.
	-2 to: 2 by: 2 do: [:d |
		self isHorizontal
			ifTrue: [aCanvas fillRect: ((c x + d) @ (c y - 3) extent: 1 @ 6) color: (t color: #bevelDark)]
			ifFalse: [aCanvas fillRect: ((c x - 3) @ (c y + d) extent: 6 @ 1) color: (t color: #bevelDark)]]
! !

!ScrollBar methodsFor: 'events'!
mouseDown: anEvent
	| thumb p |
	anEvent button = 1 ifFalse: [^false].
	thumb := self thumbRect.
	thumb isNil ifTrue: [^true].
	p := self along: (self localEventPosition: anEvent).
	(p between: (self along: thumb origin) and: (self along: thumb corner))
		ifTrue: [dragOffset := p - (self along: thumb origin)]
		ifFalse: [
			p < (self along: thumb origin)
				ifTrue: [client scrollOffset: client scrollOffset - client scrollVisible]
				ifFalse: [client scrollOffset: client scrollOffset + client scrollVisible]].
	^true
!
mouseMove: anEvent
	| thumb start range |
	dragOffset isNil ifTrue: [^false].
	thumb := self thumbRect.
	thumb isNil ifTrue: [^true].
	start := (self along: (self localEventPosition: anEvent)) - dragOffset.
	range := self trackLength - (self along: thumb extent).
	range <= 0 ifTrue: [^true].
	client scrollOffset: (start / range) * (client scrollTotal - client scrollVisible).
	^true
!
mouseUp: anEvent
	dragOffset := nil.
	^true
! !

!ScrollBar methodsFor: 'remote control'!
remoteRole
	^#scrollbar
!
remoteState
	client isNil ifTrue: [^#()].
	^Array with: 'offset=', client scrollOffset rounded printString with: 'total=', client scrollTotal rounded printString
! !
