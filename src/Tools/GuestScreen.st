Widget subclass: #GuestScreen
	instanceVariableNames: 'screenExtent back form nearest rows font glyphs events lock invalid dirty pressed frames frameStart inputStart frameTimes latency onOpen'
	classVariableNames: 'Black White'
	package: 'Tools'!

GuestScreen comment: 'I am the screen of the VM Simulator''s guest (VMSimulation>>display:, what VM-Core''s GuestDisplay draws on): 1-bit pixels, as many as the guest opens, scaled to fit me by a whole number of device pixels, unfiltered. The simulation''s Process draws into a back buffer (I clip); flush copies it into the Form I show and has my window draw me again. Text is JetBrains Mono at 11.67 px, thresholded at half coverage: cells of 7 by 16 pixels. My pointer and key events, in guest pixels and character codes (DisplayPrimitives), wait in a queue for nextEvent.

Timing: a frame runs from the guest''s first call after a flush (it woke up) to the next flush; an input''s latency from its arrival here to the flush after the guest took it. Remote: role canvas, state size= frames= frame= (mean and max over the last 50 frames) input=; remotePointAt: ''x,y'' is the screen point of guest pixel x,y.'!

!GuestScreen class methodsFor: 'class initialization'!
initialize
	Black := 16rFF000000.
	White := 16rFFFFFFFF
! !

!GuestScreen methodsFor: 'initialization'!
initialize
	super initialize.
	lock := Semaphore forMutualExclusion.
	events := OrderedCollection new.
	invalid := dirty := false.
	frames := 0.
	frameTimes := OrderedCollection new
! !

!GuestScreen methodsFor: 'accessing'!
screenExtent
	"The guest's pixels (nil until it opens the display)."
	^screenExtent
!
onOpen: aBlock
	"Run aBlock in my window's Process when the guest opens the display."
	onOpen := aBlock
!
form
	"What the guest showed last."
	^form
!
frames
	^frames
!
frameTime
	"The mean and the longest of the last frames, in µs, or nil."
	frameTimes isEmpty ifTrue: [^nil].
	^Array
		with: (frameTimes inject: 0 into: [:sum :t | sum + t]) // frameTimes size
		with: (frameTimes inject: 0 into: [:m :t | m max: t])
!
latency
	"µs from the last input's arrival to the frame that answered it, or nil."
	^latency
!
cell
	^7 @ 16
! !

!GuestScreen methodsFor: 'guest display'!
open: w height: h
	"A white screen; answer the character cell."
	screenExtent := w @ h.
	back := Bitmap new: w * h withAll: White.
	form := Form width: w height: h.
	nearest := NearestForm on: form.
	rows := Dictionary new.
	rows at: 0 put: (Bitmap new: w withAll: White); at: 1 put: (Bitmap new: w withAll: Black).
	rows at: 2 put: (Bitmap new: w + 1).
	1 to: w + 1 do: [:i | (rows at: 2) at: i put: (i odd ifTrue: [Black] ifFalse: [White])].
	font := Font face: (Font faceNamed: 'JetBrainsMono-Regular') size: 11.67 scale: 1.
	glyphs := Array new: 512.
	lock critical: [events removeAll].
	frames := 0.
	frameTimes removeAll.
	frameStart := inputStart := latency := nil.
	dirty := true.
	self flush.
	onOpen isNil ifFalse: [self inWindowDo: onOpen].
	^self cell
!
fillX: x y: y width: w height: h rule: rule
	| x0 y0 x1 y1 i |
	x0 := x max: 0.
	y0 := y max: 0.
	x1 := x + w min: screenExtent x.
	y1 := y + h min: screenExtent y.
	self noteDrawing.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^self].
	y0 to: y1 - 1 do: [:row |
		i := row * screenExtent x.
		rule = 3
			ifTrue: [x0 + 1 to: x1 do: [:k | back at: i + k put: ((back at: i + k) bitXor: 16rFFFFFF)]]
			ifFalse: [
				back
					replaceFrom: i + x0 + 1 to: i + x1
					with: (rows at: (rule min: 2))
					startingAt: (rule = 2 ifTrue: [(x0 + row) \\ 2 + 1] ifFalse: [1])]]
!
copyX: x y: y width: w height: h toX: toX y: toY
	"The rectangle, clipped where it or its destination leaves the screen."
	| sx sy dx dy cw ch |
	sx := x. sy := y. dx := toX. dy := toY. cw := w. ch := h.
	self noteDrawing.
	sx < 0 ifTrue: [dx := dx - sx. cw := cw + sx. sx := 0].
	dx < 0 ifTrue: [sx := sx - dx. cw := cw + dx. dx := 0].
	sy < 0 ifTrue: [dy := dy - sy. ch := ch + sy. sy := 0].
	dy < 0 ifTrue: [sy := sy - dy. ch := ch + dy. dy := 0].
	cw := (cw min: screenExtent x - sx) min: screenExtent x - dx.
	ch := (ch min: screenExtent y - sy) min: screenExtent y - dy.
	(cw > 0 and: [ch > 0]) ifFalse: [^self].
	(dy > sy ifTrue: [ch - 1 to: 0 by: -1] ifFalse: [0 to: ch - 1]) do: [:r |
		back
			replaceFrom: (dy + r) * screenExtent x + dx + 1 to: (dy + r) * screenExtent x + dx + cw
			with: back
			startingAt: (sy + r) * screenExtent x + sx + 1]
!
text: aString x: x y: y rule: rule
	| cx |
	self noteDrawing.
	cx := x.
	aString do: [:c |
		self glyph: (self glyphFor: c value reversed: rule = 1) x: cx y: y.
		cx := cx + self cell x]
!
bits: aByteArray x: x y: y width: w height: h rule: rule
	"Rows of (w + 7) // 8 bytes, the high bit leftmost: rule 0 opaque, 1 the set bits black, 2 the set bits reversed."
	| stride set i |
	self noteDrawing.
	stride := w + 7 // 8.
	0 to: h - 1 do: [:r |
		(y + r between: 0 and: screenExtent y - 1) ifTrue: [
			0 to: w - 1 do: [:c |
				(x + c between: 0 and: screenExtent x - 1) ifTrue: [
					set := ((aByteArray at: r * stride + (c // 8) + 1) bitAnd: (128 bitShift: (c \\ 8) negated)) ~= 0.
					i := (y + r) * screenExtent x + x + c + 1.
					rule = 0 ifTrue: [back at: i put: (set ifTrue: [Black] ifFalse: [White])].
					(rule = 1 and: [set]) ifTrue: [back at: i put: Black].
					(rule = 2 and: [set]) ifTrue: [back at: i put: ((back at: i) bitXor: 16rFFFFFF)]]]]]
!
nextEvent
	| e |
	frameStart isNil ifTrue: [frameStart := Time microsecondClockValue].
	e := lock critical: [events isEmpty ifTrue: [nil] ifFalse: [events removeFirst]].
	e isNil ifTrue: [^nil].
	inputStart isNil ifTrue: [inputStart := e last].
	^e first: 5
!
flush
	"The frame is complete: show it, if anything was drawn."
	| now |
	now := Time microsecondClockValue.
	inputStart isNil ifFalse: [latency := now - inputStart].
	dirty ifFalse: [^frameStart := inputStart := nil].
	dirty := false.
	form bits replaceFrom: 1 to: back size with: back startingAt: 1.
	form changed.
	frames := frames + 1.
	frameStart isNil ifFalse: [
		frameTimes addLast: now - frameStart.
		frameTimes size > 50 ifTrue: [frameTimes removeFirst]].
	frameStart := inputStart := nil.
	invalid ifTrue: [^self].
	invalid := true.
	self inWindowDo: [
		invalid := false.
		self invalidate]
! !

!GuestScreen methodsFor: 'private'!
noteDrawing
	frameStart isNil ifTrue: [frameStart := Time microsecondClockValue].
	dirty := true
!
glyph: aBitmap x: x y: y
	| x0 x1 y0 y1 cw |
	cw := self cell x.
	x0 := x max: 0.
	x1 := x + cw min: screenExtent x.
	y0 := y max: 0.
	y1 := y + self cell y min: screenExtent y.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^self].
	y0 to: y1 - 1 do: [:row |
		back
			replaceFrom: row * screenExtent x + x0 + 1 to: row * screenExtent x + x1
			with: aBitmap
			startingAt: (row - y) * cw + (x0 - x) + 1]
!
glyphFor: code reversed: aBoolean
	| index |
	index := code + 1 + (aBoolean ifTrue: [256] ifFalse: [0]).
	^(glyphs at: index) ifNil: [glyphs at: index put: (self rasterize: code ink: (aBoolean ifTrue: [White] ifFalse: [Black]))]
!
rasterize: code ink: ink
	"A cell of pixels: the glyph where its coverage is at least half."
	| cell bits info baseline px py |
	cell := self cell.
	bits := Bitmap new: cell x * cell y withAll: (ink = Black ifTrue: [White] ifFalse: [Black]).
	info := font glyphForCodePoint: code phase: 0.
	baseline := font ascent rounded.
	0 to: info height - 1 do: [:gy |
		0 to: info width - 1 do: [:gx |
			px := gx + info left.
			py := baseline + info top + gy.
			((px between: 0 and: cell x - 1) and: [(py between: 0 and: cell y - 1) and: [(info coverageAtX: gx y: gy) >= 128]])
				ifTrue: [bits at: py * cell x + px + 1 put: ink]]].
	^bits
!
queue: type at: aPoint key: key modifiers: aModifiers
	lock critical: [
		events addLast: (Array with: type with: aPoint x with: aPoint y with: key with: aModifiers bits with: Time microsecondClockValue)]
! !

!GuestScreen methodsFor: 'geometry'!
pixelSize
	"Points per guest pixel: the most whole device pixels that fit, at least one."
	| s |
	s := self window isNil ifTrue: [1] ifFalse: [self window world isNil ifTrue: [1] ifFalse: [self window world displayScale]].
	^(((self width * s / screenExtent x) floor min: (self height * s / screenExtent y) floor) max: 1) / s
!
screenRect
	| p |
	p := self pixelSize.
	^((self width - (screenExtent x * p)) / 2) floor @ ((self height - (screenExtent y * p)) / 2) floor extent: (screenExtent x * p) @ (screenExtent y * p)
!
guestPoint: aLocalPoint
	| r |
	r := self screenRect.
	^((((aLocalPoint x - r left) / self pixelSize) floor min: screenExtent x - 1) max: 0)
		@ ((((aLocalPoint y - r top) / self pixelSize) floor min: screenExtent y - 1) max: 0)
! !

!GuestScreen methodsFor: 'drawing'!
drawSelfOn: aCanvas
	aCanvas fillRect: self localBounds color: self theme ink.
	form isNil ifTrue: [
		^aCanvas drawString: 'no guest display' in: self localBounds font: (self theme font: #smallItalic) color: self theme paper align: #center].
	aCanvas image: nearest in: self screenRect
! !

!GuestScreen methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
mouseDown: anEvent
	screenExtent isNil ifTrue: [^false].
	self focus.
	pressed := anEvent button.
	self queue: 1 at: (self guestPoint: (self localEventPosition: anEvent)) key: pressed modifiers: anEvent modifiers.
	^true
!
rightMouseDown: anEvent
	^self mouseDown: anEvent
!
mouseMove: anEvent
	pressed isNil ifTrue: [^false].
	self queue: 3 at: (self guestPoint: (self localEventPosition: anEvent)) key: pressed modifiers: anEvent modifiers.
	^true
!
mouseUp: anEvent
	pressed isNil ifTrue: [^false].
	self queue: 2 at: (self guestPoint: (self localEventPosition: anEvent)) key: pressed modifiers: anEvent modifiers.
	pressed := nil.
	^true
!
keyDown: anEvent
	"Named keys as character codes; printable ones come as text, cmd-P and cmd-D as their letters."
	| key code |
	screenExtent isNil ifTrue: [^false].
	key := anEvent key.
	key isCharacter ifTrue: [
		anEvent modifiers commandKey ifFalse: [^true].
		('pd' includes: key) ifFalse: [^false].
		self queue: 4 at: 0 @ 0 key: key value modifiers: anEvent modifiers.
		^true].
	code := #(#backspace 8 #tab 9 #return 13 #enter 13 #escape 27 #left 28 #right 29 #up 30 #down 31 #delete 127)
		indexOf: key.
	code = 0 ifTrue: [^false].
	self queue: 4 at: 0 @ 0 key: (#(#backspace 8 #tab 9 #return 13 #enter 13 #escape 27 #left 28 #right 29 #up 30 #down 31 #delete 127) at: code + 1) modifiers: anEvent modifiers.
	^true
!
textInput: anEvent
	screenExtent isNil ifTrue: [^false].
	anEvent string do: [:c |
		(c value between: 32 and: 255) ifTrue: [self queue: 4 at: 0 @ 0 key: c value modifiers: anEvent modifiers]].
	^true
!
cursorAt: aPoint
	^#crosshair
! !

!GuestScreen methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^'guest screen'
!
remoteState
	| s t |
	s := OrderedCollection new.
	self isFocused ifTrue: [s add: #focused].
	screenExtent isNil ifTrue: [^s asArray].
	s add: 'size=' , screenExtent x printString , 'x' , screenExtent y printString.
	s add: 'frames=' , frames printString.
	t := self frameTime.
	t isNil ifFalse: [s add: 'frame=' , (t first / 1000.0 printShowingDecimalPlaces: 1) , '/' , (t last / 1000.0 printShowingDecimalPlaces: 1) , 'ms'].
	latency isNil ifFalse: [s add: 'input=' , (latency / 1000.0 printShowingDecimalPlaces: 1) , 'ms'].
	^s asArray
!
remotePointAt: aString
	"The screen point of guest pixel 'x,y'."
	| parts r p |
	parts := aString substrings: ', '.
	(parts size = 2 and: [screenExtent notNil]) ifFalse: [^nil].
	r := self screenRect.
	p := self pixelSize.
	^self localToScreen: r origin + ((parts first asNumber + 0.5) @ (parts last asNumber + 0.5) * p)
! !
