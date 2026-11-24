Widget subclass: #PaintStatusBar
	instanceVariableNames: 'toolName position pictureExtent'
	classVariableNames: ''
	package: 'Tools'!

PaintStatusBar comment: 'I am the status bar of Paint: the selected tool, the pixel under the pointer and the picture''s size, each in a sunken field.'!

!PaintStatusBar methodsFor: 'drawing'!
drawField: aRectangle on: aCanvas
	"Sunken: dark above and at the left, light below and at the right."
	| t r |
	t := self theme.
	r := aRectangle.
	t isBevelled ifFalse: [^aCanvas strokeRect: r color: t rule width: 1].
	aCanvas fillRect: (r origin extent: r width @ 1) color: (t color: #bevelDark).
	aCanvas fillRect: (r origin extent: 1 @ r height) color: (t color: #bevelDark).
	aCanvas fillRect: (r left @ (r bottom - 1) extent: r width @ 1) color: (t color: #bevelLight).
	aCanvas fillRect: ((r right - 1) @ r top extent: 1 @ r height) color: (t color: #bevelLight)
!
drawSelfOn: aCanvas
	| b right font |
	b := self localBounds.
	font := self theme font: #ui.
	right := b right.
	self fields reverseDo: [:each | | r |
		r := each value isNil
			ifTrue: [b left @ b top corner: right @ b bottom]
			ifFalse: [(right - each value) @ b top corner: right @ b bottom].
		self drawField: r on: aCanvas.
		aCanvas drawString: each key in: (r insetBy: 6 @ 0) font: font color: (self theme color: #ink2) align: #left.
		right := r left - 4]
!
fields
	"label -> width (nil: the rest), left to right"
	^Array
		with: (toolName ifNil: ['']) -> nil
		with: (position isNil ifTrue: [''] ifFalse: [position x printString , ', ' , position y printString]) -> 84
		with: (pictureExtent isNil ifTrue: [''] ifFalse: [pictureExtent x printString , ' × ' , pictureExtent y printString]) -> 92
! !

!PaintStatusBar methodsFor: 'accessing'!
pictureExtent: aPoint
	pictureExtent = aPoint ifTrue: [^self].
	pictureExtent := aPoint.
	self invalidate
!
position: aPointOrNil
	position = aPointOrNil ifTrue: [^self].
	position := aPointOrNil.
	self invalidate
!
toolName: aString
	toolName = aString ifTrue: [^self].
	toolName := aString.
	self invalidate
! !

!PaintStatusBar methodsFor: 'layout'!
preferredExtent
	^200 @ 20
! !

!PaintStatusBar methodsFor: 'remote'!
remoteLabel
	^(self fields collect: [:each | each key]) inject: 'status' into: [:a :b | a , ' ' , b]
! !
