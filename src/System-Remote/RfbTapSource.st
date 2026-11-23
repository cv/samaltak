RfbFrameSource subclass: #RfbTapSource
	instanceVariableNames: 'tapListeners'
	classVariableNames: ''
	package: 'System-Remote'!

RfbTapSource comment: 'I am the screen for an RFB server as the frame tap gives it (FrameTap current: the firmware screen''s on UEFI, the World compositor''s hosted): its size (the last frame''s), its pixels (FrameTap>>read:, BGRA from the firmware screen''s pointer-free shadow, RGBA read back from the compositor''s surface and swapped) and its damage. Each listener (an RfbConnection) gets a FrameTapListener that signals its wakeSemaphore when a frame damaged something; its writer then collects the damage (collectFor:) and nothing is done for it in the Process that presents beyond adding rectangles. FrameTap is reached late-bound so that I load without it.'!

!RfbTapSource methodsFor: 'screen'!
tap
	^(Smalltalk at: #FrameTap ifAbsent: [^nil]) current
!
extent
	^self tap ifNotNil: [:t | t extent]
!
bgraOf: aRectangle
	| t bytes |
	t := self tap.
	t isNil ifTrue: [^ByteArray new: aRectangle width * aRectangle height * 4].
	bytes := t read: aRectangle.
	t pixelOrder == #rgba ifTrue: [self swapRedBlue: bytes].
	^bytes
!
bgraOfAll: rects
	"One read of all of rects (hosted: one request to the compositor, between two frames). A rectangle the screen no longer holds whole (it shrank meanwhile, and its new size is full damage) is sent black."
	| t all |
	t := self tap.
	t isNil ifTrue: [^super bgraOfAll: rects].
	all := t readAll: rects.
	^rects with: all collect: [:r :bytes | | b |
		b := bytes size = (r area * 4) ifTrue: [bytes] ifFalse: [ByteArray new: r area * 4].
		t pixelOrder == #rgba ifTrue: [self swapRedBlue: b].
		b]
!
pointScale
	"Hosted, the World's points are displayScale pixels; the firmware display works in pixels."
	(Smalltalk at: #FirmwareDisplay ifAbsent: [nil]) ifNotNil: [:c | c current isNil ifFalse: [^1]].
	^(Smalltalk at: #World ifAbsent: [^1]) current ifNil: [1] ifNotNil: [:w | w displayScale]
!
swapRedBlue: bytes
	| n |
	n := bytes size // 4.
	([SoftwareRaster copy: bytes stride: n * 4 from: bytes stride: n * 4 width: n height: 1 bytesPerPixel: 4 mode: 1. true]
		on: Error do: [:e | e return: false]) ifTrue: [^bytes].
	0 to: n - 1 do: [:i | | r |
		r := bytes at: i * 4 + 1.
		bytes at: i * 4 + 1 put: (bytes at: i * 4 + 3).
		bytes at: i * 4 + 3 put: r].
	^bytes
! !

!RfbTapSource methodsFor: 'listeners'!
attach: aConnection
	| l |
	super attach: aConnection.
	l := self tap ifNotNil: [:t | t listen].
	l isNil ifTrue: [^self].
	l semaphore: aConnection wakeSemaphore.
	self lock critical: [self tapListeners at: aConnection put: l]
!
detach: aConnection
	| l |
	l := self lock critical: [self tapListeners removeKey: aConnection ifAbsent: [nil]].
	l isNil ifFalse: [l close].
	super detach: aConnection
!
collectFor: aConnection
	| l d |
	l := self lock critical: [self tapListeners at: aConnection ifAbsent: [nil]].
	(l isNil or: [l hasDamage not]) ifTrue: [^self].
	d := l takeDamage.
	aConnection takeDamage: d rects full: d isFull extent: d bounds extent
!
tapListeners
	^tapListeners ifNil: [tapListeners := IdentityDictionary new]
! !
