Button subclass: #CalculatorKey
	instanceVariableNames: 'ink'
	classVariableNames: ''
	package: 'Tools'!

CalculatorKey comment: 'I am a calculator key: a Button whose label has its own ink, as on the Windows 95 calculator (blue digits, red operators). Themes without bevels draw me as a plain Button.'!

!CalculatorKey methodsFor: 'accessing'!
ink
	^ink
!
ink: aColor
	ink := aColor.
	self invalidate
! !

!CalculatorKey methodsFor: 'drawing'!
drawBevelledOn: aCanvas
	"Button's raised face, the label in my ink."
	| t r |
	t := self theme.
	r := self localBounds.
	aCanvas fillRect: r color: t panel.
	t drawRaised: r pressed: self isInverted hover: (hover == true and: [self isEnabled]) on: aCanvas.
	aCanvas drawString: self label in: r font: self font color: (self isEnabled ifTrue: [ink ifNil: [t ink]] ifFalse: [t color: #ink4]) align: #center
! !
