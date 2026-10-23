Object subclass: #WorldTooltip
	instanceVariableNames: 'world text position'
	classVariableNames: ''
	package: 'UI-Windows'!

WorldTooltip comment: 'I am the tooltip the World shows near the pointer (a View''s tooltipAt:): small italic text in a 1-point frame with a hard 1-point shadow. The InputDispatcher hides me when the pointer moves on.'!

!WorldTooltip methodsFor: 'initialization'!
setWorld: aWorld text: aString at: aPoint
	world := aWorld.
	text := aString asString.
	position := aPoint
! !

!WorldTooltip methodsFor: 'accessing'!
text
	^text
!
font
	^Font smallItalic
!
bounds
	| ext x y |
	ext := ((self font widthOf: text) + 12) ceiling @ (self font lineHeight + 6) ceiling.
	x := (position x min: world extent x - ext x - 4) max: 4.
	y := position y + ext y > world extent y ifTrue: [position y - ext y - 24] ifFalse: [position y].
	^x @ y extent: ext
! !

!WorldTooltip methodsFor: 'drawing'!
drawOn: c
	| box |
	box := self bounds.
	c fillRect: (box translateBy: 1 @ 1) color: Color black.
	c fillRect: box color: Color white.
	c strokeRect: box color: Color black width: 1.
	c drawString: text at: box origin + (6 @ 3) font: self font color: Color black
! !

!WorldTooltip methodsFor: 'remote control'!
remoteRole
	^#tooltip
!
remoteLabel
	^text
!
remoteState
	^#()
!
remoteChildren
	^#()
! !

!WorldTooltip class methodsFor: 'instance creation'!
world: aWorld text: aString at: aPoint
	^self new setWorld: aWorld text: aString at: aPoint
! !
