Widget subclass: #CalculatorDisplay
	instanceVariableNames: 'text align'
	classVariableNames: ''
	package: 'Tools'!

CalculatorDisplay comment: 'I am the Calculator''s readout: a framed white field showing text: in the readout font, right-aligned (align: #center for the memory light).'!

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
	"A sunken readout: a white field with a double rule along its top and left."
	| r ink |
	r := self localBounds.
	ink := self theme ink.
	aCanvas fillRect: r color: self theme paper.
	aCanvas strokeRect: r color: ink width: 1.
	aCanvas fillRect: (r origin extent: r width @ 2) color: ink.
	aCanvas fillRect: (r origin extent: 2 @ r height) color: ink.
	aCanvas drawString: text in: (r insetBy: (8 @ 0 corner: 8 @ 0)) font: (self fontFor: #readout) color: ink align: align
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
