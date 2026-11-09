Object subclass: #Animation
	instanceVariableNames: 'from to duration easing action startTime delay value finished doneBlocks frameBlock'
	classVariableNames: 'Clock'
	package: 'UI-Windows'!

Animation comment: 'I tween a value (Number, Point, Rectangle or Color: interpolateTo:at:) from from to to over duration milliseconds with an easing, on the compositor clock (milliseconds, Float), calling action with each value:

	Animation from: 0 to: 100 duration: 140 easing: #easeOutCubic do: [:x | ...]

Run me with aWindow animate: (stepped in the window''s Process, the window redraws after each step) or aLayer animate: (stepped by the Compositor: smooth even when the window''s Process is busy). A frame animation (Animation everyFrame: [:ms | ... true to continue]) runs until its block answers false. I start at the first frame after I am added (or at startAt:). whenDone: blocks run once when I reach my end (not when stopped).

The clock is real time slowed down by timeScale (Animation timeScale: 10 is slow motion for every animation, the compositor''s included; 1 is normal speed); changing the scale never makes the clock jump.

Easings: #linear #easeInQuad #easeOutQuad #easeInOutQuad #easeInCubic #easeOutCubic #easeInOutCubic #spring (critically damped, no overshoot).'!

!Animation methodsFor: 'initialization'!
setFrom: a to: b duration: ms easing: aSymbol action: aBlock
	from := a.
	to := b.
	duration := ms max: 0.
	easing := aSymbol ifNil: [#linear].
	action := aBlock.
	delay := 0.
	finished := false.
	value := a
!
setFrameBlock: aBlock
	frameBlock := aBlock.
	duration := 0.
	delay := 0.
	finished := false
! !

!Animation methodsFor: 'accessing'!
from
	^from
!
to
	^to
!
duration
	^duration
!
easing
	^easing
!
value
	"The current value."
	^value
!
startTime
	^startTime
!
delay: milliseconds
	"Start milliseconds after the first frame."
	delay := milliseconds
!
startAt: ms
	startTime := ms
!
whenDone: aBlock
	doneBlocks isNil ifTrue: [doneBlocks := OrderedCollection new].
	doneBlocks add: aBlock
!
isFinished
	^finished
!
isFrameAnimation
	^frameBlock notNil
! !

!Animation methodsFor: 'running'!
stop
	"Stop without reaching the end (whenDone: blocks do not run)."
	finished := true
!
finish
	"Jump to the end value now."
	finished ifTrue: [^self].
	frameBlock isNil ifTrue: [
		value := to.
		action isNil ifFalse: [action value: value]].
	self complete
!
stepAt: ms
	"Advance to the compositor time ms (milliseconds); answer whether I am still running."
	| t |
	finished ifTrue: [^false].
	startTime isNil ifTrue: [startTime := ms].
	frameBlock isNil ifFalse: [
		(frameBlock value: ms) == false ifTrue: [self complete].
		^finished not].
	ms < (startTime + delay) ifTrue: [^true].
	t := duration <= 0
		ifTrue: [1]
		ifFalse: [((ms - startTime - delay) / duration max: 0) min: 1].
	value := t >= 1 ifTrue: [to] ifFalse: [self class interpolate: from to: to at: (self class ease: easing at: t)].
	action isNil ifFalse: [action value: value].
	t >= 1 ifTrue: [self complete].
	^finished not
!
complete
	finished := true.
	doneBlocks isNil ifFalse: [doneBlocks do: [:each | each cull: self]]
! !

!Animation methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an Animation('.
	frameBlock isNil
		ifTrue: [aStream print: from; nextPutAll: ' -> '; print: to; space; print: duration; nextPutAll: ' ms '; print: easing]
		ifFalse: [aStream nextPutAll: 'every frame'].
	finished ifTrue: [aStream nextPutAll: ' finished'].
	aStream nextPut: $)
! !

!Animation class methodsFor: 'instance creation'!
from: a to: b duration: milliseconds easing: aSymbol do: aBlock
	^self new setFrom: a to: b duration: milliseconds easing: aSymbol action: aBlock
!
from: a to: b duration: milliseconds do: aBlock
	^self from: a to: b duration: milliseconds easing: #easeOutCubic do: aBlock
!
everyFrame: aBlock
	"aBlock value: ms each frame until it answers false."
	^self new setFrameBlock: aBlock
! !

!Animation class methodsFor: 'easing'!
easings
	^#(#linear #easeInQuad #easeOutQuad #easeInOutQuad #easeInCubic #easeOutCubic #easeInOutCubic #spring)
!
ease: aSymbol at: t
	"Map t in [0, 1] through the easing aSymbol (f(0) = 0, f(1) = 1)."
	| u |
	aSymbol == #linear ifTrue: [^t].
	aSymbol == #easeOutCubic ifTrue: [u := 1 - t. ^1 - (u * u * u)].
	aSymbol == #easeInCubic ifTrue: [^t * t * t].
	aSymbol == #easeOutQuad ifTrue: [^t * (2 - t)].
	aSymbol == #easeInQuad ifTrue: [^t * t].
	aSymbol == #easeInOutQuad ifTrue: [
		^t < 0.5 ifTrue: [2 * t * t] ifFalse: [u := -2 * t + 2. 1 - (u * u / 2)]].
	aSymbol == #easeInOutCubic ifTrue: [
		^t < 0.5 ifTrue: [4 * t * t * t] ifFalse: [u := -2 * t + 2. 1 - (u * u * u / 2)]].
	aSymbol == #spring ifTrue: [
		"Critically damped spring, normalized so that f(1) = 1."
		^(1 - ((1 + (8 * t)) * (-8 * t) exp)) / (1 - (9 * -8 exp))].
	^self error: 'Unknown easing ', aSymbol printString
!
interpolate: a to: b at: e
	"The value e of the way from a to b (Numbers, Points, Rectangles, Colors; other objects jump to b at the end): a interpolateTo: b at: e."
	^a interpolateTo: b at: e
!
now
	"The clock animations run on (milliseconds, Float): real time, timeScale times slower since the scale was set. On the recording clock that of the compositor's last tick, so that a moment noted a few cycles later does not move an animation."
	| world |
	(Smalltalk vm isOnWorkClock and: [(world := World current) notNil and: [world compositor tickClock notNil]])
		ifTrue: [^world compositor tickClock].
	^self nowAt: Time microsecondClockValue / 1000.0
!
nowAt: realMilliseconds
	| c |
	c := Clock.
	c isNil ifTrue: [^realMilliseconds].
	^(c at: 2) + ((realMilliseconds - (c at: 1)) / (c at: 3))
!
timeScale
	"How many times slower than real time animations run (1: normal)."
	| c |
	c := Clock.
	^c isNil ifTrue: [1] ifFalse: [c at: 3]
!
timeScale: aNumber
	"Run every animation aNumber times slower (10: slow motion, 1: normal), running ones included, without a jump."
	| real |
	aNumber > 0 ifFalse: [^self error: 'The time scale must be positive'].
	real := Time microsecondClockValue / 1000.0.
	Clock := Array with: real with: (self nowAt: real) with: aNumber
!
realMilliseconds: milliseconds
	"The real milliseconds that milliseconds of the animation clock take now (for timers: Delays run on real time)."
	^(milliseconds * self timeScale) rounded
! !
