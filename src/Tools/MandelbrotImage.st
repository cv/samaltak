Widget subclass: #MandelbrotImage
	instanceVariableNames: 'mandelbrot stripePhase badge'
	classVariableNames: ''
	package: 'Tools'!

MandelbrotImage comment: 'I am the picture of a MandelbrotView: its Form scaled to my bounds, a moving ultramarine stripe along my top edge while it renders, and the black badge counting the clicks queued while the window''s Process is busy. Clicks zoom (shift: out).'!

!MandelbrotImage methodsFor: 'accessing'!
mandelbrot: aMandelbrotView
	mandelbrot := aMandelbrotView
!
stripePhase: aNumber
	stripePhase := aNumber
! !

!MandelbrotImage methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| form |
	aCanvas fillRect: self localBounds color: self theme paper.
	form := mandelbrot form.
	form isNil ifFalse: [aCanvas image: form in: self localBounds].
	mandelbrot isRendering ifTrue: [
		aCanvas fillRect: (0 @ 0 extent: self width @ 3) color: self theme paper.
		aCanvas translateBy: ((stripePhase ifNil: [0]) * 8) rounded - 8 @ 0 during: [
			aCanvas pattern: #diagonalStripes in: (0 @ 0 extent: self width + 8 @ 3) color: self theme ultramarine]].
	mandelbrot queuedClicks > 0 ifTrue: [self drawBadgeOn: aCanvas]
!
drawBadgeOn: aCanvas
	"Black, italic white text, a white hard shadow (Blue Book .mb-queued); two lines when narrow."
	| lines font w h box y |
	font := self theme font: #smallItalic.
	lines := self badgeLines: mandelbrot queuedClicks.
	(font widthOf: lines first) + (font widthOf: lines last) + 30 <= self width
		ifTrue: [lines := Array with: (self badgeText: mandelbrot queuedClicks)].
	w := (lines inject: 0 into: [:m :l | m max: (font widthOf: l)]) + 20.
	h := lines size * font lineHeight + 8.
	box := ((self width - w) / 2) rounded @ (self height - h - 10) extent: w ceiling @ h.
	aCanvas fillRect: (box translateBy: 2 @ 2) color: self theme paper.
	aCanvas fillRect: box color: self theme ink.
	y := box top + 4.
	lines do: [:l |
		aCanvas drawString: l in: (box left @ y extent: box width @ font lineHeight) font: font color: self theme paper align: #center.
		y := y + font lineHeight]
! !

!MandelbrotImage methodsFor: 'badge'!
badgeText: anInteger
	"'1 click queued — this window''s Process is busy' (cached: concatenating a WideString is slow)."
	(badge notNil and: [badge first = anInteger]) ifTrue: [^badge last].
	badge := Array with: anInteger with: ((anInteger printString, (anInteger = 1 ifTrue: [' click'] ifFalse: [' clicks'])) asWideString, ' queued — this window''s Process is busy').
	^badge last
!
badgeLines: anInteger
	^Array
		with: anInteger printString, (anInteger = 1 ifTrue: [' click queued'] ifFalse: [' clicks queued'])
		with: 'this window''s Process is busy'
! !

!MandelbrotImage methodsFor: 'events'!
mouseDown: anEvent
	anEvent button = 1 ifFalse: [^false].
	mandelbrot zoomAt: (self localEventPosition: anEvent) out: anEvent modifiers shift.
	^true
!
mouseUp: anEvent
	^true
!
cursorAt: aPoint
	^#crosshair
! !

!MandelbrotImage methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^'Mandelbrot'
!
remoteState
	| s |
	s := OrderedCollection new.
	mandelbrot isRendering ifTrue: [s add: #busy; add: 'progress=', (mandelbrot progress * 100) rounded printString, '%'].
	mandelbrot queuedClicks > 0 ifTrue: [s add: 'queued=', mandelbrot queuedClicks printString].
	s add: 'iterations=', mandelbrot maxIterations printString.
	s add: 'zoom=', mandelbrot zoomFactor printString.
	^s asArray
! !
