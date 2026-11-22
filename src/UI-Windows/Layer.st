Object subclass: #Layer
	instanceVariableNames: 'surface contentList chromeList renderedContent renderedChrome pixelExtent offset scale opacity animations needsRender clearColor chromeKey renderedExtent waitingSince contentStamps chromeStamps lastDamage'
	classVariableNames: ''
	package: 'UI-Windows'!

Layer comment: 'I am one composited layer: an offscreen Surface (RGBA8, premultiplied) with the latest frozen DisplayList of my owner (contentList, published atomically by the owner''s Process) and an optional chromeList drawn over it (window frames, by the Compositor). The Compositor renders me when either list changed and composites my surface onto the screen with my offset (points), scale (about my center) and opacity. My surface is allocated with slack, so live resizing rarely reallocates it.

Rendering is damage-limited: my surface keeps the last frame, and when a list changed I draw again only where the new lists draw differently from the ones I show (DisplayListDiff: a line of streamed text, a blinking caret), filled with my clear color first, so the pixels are those of drawing everything. I render whole after markNeedsRender (a new pipeline, restyling), at a new size or scale, on a new surface, and when the damage is more than half of me; lastDamage says what the last render changed (nil: everything), for the Compositor''s own damage.

Layer properties animate in the Compositor (animate:to:duration:easing:), never involving the owner''s Process.'!

!Layer methodsFor: 'initialization'!
initialize
	offset := 0 @ 0.
	scale := 1.
	opacity := 1.
	needsRender := true.
	animations := OrderedCollection new.
	clearColor := nil
! !

!Layer methodsFor: 'accessing'!
surface
	^surface
!
contentList
	^contentList
!
contentList: aDisplayList
	"Publish a new frozen DisplayList (any Process); the Compositor renders what it changed (needsRender)."
	contentList := aDisplayList
!
chromeList
	^chromeList
!
chromeList: aDisplayListOrNil
	chromeList := aDisplayListOrNil
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
	clearColor := aColor.
	needsRender := true
!
lastDamage
	"What my last render changed: a DamageRegion of my surface's pixels, nil if it rendered everything."
	^lastDamage
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
renderedContent
	"The content list my surface shows."
	^renderedContent
!
renderedChrome
	^renderedChrome
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
	"Render everything again at the next frame, not only what my lists changed."
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
	"Render all of my lists for a frame of aPoint points at aNumber device pixels per point."
	^self renderExtent: aPoint scale: aNumber renderer: aRenderer commandBuffer: aCommandBuffer differ: nil
!
renderExtent: aPoint scale: aNumber renderer: aRenderer commandBuffer: aCommandBuffer differ: aDisplayListDiffOrNil
	"Render my lists for a frame of aPoint points at aNumber device pixels per point: only what they changed when aDisplayListDiffOrNil (the Compositor's) finds that little, else all of them. Answer lastDamage (layer.render while StageTimes measures, with the bytes drawn; the diff in it also as layer.diff)."
	| pixels list s t old region scissors |
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	pixels := (aPoint x * aNumber) ceiling @ (aPoint y * aNumber) ceiling.
	old := surface.
	self ensureSurface: pixels scale: aNumber.
	list := contentList ifNil: [(Canvas extent: aPoint scale: aNumber) displayList].
	(aDisplayListDiffOrNil isNil or: [old ~~ surface]) ifFalse: [| d |
		s isNil ifFalse: [d := Time microsecondClockValue].
		region := self damageFor: list pixels: pixels differ: aDisplayListDiffOrNil.
		s isNil ifFalse: [s add: #'layer.diff' since: d bytes: 0]].
	region isNil
		ifTrue: [
			aRenderer render: list into: surface texture clear: self clearColorOrPaper commandBuffer: aCommandBuffer.
			chromeList isNil ifFalse: [
				aRenderer render: chromeList into: surface texture clear: nil commandBuffer: aCommandBuffer]]
		ifFalse: [
			region isEmpty ifFalse: [
				scissors := region scissors.
				aRenderer fill: scissors color: self clearColorOrPaper into: surface texture commandBuffer: aCommandBuffer.
				aRenderer render: list into: surface texture clear: nil commandBuffer: aCommandBuffer within: scissors.
				chromeList isNil ifFalse: [
					aRenderer render: chromeList into: surface texture clear: nil commandBuffer: aCommandBuffer within: scissors]]].
	contentStamps := DisplayListDiff stampsOf: list.
	chromeStamps := DisplayListDiff stampsOf: chromeList.
	lastDamage := region.
	pixelExtent := pixels.
	renderedExtent := aPoint.
	renderedContent := contentList.
	renderedChrome := chromeList.
	needsRender := false.
	s isNil ifFalse: [s add: #'layer.render' since: t bytes: (region isNil ifTrue: [pixels x * pixels y] ifFalse: [region area]) * 4].
	^region
!
damageFor: list pixels: pixels differ: aDisplayListDiff
	"What list and my chrome list change of what my surface shows (a DamageRegion), or nil to render everything: when asked to (markNeedsRender, DamageCheck forcesFull), at another size, without a previous frame, with a clear color that is not opaque (a fill would not replace what it covers), or when more than half of me changed."
	| region |
	(needsRender or: [pixelExtent ~= pixels or: [renderedContent isNil or: [contentList isNil or: [DamageCheck forcesFull]]]]) ifTrue: [^nil].
	self clearColorOrPaper alpha < 1 ifTrue: [^nil].
	renderedChrome isNil = chromeList isNil ifFalse: [^nil].
	region := DamageRegion extent: pixels.
	aDisplayListDiff region: region.
	renderedContent == list ifFalse: [
		aDisplayListDiff diff: renderedContent stamps: contentStamps to: list stamps: (DisplayListDiff stampsOf: list)].
	(renderedChrome == chromeList or: [region isFull]) ifFalse: [
		aDisplayListDiff diff: renderedChrome stamps: chromeStamps to: chromeList stamps: (DisplayListDiff stampsOf: chromeList)].
	region isFull ifTrue: [^nil].
	^region
!
clearColorOrPaper
	^clearColor ifNil: [Color paper]
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
