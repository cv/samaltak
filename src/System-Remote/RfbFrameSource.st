Object subclass: #RfbFrameSource
	instanceVariableNames: 'listeners listenersLock'
	classVariableNames: ''
	package: 'System-Remote'!

RfbFrameSource comment: 'I am where an RFB server (RfbServer) gets the screen: its size, its pixels and what changed. Subclasses answer extent (pixels, nil: no screen), bgraOf: aRectangle (that rectangle''s pixels as BGRA8 rows, a ByteArray, read at send time: a pixel that changes after being read is in a later frame''s damage) and cursor (an RfbCursor, nil: none).

Listeners (RfbConnections, attach:/detach:) are told, from whatever Process presents the frame and with no work beyond the rectangles'' count:
	damaged: aCollectionOfRectangles	these pixels changed
	damagedAll	all of them did
	moved: aRectangle to: aPoint	the pixels of aRectangle are now at aPoint (CopyRect); the damage reported with it does not include the destination
	resized: anExtent	the screen has a new size (and all of it is new)
	cursorChanged	the pointer''s shape changed
RfbBufferSource is a screen in memory (tests, and a frame source to start against); RfbWorldSource reads the World''s compositor. The frame tap (D1) feeds the same protocol from the compositor and the firmware screen.'!

!RfbFrameSource methodsFor: 'screen'!
extent
	^self subclassResponsibility
!
bounds
	^0 @ 0 extent: self extent
!
bgraOf: aRectangle
	"aRectangle's pixels (within my extent): BGRA8 rows, width * height * 4 bytes."
	^self subclassResponsibility
!
cursor
	^RfbCursor arrow
! !

!RfbFrameSource methodsFor: 'listeners'!
attach: aListener
	self lock critical: [listeners := (listeners ifNil: [#()]) copyWith: aListener].
	self attached
!
detach: aListener
	self lock critical: [listeners := (listeners ifNil: [#()]) copyWithout: aListener].
	self listeners isEmpty ifTrue: [self detachedAll]
!
listeners
	^listeners ifNil: [#()]
!
attached
	"A listener came (start watching, if a subclass must)."
!
detachedAll
	"The last listener went."
!
notify: aBlock
	self listeners do: [:each | aBlock value: each]
!
lock
	^listenersLock ifNil: [listenersLock := Semaphore forMutualExclusion]
! !
