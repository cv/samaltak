Object subclass: #DisplayWindow
	instanceVariableNames: 'window swapchain surface renderer'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayWindow comment: 'I am a host window that shows DisplayLists: each frame is rendered into my offscreen Surface (RGBA8, the frame''s pixel size, readable) and copied to the swapchain, never scaled. Present at most 60 Hz (vm/platform/README.md).

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
	"The offscreen surface of the last frame (before the first, one of the window's size)."
	^surface ifNil: [self surfaceFor: window pixelExtent]
!
surfaceFor: pixels
	"The offscreen surface for a frame of pixels."
	(surface isNil or: [surface pixelExtent ~= pixels]) ifTrue: [
		surface isNil ifFalse: [surface release].
		surface := Surface width: pixels x height: pixels y scale: window scale].
	^surface
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
background: aColor
	"What the host window shows where no frame is drawn."
	window background: aColor
!
minimumExtent: aPoint
	"Keep the host window at least aPoint points, also when the user resizes it."
	window minimumExtent: aPoint
!
hidden: aBoolean
	"Hidden or shown when my host window opens next (after an image restart)."
	window hidden: aBoolean
!
textInputArea: aRectangle cursor: x
	window textInputArea: aRectangle cursor: x
! !

!DisplayWindow methodsFor: 'presenting'!
show: aDisplayList clear: aColorOrNil
	"Render aDisplayList at its size and present it. A window the host sizes by its frames (macOS, while the user resizes it by its edges) takes that size first; in another window of another size the frame shows from the top left, unscaled, the rest cleared. Answer false if the window could not be drawn (hidden, minimized, too many frames in flight)."
	| cmd target swap w h |
	target := self surfaceFor: aDisplayList pixelExtent.
	cmd := renderer device commandBuffer.
	renderer render: aDisplayList into: target texture clear: aColorOrNil commandBuffer: cmd.
	window presenting: aDisplayList extent.
	swap := cmd acquireSwapchainTexture: swapchain.
	swap isNil ifFalse: [
		w := swap width min: target width.
		h := swap height min: target height.
		(w = swap width and: [h = swap height]) ifFalse: [
			(cmd beginPassOn: swap clear: (aColorOrNil ifNil: [Color black]) asArray) end].
		cmd blit: target texture rect: {0. 0. w. h} to: swap rect: {0. 0. w. h} linear: false].
	cmd submit.
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
!
systemAppearance
	"#dark or #light, as the system shows its windows; nil if it does not tell."
	^HostWindow systemAppearance
!
desktopArea
	"The part of the primary display that docked bars leave free (points), or nil."
	^HostWindow desktopArea
! !
