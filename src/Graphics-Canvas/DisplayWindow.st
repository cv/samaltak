Object subclass: #DisplayWindow
	instanceVariableNames: 'window swapchain surface renderer fresh swapValid keepsContents presented presentedValid'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayWindow comment: 'I am a host window that shows DisplayLists: each frame is rendered into my offscreen Surface (RGBA8, readable, the size of the frame: its DisplayList''s pixelExtent, which is the window''s pixel size unless the host reports a window''s pixels as its points while the display scale is 2, as X11 with SDL_VIDEO_X11_SCALING_FACTOR; the blit then scales) and blitted to the swapchain. An overlay (the remote pointer) is drawn over a copy of it, so that the surface holds the frame without it. Present at most 60 Hz (vm/platform/README.md).

My surface keeps the last frame: show:clear:damage: renders only the damaged rectangles (a DamageRegion) and, where the swapchain keeps its texture''s pixels too (a software GPU''s back buffer: GPUSwapchain>>keepsContents), blits and presents only them; SDL_GPU''s swapchain gets the whole surface blitted (on the GPU). needsFullFrame says when the next frame must be drawn whole (a new surface).

	| w | w := DisplayWindow width: 900 height: 560 title: ''Samaltak''.
	w show: aDisplayList clear: Color white'!

!DisplayWindow methodsFor: 'initialization'!
setWindow: aHostWindow
	window := aHostWindow.
	renderer := Renderer default.
	swapchain := renderer device swapchainFor: aHostWindow
! !

!DisplayWindow methodsFor: 'glass'!
setGlassWindow: aHostWindow
	"No swapchain: the GPU does not draw a transparent window (flag 16); it shows rectangles (fillRects:)."
	window := aHostWindow
!
fillRects: anArray
	"A glass window: show these rectangles (x y w h rgba groups, pixels, rgba premultiplied) over a transparent background (HostWindow>>fillRects:)."
	^window fillRects: anArray
! !

!DisplayWindow methodsFor: 'accessing'!
hostWindow
	^window
!
extent
	"Size in points."
	^window extent
!
scale
	^window scale
!
surface
	"The offscreen surface of the last frame, without the overlay, the size of that frame (show:clear:damage:); before the first, of the window's pixels."
	^surface ifNil: [self surfaceExtent: window pixelExtent scale: window scale]
!
surfaceExtent: aPoint scale: aNumber
	"My surface, made anew if it is not aPoint pixels (a new one holds no frame yet)."
	(surface isNil or: [surface pixelExtent ~= aPoint]) ifTrue: [
		surface isNil ifFalse: [surface release].
		surface := Surface width: aPoint x height: aPoint y scale: aNumber.
		fresh := true].
	^surface
!
shownSurface
	"What the last frame showed: my surface, or with an overlay the copy it was drawn on."
	^(presentedValid == true and: [presented notNil]) ifTrue: [presented] ifFalse: [self surface]
!
needsFullFrame
	"Whether the next frame must be drawn whole: my surface holds no frame yet (a frame of another size makes a new one)."
	^surface isNil or: [fresh ~~ false]
!
refreshRate
	"The display's refresh rate in Hz (0 if unknown)."
	^window refreshRate
!
title: aString
	window title: aString
!
extent: aPoint
	"Resize the host window to aPoint points; answer whether it did."
	^window extent: aPoint
!
hidden: aBoolean
	"Hidden or shown when my host window opens next (after an image restart)."
	window hidden: aBoolean
!
textInputArea: aRectangle cursor: x
	window textInputArea: aRectangle cursor: x
! !

!DisplayWindow methodsFor: 'presenting'!
swapchainKeepsContents
	keepsContents isNil ifTrue: [keepsContents := [swapchain keepsContents] on: Error do: [:e | e return: false]].
	^keepsContents
!
show: aDisplayList clear: aColorOrNil
	"Render aDisplayList whole and present it. Answer false if the window could not be drawn (hidden, minimized, too many frames in flight)."
	^self show: aDisplayList clear: aColorOrNil damage: nil
!
show: aDisplayList clear: aColorOrNil damage: aDamageRegionOrNil
	^self show: aDisplayList clear: aColorOrNil damage: aDamageRegionOrNil overlay: nil damage: nil
!
show: aDisplayList clear: aColorOrNil damage: aDamageRegionOrNil overlay: anOverlayOrNil damage: overlayDamageOrNil
	"Render aDisplayList where aDamageRegionOrNil says it changed my last frame (nil: everywhere; whole anyway when needsFullFrame) into my surface, which is its size (its pixelExtent: the frame in its own pixels, whatever the window's pixel size), and present it: the whole surface blitted to the swapchain, or only what changed where the swapchain keeps its pixels. anOverlayOrNil (the remote pointer: a DisplayList of the same extent and scale; nil or empty: none) is drawn over the frame on a copy of my surface, and that copy is shown (shownSurface): my surface keeps the frame without it, for the frame tap and screenshots. overlayDamageOrNil (a DamageRegion, nil: nowhere) is where the overlay changed since the last frame. Answer false if the window could not be drawn (hidden, minimized, too many frames in flight). While StageTimes measures, the stages count as composite.render, composite.blit and present.submit (encoding on a GPU, the work itself on a SoftwareGPU), with the bytes drawn and blitted."
	| cmd target swap s t area full scissors blits shown blitted |
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	target := self surfaceExtent: aDisplayList pixelExtent scale: aDisplayList scale.
	full := aDamageRegionOrNil isNil or: [aDamageRegionOrNil isFull or: [self needsFullFrame]].
	full ifFalse: [scissors := aDamageRegionOrNil scissors].
	area := full ifTrue: [target pixelExtent x * target pixelExtent y * 4] ifFalse: [aDamageRegionOrNil area * 4].
	cmd := renderer device commandBuffer.
	full
		ifTrue: [renderer render: aDisplayList into: target texture clear: aColorOrNil commandBuffer: cmd]
		ifFalse: [
			scissors isEmpty ifFalse: [
				aColorOrNil isNil ifFalse: [renderer fill: scissors color: aColorOrNil into: target texture commandBuffer: cmd].
				renderer render: aDisplayList into: target texture clear: nil commandBuffer: cmd within: scissors]].
	fresh := false.
	blits := full ifFalse: [self blitsOf: aDamageRegionOrNil and: overlayDamageOrNil].
	shown := self drawOverlay: anOverlayOrNil over: target blits: blits commandBuffer: cmd.
	s isNil ifFalse: [t := s add: #'composite.render' since: t bytes: area].
	swap := cmd acquireSwapchainTexture: swapchain.
	blitted := 0.
	swap isNil
		ifTrue: [swapValid := false]
		ifFalse: [
			(blits notNil and: [swapValid == true and: [swap width = shown width and: [swap height = shown height and: [self swapchainKeepsContents]]]])
				ifTrue: [
					blits do: [:r | cmd blit: shown texture rect: r to: swap rect: r linear: true].
					cmd presentDamage: blits.
					blitted := (blits inject: 0 into: [:sum :r | sum + ((r at: 3) * (r at: 4))]) * 4]
				ifFalse: [
					self blitWhole: shown to: swap commandBuffer: cmd.
					blitted := shown pixelExtent x * shown pixelExtent y * 4].
			swapValid := true].
	s isNil ifFalse: [t := s add: #'composite.blit' since: t bytes: blitted].
	cmd submit.
	s isNil ifFalse: [s add: #'present.submit' since: t bytes: 0].
	^swap notNil
!
blitsOf: aDamageRegion and: overlayDamageOrNil
	"What changed on the screen, {x. y. width. height} Arrays: the frame's damage and the overlay's; nil: all of it."
	| union |
	(overlayDamageOrNil isNil or: [overlayDamageOrNil isEmpty]) ifTrue: [^aDamageRegion scissors].
	union := DamageRegion bounds: aDamageRegion bounds.
	union addAll: aDamageRegion; addAll: overlayDamageOrNil.
	^union isFull ifTrue: [nil] ifFalse: [union scissors]
!
drawOverlay: anOverlayOrNil over: target blits: blitsOrNil commandBuffer: cmd
	"The surface to show: target, or with an overlay a copy of it, brought up to date where blitsOrNil says (nil, or a copy that does not hold the last frame: everywhere), with the overlay drawn over it there."
	(anOverlayOrNil isNil or: [anOverlayOrNil isEmpty]) ifTrue: [
		presentedValid := false.
		^target].
	(presented isNil or: [presented pixelExtent ~= target pixelExtent]) ifTrue: [
		presented isNil ifFalse: [presented release].
		presented := Surface width: target pixelExtent x height: target pixelExtent y scale: target scale.
		presentedValid := false].
	(blitsOrNil isNil or: [presentedValid ~~ true])
		ifTrue: [
			cmd blit: target texture rect: {0. 0. target width. target height} to: presented texture rect: {0. 0. target width. target height} linear: false.
			renderer render: anOverlayOrNil into: presented texture clear: nil commandBuffer: cmd]
		ifFalse: [
			blitsOrNil isEmpty ifFalse: [
				blitsOrNil do: [:r | cmd blit: target texture rect: r to: presented texture rect: r linear: false].
				renderer render: anOverlayOrNil into: presented texture clear: nil commandBuffer: cmd within: blitsOrNil]].
	presentedValid := true.
	^presented
!
blitWhole: aSurface to: swap commandBuffer: cmd
	"All of aSurface onto the swapchain texture: copied 1:1 when the sizes are equal or differ by at most two pixels (a fractional scale's rounding: no blur), else scaled (a window whose pixels are its points while the World draws at a display scale of 2, as X11 with SDL_VIDEO_X11_SCALING_FACTOR)."
	| w h |
	w := aSurface width.
	h := aSurface height.
	((w - swap width) abs <= 2 and: [(h - swap height) abs <= 2]) ifFalse: [^cmd blit: aSurface texture to: swap].
	w := w min: swap width.
	h := h min: swap height.
	cmd blit: aSurface texture rect: {0. 0. w. h} to: swap rect: {0. 0. w. h} linear: false
!
close
	surface isNil ifFalse: [surface release. surface := nil].
	presented isNil ifFalse: [presented release. presented := nil].
	presentedValid := false.
	window close
! !

!DisplayWindow class methodsFor: 'instance creation'!
width: w height: h title: aString
	^self new setWindow: (HostWindow width: w height: h title: aString)
!
width: w height: h title: aString hidden: aBoolean
	"A resizable high-density window; hidden ones render offscreen only (tests, readback)."
	^self new setWindow: (HostWindow width: w height: h title: aString flags: (aBoolean ifTrue: [7] ifFalse: [6]))
!
width: w height: h title: aString flags: anInteger
	"flags: 1 hidden, 2 resizable, 4 highDensity, 8 desktop (HostWindow)."
	^self new setWindow: (HostWindow width: w height: h title: aString flags: anInteger)
!
glassWidth: w height: h title: aString flags: anInteger
	"A transparent window (flag 16 added), which the GPU does not draw: it shows rectangles (fillRects:). flags as for width:height:title:flags:."
	^self new setGlassWindow: (HostWindow width: w height: h title: aString flags: (anInteger bitOr: 16))
!
on: aHostWindow
	^self new setWindow: aHostWindow
! !

!DisplayWindow methodsFor: 'events'!
windowId
	"The id platform events for me carry in slot 8."
	^window windowId
! !

!DisplayWindow class methodsFor: 'events'!
nextEventInto: anArray
	"Fill anArray (8 slots: type timeMs x y buttonOrKey modifiers textOrDelta windowId; see vm/platform/README.md) with the next platform event and answer it, or answer nil."
	^HostWindow nextEventInto: anArray
!
injectEvent: anArray
	^HostWindow injectEvent: anArray
!
inputSemaphoreIndex: anInteger
	"Signal external semaphore anInteger when events are pending (drain with nextEventInto: until nil, then wait)."
	^HostWindow inputSemaphoreIndex: anInteger
!
vsyncSemaphoreIndex: anInteger
	^HostWindow vsyncSemaphoreIndex: anInteger
!
cursor: aSymbol
	^HostWindow cursor: aSymbol
!
clipboard
	^HostWindow clipboard
!
clipboard: aString
	^HostWindow clipboard: aString
!
clipboardData: mime
	^HostWindow clipboardData: mime
! !
