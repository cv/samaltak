Object subclass: #Application
	instanceVariableNames: 'world window'
	classVariableNames: 'MenuItems'
	package: 'UI-Widgets'!

Application comment: 'I am an application that runs as a window of the host''s window manager (Hyprland on Linux) rather than on the Samaltak desktop: an AppWorld of my own with one AppWindow showing my content. Subclass me, then run me from the source with bin/samaltak:

	bin/samaltak run apps/Weather          "files in the package directory apps/Weather, runs its Application"
	WeatherApp run                         "the same from a running image"

Subclasses answer content (a View, built once), and may override title, extent (default: the content''s preferredExtent; fitToContent resizes the host window to it when it changed), backgroundColor, prepare (before the window opens: themes, fonts) and started (after it opened: timers, fetching). Code that touches my widgets runs in my window''s Process (window do: [...]). Unhandled errors in my window''s Process are reported (stderr, a toast) and its event loop restarts. The sampling profiler is paused unless the command line has --profile.

⌘J, ⌘I, ⌘B and ⌘C that my content does not take act on me (commandKey:). A right-click my content does not take opens my menu (contextMenu): the items subclasses add (addMenuItemsTo:), then those other packages add to every application (Application addMenuItem:with:; UI-Agent''s Agent opens the agent on me, agentContext). isResizable makes my host window resizable (a tiling window manager then tiles it).'!

!Application methodsFor: 'accessing'!
world
	^world
!
window
	^window
!
title
	"The host window's title."
	^self class name asString
!
content
	"My View, built once."
	^self subclassResponsibility
!
extent
	"The host window's size in points (fixed: a tiling window manager floats it)."
	^window isNil
		ifTrue: [self content preferredExtent]
		ifFalse: [window content preferredExtent]
!
backgroundColor
	"What shows before my content drew its first frame."
	^Theme current paper
!
isResizable
	"Whether the host window may be resized (its content then follows); a fixed one floats in a tiling window manager."
	^false
! !

!Application methodsFor: 'menu'!
contextMenu
	"My right-click menu: my own items, then the ones other packages add to every application."
	| menu |
	menu := Menu new.
	self addMenuItemsTo: menu.
	(MenuItems ifNil: [#()]) do: [:each | each value value: self value: menu].
	^menu
!
addMenuItemsTo: aMenu
	"Add my own items to my right-click menu."
! !

!Application methodsFor: 'keys'!
commandKey: aKeyEvent
	"A key no view of my window took: ⌘J opens the Agent on me (as my menu's Agent does), ⌘I inspects me, ⌘B browses my class, ⌘C copies me (for the Agent's ask box), as a tool's do on the desktop (ActionContext; the tools are filed in the first time, Desktop actions). Answer whether I took it."
	| key actions |
	(aKeyEvent isDown and: [aKeyEvent modifiers commandKey]) ifFalse: [^false].
	key := aKeyEvent key.
	key isCharacter ifFalse: [^false].
	key := key asLowercase.
	key = $j ifTrue: [
		(Smalltalk at: #AgentWindow ifAbsent: [nil]) ifNotNil: [:agent | agent openNativeFor: self. ^true].
		^false].
	(#($i $b $c) includes: key) ifFalse: [^false].
	actions := Desktop actions.
	actions isNil ifTrue: [^false].
	key = $i ifTrue: [(actions for: self) inspect. ^true].
	key = $b ifTrue: [(actions for: self) browse. ^true].
	window clipboard: self printString.
	actions copied: (actions for: self).
	^true
! !

!Application methodsFor: 'hooks'!
prepare
	"Before my window opens."
!
started
	"After my window opened."
!
stopped
	"After my window closed."
! !

!Application methodsFor: 'resizing'!
fitToContent
	"Resize the host window to my extent if that changed (new data made the content taller); in my window's Process."
	| e |
	world isNil ifTrue: [^self].
	e := self extent ceiling.
	world extent = e ifFalse: [world resizeTo: e]
! !

!Application methodsFor: 'running'!
run
	^self runHidden: false
!
runHidden: aBoolean
	"Open my window (hidden: offscreen, for tests) and answer myself."
	^self openHidden: aBoolean main: true desktop: false
!
runOnDesktopHidden: aBoolean
	"Open my window on the desktop, below every window, as one of several applications of this process (closing it does not quit; OmarchyDesk places it with world moveTo:); answer myself."
	^self openHidden: aBoolean main: false desktop: true
!
openHidden: aBoolean main: mainBoolean desktop: desktopBoolean
	| view |
	Desktop windowErrorHandler: nil.
	"The always-on sampling profiler wakes the VM every millisecond, also while it idles: an application, often idle all day, runs without it unless --profile."
	(Smalltalk vm arguments includes: '--profile') ifFalse: [Profiler pause].
	self prepare.
	view := self content.
	world := AppWorld openExtent: self extent title: self title hidden: aBoolean main: mainBoolean
		resizable: (self isResizable and: [desktopBoolean not]) desktop: desktopBoolean.
	world deskColor: self backgroundColor.
	window := AppWindow new title: self title; content: view; yourself.
	window menuBlock: [self contextMenu].
	window keyBlock: [:event | self commandKey: event].
	window whenClosed: [:w | self stopped].
	window openIn: world.
	self started
!
stop
	"Close my window; the application quits."
	window isNil ifFalse: [window close]
! !

!Application class methodsFor: 'menu'!
addMenuItem: aSymbol with: aBlock
	"[:application :menu | ...] adds items to every application's right-click menu; another block under aSymbol replaces it."
	| items |
	items := (MenuItems ifNil: [#()]) reject: [:each | each key == aSymbol].
	MenuItems := items copyWith: aSymbol -> aBlock
!
removeMenuItem: aSymbol
	MenuItems := (MenuItems ifNil: [#()]) reject: [:each | each key == aSymbol]
! !

!Application class methodsFor: 'running'!
run
	^self new run
!
runHidden
	^self new runHidden: true
! !
