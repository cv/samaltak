TestCase subclass: #FrameTapTest
	instanceVariableNames: 'screen frame'
	classVariableNames: ''
	package: 'Tests-Devices'!

FrameTapTest comment: 'The damage feed of a remote display (FrameTap): listeners accumulate the rectangles of the frames presented until they take them, whole frames and new sizes damage everything, a listener''s semaphore is signalled when its damage stops being empty; and on a firmware screen in memory (FirmwareScreen offscreen:) the damage taken and the pixels read from the shadow copy rebuild each frame presented, without the pointer.'!

!FrameTapTest methodsFor: 'running'!
tearDown
	screen isNil ifFalse: [screen freeOffscreen].
	frame isNil ifFalse: [Machine free: frame]
! !

!FrameTapTest methodsFor: 'support'!
tap
	^FrameTap source: nil extent: 200 @ 100
!
signalled: aSemaphore
	"Whether aSemaphore has a signal (consumes it)."
	^(aSemaphore waitTimeoutMSecs: 0) not
!
fill: aRectangle seed: n width: w
	"Pixels of the frame in memory (rows of w pixels) in aRectangle: a pattern of n."
	aRectangle top to: aRectangle bottom - 1 do: [:y |
		aRectangle left to: aRectangle right - 1 do: [:x |
			Machine uint32At: frame + ((y * w + x) * 4) put: (x * 7 + (y * 13) + (n * 101) bitAnd: 16rFFFFFF) + 16rFF000000]]
! !

!FrameTapTest methodsFor: 'tests'!
testListenerAccumulatesFramesUntilTaken
	| tap l d |
	tap := self tap.
	l := tap listen.
	self deny: l hasDamage.
	tap presented: #(#(10 10 5 5)) extent: 200 @ 100.
	tap presented: (Array with: (100 @ 50 extent: 4 @ 4)) extent: 200 @ 100.
	self assert: l hasDamage.
	self assert: l frame equals: 2.
	d := l takeDamage.
	self deny: d isFull.
	self assert: d rects asSet equals: (Set with: (10 @ 10 extent: 5 @ 5) with: (100 @ 50 extent: 4 @ 4)).
	self deny: l hasDamage.
	self assert: l takeDamage isEmpty.
	self assert: tap frame equals: 2
!
testWholeFrameIsFull
	| tap l |
	tap := self tap.
	l := tap listen.
	tap presented: #(#(1 1 1 1)) extent: 200 @ 100.
	tap presented: #full extent: 200 @ 100.
	self assert: l takeDamage isFull.
	tap presented: #() extent: 200 @ 100.
	self deny: l hasDamage
!
testKeepsMoreRectanglesThanABlit
	"32 rectangles, not 8: a remote display pays per byte."
	| tap l d |
	tap := self tap.
	l := tap listen.
	0 to: 19 do: [:i | tap presented: (Array with: (Array with: i \\ 5 * 40 with: i // 5 * 25 with: 2 with: 2)) extent: 200 @ 100].
	d := l takeDamage.
	self assert: d rects size equals: 20.
	self assert: d area equals: 80
!
testSemaphoreSignalledWhenDamageStarts
	| tap l |
	tap := self tap.
	l := tap listen.
	self deny: (self signalled: l semaphore).
	tap presented: #(#(1 1 2 2)) extent: 200 @ 100.
	tap presented: #(#(50 1 2 2)) extent: 200 @ 100.
	self assert: (self signalled: l semaphore).
	self deny: (self signalled: l semaphore) description: 'once while the damage waits'.
	l takeDamage.
	tap presented: #() extent: 200 @ 100.
	self deny: (self signalled: l semaphore) description: 'no damage, no signal'.
	tap presented: #(#(1 1 2 2)) extent: 200 @ 100.
	self assert: (self signalled: l semaphore)
!
testSharedSemaphore
	| tap l s |
	tap := self tap.
	s := Semaphore new.
	l := tap listen semaphore: s; yourself.
	tap presented: #(#(1 1 2 2)) extent: 200 @ 100.
	self assert: (self signalled: s)
!
testNewSizeDamagesEverything
	| tap l d |
	tap := self tap.
	l := tap listen.
	self assert: l extent equals: 200 @ 100.
	tap presented: #(#(1 1 2 2)) extent: 300 @ 120.
	self assert: l extent equals: 300 @ 120.
	d := l takeDamage.
	self assert: d isFull.
	self assert: d bounds equals: (0 @ 0 extent: 300 @ 120).
	self assert: tap extent equals: 300 @ 120
!
testClosedListenerHearsNothing
	| tap l other |
	tap := self tap.
	l := tap listen.
	other := tap listen.
	l close.
	self assert: tap listeners asArray equals: (Array with: other).
	tap presented: #full extent: 200 @ 100.
	self deny: l hasDamage.
	self assert: other hasDamage
!
testDamageIsClippedToTheScreen
	| tap l |
	tap := self tap.
	l := tap listen.
	tap presented: #(#(190 90 30 30) #(500 500 10 10)) extent: 200 @ 100.
	self assert: l takeDamage rects asArray equals: (Array with: (190 @ 90 corner: 200 @ 100))
!
testFirmwareScreenRebuildsEachFrameWithoutThePointer
	| tap l w h mirror whole check d |
	w := 64. h := 48.
	screen := FirmwareScreen offscreen: w @ h.
	frame := Machine allocate: w * h * 4.
	tap := screen frameTap.
	self assert: tap source == screen.
	self assert: tap pixelOrder equals: #bgra.
	self assert: tap extent equals: w @ h.
	l := tap listen.
	self fill: (0 @ 0 extent: w @ h) seed: 1 width: w.
	screen present: frame width: w height: h.
	self assert: l takeDamage isFull.
	whole := 0 @ 0 extent: w @ h.
	mirror := tap read: whole.
	self assert: mirror equals: (Machine bytesAt: frame count: w * h * 4).
	"The pointer, drawn on the screen in the middle, is not in what the tap reads."
	self deny: (Machine bytesAt: screen frameBuffer count: w * h * 4) = mirror.
	check := [:rects :seed |
		rects do: [:r | self fill: r seed: seed width: w].
		screen present: frame width: w height: h rects: (rects collect: [:r | Array with: r left with: r top with: r width with: r height]).
		d := l takeDamage.
		d rects do: [:r | | bytes |
			bytes := tap read: r.
			0 to: r height - 1 do: [:y |
				mirror replaceFrom: ((r top + y) * w + r left) * 4 + 1 to: ((r top + y) * w + r right) * 4 with: bytes startingAt: y * r width * 4 + 1]].
		self assert: mirror equals: (Machine bytesAt: frame count: w * h * 4)].
	check value: (Array with: (5 @ 6 extent: 7 @ 8)) value: 2.
	self assert: d rects asArray equals: (Array with: (5 @ 6 extent: 7 @ 8)).
	check value: (Array with: (30 @ 20 extent: 10 @ 10) with: (0 @ 40 extent: 3 @ 8)) value: 3.
	check value: (Array with: (60 @ 0 extent: 4 @ 48)) value: 4.
	self assert: tap frame equals: 4.
	self assert: ((tap readAll: (Array with: (0 @ 0 extent: 2 @ 2) with: (62 @ 46 extent: 9 @ 9))) collect: [:b | b size]) equals: #(16 16)
! !
