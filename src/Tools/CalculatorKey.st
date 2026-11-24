Button subclass: #CalculatorKey
	instanceVariableNames: 'kind'
	classVariableNames: ''
	package: 'Tools'!

CalculatorKey comment: 'I am a calculator key: a graphite Button with light lettering, gold lettering (kind: #gold) or a gold face (kind: #accent), as on the HP 12C. Themes without bevels draw me as a plain Button.'!

!CalculatorKey methodsFor: 'accessing'!
kind
	^kind
!
kind: aSymbol
	"#plain, #gold (gold lettering) or #accent (the gold key)."
	kind := aSymbol.
	self invalidate
! !

!CalculatorKey methodsFor: 'drawing'!
drawBevelledOn: aCanvas
	"A graphite key, lit along its top, its corners cut to the faceplate; the accent key gold."
	| r gold top bottom bed |
	r := self localBounds.
	gold := self theme color: #tab.
	bed := Calculator bedColor.
	kind == #accent
		ifTrue: [top := gold mixed: 0.3 with: Color white. bottom := gold]
		ifFalse: [top := Color hex: 16r555555. bottom := Color hex: 16r383838].
	self isInverted ifTrue: [top := bottom mixed: 0.25 with: Color black. bottom := top].
	(hover == true and: [self isEnabled and: [self isInverted not]]) ifTrue: [
		top := top mixed: 0.12 with: Color white. bottom := bottom mixed: 0.12 with: Color white].
	aCanvas fillRect: r color: (Color hex: 16r141414).
	self theme shade: (r insetBy: 1) from: top to: bottom on: aCanvas.
	self isInverted ifFalse: [
		aCanvas fillRect: ((r insetBy: 1) origin extent: (r width - 2) @ 1) color: (top mixed: 0.3 with: Color white)].
	{r origin. r topRight - (1 @ 0). r bottomLeft - (0 @ 1). r corner - 1} do: [:p |
		aCanvas fillRect: (p extent: 1 @ 1) color: bed].
	aCanvas drawString: self label in: r font: self font color: self labelColor align: #center
!
labelColor
	self isEnabled ifFalse: [^Color hex: 16r808080].
	kind == #accent ifTrue: [^Color hex: 16r1E1E1E].
	kind == #gold ifTrue: [^self theme color: #tab].
	^Color hex: 16rF2F2F2
! !
