Object subclass: #BallView
	instanceVariableNames: 'window x y dx dy room frames'
	classVariableNames: 'Ball'
	package: 'ST80-UI'!

BallView comment: 'I am the animation: a ball bouncing in my window, two pixels a frame. Its picture has a white margin that wide, so drawing it opaque at its new place erases the old one: one displayBits a frame. My window''s title is what the VM calls itself (Smalltalk vmBanner), read again every second: edit VMMain>>banner in the host and it changes. A click reverses the ball.'!

!BallView class methodsFor: 'picture'!
ball
	"20 by 20 pixels, rows of 3 bytes: a black disc 16 across with a white highlight, in a 2-pixel white margin."
	| bits |
	Ball isNil ifFalse: [^Ball].
	bits := ByteArray new: 60.
	0 to: 19 do: [:row |
		0 to: 19 do: [:col |
			((col * 2 - 19) squared + (row * 2 - 19) squared <= 256
				and: [(col * 2 - 13) squared + (row * 2 - 13) squared > 9]) ifTrue: [
					| i |
					i := row * 3 + (col // 8) + 1.
					bits at: i put: ((bits at: i) bitOr: (128 bitShift: (col \\ 8) negated))]]].
	^Ball := bits
! !

!BallView methodsFor: 'initialization'!
initialize
	x := 40.
	y := 10.
	dx := dy := 2.
	frames := 0
!
window: aSystemView
	window := aSystemView.
	self layout
!
layout
	"Where the ball's top left may go."
	room := window inner extent - 20
! !

!BallView methodsFor: 'displaying'!
display
	Display bits: self class ball extent: 20 @ 20 at: window inner origin + (x @ y)
!
step
	"Move, bounce off my window's sides, draw (unless a window in front would be drawn over)."
	x := x + dx.
	y := y + dy.
	(x < 0 or: [x > room x]) ifTrue: [dx := dx negated. x := (x max: 0) min: room x].
	(y < 0 or: [y > room y]) ifTrue: [dy := dy negated. y := (y max: 0) min: room y].
	window isCovered ifFalse: [self display].
	frames := frames + 1.
	(frames \\ 50 = 0 and: [Smalltalk vmBanner ~= window title]) ifTrue: [window title: Smalltalk vmBanner]
!
mouseDown: aPoint
	dx := dx negated.
	dy := dy negated
!
key: aCode modifiers: anInteger
! !
