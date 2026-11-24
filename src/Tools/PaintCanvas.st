Widget subclass: #PaintCanvas
	instanceVariableNames: 'form nearest undo snapshot tool foreground background brushSize filled start last ink onPick onHover'
	classVariableNames: ''
	package: 'Tools'!

PaintCanvas comment: 'I am Paint''s picture: a Form (480x320, white) shown unscaled on a grey desk, and the tools that draw into it: #pencil #brush #spray (airbrush) #eraser #fill (flood fill) #picker #line #rectangle #ellipse. The left button paints with the foreground, the right with the background; shapes are rubber-banded from a snapshot until the button is released, and filled: true fills rectangles and ellipses with the other color. Each stroke remembers the picture before it: undo swaps them (undo again redoes).'!

!PaintCanvas methodsFor: 'accessing'!
background
	^background
!
background: aColor
	background := aColor
!
brushSize
	^brushSize
!
brushSize: anInteger
	brushSize := anInteger
!
filled: aBoolean
	"Whether rectangles and ellipses are filled with the other color."
	filled := aBoolean
!
foreground
	^foreground
!
foreground: aColor
	foreground := aColor
!
form
	^form
!
onHover: aBlock
	"[:pixelOrNil] as the pointer moves."
	onHover := aBlock
!
onPick: aBlock
	"[:color :isForeground] after the picker took a color."
	onPick := aBlock
!
tool
	^tool
!
tool: aSymbol
	"#pencil #brush #eraser #spray #fill #picker #line #rectangle #ellipse"
	tool := aSymbol
! !

!PaintCanvas methodsFor: 'strokes'!
beginAt: aPoint primary: aBoolean
	"Start a stroke with the foreground color (left button) or the background (right)."
	tool == #picker ifTrue: [^self pickAt: aPoint primary: aBoolean].
	self remember.
	ink := (aBoolean ifTrue: [foreground] ifFalse: [background]) premultipliedRGBA8.
	tool == #eraser ifTrue: [ink := background premultipliedRGBA8].
	tool == #fill ifTrue: [self fillAt: aPoint value: ink. ^self changed].
	snapshot := form bits copy.
	start := last := aPoint.
	self dragTo: aPoint
!
changed
	form changed.
	self invalidate
!
dragTo: aPoint
	(#(#line #rectangle #ellipse) includes: tool) ifTrue: [
		form bits replaceFrom: 1 to: snapshot size with: snapshot startingAt: 1.
		tool == #line ifTrue: [self lineFrom: start to: aPoint value: ink radius: brushSize // 2].
		tool == #rectangle ifTrue: [self rectangleFrom: start to: aPoint].
		tool == #ellipse ifTrue: [self ellipseFrom: start to: aPoint].
		^self changed].
	tool == #pencil ifTrue: [self lineFrom: last to: aPoint value: ink radius: 0].
	tool == #brush ifTrue: [self lineFrom: last to: aPoint value: ink radius: brushSize // 2].
	tool == #eraser ifTrue: [self lineFrom: last to: aPoint value: ink radius: brushSize + 2].
	tool == #spray ifTrue: [self sprayAt: aPoint].
	last := aPoint.
	self changed
!
endStroke
	start := last := nil
!
pickAt: aPoint primary: aBoolean
	| color |
	(self contains: aPoint) ifFalse: [^self].
	color := form at: aPoint.
	aBoolean ifTrue: [foreground := color] ifFalse: [background := color].
	onPick isNil ifFalse: [onPick value: color value: aBoolean]
! !

!PaintCanvas methodsFor: 'picture'!
clear
	self remember.
	form fill: background.
	self invalidate
!
newPicture: anExtent
	form := Form extent: anExtent.
	form fill: background.
	undo := nil.
	self invalidate
!
remember
	undo := form bits copy
!
undo
	"Swap the picture with the one before the last stroke (undo again redoes it)."
	| bits |
	undo isNil ifTrue: [^false].
	bits := form bits copy.
	form bits replaceFrom: 1 to: bits size with: undo startingAt: 1.
	undo := bits.
	form changed.
	self invalidate.
	^true
! !

!PaintCanvas methodsFor: 'events'!
contains: aPoint
	^aPoint x >= 0 and: [aPoint y >= 0 and: [aPoint x < form width and: [aPoint y < form height]]]
!
mouseDown: anEvent
	anEvent button = 1 ifFalse: [^false].
	self beginAt: (self pixelAt: (self localEventPosition: anEvent)) primary: true.
	^true
!
mouseLeave: anEvent
	onHover isNil ifFalse: [onHover value: nil].
	^false
!
mouseMove: anEvent
	| p |
	p := self pixelAt: (self localEventPosition: anEvent).
	onHover isNil ifFalse: [onHover value: ((self contains: p) ifTrue: [p])].
	start isNil ifTrue: [^true].
	self dragTo: p.
	^true
!
mouseUp: anEvent
	start isNil ifTrue: [^false].
	self endStroke.
	^true
!
pixelAt: aLocalPoint
	^(aLocalPoint - self origin) floor
!
rightMouseDown: anEvent
	self beginAt: (self pixelAt: (self localEventPosition: anEvent)) primary: false.
	^true
! !

!PaintCanvas methodsFor: 'drawing'!
drawSelfOn: aCanvas
	"The picture on a darker workspace inside a sunken edge, with a soft shadow."
	| r workspace |
	workspace := self localBounds insetBy: 1.
	aCanvas fillRect: workspace color: (((self theme color: #ink3) mixed: 0.5 with: (self theme color: #ink4)) mixed: 0.5 with: (self theme color: #ink4)).
	self class drawSunken: workspace on: aCanvas.
	r := self origin extent: form extent.
	(nearest isNil or: [nearest bits ~~ form bits]) ifTrue: [nearest := NearestForm on: form].
	#(4 3 2) doWithIndex: [:d :i |
		aCanvas fillRect: (r translateBy: d @ d) color: (Color black alpha: 0.12 * i)].
	aCanvas image: nearest in: r.
	aCanvas strokeRect: (r expandBy: 1) color: (self theme ink alpha: 0.6) width: 1.
	aCanvas noteVolatile
!
origin
	^8 @ 8
!
preferredExtent
	^form extent + (self origin * 2) + 4
! !

!PaintCanvas methodsFor: 'rasterizing'!
ellipseFrom: p0 to: p1
	"The ellipse in the box p0 p1: filled row by row, outlined by joining points around it."
	| r c a b other steps previous |
	r := (p0 min: p1) corner: (p0 max: p1).
	c := r center.
	a := r width / 2.
	b := r height / 2.
	(filled and: [b > 0]) ifTrue: [
		other := (ink = foreground premultipliedRGBA8 ifTrue: [background] ifFalse: [foreground]) premultipliedRGBA8.
		r top to: r bottom do: [:y | | t half |
			t := (y - c y / b) asFloat.
			half := (1 - (t * t) max: 0) sqrt * a.
			(c x - half) rounded to: (c x + half) rounded do: [:x | self plotX: x y: y value: other]]].
	steps := (a + b) * 2 max: 8.
	0 to: steps do: [:i | | angle p |
		angle := i * 2 * Float pi / steps.
		p := ((c x + (a * angle cos)) rounded) @ ((c y + (b * angle sin)) rounded).
		previous isNil ifFalse: [self lineFrom: previous to: p value: ink radius: brushSize // 2].
		previous := p]
!
fillAt: aPoint value: v
	"Flood fill the area of aPoint's color, a scanline at a time."
	| bits w h target stack |
	(self contains: aPoint) ifFalse: [^self].
	bits := form bits.
	w := form width.
	h := form height.
	target := bits at: aPoint y * w + aPoint x + 1.
	target = v ifTrue: [^self].
	stack := OrderedCollection with: aPoint.
	[stack isEmpty] whileFalse: [| p x y left right |
		p := stack removeLast.
		x := p x. y := p y.
		(bits at: y * w + x + 1) = target ifTrue: [
			left := x.
			[left > 0 and: [(bits at: y * w + left) = target]] whileTrue: [left := left - 1].
			right := x.
			[right < (w - 1) and: [(bits at: y * w + right + 2) = target]] whileTrue: [right := right + 1].
			left to: right do: [:i |
				bits at: y * w + i + 1 put: v.
				(y > 0 and: [(bits at: y - 1 * w + i + 1) = target]) ifTrue: [stack addLast: i @ (y - 1)].
				(y < (h - 1) and: [(bits at: y + 1 * w + i + 1) = target]) ifTrue: [stack addLast: i @ (y + 1)]]]]
!
lineFrom: p0 to: p1 value: v radius: r
	"Bresenham, a dab at every step."
	| x y dx dy sx sy err e2 |
	x := p0 x. y := p0 y.
	dx := (p1 x - x) abs. dy := (p1 y - y) abs negated.
	sx := x < p1 x ifTrue: [1] ifFalse: [-1].
	sy := y < p1 y ifTrue: [1] ifFalse: [-1].
	err := dx + dy.
	[self stampX: x y: y value: v radius: r.
	 x = p1 x and: [y = p1 y]] whileFalse: [
		e2 := 2 * err.
		e2 >= dy ifTrue: [err := err + dy. x := x + sx].
		e2 <= dx ifTrue: [err := err + dx. y := y + sy]]
!
plotX: x y: y value: v
	(x >= 0 and: [y >= 0 and: [x < form width and: [y < form height]]])
		ifTrue: [form bits at: y * form width + x + 1 put: v]
!
rectangleFrom: p0 to: p1
	| r other |
	r := (p0 min: p1) corner: (p0 max: p1).
	filled ifTrue: [
		other := (ink = foreground premultipliedRGBA8 ifTrue: [background] ifFalse: [foreground]) premultipliedRGBA8.
		r top to: r bottom do: [:y | r left to: r right do: [:x | self plotX: x y: y value: other]]].
	self lineFrom: r topLeft to: r topRight value: ink radius: brushSize // 2.
	self lineFrom: r topRight to: r bottomRight value: ink radius: brushSize // 2.
	self lineFrom: r bottomRight to: r bottomLeft value: ink radius: brushSize // 2.
	self lineFrom: r bottomLeft to: r topLeft value: ink radius: brushSize // 2
!
sprayAt: aPoint
	"The airbrush: random dots within a circle."
	| r rnd |
	r := brushSize * 3 + 4.
	rnd := Random new.
	1 to: r * 2 do: [:i | | dx dy |
		dx := (rnd nextInt: 2 * r + 1) - r - 1.
		dy := (rnd nextInt: 2 * r + 1) - r - 1.
		dx * dx + (dy * dy) <= (r * r) ifTrue: [self plotX: aPoint x + dx y: aPoint y + dy value: ink]]
!
stampX: x y: y value: v radius: r
	"A round dab of radius r (0: one pixel)."
	r = 0 ifTrue: [^self plotX: x y: y value: v].
	r negated to: r do: [:dy |
		r negated to: r do: [:dx |
			dx * dx + (dy * dy) <= (r * r + r) ifTrue: [self plotX: x + dx y: y + dy value: v]]]
! !

!PaintCanvas methodsFor: 'initialize-release'!
initialize
	super initialize.
	tool := #pencil.
	foreground := Color black.
	background := Color white.
	brushSize := 3.
	filled := false.
	self newPicture: 480 @ 320
! !

!PaintCanvas methodsFor: 'remote control'!
remoteLabel
	^'picture ' , form width printString , 'x' , form height printString
! !

!PaintCanvas class methodsFor: 'drawing'!
drawSunken: aRectangle on: aCanvas
	"A 1-pixel sunken edge just outside aRectangle: dark above and at the left, light below and at the right (an outline in flat themes)."
	| t r |
	t := Theme current.
	r := aRectangle expandBy: 1.
	t isBevelled ifFalse: [^aCanvas strokeRect: r color: t rule width: 1].
	aCanvas fillRect: (r origin extent: r width @ 1) color: (t color: #bevelDark).
	aCanvas fillRect: (r origin extent: 1 @ r height) color: (t color: #bevelDark).
	aCanvas fillRect: (r left @ (r bottom - 1) extent: r width @ 1) color: (t color: #bevelLight).
	aCanvas fillRect: ((r right - 1) @ r top extent: 1 @ r height) color: (t color: #bevelLight)
! !
