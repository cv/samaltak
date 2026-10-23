Object subclass: #Animation
	instanceVariableNames: 'from to duration easing action startTime delay value finished doneBlocks frameBlock'
	classVariableNames: ''
	package: 'UI-Windows'!

Animation comment: 'I tween a value (Number, Point, Rectangle or Color: interpolateTo:at:) from from to to over duration milliseconds with an easing, on the compositor clock (milliseconds, Float), calling action with each value:

	Animation from: 0 to: 100 duration: 140 easing: #easeOutCubic do: [:x | ...]

Run me with aWindow animate: (stepped in the window''s Process, the window redraws after each step) or aLayer animate: (stepped by the Compositor: smooth even when the window''s Process is busy). A frame animation (Animation everyFrame: [:ms | ... true to continue]) runs until its block answers false. I start at the first frame after I am added (or at startAt:). whenDone: blocks run once when I reach my end (not when stopped).

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
	"The clock animations run on (milliseconds, Float)."
	^Time microsecondClockValue / 1000.0
! !
