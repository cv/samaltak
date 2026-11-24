Widget subclass: #CalculatorDisplay
	instanceVariableNames: 'text annunciator'
	classVariableNames: ''
	package: 'Tools'!

CalculatorDisplay comment: 'I am the Calculator''s top: a light bezel with a gold rule along its foot and an inset LCD showing text: right-aligned in the readout font, and the annunciator: (M while memory holds a number) at its lower left.'!

!CalculatorDisplay methodsFor: 'accessing'!
text
	^text
!
text: aString
	text = aString ifTrue: [^self].
	text := aString.
	self invalidate
!
annunciator
	^annunciator
!
annunciator: aString
	"The small mark under the digits: M while memory holds a number."
	annunciator = aString ifTrue: [^self].
	annunciator := aString.
	self invalidate
! !

!CalculatorDisplay methodsFor: 'drawing'!
drawSelfOn: aCanvas
	"The HP 12C's top: a light bezel, a gold rule along its foot, and an inset grey-green LCD with the digits right-aligned and the annunciator at its lower left."
	| t r lcd |
	t := self theme.
	r := self localBounds.
	aCanvas fillRect: r color: t panel.
	aCanvas fillRect: (r left @ (r bottom - 3) extent: r width @ 3) color: (t color: #tab).
	lcd := r insetBy: (14 @ 12 corner: 14 @ 15).
	aCanvas fillRect: lcd color: (t color: #bevelDark).
	aCanvas fillRect: (lcd left @ (lcd bottom - 1) extent: lcd width @ 1) color: (t color: #bevelLight).
	lcd := lcd insetBy: 1.
	t shade: lcd from: (Color hex: 16rB4BA9E) to: (Color hex: 16rC9CEB4) on: aCanvas.
	aCanvas drawString: text in: (lcd insetBy: (12 @ 0 corner: 12 @ 4)) font: (self fontFor: #readout) color: (Color hex: 16r20251B) align: #right.
	annunciator isEmpty ifFalse: [
		aCanvas drawString: annunciator at: (lcd left + 8) @ (lcd bottom - 17) font: (self fontFor: #small) color: (Color hex: 16r20251B)]
! !

!CalculatorDisplay methodsFor: 'initialize-release'!
initialize
	super initialize.
	text := ''.
	annunciator := ''
! !

!CalculatorDisplay methodsFor: 'remote control'!
remoteLabel
	^text
! !
