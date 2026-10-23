Object subclass: #Layer
	instanceVariableNames: 'surface contentList chromeList renderedContent renderedChrome pixelExtent offset scale opacity animations needsRender clearColor chromeKey renderedExtent waitingSince'
	classVariableNames: ''
	package: 'UI-Windows'!

Layer comment: 'I am one composited layer: an offscreen Surface (RGBA8, premultiplied) with the latest frozen DisplayList of my owner (contentList, published atomically by the owner''s Process) and an optional chromeList drawn over it (window frames, by the Compositor). The Compositor renders me when either list changed and composites my surface onto the screen with my offset (points), scale (about my center) and opacity. My surface is allocated with slack, so live resizing rarely reallocates it.

Layer properties animate in the Compositor (animate:to:duration:easing:), never involving the owner''s Process.'!

!Layer methodsFor: 'initialization'!
initialize
	offset := 0 @ 0.
	scale := 1.
	opacity := 1.
	needsRender := true.
	animations := OrderedCollection new.
	clearColor := Color white
! !

!Layer methodsFor: 'accessing'!
surface
	^surface
!
contentList
	^contentList
!
contentList: aDisplayList
	"Publish a new frozen DisplayList (any Process)."
	contentList := aDisplayList.
	needsRender := true
!
chromeList
	^chromeList
!
chromeList: aDisplayListOrNil
	chromeList := aDisplayListOrNil.
	needsRender := true
!
pixelExtent
	"The device pixels of my surface that hold the last rendered frame."
	^pixelExtent
!
offset
	^offset
!
offset: aPoint
	offset := aPoint
!
scale
	^scale
!
scale: aNumber
	scale := aNumber
!
opacity
	^opacity
!
opacity: aNumber
	opacity := aNumber
!
clearColor: aColor
	clearColor := aColor
!
chromeKey
	^chromeKey
!
chromeKey: anObject
	chromeKey := anObject
!
renderedExtent
	"The extent (points) of the last rendered frame."
	^renderedExtent
!
waitForContent
	"Hold my first appearance (and animations) until my owner published a frame, at most 150 ms."
	waitingSince := 0
!
isWaitingAt: ms
	waitingSince isNil ifTrue: [^false].
	contentList notNil ifTrue: [waitingSince := nil. ^false].
	waitingSince = 0 ifTrue: [waitingSince := ms].
	ms - waitingSince > 150 ifTrue: [waitingSince := nil. ^false].
	^true
!
hasContent
	^contentList notNil
!
isRendered
	^surface notNil and: [pixelExtent notNil]
!
needsRender
	^needsRender or: [renderedContent ~~ contentList or: [renderedChrome ~~ chromeList]]
!
markNeedsRender
	needsRender := true
! !

!Layer methodsFor: 'animating'!
animations
	^animations
!
addAnimation: anAnimation
	"Compositor Process only (use animate:... from elsewhere: it hands the animation over safely)."
	animations add: anAnimation.
	^anAnimation
!
animate: aSymbol to: aValue duration: milliseconds easing: anEasing
	"Animate my property aSymbol (#offset #scale #opacity) from its current value."
	^self animate: aSymbol from: (self perform: aSymbol) to: aValue duration: milliseconds easing: anEasing
!
animate: aSymbol from: startValue to: aValue duration: milliseconds easing: anEasing
	| setter anim |
	setter := (aSymbol, ':') asSymbol.
	self perform: setter with: startValue.
	anim := Animation from: startValue to: aValue duration: milliseconds easing: anEasing do: [:v | self perform: setter with: v].
	animations := animations copyWith: anim.
	^anim
!
run: anAnimation
	"Step anAnimation on the compositor clock (any Process)."
	animations := animations copyWith: anAnimation.
	^anAnimation
!
isAnimating
	^animations notEmpty
!
stepAnimationsAt: ms
	"Advance my animations; answer whether any is still running."
	| running |
	animations isEmpty ifTrue: [^false].
	(self isWaitingAt: ms) ifTrue: [^true].
	running := animations select: [:each | each stepAt: ms].
	running size = animations size ifFalse: [animations := running].
	^running notEmpty
!
finishAnimations
	animations do: [:each | each finish].
	animations := OrderedCollection new
! !

!Layer methodsFor: 'rendering'!
renderExtent: aPoint scale: aNumber renderer: aRenderer commandBuffer: aCommandBuffer
	"Render my lists for a frame of aPoint points at aNumber device pixels per point."
	| pixels list |
	pixels := (aPoint x * aNumber) ceiling @ (aPoint y * aNumber) ceiling.
	self ensureSurface: pixels scale: aNumber.
	list := contentList ifNil: [(Canvas extent: aPoint scale: aNumber) displayList].
	aRenderer render: list into: surface texture clear: clearColor commandBuffer: aCommandBuffer.
	chromeList isNil ifFalse: [
		aRenderer render: chromeList into: surface texture clear: nil commandBuffer: aCommandBuffer].
	pixelExtent := pixels.
	renderedExtent := aPoint.
	renderedContent := contentList.
	renderedChrome := chromeList.
	needsRender := false
!
ensureSurface: pixels scale: aNumber
	| w h |
	(surface notNil and: [surface scale = aNumber
		and: [surface width >= pixels x and: [surface height >= pixels y
		and: [surface width * surface height <= (pixels x * pixels y * 3 max: 65536)]]]]) ifTrue: [^surface].
	surface isNil ifFalse: [surface release].
	w := (pixels x max: 1) + 127 // 128 * 128.
	h := (pixels y max: 1) + 127 // 128 * 128.
	^surface := Surface width: w height: h scale: aNumber
!
release
	surface isNil ifFalse: [surface release].
	surface := nil.
	pixelExtent := nil
! !
