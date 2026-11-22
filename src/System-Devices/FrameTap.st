Object subclass: #FrameTap
	instanceVariableNames: 'source extent frame listeners lock'
	classVariableNames: ''
	package: 'System-Devices'!

FrameTap comment: 'I tell listeners what changed on a screen, frame by frame (a remote display''s damage feed, docs/graphics-damage.md). The screen''s presenter sends me presented:extent: after each frame it presented, with the rectangles that changed or #full, synchronously and at a cost of O(rectangles) a listener: the firmware screen (UEFI: FirmwareScreen>>present:width:height:rects: and the whole-frame present:width:height:), or the Compositor (hosted, after DisplayWindow>>show:clear:damage:). Each listener (a FrameTapListener, one per client) adds them to its own DamageRegion; its semaphore is signalled when that stops being empty. Damage piles up while a listener does not take it, so the frames it missed cost nothing.

Pixels are read later, when they are sent, from my source (read:, readAll:): the firmware screen''s shadow copy (BGRA8, without the pointer, read under its lock), or the compositor''s surface (RGBA8, read back in its Process); pixelOrder says which. A pixel that changes after it was read is in a later frame''s damage, so a torn rectangle is repaired by the next update.

FrameTap current is the screen''s tap: the firmware screen''s while it draws, else the tap of the World''s compositor.

	| tap l |
	tap := FrameTap current.
	l := tap listen.
	[l hasDamage] whileFalse: [l semaphore wait].
	l takeDamage rects collect: [:r | tap read: r]'!

!FrameTap methodsFor: 'initialization'!
setSource: aSource
	source := aSource.
	frame := 0.
	listeners := #().
	lock := Semaphore forMutualExclusion
!
setExtent: aPointOrNil
	extent := aPointOrNil
! !

!FrameTap methodsFor: 'accessing'!
source
	"What presents the frames and has their pixels: it answers frameTapPixelOrder and frameTapRead:into:."
	^source
!
extent
	"The size in pixels of the last frame presented (nil before the first)."
	^extent
!
frame
	"How many frames were presented."
	^frame
!
listeners
	^listeners
!
pixelOrder
	"#bgra (the firmware screen: RFB's 32-bit true colour with red at 16, green 8, blue 0) or #rgba (a host surface: red at 0), the byte order of the pixels read: answers."
	^source frameTapPixelOrder
! !

!FrameTap methodsFor: 'listening'!
listen
	"A new listener: damage from the next frame on (none yet: read the whole screen first)."
	^self add: (FrameTapListener tap: self)
!
add: aListener
	lock critical: [
		extent isNil ifFalse: [aListener extent: extent].
		listeners := listeners copyWith: aListener].
	^aListener
!
remove: aListener
	lock critical: [listeners := listeners copyWithout: aListener]
!
critical: aBlock
	"Run aBlock while no frame is told to my listeners."
	^lock critical: aBlock
! !

!FrameTap methodsFor: 'presenting'!
presented: rectsOrFull extent: aPoint
	"A frame of aPoint pixels was presented: rectsOrFull (Rectangles or {x. y. width. height} Arrays of pixels) changed since the last one, or #full: all of it. A new size damages everything."
	lock critical: [
		frame := frame + 1.
		extent := aPoint.
		listeners do: [:each | each frame: frame damaged: rectsOrFull extent: aPoint]]
! !

!FrameTap methodsFor: 'reading'!
read: aRectangle
	"The pixels of aRectangle (clipped to the screen) as a ByteArray of rows of 4-byte pixels (pixelOrder), no padding."
	^(self readAll: (Array with: aRectangle)) first
!
readAll: rects
	"The pixels of each of rects (clipped to the screen), read together (under the screen's lock, or in one request to the compositor): ByteArrays as read: answers."
	| clipped |
	clipped := self clip: rects.
	^self readAll: clipped into: (clipped collect: [:r | ByteArray new: r area * 4])
!
readAll: rects into: buffers
	"The pixels of each of rects, which lie within the screen, into the matching ByteArray of buffers (rows of width * 4 bytes); answer buffers."
	(rects anySatisfy: [:r | r area > 0]) ifTrue: [source frameTapRead: rects into: buffers].
	^buffers
!
clip: rects
	"rects (Rectangles or {x. y. width. height}) as Rectangles clipped to the last frame's extent."
	| screen |
	screen := 0 @ 0 extent: (extent isNil ifTrue: [0 @ 0] ifFalse: [extent]).
	^rects asArray collect: [:each | | r |
		r := each isArray ifTrue: [(each at: 1) @ (each at: 2) extent: (each at: 3) @ (each at: 4)] ifFalse: [each].
		r := r intersect: screen.
		(r width > 0 and: [r height > 0]) ifTrue: [r] ifFalse: [screen origin extent: 0 @ 0]]
! !

!FrameTap methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FrameTap('; print: extent; nextPutAll: ', frame '; print: frame; nextPutAll: ', '; print: listeners size; nextPutAll: ' listeners)'
! !

!FrameTap class methodsFor: 'instance creation'!
source: aSource
	"A tap of what aSource presents (FirmwareScreen, Compositor): see FrameTap>>source."
	^self new setSource: aSource
!
source: aSource extent: aPointOrNil
	"The same, of a screen of aPointOrNil pixels so far."
	^(self source: aSource) setExtent: aPointOrNil
! !

!FrameTap class methodsFor: 'accessing'!
current
	"The tap of the screen: the firmware screen's while it draws (UEFI), else that of the World's compositor (hosted), else nil."
	FirmwareDisplay current ifNotNil: [:d | d screen isStarted ifTrue: [^d screen frameTap]].
	^(Smalltalk at: #World ifAbsent: [nil]) ifNotNil: [:w |
		w current ifNotNil: [:world | world compositor ifNotNil: [:c | c frameTap]]]
! !
