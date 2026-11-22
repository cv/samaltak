View subclass: #DamageTestView
	instanceVariableNames: 'lines color'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

DamageTestView comment: 'I am a test View for damage-limited composition: lines of text over a color, a line appended at a time, as a transcript streams them.'!

!DamageTestView methodsFor: 'initialization'!
initialize
	super initialize.
	lines := OrderedCollection new.
	color := Color white
! !

!DamageTestView methodsFor: 'accessing'!
add: aString
	lines add: aString.
	self invalidate
!
color: aColor
	color := aColor.
	self invalidate
! !

!DamageTestView methodsFor: 'drawing'!
drawOn: aCanvas
	| font y |
	aCanvas fillRect: self localBounds color: color.
	font := Font code.
	y := 4.
	lines do: [:each |
		aCanvas drawString: each at: 4 @ y font: font color: Color ink.
		y := y + font lineHeight]
! !
