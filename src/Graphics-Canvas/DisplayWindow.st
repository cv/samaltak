Object subclass: #DisplayWindow
	instanceVariableNames: 'window swapchain surface renderer fresh swapValid keepsContents'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayWindow comment: 'I am a host window that shows DisplayLists: each frame is rendered into my offscreen Surface (RGBA8, the window''s pixel size, readable) and blitted to the swapchain. Present at most 60 Hz (vm/platform/README.md).

My surface keeps the last frame: show:clear:damage: renders only the damaged rectangles (a DamageRegion) and, where the swapchain keeps its texture''s pixels too (a software GPU''s back buffer: GPUSwapchain>>keepsContents), blits and presents only them; SDL_GPU''s swapchain gets the whole surface blitted (on the GPU). needsFullFrame says when the next frame must be drawn whole (a new surface).

	| w | w := DisplayWindow width: 900 height: 560 title: ''Samaltak''.
	w show: aDisplayList clear: Color white'!

!DisplayWindow methodsFor: 'initialization'!
setWindow: aHostWindow
	window := aHostWindow.
	renderer := Renderer default.
	swapchain := renderer device swapchainFor: aHostWindow
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
	"The offscreen surface of the last frame (its size follows the window)."
	| pixels |
	pixels := window pixelExtent.
	(surface isNil or: [surface pixelExtent ~= pixels]) ifTrue: [
		surface isNil ifFalse: [surface release].
		surface := Surface width: pixels x height: pixels y scale: window scale.
		fresh := true].
	^surface
!
needsFullFrame
	"Whether the next frame must be drawn whole: my surface holds no frame yet, or the window's size changed."
	^surface isNil or: [fresh ~~ false or: [surface pixelExtent ~= window pixelExtent]]
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
	"Render aDisplayList where aDamageRegionOrNil says it changed my last frame (nil: everywhere; whole anyway when needsFullFrame) and present it: the whole surface blitted to the swapchain, or only the damage where the swapchain keeps its pixels. Answer false if the window could not be drawn (hidden, minimized, too many frames in flight). While StageTimes measures, the stages count as composite.render, composite.blit and present.submit (encoding on a GPU, the work itself on a SoftwareGPU), with the bytes drawn and blitted."
	| cmd target swap s t area full scissors blitted |
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	full := aDamageRegionOrNil isNil or: [aDamageRegionOrNil isFull or: [self needsFullFrame]].
	target := self surface.
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
	s isNil ifFalse: [t := s add: #'composite.render' since: t bytes: area].
	swap := cmd acquireSwapchainTexture: swapchain.
	blitted := 0.
	swap isNil
		ifTrue: [swapValid := false]
		ifFalse: [
			(full not and: [swapValid == true and: [swap width = target width and: [swap height = target height and: [self swapchainKeepsContents]]]])
				ifTrue: [
					scissors do: [:r | cmd blit: target texture rect: r to: swap rect: r linear: true].
					cmd presentDamage: scissors.
					blitted := area]
				ifFalse: [
					cmd blit: target texture to: swap.
					blitted := target pixelExtent x * target pixelExtent y * 4].
			swapValid := true].
	s isNil ifFalse: [t := s add: #'composite.blit' since: t bytes: blitted].
	cmd submit.
	s isNil ifFalse: [s add: #'present.submit' since: t bytes: 0].
	^swap notNil
!
close
	surface isNil ifFalse: [surface release. surface := nil].
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
	"flags: 1 hidden, 2 resizable, 4 highDensity (HostWindow)."
	^self new setWindow: (HostWindow width: w height: h title: aString flags: anInteger)
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
