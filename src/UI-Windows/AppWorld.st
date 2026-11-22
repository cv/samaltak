World subclass: #AppWorld
	instanceVariableNames: 'deskColor'
	classVariableNames: ''
	package: 'UI-Windows'!

AppWorld comment: 'I am the World of an application that runs as a window of the host''s window manager (Hyprland on Linux, the Dock on macOS) instead of on the Samaltak desktop. My host window shows one AppWindow, chromeless and filling me, and its overlays (menus, tooltips, toasts); there is no desk and no top bar. The window manager places, decorates and closes the host window: closing it, or my last window, quits. My Compositor presents only frames in which something changed, so an idle application costs no CPU.

	| world |
	world := AppWorld openExtent: 480 @ 200 title: ''Weather''.
	(AppWindow new title: ''Weather''; content: aView) openIn: world

The host window has a fixed size (the content''s), so a tiling window manager such as Hyprland floats it. On Linux the Wayland app_id comes from SDL_APP_ID (bin/samaltak sets it).'!

!AppWorld methodsFor: 'kind'!
showsTopBar
	^false
!
presentsContinuously
	^false
! !

!AppWorld methodsFor: 'accessing'!
deskColor
	"What shows where no window is (before the first frame, or while my window redraws after a resize)."
	^deskColor ifNil: [Color white]
!
deskColor: aColor
	deskColor := aColor.
	self changed
! !

!AppWorld methodsFor: 'windows'!
addWindow: aWindow
	"No opening animation: my window fills me from its first frame."
	lock critical: [
		windowCounter := windowCounter + 1.
		aWindow remoteName isNil ifTrue: [aWindow remoteName: 'w', windowCounter printString].
		windows := (Array with: aWindow), windows].
	aWindow bounds: self bounds.
	aWindow layer waitForContent.
	self activate: aWindow.
	self changed.
	^aWindow
!
removeWindow: aWindow
	"The application ends with its last window: on screen it quits, hidden (tests) I stop."
	super removeWindow: aWindow.
	windows isEmpty ifTrue: [
		[hidden ifTrue: [self stop] ifFalse: [self quitRequested]] forkAt: Processor userBackgroundPriority]
!
nextWindowPosition: anExtent
	^0 @ 0
! !

!AppWorld methodsFor: 'desk'!
desktopClickedAt: aPoint button: anInteger
	"There is no desk to click: no World menu."
! !

!AppWorld methodsFor: 'host window'!
hostResized: aPoint
	extent := displayWindow extent.
	windows do: [:w | w bounds: self bounds].
	self changed
! !

!AppWorld methodsFor: 'drawing'!
drawDeskOn: aCanvas
	aCanvas fillRect: self bounds color: self deskColor
! !

!AppWorld methodsFor: 'remote control'!
remoteRole
	^#app
! !

!AppWorld class methodsFor: 'instance creation'!
openExtent: aPoint title: aString
	^self openExtent: aPoint title: aString hidden: false
!
openExtent: aPoint title: aString hidden: aBoolean
	"Open a host window of aPoint points with the title aString, start an AppWorld on it and make it current."
	| display world |
	display := DisplayWindow width: aPoint x ceiling height: aPoint y ceiling title: aString flags: (aBoolean ifTrue: [5] ifFalse: [4]).
	Font deviceScale = display scale ifFalse: [Font deviceScale: display scale].
	world := self new setDisplayWindow: display hidden: aBoolean.
	Current := world.
	world start.
	^world
! !
