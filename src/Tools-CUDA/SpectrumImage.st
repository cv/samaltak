Widget subclass: #SpectrumImage
	instanceVariableNames: 'form tool role pressing'
	classVariableNames: ''
	package: 'Tools-CUDA'!

SpectrumImage comment: 'I am one of the Spectrum window''s three pictures (the picture, its spectrum, the filtered picture): a Form scaled to the largest square that fits me, pixels kept square. On the spectrum the filter''s circles are drawn over it, and a press or drag sets their radius (the distance from the middle, the zero frequency).'!

!SpectrumImage methodsFor: 'accessing'!
tool: aSpectrumWindow role: aSymbol
	tool := aSpectrumWindow.
	role := aSymbol
!
form
	^form
!
form: aForm
	form := aForm.
	self invalidate
! !

!SpectrumImage methodsFor: 'geometry'!
square
	| side |
	side := (self width min: self height) - 12 max: 4.
	^((self width - side) / 2) rounded @ ((self height - side) / 2) rounded extent: side @ side
!
frequencyAt: aLocalPoint
	"The distance from the middle of the spectrum, in its cells."
	| r d |
	r := self square.
	d := aLocalPoint - r center.
	^(d x squared + d y squared) sqrt / r width * tool size
! !

!SpectrumImage methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| r |
	aCanvas fillRect: self localBounds color: self theme paper.
	r := self square.
	form isNil ifFalse: [aCanvas image: form in: r].
	aCanvas strokeRect: (r insetBy: -1) color: self theme ink width: 1.
	role == #spectrum ifTrue: [
		tool radii do: [:f | self drawCircle: f / tool size * r width in: r on: aCanvas]]
!
drawCircle: radius in: r on: aCanvas
	| c prev |
	radius <= 0 ifTrue: [^self].
	c := r center.
	aCanvas clip: r during: [
		prev := c + (radius @ 0).
		1 to: 96 do: [:k | | a p |
			a := k * 2 * Float pi / 96.
			p := c + ((a cos * radius) @ (a sin * radius)).
			aCanvas line: prev to: p color: self theme paper width: 3.
			aCanvas line: prev to: p color: self theme ultramarine width: 1.5.
			prev := p]]
! !

!SpectrumImage methodsFor: 'events'!
mouseDown: anEvent
	role == #spectrum ifFalse: [^false].
	anEvent button = 1 ifFalse: [^false].
	pressing := true.
	tool radius: (self frequencyAt: (self localEventPosition: anEvent)).
	^true
!
mouseMove: anEvent
	role == #spectrum ifFalse: [^false].
	pressing == true ifFalse: [^false].
	tool radius: (self frequencyAt: (self localEventPosition: anEvent)).
	^true
!
mouseUp: anEvent
	pressing := false.
	^role == #spectrum
!
cursorAt: aPoint
	^role == #spectrum ifTrue: [#crosshair] ifFalse: [#arrow]
! !

!SpectrumImage methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^role asString
!
remoteState
	| s |
	s := OrderedCollection new.
	form isNil ifFalse: [s add: 'size=' , form width printString , 'x' , form height printString].
	role == #spectrum ifTrue: [s add: 'radius=' , (tool radius printShowingDecimalPlaces: 1)].
	^s asArray
!
remotePointAt: aString
	"On the spectrum: the point at frequency aString (a number) right of the middle."
	| f r |
	f := [aString asNumber] on: Error do: [:e | e return: nil].
	f isNil ifTrue: [^nil].
	r := self square.
	^self localToScreen: r center + ((f / tool size * r width) @ 0)
! !
