CLibrary subclass: #SDL
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SDL comment: 'The SDL3 functions of the platform layer: video, events, windows, cursors, the clipboard, hints, the log. Not simulated.'!

!SDL class methodsFor: 'declaring'!
headers
	^#('<SDL3/SDL.h>')
!
typedefs
	^#((Uint8 uint8_t) (Uint16 uint16_t) (Uint32 uint32_t) (Uint64 uint64_t) (Sint32 int32_t)
		(SDL_Window opaque) (SDL_Cursor opaque) (SDL_DisplayID uint32_t) (SDL_WindowID uint32_t) (SDL_WindowFlags uint64_t)
		(SDL_InitFlags uint32_t) (SDL_Keymod uint16_t) (SDL_Keycode uint32_t) (SDL_MouseButtonFlags uint32_t)
		(SDL_MouseWheelDirection uint32_t) (SDL_EventAction uint32_t) (SDL_SystemCursor uint32_t) (SDL_LogPriority uint32_t)
		(SDL_LogOutputFunction 'void (*)(void *, int, SDL_LogPriority, const char *)') (SDL_Surface opaque) (SDL_PixelFormat uint32_t))
! !

!SDL methodsFor: 'simulation'!
notSimulated
	^self error: 'SDL is not simulated'
! !

!SDL methodsFor: 'init'!
init: flags
	<c: 'bool SDL_Init(SDL_InitFlags flags)'>
	^self notSimulated
!
quit
	<c: 'void SDL_Quit(void)'>
	^self notSimulated
!
SDL_INIT_VIDEO
	<cMacro: 'SDL_InitFlags SDL_INIT_VIDEO'>
	^self notSimulated
!
setHint: name value: value
	<c: 'bool SDL_SetHint(const char *name, const char *value)'>
	^self notSimulated
!
SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE
	<cMacro: 'const char *SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE'>
	^self notSimulated
!
SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH
	<cMacro: 'const char *SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH'>
	^self notSimulated
!
SDL_HINT_IME_IMPLEMENTED_UI
	<cMacro: 'const char *SDL_HINT_IME_IMPLEMENTED_UI'>
	^self notSimulated
!
getError
	<c: 'const char *SDL_GetError(void)'>
	^self notSimulated
!
clearError
	<c: 'bool SDL_ClearError(void)'>
	^self notSimulated
!
getTicksNS
	<c: 'Uint64 SDL_GetTicksNS(void)'>
	^self notSimulated
!
free: mem
	<c: 'void SDL_free(void *mem)'>
	^self notSimulated
!
strlcpy: dst from: src size: maxlen
	<c: 'size_t SDL_strlcpy(char *dst, const char *src, size_t maxlen)'>
	^self notSimulated
! !

!SDL methodsFor: 'log'!
getLogOutputFunction: callback userdata: userdata
	<c: 'void SDL_GetLogOutputFunction(SDL_LogOutputFunction *callback, void **userdata)'>
	^self notSimulated
!
setLogOutputFunction: callback userdata: userdata
	<c: 'void SDL_SetLogOutputFunction(SDL_LogOutputFunction callback, void *userdata)'>
	^self notSimulated
!
logWarn: category format: fmt with: value
	<c: 'void SDL_LogWarn(int category, const char *fmt, ...)'>
	^self notSimulated
!
SDL_LOG_CATEGORY_APPLICATION
	<cMacro: 'int SDL_LOG_CATEGORY_APPLICATION'>
	^self notSimulated
!
SDL_LOG_PRIORITY_ERROR
	<cMacro: 'SDL_LogPriority SDL_LOG_PRIORITY_ERROR'>
	^self notSimulated
! !

!SDL methodsFor: 'events'!
pumpEvents
	<c: 'void SDL_PumpEvents(void)'>
	^self notSimulated
!
peepEvents: events count: numevents action: action minType: minType maxType: maxType
	<c: 'int SDL_PeepEvents(SDL_Event *events, int numevents, SDL_EventAction action, Uint32 minType, Uint32 maxType)'>
	^self notSimulated
!
pushEvent: event
	<c: 'bool SDL_PushEvent(SDL_Event *event)'>
	^self notSimulated
!
registerEvents: numevents
	<c: 'Uint32 SDL_RegisterEvents(int numevents)'>
	^self notSimulated
!
waitEvent: event timeout: timeoutMS
	<c: 'bool SDL_WaitEventTimeout(SDL_Event *event, Sint32 timeoutMS)'>
	^self notSimulated
!
getModState
	<c: 'SDL_Keymod SDL_GetModState(void)'>
	^self notSimulated
!
SDL_GETEVENT
	<cMacro: 'SDL_EventAction SDL_GETEVENT'>
	^self notSimulated
!
SDL_EVENT_FIRST
	<cMacro: 'Uint32 SDL_EVENT_FIRST'>
	^self notSimulated
!
SDL_EVENT_LAST
	<cMacro: 'Uint32 SDL_EVENT_LAST'>
	^self notSimulated
!
SDL_EVENT_QUIT
	<cMacro: 'Uint32 SDL_EVENT_QUIT'>
	^self notSimulated
!
SDL_EVENT_MOUSE_MOTION
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_MOTION'>
	^self notSimulated
!
SDL_EVENT_MOUSE_BUTTON_DOWN
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_BUTTON_DOWN'>
	^self notSimulated
!
SDL_EVENT_MOUSE_BUTTON_UP
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_BUTTON_UP'>
	^self notSimulated
!
SDL_EVENT_MOUSE_WHEEL
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_WHEEL'>
	^self notSimulated
!
SDL_EVENT_KEY_DOWN
	<cMacro: 'Uint32 SDL_EVENT_KEY_DOWN'>
	^self notSimulated
!
SDL_EVENT_KEY_UP
	<cMacro: 'Uint32 SDL_EVENT_KEY_UP'>
	^self notSimulated
!
SDL_EVENT_TEXT_INPUT
	<cMacro: 'Uint32 SDL_EVENT_TEXT_INPUT'>
	^self notSimulated
!
SDL_EVENT_TEXT_EDITING
	<cMacro: 'Uint32 SDL_EVENT_TEXT_EDITING'>
	^self notSimulated
!
SDL_EVENT_WINDOW_RESIZED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_RESIZED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_CLOSE_REQUESTED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_CLOSE_REQUESTED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_FOCUS_GAINED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_FOCUS_GAINED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_FOCUS_LOST
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_FOCUS_LOST'>
	^self notSimulated
!
SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_MOUSE_LEAVE
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_MOUSE_LEAVE'>
	^self notSimulated
!
SDL_EVENT_WINDOW_EXPOSED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_EXPOSED'>
	^self notSimulated
!
SDL_KMOD_SHIFT
	<cMacro: 'SDL_Keymod SDL_KMOD_SHIFT'>
	^self notSimulated
!
SDL_KMOD_CTRL
	<cMacro: 'SDL_Keymod SDL_KMOD_CTRL'>
	^self notSimulated
!
SDL_KMOD_ALT
	<cMacro: 'SDL_Keymod SDL_KMOD_ALT'>
	^self notSimulated
!
SDL_KMOD_GUI
	<cMacro: 'SDL_Keymod SDL_KMOD_GUI'>
	^self notSimulated
! !

!SDL methodsFor: 'windows'!
createWindow: title width: w height: h flags: flags
	<c: 'SDL_Window *SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags)'>
	^self notSimulated
!
destroyWindow: window
	<c: 'void SDL_DestroyWindow(SDL_Window *window)'>
	^self notSimulated
!
createWindowWithProperties: props
	<c: 'SDL_Window *SDL_CreateWindowWithProperties(Uint32 props)'>
	^self notSimulated
!
getWindowProperties: window
	<c: 'Uint32 SDL_GetWindowProperties(SDL_Window *window)'>
	^self notSimulated
!
setWindowPosition: window x: x y: y
	<c: 'bool SDL_SetWindowPosition(SDL_Window *window, int x, int y)'>
	^self notSimulated
!
getCurrentVideoDriver
	"NULL before the video subsystem is up."
	<c: 'const char *SDL_GetCurrentVideoDriver(void)'>
	^self notSimulated
!
startTextInput: window
	<c: 'bool SDL_StartTextInput(SDL_Window *window)'>
	^self notSimulated
!
stopTextInput: window
	<c: 'bool SDL_StopTextInput(SDL_Window *window)'>
	^self notSimulated
!
setTextInputArea: window rect: rect cursor: cursor
	<c: 'bool SDL_SetTextInputArea(SDL_Window *window, const SDL_Rect *rect, int cursor)'>
	^self notSimulated
!
getWindowSurface: window
	<c: 'SDL_Surface *SDL_GetWindowSurface(SDL_Window *window)'>
	^self notSimulated
!
updateWindowSurface: window rects: rects count: n
	<c: 'bool SDL_UpdateWindowSurfaceRects(SDL_Window *window, const SDL_Rect *rects, int numrects)'>
	^self notSimulated
!
updateWindowSurface: window
	<c: 'bool SDL_UpdateWindowSurface(SDL_Window *window)'>
	^self notSimulated
!
createSurfaceFrom: w height: h format: format pixels: pixels pitch: pitch
	<c: 'SDL_Surface *SDL_CreateSurfaceFrom(int width, int height, SDL_PixelFormat format, void *pixels, int pitch)'>
	^self notSimulated
!
blitSurface: src rect: srcRect to: dst rect: dstRect
	<c: 'bool SDL_BlitSurface(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst, const SDL_Rect *dstrect)'>
	^self notSimulated
!
destroySurface: surface
	<c: 'void SDL_DestroySurface(SDL_Surface *surface)'>
	^self notSimulated
!
getWindowID: window
	<c: 'SDL_WindowID SDL_GetWindowID(SDL_Window *window)'>
	^self notSimulated
!
getWindowSize: window width: w height: h
	<c: 'bool SDL_GetWindowSize(SDL_Window *window, int *w, int *h)'>
	^self notSimulated
!
getWindowSizeInPixels: window width: w height: h
	<c: 'bool SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h)'>
	^self notSimulated
!
getWindowDisplayScale: window
	<c: 'float SDL_GetWindowDisplayScale(SDL_Window *window)'>
	^self notSimulated
!
getPrimaryDisplay
	<c: 'SDL_DisplayID SDL_GetPrimaryDisplay(void)'>
	^self notSimulated
!
getDisplayForWindow: window
	<c: 'SDL_DisplayID SDL_GetDisplayForWindow(SDL_Window *window)'>
	^self notSimulated
!
getCurrentDisplayMode: displayID
	<c: 'const SDL_DisplayMode *SDL_GetCurrentDisplayMode(SDL_DisplayID displayID)'>
	^self notSimulated
!
setWindowTitle: window title: title
	<c: 'bool SDL_SetWindowTitle(SDL_Window *window, const char *title)'>
	^self notSimulated
!
setWindowSize: window w: w h: h
	<c: 'bool SDL_SetWindowSize(SDL_Window *window, int w, int h)'>
	^self notSimulated
!
showWindow: window
	<c: 'bool SDL_ShowWindow(SDL_Window *window)'>
	^self notSimulated
!
raiseWindow: window
	<c: 'bool SDL_RaiseWindow(SDL_Window *window)'>
	^self notSimulated
!
hideWindow: window
	<c: 'bool SDL_HideWindow(SDL_Window *window)'>
	^self notSimulated
!
getWindowFlags: window
	<c: 'SDL_WindowFlags SDL_GetWindowFlags(SDL_Window *window)'>
	^self notSimulated
!
SDL_WINDOW_HIDDEN
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_HIDDEN'>
	^self notSimulated
!
SDL_PIXELFORMAT_XRGB8888
	<cMacro: 'SDL_PixelFormat SDL_PIXELFORMAT_XRGB8888'>
	^self notSimulated
!
SDL_WINDOW_MINIMIZED
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_MINIMIZED'>
	^self notSimulated
!
SDL_WINDOW_RESIZABLE
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_RESIZABLE'>
	^self notSimulated
!
SDL_WINDOW_HIGH_PIXEL_DENSITY
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_HIGH_PIXEL_DENSITY'>
	^self notSimulated
!
SDL_WINDOW_TRANSPARENT
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_TRANSPARENT'>
	^self notSimulated
!
setWindowOpacity: window opacity: opacity
	<c: 'bool SDL_SetWindowOpacity(SDL_Window *window, float opacity)'>
	^self notSimulated
!
fillSurfaceRect: surface rect: rect color: color
	<c: 'bool SDL_FillSurfaceRect(SDL_Surface *dst, const SDL_Rect *rect, Uint32 color)'>
	^self notSimulated
!
mapSurfaceRGBA: surface r: r g: g b: b a: a
	<c: 'Uint32 SDL_MapSurfaceRGBA(SDL_Surface *surface, Uint8 r, Uint8 g, Uint8 b, Uint8 a)'>
	^self notSimulated
! !

!SDL methodsFor: 'cursors'!
createSystemCursor: id
	<c: 'SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id)'>
	^self notSimulated
!
setCursor: cursor
	<c: 'bool SDL_SetCursor(SDL_Cursor *cursor)'>
	^self notSimulated
!
destroyCursor: cursor
	<c: 'void SDL_DestroyCursor(SDL_Cursor *cursor)'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_DEFAULT
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_DEFAULT'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_TEXT
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_TEXT'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_POINTER
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_POINTER'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_EW_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_EW_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NS_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NS_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NWSE_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NWSE_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NESW_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NESW_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_MOVE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_MOVE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_WAIT
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_WAIT'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_CROSSHAIR
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_CROSSHAIR'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NOT_ALLOWED
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NOT_ALLOWED'>
	^self notSimulated
! !

!SDL methodsFor: 'clipboard'!
getClipboardText
	<c: 'char *SDL_GetClipboardText(void)'>
	^self notSimulated
!
setClipboardText: text
	<c: 'bool SDL_SetClipboardText(const char *text)'>
	^self notSimulated
!
getClipboardData: mime size: size
	<c: 'void *SDL_GetClipboardData(const char *mime_type, size_t *size)'>
	^self notSimulated
! !

!SDL methodsFor: 'properties'!
createProperties
	<c: 'Uint32 SDL_CreateProperties(void)'>
	^self notSimulated
!
destroyProperties: props
	<c: 'void SDL_DestroyProperties(Uint32 props)'>
	^self notSimulated
!
getGlobalProperties
	<c: 'Uint32 SDL_GetGlobalProperties(void)'>
	^self notSimulated
!
setStringProperty: props name: name value: value
	<c: 'bool SDL_SetStringProperty(Uint32 props, const char *name, const char *value)'>
	^self notSimulated
!
setNumberProperty: props name: name value: value
	<c: 'bool SDL_SetNumberProperty(Uint32 props, const char *name, int64_t value)'>
	^self notSimulated
!
setBooleanProperty: props name: name value: value
	<c: 'bool SDL_SetBooleanProperty(Uint32 props, const char *name, bool value)'>
	^self notSimulated
!
setPointerProperty: props name: name value: value
	<c: 'bool SDL_SetPointerProperty(Uint32 props, const char *name, void *value)'>
	^self notSimulated
!
getPointerProperty: props name: name default: value
	<c: 'void *SDL_GetPointerProperty(Uint32 props, const char *name, void *value)'>
	^self notSimulated
!
SDL_PROP_WINDOW_CREATE_TITLE_STRING
	<cMacro: 'const char *SDL_PROP_WINDOW_CREATE_TITLE_STRING'>
	^self notSimulated
!
SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER
	<cMacro: 'const char *SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER'>
	^self notSimulated
!
SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER
	<cMacro: 'const char *SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER'>
	^self notSimulated
!
SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER
	<cMacro: 'const char *SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER'>
	^self notSimulated
!
SDL_PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN
	<cMacro: 'const char *SDL_PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN'>
	^self notSimulated
!
SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER
	<cMacro: 'const char *SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER'>
	^self notSimulated
!
SDL_PROP_GLOBAL_VIDEO_WAYLAND_WL_DISPLAY_POINTER
	<cMacro: 'const char *SDL_PROP_GLOBAL_VIDEO_WAYLAND_WL_DISPLAY_POINTER'>
	^self notSimulated
! !

ExternStruct subclass: #SDLCommonEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLCommonEvent class methodsFor: 'declaring'!
cName
	^'SDL_CommonEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64))
! !

ExternStruct subclass: #SDLMouseMotionEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLMouseMotionEvent class methodsFor: 'declaring'!
cName
	^'SDL_MouseMotionEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (state SDL_MouseButtonFlags) (x float) (y float))
! !

ExternStruct subclass: #SDLMouseButtonEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLMouseButtonEvent class methodsFor: 'declaring'!
cName
	^'SDL_MouseButtonEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (button Uint8) (down bool) (clicks Uint8) (x float) (y float))
! !

ExternStruct subclass: #SDLMouseWheelEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLMouseWheelEvent class methodsFor: 'declaring'!
cName
	^'SDL_MouseWheelEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (x float) (y float) (direction SDL_MouseWheelDirection) (mouse_x float) (mouse_y float))
! !

ExternStruct subclass: #SDLKeyboardEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLKeyboardEvent class methodsFor: 'declaring'!
cName
	^'SDL_KeyboardEvent'
!
cNameOfField: aSymbol
	"repeat is a Lowtalk control structure."
	^aSymbol = #isRepeat ifTrue: ['repeat'] ifFalse: [super cNameOfField: aSymbol]
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (scancode Uint32) (key SDL_Keycode) (mod SDL_Keymod) (raw Uint16) (down bool) (isRepeat bool))
! !

ExternStruct subclass: #SDLTextInputEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLTextInputEvent class methodsFor: 'declaring'!
cName
	^'SDL_TextInputEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (text 'const char *'))
! !

ExternStruct subclass: #SDLTextEditingEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLTextEditingEvent class methodsFor: 'declaring'!
cName
	^'SDL_TextEditingEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (text 'const char *') (start Sint32) (length Sint32))
! !

ExternStruct subclass: #SDLWindowEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLWindowEvent class methodsFor: 'declaring'!
cName
	^'SDL_WindowEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (data1 Sint32) (data2 Sint32))
! !

ExternStruct subclass: #SDLUserEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLUserEvent class methodsFor: 'declaring'!
cName
	^'SDL_UserEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (code Sint32) (data1 'void *') (data2 'void *'))
! !

ExternStruct subclass: #SDLEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLEvent class methodsFor: 'declaring'!
cName
	^'SDL_Event'
!
fields
	^#((union (type Uint32) (common SDL_CommonEvent) (motion SDL_MouseMotionEvent) (button SDL_MouseButtonEvent)
		(wheel SDL_MouseWheelEvent) (key SDL_KeyboardEvent) (edit SDL_TextEditingEvent) (text SDL_TextInputEvent) (window SDL_WindowEvent) (user SDL_UserEvent) (padding 'Uint8[128]')))
! !

ExternStruct subclass: #SDLDisplayMode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLDisplayMode class methodsFor: 'declaring'!
cName
	^'SDL_DisplayMode'
!
fields
	^#((displayID SDL_DisplayID) (format Uint32) (w int) (h int) (pixel_density float) (refresh_rate float))
! !

ExternStruct subclass: #SDLRect
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLRect class methodsFor: 'declaring'!
cName
	^'SDL_Rect'
!
fields
	^#((x int) (y int) (w int) (h int))
! !

ExternStruct subclass: #SDLFColor
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLFColor class methodsFor: 'declaring'!
cName
	^'SDL_FColor'
!
fields
	^#((r float) (g float) (b float) (a float))
! !
