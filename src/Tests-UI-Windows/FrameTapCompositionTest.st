UIWindowsTestCase subclass: #FrameTapCompositionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

FrameTapCompositionTest comment: 'The hosted damage feed of a remote display: a listener on the World''s compositor''s FrameTap, reading back only the rectangles its damage names, keeps a copy of the screen that equals the whole surface read back, through typing, dragging, raising, toasts, menus and closing windows; the feed is partial for small changes.'!

!FrameTapCompositionTest methodsFor: 'support'!
follow: aListener into: mirror
	"Take aListener's damage, read its rectangles into mirror (the screen's pixels so far) and check mirror against the whole screen read back, both between the same two frames (in the compositor's Process: the top bar's readout may change at any frame); answer the damage."
	| tap d rects w whole |
	self settle.
	tap := aListener tap.
	world compositor sync: [
		d := aListener takeDamage.
		w := tap extent x.
		rects := tap clip: d rects.
		rects with: (tap readAll: rects) do: [:r :bytes |
			0 to: r height - 1 do: [:y |
				mirror replaceFrom: ((r top + y) * w + r left) * 4 + 1 to: ((r top + y) * w + r right) * 4 with: bytes startingAt: y * r width * 4 + 1]].
		whole := tap read: (0 @ 0 extent: tap extent)].
	self assert: mirror size = whole size description: 'the screen changed size'.
	self assert: (self differingPixels: mirror and: whole) = 0 description: (self differingPixels: mirror and: whole) printString, ' pixels missed by ', d printString.
	^d
!
differingPixels: a and: b
	| n |
	n := 0.
	1 to: a size by: 4 do: [:i | ((a at: i) = (b at: i) and: [(a at: i + 1) = (b at: i + 1) and: [(a at: i + 2) = (b at: i + 2)]]) ifFalse: [n := n + 1]].
	^n
! !

!FrameTapCompositionTest methodsFor: 'tests'!
testCurrentIsTheWorldsCompositor
	| tap |
	tap := FrameTap current.
	FirmwareDisplay current isNil ifTrue: [
		self assert: tap source == world compositor.
		self assert: tap pixelOrder equals: #rgba].
	self settle.
	self assert: tap extent notNil
!
testListenerRebuildsTheScreen
	| tap l mirror a b partial |
	tap := world compositor frameTap.
	self settle.
	world compositor sync: [
		l := tap listen.
		mirror := tap read: (0 @ 0 extent: tap extent)].
	partial := 0.
	a := self open: (DamageTestView new color: Color white; yourself) title: 'A' at: (100 @ 100 extent: 300 @ 200).
	self follow: l into: mirror.
	b := self open: (RecordingTestView new color: Color ultramarine; yourself) title: 'B' at: (450 @ 150 extent: 300 @ 200).
	self follow: l into: mirror.
	1 to: 4 do: [:i |
		a content add: 'line ', i printString.
		(self follow: l into: mirror) isFull ifFalse: [partial := partial + 1]].
	self drag: 200 @ 110 to: 500 @ 400.
	self follow: l into: mirror.
	world toast: 'Hello'.
	self follow: l into: mirror.
	self rightClick: 800 @ 600.
	self follow: l into: mirror.
	self key: #escape modifiers: 0.
	self follow: l into: mirror.
	b close.
	self follow: l into: mirror.
	self assert: partial > 0 description: 'typing damages part of the screen'.
	l close
!
testDraggedWindowIsAMove
	"Dragging a window by its title bar (held, in steps: lifted, it is drawn a little smaller, the same each frame): the frame tap hears that its layer's pixels moved, by the step in device pixels."
	| tap l a moves s |
	tap := world compositor frameTap.
	a := self open: (DamageTestView new color: Color white; yourself) title: 'Moved' at: (100 @ 100 extent: 300 @ 200).
	self settle.
	self down: 200 @ 110.
	self moveTo: 205 @ 112.
	self settle.
	l := tap listen.
	moves := OrderedCollection new.
	1 to: 6 do: [:i |
		self moveTo: (205 + (i * 10)) @ (112 + (i * 6)).
		self settle.
		moves addAll: (l take at: 2)].
	self up: 265 @ 148.
	self settle.
	s := world displayScale.
	self assert: moves notEmpty description: 'no move heard'.
	self assert: (moves anySatisfy: [:m | (m at: 2) - m first origin = ((10 @ 6) * s) rounded]).
	l close.
	a close
!
testIdleWorldGivesLittleDamage
	| tap l d |
	tap := world compositor frameTap.
	self settle.
	l := tap listen.
	world waitForFrames: 5.
	d := l takeDamage.
	self deny: d isFull.
	self assert: d area < (tap extent x * 40) description: 'at most the top bar''s readout'.
	l close
! !
