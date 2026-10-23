ToolPane subclass: #MandelbrotView
	instanceVariableNames: 'image status form centerX centerY span maxIterations escapeMagnitude palette rendering progress renderStart lastSeconds lastPublish queued pendingRender'
	classVariableNames: ''
	package: 'Tools'!

MandelbrotView comment: 'I am the Mandelbrot window, the busy-window demo: render computes the set in my window''s own Process, in Smalltalk, row by row into a Form (escapeTimeAt: iterates z := z squared + c with Complex numbers), publishing my DisplayList every few rows so the picture appears progressively while the compositor keeps every other window smooth. Meanwhile the title bar shows the window busy, a stripe runs above the picture and the status bar counts the progress.

A click zooms ×3 at the clicked point (shift-click zooms out) and renders again with more iterations. Clicks made while I render wait in my window''s event queue: I count them ("1 click queued — this window''s Process is busy") and they are handled, one zoom each, when the rendering is done. Palette: the Blue Book one of the prototype (white, greys, ultramarine, a black interior).'!

!MandelbrotView methodsFor: 'initialization'!
initialize
	super initialize.
	centerX := -0.62.
	centerY := 0.0.
	span := 3.1.
	maxIterations := 160.
	rendering := false.
	progress := 0.
	queued := 0.
	lastPublish := 0.
	palette := self class bluePalette.
	image := MandelbrotImage new name: 'view'; yourself.
	image mandelbrot: self.
	status := StatusBar new name: 'status'; yourself.
	self updateStatus.
	self addAll: (Array with: image with: status)
!
minimumWindowExtent
	^200 @ 160
! !

!MandelbrotView methodsFor: 'accessing'!
form
	^form
!
isRendering
	^rendering
!
progress
	^progress
!
queuedClicks
	^queued
!
maxIterations
	^maxIterations
!
zoomFactor
	^(3.1 / span) rounded
!
lastSeconds
	^lastSeconds
!
center
	^centerX @ centerY
!
progressText
	"While rendering: how far, e.g. '85%' (the Process Browser shows it after my Process)."
	^rendering ifTrue: [(progress * 100) rounded printString, '%'] ifFalse: [nil]
!
span
	^span
! !

!MandelbrotView methodsFor: 'rendering'!
pixelScale
	"Pixels per point of the picture: 1.5, as the prototype's (on a Retina display)."
	^1.5
!
prepareForm
	| s w h |
	s := self pixelScale.
	w := (image width * s) rounded max: 1.
	h := (image height * s) rounded max: 1.
	(form isNil or: [form width ~= w or: [form height ~= h]]) ifTrue: [
		form := Form width: w height: h.
		form fill: Color white]
!
render
	"Runs in my window's Process: compute every row, publishing as I go. The compositor keeps showing my last published DisplayList, so the rest of the world stays smooth."
	| w |
	pendingRender := nil.
	image width < 1 ifTrue: [^self].
	self prepareForm.
	w := self window.
	rendering := true.
	progress := 0.
	renderStart := Time millisecondClockValue.
	w isNil ifFalse: [w busyLabel: 'rendering'; busy: true].
	[0 to: form height - 1 do: [:y |
		self renderRow: y.
		Time millisecondClockValue - lastPublish > 50 ifTrue: [
			progress := y + 1 / form height.
			self publish]]]
		ensure: [
			rendering := false.
			lastSeconds := Time millisecondClockValue - renderStart / 1000.0.
			w isNil ifFalse: [w busy: false; busyLabel: nil]].
	progress := 1.
	self publish
!
renderRow: y
	| bits base half scale ci |
	bits := form bits.
	base := y * form width.
	half := form width / 2.0.
	scale := span / form width.
	ci := centerY + ((y - (form height / 2.0)) * scale).
	0 to: form width - 1 do: [:x |
		bits at: base + x + 1 put: (self pixelFor: (self escapeTimeAt: (Complex real: centerX + ((x - half) * scale) imaginary: ci)))]
!
escapeTimeAt: c
	"The number of iterations of z := z squared + c until |z| > 4 (at most maxIterations); escapeMagnitude keeps |z|² for smooth colouring. Periodicity checking (Brent): z is compared with a value saved at doubling intervals; when the orbit comes back within the tolerance (Euclidean distance) it is periodic, so c is inside the set and answers maxIterations at once."
	| z n saved period limit tolerance dx dy |
	z := Complex zero.
	saved := z.
	n := 0.
	period := 0.
	limit := 2.
	tolerance := self class periodicityTolerance squared.
	[n < maxIterations and: [z squaredMagnitude <= 16.0]] whileTrue: [
		z := z squared + c.
		n := n + 1.
		dx := z real - saved real.
		dy := z imaginary - saved imaginary.
		(dx * dx) + (dy * dy) < tolerance ifTrue: [^maxIterations].
		(period := period + 1) = limit ifTrue: [
			saved := z.
			period := 0.
			limit := limit * 2]].
	escapeMagnitude := z squaredMagnitude.
	^n
!
pixelFor: n
	"Premultiplied RGBA8 of an escape time (black inside), smoothed like the prototype."
	| smooth index |
	n >= maxIterations ifTrue: [^16rFF000000].
	smooth := n + 1 - ((escapeMagnitude ln / 2.0) ln / 2.0 ln).
	index := ((smooth max: 0) sqrt * 34) floor \\ 256.
	^palette at: index + 1
!
publish
	"Show what I have so far: redraw now, in my Process (the event loop is busy with me)."
	| w |
	lastPublish := Time millisecondClockValue.
	form isNil ifFalse: [form changed].
	w := self window.
	queued := w isNil
		ifTrue: [0]
		ifFalse: [w queue countItemsSatisfying: [:e | (e respondsTo: #isPointer) and: [e isPointer and: [e type == #down]]]].
	image stripePhase: (lastPublish / 400.0) \\ 1.
	image invalidate.
	self updateStatus.
	w isNil ifFalse: [w redraw]
!
scheduleRender
	"Render again soon (after a resize), once."
	pendingRender isNil ifFalse: [pendingRender cancel].
	pendingRender := self after: 200 do: [self render]
! !

!MandelbrotView methodsFor: 'zooming'!
zoomAt: aPoint out: aBoolean
	"aPoint in the picture's coordinates (points)."
	| s |
	form isNil ifTrue: [^self render].
	s := span / image width.
	centerX := centerX + ((aPoint x - (image width / 2.0)) * s).
	centerY := centerY + ((aPoint y - (image height / 2.0)) * s).
	aBoolean
		ifTrue: [span := span * 3 min: 3.1. maxIterations := maxIterations - 90 max: 160]
		ifFalse: [span := span / 3. maxIterations := maxIterations + 90].
	queued := queued - 1 max: 0.
	self render
!
reset
	centerX := -0.62.
	centerY := 0.0.
	span := 3.1.
	maxIterations := 160.
	self render
! !

!MandelbrotView methodsFor: 'status'!
updateStatus
	status clear.
	status add: maxIterations printString, ' iterations · ×', self zoomFactor printString style: #mono.
	rendering
		ifTrue: [status addRight: 'rendering ', (progress * 100) rounded printString, '%' style: #pillBusy]
		ifFalse: [
			lastSeconds isNil ifFalse: [
				status add: (lastSeconds printShowingDecimalPlaces: 1), ' s in Process ''', (self window isNil ifTrue: ['Mandelbrot'] ifFalse: [self window process name]), '''' style: #text]]
! !

!MandelbrotView methodsFor: 'layout'!
layout
	| old |
	old := image isNil ifTrue: [nil] ifFalse: [image extent].
	super layout.
	(image notNil and: [old notNil and: [old ~= image extent and: [form notNil and: [rendering not]]]])
		ifTrue: [self scheduleRender]
! !

!MandelbrotView class methodsFor: 'rendering'!
periodicityTolerance
	"How close (Euclidean distance) an orbit must come back to a saved value to count as periodic."
	^1.0e-3
! !

!MandelbrotView class methodsFor: 'palette'!
bluePalette
	"256 premultiplied RGBA8 words interpolated through the Blue Book stops (themes/blue-book.css --fractal-stops)."
	| stops lut |
	stops := #(#(255 255 255) #(232 234 240) #(176 184 206) #(27 58 140) #(6 12 36) #(120 120 120) #(255 255 255)).
	lut := Array new: 256.
	0 to: 255 do: [:i |
		| t k f rgb |
		t := i / 256.0 * (stops size - 1).
		k := t floor.
		f := t - k.
		rgb := (1 to: 3) collect: [:c |
			| a b |
			a := (stops at: k + 1) at: c.
			b := (stops at: k + 2) at: c.
			(a + (b - a * f)) rounded].
		lut at: i + 1 put: (rgb at: 1) + ((rgb at: 2) bitShift: 8) + ((rgb at: 3) bitShift: 16) + 16rFF000000].
	^lut
! !

!MandelbrotView class methodsFor: 'opening'!
openIn: aRectangle delay: milliseconds
	| view window |
	view := self new.
	window := view openIn: aRectangle title: 'Mandelbrot'.
	window do: [view after: milliseconds do: [view render]].
	^window
!
initialize
	ToolsMenu register: 'Mandelbrot' description: 'busy window demo' order: 50 action: [:point |
		self openIn: (Tools placeAt: point extent: 330 @ 300) delay: 50]
! !
