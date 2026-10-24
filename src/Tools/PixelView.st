Widget subclass: #PixelView
	instanceVariableNames: 'form nearest drawnVersion zoom hover wheel onChange'
	classVariableNames: ''
	package: 'Tools'!

PixelView comment: 'I show a Form''s pixels magnified without filtering, at an integer zoom (points per pixel: the largest that fits, centered, until the wheel or + - change it; 0 fits again), with a one-device-pixel grid from zoom 6 on. The pixel under the pointer is outlined; its coordinates and value (Form>>pixelComponentsAt:: a GlyphForm''s coverage, else the stored r g b a) are in hoverText and my remote state. onChange: [:view] runs when the hover or the zoom changes. The Inspector shows me for Forms.

Remote: role canvas, state zoom=16 size=13x20 hover=4,7 value=211; remotePointAt: ''4,7'' is the screen point of that pixel (samaltak-ctl hover @w3.pixels --at 4,7).'!

!PixelView methodsFor: 'initialization'!
initialize
	super initialize.
	wheel := 0
! !

!PixelView methodsFor: 'accessing'!
form
	^form
!
form: aForm
	form := aForm.
	nearest := nil.
	hover := nil.
	self invalidate
!
onChange: aBlock
	onChange := aBlock
!
hover
	"The pixel (0-based Point) under the pointer, or nil."
	^hover
!
zoom
	^zoom ifNil: [self fitZoom]
!
zoom: anIntegerOrNil
	"Points per pixel; nil: the largest that fits."
	zoom := anIntegerOrNil isNil ifFalse: [(anIntegerOrNil max: 1) min: 64].
	hover := nil.
	self invalidate.
	self notifyChange
!
fitZoom
	(form isNil or: [form width = 0 or: [form height = 0]]) ifTrue: [^1].
	^((((self width - 16) / form width) floor min: ((self height - 16) / form height) floor) max: 1) min: 64
!
isEmpty
	^form isNil or: [form width = 0 or: [form height = 0]]
! !

!PixelView methodsFor: 'geometry'!
origin
	"The local top-left of pixel 0@0 (whole points, centered)."
	| z |
	z := self zoom.
	^((self width - (form width * z)) / 2) floor @ ((self height - (form height * z)) / 2) floor
!
pixelAt: aLocalPoint
	"The pixel under aLocalPoint, or nil."
	| z o x y |
	self isEmpty ifTrue: [^nil].
	z := self zoom.
	o := self origin.
	x := (aLocalPoint x - o x / z) floor.
	y := (aLocalPoint y - o y / z) floor.
	(x < 0 or: [y < 0 or: [x >= form width or: [y >= form height]]]) ifTrue: [^nil].
	^x @ y
!
rectOfPixel: aPoint
	| z |
	z := self zoom.
	^self origin + (aPoint * z) extent: z @ z
!
screenPointOfPixel: aPoint
	^self localToScreen: (self rectOfPixel: aPoint) center
! !

!PixelView methodsFor: 'values'!
hoverText
	"x 4  y 7   coverage 211, or nil."
	| s names values |
	hover isNil ifTrue: [^nil].
	names := form pixelComponentNames.
	values := form pixelComponentsAt: hover.
	s := WriteStream on: (String new: 40).
	s nextPutAll: 'x '; print: hover x; nextPutAll: '  y '; print: hover y; nextPutAll: ' '.
	names with: values do: [:n :v | s nextPutAll: '  '; nextPutAll: n; space; print: v].
	^s contents
!
valueString
	"The hovered pixel's components, comma-separated (211, or 255,0,0,255)."
	| s |
	s := WriteStream on: (String new: 16).
	(form pixelComponentsAt: hover) do: [:v | s print: v] separatedBy: [s nextPut: $,].
	^s contents
!
summary
	"13×20 · zoom 16"
	form isNil ifTrue: [^''].
	^form width printString, '×', form height printString, ' · zoom ', self zoom printString
! !

!PixelView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| z o r |
	aCanvas fillRect: self localBounds color: self theme paper.
	form isNil ifTrue: [^self].
	drawnVersion := form version.
	self isEmpty ifTrue: [
		^aCanvas drawString: 'no pixels' in: self localBounds font: (self theme font: #smallItalic) color: self theme muted align: #center].
	z := self zoom.
	o := self origin.
	r := o extent: (form width * z) @ (form height * z).
	aCanvas image: self nearestForm in: r.
	z >= 6 ifTrue: [self drawGridIn: r zoom: z on: aCanvas].
	aCanvas strokeRect: (r expandBy: 1) color: (self theme color: #ink4) width: 1
!
drawGridIn: r zoom: z on: aCanvas
	"One device pixel wide lines between the visible cells."
	| lw color top bottom left right |
	lw := 1 / aCanvas scale.
	color := (self theme color: #l3) alpha: 0.75.
	top := r top max: 0.
	bottom := r bottom min: self height.
	left := r left max: 0.
	right := r right min: self width.
	(0 max: (left - r left / z) floor) to: (form width min: (right - r left / z) ceiling) do: [:i |
		aCanvas fillRect: (r left + (i * z) @ top extent: lw @ (bottom - top)) color: color].
	(0 max: (top - r top / z) floor) to: (form height min: (bottom - r top / z) ceiling) do: [:i |
		aCanvas fillRect: (left @ (r top + (i * z)) extent: (right - left) @ lw) color: color]
!
drawOverlayOn: aCanvas
	| cell |
	(hover isNil or: [self isEmpty]) ifTrue: [^self].
	cell := self rectOfPixel: hover.
	aCanvas strokeRect: (cell expandBy: 2) color: self theme paper width: 3.
	aCanvas strokeRect: (cell expandBy: 1) color: self theme ultramarine width: 2
!
nearestForm
	(nearest isNil or: [nearest bits ~~ form bits or: [nearest extent ~= form extent]]) ifTrue: [nearest := NearestForm on: form].
	^nearest
!
refresh
	"Redraw when the form's pixels changed (the Inspector asks twice a second)."
	(form isNil or: [form version = drawnVersion]) ifTrue: [^self].
	self invalidate.
	self notifyChange
!
notifyChange
	onChange isNil ifFalse: [onChange value: self]
! !

!PixelView methodsFor: 'events'!
hoverAt: aLocalPoint
	| p |
	p := self pixelAt: aLocalPoint.
	p = hover ifTrue: [^self].
	hover := p.
	self invalidateOverlay.
	self notifyChange
!
mouseMove: anEvent
	self hoverAt: (self localEventPosition: anEvent).
	^true
!
mouseEnter: anEvent
	self hoverAt: (self localEventPosition: anEvent).
	^true
!
mouseLeave: anEvent
	hover isNil ifFalse: [hover := nil. self invalidateOverlay. self notifyChange].
	^true
!
mouseDown: anEvent
	^anEvent button = 1
!
mouseUp: anEvent
	^true
!
wheel: anEvent
	"Zoom in (away from the user) or out, one step per wheel unit."
	| steps |
	wheel := wheel + anEvent delta y.
	steps := wheel truncated.
	steps = 0 ifTrue: [^true].
	wheel := wheel - steps.
	self zoom: self zoom + steps.
	self hoverAt: (self localEventPosition: anEvent).
	^true
!
wantsKeyboardFocus
	^true
!
keyDown: anEvent
	| key |
	key := anEvent key.
	(key = $= or: [key = $+]) ifTrue: [self zoom: self zoom + 1. ^true].
	key = $- ifTrue: [self zoom: self zoom - 1. ^true].
	key = $0 ifTrue: [self zoom: nil. ^true].
	^false
!
cursorAt: aPoint
	^#crosshair
!
layout
	"A new extent moves the pixels (and may change the fitting zoom)."
	hover := nil.
	self notifyChange
! !

!PixelView methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^'Pixels'
!
remoteState
	| s |
	s := OrderedCollection withAll: super remoteState.
	form isNil ifTrue: [^s asArray].
	s add: 'zoom=', self zoom printString.
	s add: 'size=', form width printString, 'x', form height printString.
	hover isNil ifFalse: [
		s add: 'hover=', hover x printString, ',', hover y printString.
		s add: 'value=', self valueString].
	^s asArray
!
remotePointAt: aString
	"The screen point of pixel 'x,y'."
	| parts |
	parts := aString substrings: ', '.
	parts size = 2 ifFalse: [^nil].
	^self screenPointOfPixel: parts first asNumber @ parts last asNumber
! !
