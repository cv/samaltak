Object subclass: #GPUPrimitives
	instanceVariableNames: ''
	classVariableNames: 'CloseWindowCall DisplayScaleCall RefreshRateCall TextInputAreaCall WindowVisibilityCall SetCursorCall'
	package: 'Graphics-GPU'!

GPUPrimitives comment: 'I provide GPUPlatform''s hosted SDL window and GPU backend. On failure I signal a GPUError carrying the platform''s last error message.'!

!GPUPrimitives class methodsFor: 'errors'!
fail: operation
	^GPUError new operation: operation; platformLastError: self lastError; signal
!
ffiRejected: operation
	^GPUError new operation: operation; platformLastError: 'Platform call unavailable or invalid arguments'; signal
! !

!GPUPrimitives class methodsFor: 'resources'!
textureSize: texture
	<primitive: 'gpuTextureSize'>
	^self fail: 'gpuTextureSize'
! !

!GPUPrimitives class methodsFor: 'windows'!
closeWindow: window
	| binding result |
	binding := CloseWindowCall ifNil: [
		CloseWindowCall := PlatformFFI bind: #(call 'platform' 'platform_windows_close' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: window].
	result == false ifTrue: [^self legacyCloseWindow: window].
	result = 0 ifTrue: [^self fail: 'windowClose'].
	^self
!
keepsWindowOpen: window
	"Whether closing window leaves it open: no, a window of the operating system closes."
	^false
!
windowDisplayScale: window
	| binding result |
	binding := DisplayScaleCall ifNil: [
		DisplayScaleCall := PlatformFFI bind: #(call 'platform' 'platform_windows_display_scale' (i64) f64)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: window].
	result == false ifTrue: [^self legacyWindowDisplayScale: window].
	result < 0 ifTrue: [^self fail: 'windowDisplayScale'].
	^result
!
windowRefreshRate: window
	| binding result |
	binding := RefreshRateCall ifNil: [
		RefreshRateCall := PlatformFFI bind: #(call 'platform' 'platform_windows_refresh_rate' (i64) f64)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: window].
	result == false ifTrue: [^self legacyWindowRefreshRate: window].
	result < 0 ifTrue: [^self fail: 'windowRefreshRate'].
	^result
!
window: window x: x y: y
	"Move window to x @ y points (a desktop window: from the top left of the area the bar leaves free); false where the VM cannot (it predates the primitive, or the platform refused)."
	<primitive: 'windowSetPosition'>
	^false
!
presentWindow: window address: address width: w height: h x: x y: y width: rw height: rh mode: mode
	"The rectangle x y rw rh of a frame of w x h BGRA8 pixels at address (outside the heap) in window's SDL surface: mode 1 copies it there, 2 shows that part of the surface, 3 both (HostFramePresenter without an SDL_GPU device)."
	^(self primPresentWindow: window address: address width: w height: h bytesPerRow: w * 4 x: x y: y width: rw height: rh mode: mode)
		ifNil: [self fail: 'windowPresentAddress']
!
primPresentWindow: window address: address width: w height: h bytesPerRow: bpr x: x y: y width: rw height: rh mode: mode
	<primitive: 'windowPresentAddress'>
	^nil
!
window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
	| binding result |
	binding := TextInputAreaCall ifNil: [
		TextInputAreaCall := PlatformFFI bind: #(call 'platform' 'platform_windows_set_text_input_area' (i64 i64 i64 i64 i64 i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke6: window with: x with: y with: w with: h with: cursorX].
	result == false ifTrue: [^self legacyWindow: window textInputAreaX: x y: y width: w height: h cursor: cursorX].
	result = 0 ifTrue: [^self fail: 'windowSetTextInputArea'].
	^self
!
showWindow: window
	| binding result |
	binding := WindowVisibilityCall ifNil: [
		WindowVisibilityCall := PlatformFFI bind: #(call 'platform' 'platform_windows_show' (i64 i32) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: window with: 1].
	result == false ifTrue: [^self legacyShowWindow: window].
	result = 0 ifTrue: [^self fail: 'windowShow'].
	^self
!
hideWindow: window
	| binding result |
	binding := WindowVisibilityCall ifNil: [
		WindowVisibilityCall := PlatformFFI bind: #(call 'platform' 'platform_windows_show' (i64 i32) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke2: window with: 0].
	result == false ifTrue: [^self legacyHideWindow: window].
	result = 0 ifTrue: [^self fail: 'windowHide'].
	^self
!
inputSemaphore: externalIndex
	<primitive: 'inputSemaphore'>
	^self fail: 'inputSemaphore'
!
vsyncSemaphore: externalIndex
	<primitive: 'vsyncSemaphore'>
	^self fail: 'vsyncSemaphore'
!
setCursor: kind
	| binding result |
	binding := SetCursorCall ifNil: [
		SetCursorCall := PlatformFFI bind: #(call 'platform' 'platform_windows_set_cursor' (i64) i32)].
	result := binding isNil ifTrue: [false] ifFalse: [binding tryInvoke1: kind].
	result == false ifTrue: [^self legacySetCursor: kind].
	result = 0 ifTrue: [^self fail: 'setCursor'].
	^self
! !

!GPUPrimitives class methodsFor: 'windows'!
windowClosed: window
	"The VM releases the window's swapchain itself."
! !

!GPUPrimitives class methodsFor: 'fallback primitives'!
legacyCloseWindow: window
	<primitive: 'windowClose'>
	^self fail: 'windowClose'
!
legacyWindowDisplayScale: window
	<primitive: 'windowDisplayScale'>
	^self fail: 'windowDisplayScale'
!
legacyWindowRefreshRate: window
	<primitive: 'windowRefreshRate'>
	^self fail: 'windowRefreshRate'
!
legacyWindow: window textInputAreaX: x y: y width: w height: h cursor: cursorX
	<primitive: 'windowSetTextInputArea'>
	^self fail: 'windowSetTextInputArea'
!
legacyShowWindow: window
	<primitive: 'windowShow'>
	^self fail: 'windowShow'
!
legacyHideWindow: window
	<primitive: 'windowHide'>
	^self fail: 'windowHide'
!
legacySetCursor: kind
	<primitive: 'setCursor'>
	^self fail: 'setCursor'
! !
