Object subclass: #HostWindow
	instanceVariableNames: 'handle session width height title flags'
	classVariableNames: 'Icon IconWidth'
	package: 'Graphics-GPU'!

HostWindow comment: 'I am a native window of the host (SDL3; on UEFI the screen, FirmwareDisplay). I am opened on first use in each session, with the size and title I keep, so I survive image restarts like the GPU objects do. Sizes are in points; pixelExtent and scale give the backing store.'!

!HostWindow methodsFor: 'private'!
setWidth: w height: h title: aString flags: anInteger
	width := w.
	height := h.
	title := aString.
	flags := anInteger
! !

!HostWindow methodsFor: 'accessing'!
handle
	(handle notNil and: [session == GPUDevice currentSession]) ifTrue: [^handle].
	handle := GPUPlatform openWindow: width height: height title: title flags: flags.
	session := GPUDevice currentSession.
	"a desktop window (flag 8) is no application window: it has no icon"
	(Icon notNil and: [(flags bitAnd: 8) = 0]) ifTrue: [GPUPlatform window: handle icon: Icon width: IconWidth].
	^handle
!
isOpen
	^handle notNil and: [session == GPUDevice currentSession]
!
extent
	"Answer my size in points."
	| size |
	size := GPUPlatform windowSize: self handle.
	width := size first.
	height := size last.
	^width @ height
!
pixelExtent
	| size |
	size := GPUPlatform windowPixelSize: self handle.
	^size first @ size last
!
scale
	^GPUPlatform windowDisplayScale: self handle
!
refreshRate
	"Answer the display refresh rate in Hz (0 if unknown)."
	^GPUPlatform windowRefreshRate: self handle
!
title
	^title
!
title: aString
	title := aString.
	self isOpen ifTrue: [GPUPlatform window: handle title: aString]
!
extent: aPoint
	"Resize me to aPoint points (rounded up); answer whether the host did. Opened later, I open at that size."
	width := aPoint x ceiling.
	height := aPoint y ceiling.
	^self isOpen and: [(GPUPlatform window: handle width: width height: height) ~~ false]
!
hidden: aBoolean
	"Open hidden (offscreen) or shown when my handle is created next (first use, new session)."
	flags := (flags bitAnd: -2) + (aBoolean ifTrue: [1] ifFalse: [0])
!
moveTo: aPoint
	"Move me to aPoint points: on the desktop (flag 8) from the top left of the area the bar leaves free, else on the screen (where the window manager lets me). Answer whether the host did."
	^self isOpen and: [(GPUPlatform window: handle x: aPoint x rounded y: aPoint y rounded) ~~ false]
!
textInputArea: aRectangle cursor: x
	"Where text is being typed (points; x: the caret within aRectangle): the input method shows its candidates there."
	self isOpen ifTrue: [
		GPUPlatform window: handle textInputAreaX: aRectangle left rounded y: aRectangle top rounded
			width: aRectangle width ceiling height: aRectangle height ceiling cursor: x rounded]
! !

!HostWindow methodsFor: 'showing'!
show
	"Show me, raised to the front with the focus (as far as the window manager lets an application); on the desktop (flag 8), above the other desktop windows."
	GPUPlatform showWindow: self handle
!
fillRects: anArray
	"Show rectangles over a transparent background, drawn without the GPU (a window of flag 16, which the GPU does not draw): anArray holds x y w h rgba for each (pixels; rgba 16rRRGGBBAA, premultiplied). Answer whether it was shown."
	^(GPUPlatform window: self handle fillRects: anArray) ~~ false
!
opacity: aNumber
	"Show me at aNumber (0 to 1) opacity, where the system can; answer whether it did."
	^self isOpen and: [(GPUPlatform window: handle opacity: (aNumber * 1000) rounded) ~~ false]
!
cornerRadius
	"The radius (points) the system rounds my corners with (a desktop window on macOS); 0 if square."
	^self isOpen ifTrue: [GPUPlatform cornerRadiusOf: handle] ifFalse: [0]
!
hide
	GPUPlatform hideWindow: self handle
!
close
	self isOpen ifTrue: [GPUPlatform closeWindow: handle].
	handle := nil
! !

!HostWindow class methodsFor: 'instance creation'!
width: w height: h title: aString
	"A resizable high-density window."
	^self width: w height: h title: aString flags: 6
!
width: w height: h title: aString flags: anInteger
	"flags: 1 hidden, 2 resizable, 4 highDensity, 8 desktop (above the wallpaper, below every window, never focused: a Wayland layer surface where the compositor has the layer shell, else an ordinary window), 16 transparent (drawn without the GPU, which does not draw transparent windows: fillRects:; on the desktop the pointer passes through it)."
	^self new setWidth: w height: h title: aString flags: anInteger
! !

!HostWindow methodsFor: 'events'!
windowId
	"The id platform events carry in slot 8 (nil if I am not open)."
	^self isOpen ifTrue: [handle] ifFalse: [nil]
! !

!HostWindow class methodsFor: 'icon'!
icon
	"The pixels every window but a desktop one opens with as its icon (RGBA bytes, not premultiplied, rows top to bottom; nil: the system's), iconWidth wide."
	^Icon
!
iconWidth
	^IconWidth
!
icon: aByteArray width: w
	Icon := aByteArray.
	IconWidth := w
! !

!HostWindow class methodsFor: 'events'!
nextEventInto: anArray
	"Fill anArray (8 slots: type timeMs x y buttonOrKey modifiers textOrDelta windowId) with the next event, or answer nil."
	^GPUPlatform nextEvent: anArray
!
injectEvent: anArray
	"Queue an event (same format; timeMs nil = now) as if it came from the host."
	^GPUPlatform injectEvent: anArray
!
inputSemaphoreIndex: anInteger
	"Signal the external semaphore anInteger when events are pending (0 = none); re-armed by nextEventInto:."
	^GPUPlatform inputSemaphore: anInteger
!
vsyncSemaphoreIndex: anInteger
	"Signal the external semaphore anInteger on every display refresh (0 = stop)."
	^GPUPlatform vsyncSemaphore: anInteger
! !

!HostWindow class methodsFor: 'cursor and clipboard'!
cursor: aSymbol
	"#arrow #ibeam #hand #ew #ns #nwse #nesw #move #wait #crosshair #notAllowed"
	| kind |
	kind := #(#arrow #ibeam #hand #ew #ns #nwse #nesw #move #wait #crosshair #notAllowed) indexOf: aSymbol.
	kind = 0 ifTrue: [^self error: 'Unknown cursor ', aSymbol printString].
	^GPUPlatform setCursor: kind - 1
!
systemAppearance
	"#dark or #light, as the system shows its windows (macOS); nil if it does not tell."
	^#(#light #dark) at: GPUPlatform systemTheme ifAbsent: [nil]
!
desktopArea
	"The part of the primary display that docked bars leave free (points), or nil."
	^GPUPlatform desktopArea
!
clipboard
	^GPUPlatform clipboardGet
!
clipboard: aString
	^GPUPlatform clipboardSet: aString
!
clipboardData: mime
	^GPUPlatform clipboardData: mime
! !
