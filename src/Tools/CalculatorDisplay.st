Widget subclass: #CalculatorDisplay
	instanceVariableNames: 'text align'
	classVariableNames: ''
	package: 'Tools'!

CalculatorDisplay comment: 'I am the Calculator''s readout: a sunken white field showing text: in the readout font, right-aligned (align: #center for the memory light).'!

!CalculatorDisplay methodsFor: 'accessing'!
align: aSymbol
	align := aSymbol
!
text
	^text
!
text: aString
	text = aString ifTrue: [^self].
	text := aString.
	self invalidate
! !

!CalculatorDisplay methodsFor: 'drawing'!
drawSelfOn: aCanvas
	"A sunken readout: a white field inside a two-pixel bevel, lit from below right; without bevels a plain frame."
	| t r |
	t := self theme.
	r := self localBounds.
	t isBevelled
		ifTrue: [
			self drawSunken: r on: aCanvas.
			r := r insetBy: 2]
		ifFalse: [aCanvas strokeRect: r color: t ink width: 1].
	aCanvas fillRect: (r insetBy: (t isBevelled ifTrue: [0] ifFalse: [1])) color: t paper.
	aCanvas drawString: text in: (r insetBy: (8 @ 0 corner: 8 @ 0)) font: (self fontFor: #readout) color: t ink align: align
!
drawSunken: r on: aCanvas
	"Two rules each side: dark over light at the top and left, light at the bottom and right."
	| t |
	t := self theme.
	aCanvas fillRect: r color: (t color: #bevelLight).
	aCanvas fillRect: (r origin extent: r width @ 1) color: (t color: #bevelDark).
	aCanvas fillRect: (r origin extent: 1 @ r height) color: (t color: #bevelDark).
	aCanvas fillRect: (r left + 1 @ (r top + 1) extent: (r width - 2) @ 1) color: t ink.
	aCanvas fillRect: (r left + 1 @ (r top + 1) extent: 1 @ (r height - 2)) color: t ink.
	aCanvas fillRect: (r left + 1 @ (r bottom - 2) extent: (r width - 2) @ 1) color: t panel.
	aCanvas fillRect: (r right - 2 @ (r top + 1) extent: 1 @ (r height - 2)) color: t panel
! !

!CalculatorDisplay methodsFor: 'initialize-release'!
initialize
	super initialize.
	text := ''.
	align := #right
! !

!CalculatorDisplay methodsFor: 'remote control'!
remoteLabel
	^text
! !
