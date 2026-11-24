Widget subclass: #GuestScreen
	instanceVariableNames: 'nearest pixels events lock pendingRedraw pressed frames inputStart frameTimes latency onOpen'
	classVariableNames: 'PackedPixels'
	package: 'Tools'!

GuestScreen comment: 'I present the VM Simulator guest''s completed 1-bit frames (VMGuestSimulation), scaled by whole points without filtering. I unpack the rows into an RGBA Form. Pointer and keyboard events wait in a queue for the simulator.

Remote: role canvas; state size= frames= frame= (guest processing time, mean/max over the last 50 measured frames) input= (queue arrival to the next frame after the simulator takes an event). remotePointAt: ''x,y'' is the screen point of guest pixel x,y.'!

!GuestScreen class methodsFor: 'initialization'!
initialize
	"Each possible packed byte as eight opaque RGBA pixels, high bit leftmost."
	PackedPixels := (0 to: 255) collect: [:byte |
		| bits |
		bits := Bitmap new: 8.
		1 to: 8 do: [:i |
			bits at: i put: ((byte bitAt: 9 - i) = 1 ifTrue: [16rFF000000] ifFalse: [16rFFFFFFFF])].
		bits]
! !

!GuestScreen methodsFor: 'initialization'!
initialize
	super initialize.
	lock := Semaphore forMutualExclusion.
	events := OrderedCollection new.
	frames := 0.
	frameTimes := OrderedCollection new
!
reset
	"Clear the pane after stopping its simulation, before starting another."
	pendingRedraw := nil.
	nearest := pixels := pressed := nil.
	lock critical: [events removeAll. frameTimes removeAll].
	frames := 0.
	inputStart := latency := nil.
	self invalidate
! !

!GuestScreen methodsFor: 'accessing'!
screenExtent
	"The guest's pixels (nil until its first frame)."
	^nearest ifNotNil: [nearest extent]
!
onOpen: aBlock
	"Run aBlock in my window's Process on the first frame."
	onOpen := aBlock
!
form
	"What the guest showed last."
	^nearest ifNotNil: [nearest source]
!
frames
	^frames
!
frameTime
	"The mean and the longest of the last measured frames, in µs, or nil."
	| times |
	times := lock critical: [frameTimes asArray].
	times isEmpty ifTrue: [^nil].
	^Array
		with: (times inject: 0 into: [:sum :t | sum + t]) // times size
		with: (times inject: 0 into: [:m :t | m max: t])
!
latency
	"Approximate input-to-frame latency in µs, or nil."
	^latency
! !

!GuestScreen methodsFor: 'guest display'!
displayFrame: packedBytes extent: anExtent time: frameTime
	"Called by the simulation with a complete, validated frame."
	| now firstFrame w h target |
	now := Time microsecondClockValue.
	firstFrame := nearest isNil.
	w := anExtent x.
	h := anExtent y.
	target := self form.
	(target isNil or: [target extent ~= anExtent]) ifTrue: [
		pixels := Bitmap new: w * h.
		target := Form width: w height: h].
	self unpack: packedBytes width: w height: h.
	"Publish with a bulk copy so the window never sees a partially unpacked frame."
	target bits replaceFrom: 1 to: pixels size with: pixels startingAt: 1.
	target changed.
	target == self form ifFalse: [nearest := NearestForm on: target].
	frames := frames + 1.
	inputStart isNil ifFalse: [
		latency := now - inputStart.
		inputStart := nil].
	(frameTime notNil and: [frameTime > 0]) ifTrue: [
		lock critical: [
			frameTimes addLast: frameTime.
			frameTimes size > 50 ifTrue: [frameTimes removeFirst]]].
	self redrawFrameOpening: firstFrame
!
nextEvent
	| e |
	e := lock critical: [events isEmpty ifTrue: [nil] ifFalse: [events removeFirst]].
	e isNil ifTrue: [^nil].
	inputStart isNil ifTrue: [inputStart := e last].
	^e first: 5
! !

!GuestScreen methodsFor: 'private'!
unpack: packedBytes width: w height: h
	"Map packed 1-bit pixels to RGBA, ignoring the right-hand padding of each row."
	| src dest widthInBytes remainder |
	src := dest := 1.
	widthInBytes := w // 8.
	remainder := w \\ 8.
	1 to: h do: [:row |
		1 to: widthInBytes do: [:column |
			pixels replaceFrom: dest to: dest + 7 with: (PackedPixels at: (packedBytes at: src) + 1) startingAt: 1.
			src := src + 1.
			dest := dest + 8].
		remainder > 0 ifTrue: [
			pixels replaceFrom: dest to: dest + remainder - 1 with: (PackedPixels at: (packedBytes at: src) + 1) startingAt: 1.
			src := src + 1.
			dest := dest + remainder]]
!
redrawFrameOpening: firstFrame
	| token |
	pendingRedraw isNil ifFalse: [^self].
	token := pendingRedraw := Object new.
	self inWindowDo: [
		"Ignore redraws queued by a simulation that has since been reset."
		token == pendingRedraw ifTrue: [
			pendingRedraw := nil.
			(firstFrame and: [onOpen notNil]) ifTrue: [onOpen value].
			self invalidate]]
!
queue: type at: aPoint key: key modifiers: aModifiers
	lock critical: [
		events addLast: (Array with: type with: aPoint x with: aPoint y with: key with: aModifiers bits with: Time microsecondClockValue)]
! !

!GuestScreen methodsFor: 'geometry'!
pixelSize
	"Points per guest pixel: the most whole points that fit, at least one."
	| extent |
	extent := self screenExtent.
	^((self width / extent x) floor min: (self height / extent y) floor) max: 1
!
screenRect
	| extent |
	extent := self screenExtent * self pixelSize.
	^((self width - extent x) / 2) floor @ ((self height - extent y) / 2) floor extent: extent
!
guestPoint: aLocalPoint
	| r p extent |
	r := self screenRect.
	p := self pixelSize.
	extent := self screenExtent.
	^((((aLocalPoint x - r left) / p) floor min: extent x - 1) max: 0)
		@ ((((aLocalPoint y - r top) / p) floor min: extent y - 1) max: 0)
! !

!GuestScreen methodsFor: 'drawing'!
drawSelfOn: aCanvas
	aCanvas fillRect: self localBounds color: self theme ink.
	nearest isNil ifTrue: [
		^aCanvas drawString: 'no guest display' in: self localBounds font: (self theme font: #smallItalic) color: self theme paper align: #center].
	aCanvas image: nearest in: self screenRect
! !

!GuestScreen methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
mouseDown: anEvent
	nearest isNil ifTrue: [^false].
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
	nearest isNil ifTrue: [^false].
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
	nearest isNil ifTrue: [^false].
	anEvent string do: [:c |
		(c value between: 32 and: 255) ifTrue: [self queue: 4 at: 0 @ 0 key: c value modifiers: anEvent modifiers]].
	^true
! !

!GuestScreen methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^'guest screen'
!
remoteState
	| s t extent |
	s := OrderedCollection new.
	self isFocused ifTrue: [s add: #focused].
	nearest isNil ifTrue: [^s asArray].
	extent := self screenExtent.
	s add: 'size=' , extent x printString , 'x' , extent y printString.
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
	(parts size = 2 and: [nearest notNil]) ifFalse: [^nil].
	r := self screenRect.
	p := self pixelSize.
	^self localToScreen: r origin + ((parts first asNumber + 0.5) @ (parts last asNumber + 0.5) * p)
! !
