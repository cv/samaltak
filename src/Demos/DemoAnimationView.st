DemoView subclass: #DemoAnimationView
	instanceVariableNames: 'phase animation'
	classVariableNames: ''
	package: 'Demos'!

DemoAnimationView comment: 'I animate a box gliding back and forth (Window>>requestAnimationFrames:, redrawn in my window''s Process every compositor frame). Click to start and stop.'!

!DemoAnimationView methodsFor: 'accessing'!
heading
	^'Animation on the compositor clock'
!
lines
	^#('Click the box to start or stop.')
! !

!DemoAnimationView methodsFor: 'drawing'!
drawOn: c
	| x track |
	c fillRect: self localBounds color: Color white.
	c drawString: self heading at: 16 @ 12 font: Font uiBold color: Color black.
	c drawString: self lines first at: 16 @ 36 font: Font ui color: Color black.
	track := 16 @ 70 extent: (self width - 32) @ 24.
	c pattern: #halftone in: track.
	c strokeRect: track color: Color black width: 1.
	x := track left + ((track width - 24) * (1 - ((phase ifNil: [0]) * 2 * Float pi) cos) / 2).
	c fillRect: (x @ track top extent: 24 @ 24) color: Color ultramarine.
	self drawButtonOn: c label: (animation isNil ifTrue: ['Start'] ifFalse: ['Stop'])
! !

!DemoAnimationView methodsFor: 'events'!
buttonPressed
	| start |
	animation isNil ifFalse: [animation stop. animation := nil. ^self].
	start := nil.
	animation := self window requestAnimationFrames: [:ms |
		start isNil ifTrue: [start := ms - ((phase ifNil: [0]) * 2000)].
		phase := (ms - start) / 2000.0 \\ 1.
		self invalidate.
		true]
! !
