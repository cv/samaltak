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
