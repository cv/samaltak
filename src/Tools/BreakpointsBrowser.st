Column subclass: #BreakpointsBrowser
	instanceVariableNames: 'list toggle remove removeAll count listener'
	classVariableNames: ''
	package: 'Tools'!

BreakpointsBrowser comment: 'I am the Breakpoints window: every Breakpoint (method: break, once, log, conditional; per-object) and Watchpoint (halt on write) in the image, with its mark, location, kind and hits. Disable/Enable, Remove, Remove all; double-click browses the method or inspects the object. I follow Breakpoint and Watchpoint change notifications, so hits and new breakpoints appear at once. There is one of me: open focuses it.

	BreakpointsBrowser open

Remote names: list breakpoints, buttons toggle remove remove-all.'!

!BreakpointsBrowser methodsFor: 'initialization'!
build
	| status |
	list := ListView new.
	list name: 'breakpoints'; title: 'Breakpoints'; font: #code12; cellWidth: 9.
	list labelBlock: [:each | self titleOf: each].
	list rightBlock: [:each | self descriptionOf: each].
	list styleBlock: [:each | each isEnabled ifTrue: [nil] ifFalse: [#muted]].
	list cellBlock: [:canvas :rect :each :inverted |
		DebuggerGlyphs drawMark: (DebuggerGlyphs markKindOf: each) enabled: each isEnabled
			at: (rect left + 4.5) @ rect center y inverted: inverted on: canvas].
	list emptyText: 'No breakpoints. Set one in a Browser''s method list or an Inspector.'.
	list onSelect: [:each | self updateButtons].
	list onDoubleClick: [:each | self browse: each].
	toggle := Button label: 'Disable' action: [self toggleSelected].
	toggle name: 'toggle'; minExtent: 64 @ 20; sizeToContent.
	remove := Button label: 'Remove' action: [self removeSelected].
	remove name: 'remove'; sizeToContent.
	removeAll := Button label: 'Remove all' action: [self removeEverything].
	removeAll name: 'remove-all'; sizeToContent.
	count := Label text: '' font: #smallItalic.
	count name: 'count'; color: #ink3; align: #right; flex: 1.
	status := StatusBar new.
	status name: 'status'.
	status add: 'Browser method gutter: click to set · Inspector: Halt on write'.
	status addRight: 'image-side' style: #text.
	self addAll: {
		(Row with: {toggle. remove. removeAll. count}) spacing: 5; padding: (8 @ 5 corner: 8 @ 5); background: #paper; fixed: 30; yourself.
		DebuggerRule new.
		list.
		status}.
	listener := [:changed | self inWindowDo: [self refresh]].
	Breakpoint addListener: listener.
	Watchpoint addListener: listener.
	self refresh
! !

!BreakpointsBrowser methodsFor: 'accessing'!
list
	^list
!
entries
	^Breakpoint all, Watchpoint all
!
titleOf: anEntry
	(anEntry respondsTo: #isWatchpoint) ifTrue: [^anEntry description].
	^anEntry locationDescription
!
descriptionOf: anEntry
	| kind |
	kind := (anEntry respondsTo: #isWatchpoint)
		ifTrue: ['halt on write']
		ifFalse: [
			anEntry isObjectBreakpoint
				ifTrue: ['per-object']
				ifFalse: [anEntry modeDescription]].
	anEntry isEnabled ifFalse: [kind := kind, ' · disabled'].
	^kind, ' · ', anEntry hits printString, (anEntry hits = 1 ifTrue: [' hit'] ifFalse: [' hits'])
! !

!BreakpointsBrowser methodsFor: 'actions'!
refresh
	| items |
	items := self entries.
	list items: items.
	count text: items size printString, ' set'.
	self updateButtons
!
updateButtons
	| sel |
	sel := list selection.
	toggle enabled: sel notNil.
	remove enabled: sel notNil.
	removeAll enabled: list items notEmpty.
	toggle label: ((sel notNil and: [sel isEnabled not]) ifTrue: ['Enable'] ifFalse: ['Disable'])
!
toggleSelected
	| sel |
	sel := list selection.
	sel isNil ifTrue: [^self].
	sel isEnabled ifTrue: [sel disable] ifFalse: [sel enable].
	self refresh
!
removeSelected
	| sel |
	sel := list selection.
	sel isNil ifTrue: [^self].
	sel remove.
	self refresh
!
removeEverything
	Breakpoint removeAll.
	Watchpoint removeAll.
	self refresh
!
browse: anEntry
	((anEntry respondsTo: #isMethodBreakpoint) and: [anEntry isMethodBreakpoint])
		ifTrue: [Tools browseClass: anEntry methodClass selector: anEntry selector]
		ifFalse: [Tools inspect: anEntry object]
!
windowClosed
	Breakpoint removeListener: listener.
	Watchpoint removeListener: listener
! !

!BreakpointsBrowser methodsFor: 'events'!
keyDown: anEvent
	"⌘J: my Agent window (Tools open: #agent), as in a ToolPane."
	(anEvent key = $j and: [anEvent modifiers commandKey]) ifTrue: [Tools open: #agent with: self. ^true].
	^false
! !

!BreakpointsBrowser methodsFor: 'remote control'!
remoteRole
	^#breakpoints
! !

!BreakpointsBrowser class methodsFor: 'opening'!
open
	| existing browser window |
	existing := Desktop current windows detect: [:w | w content isKindOf: self] ifNone: [nil].
	existing isNil ifFalse: [existing focus. ^existing].
	browser := self new build; yourself.
	window := Desktop newWindow.
	window title: 'Breakpoints'; content: browser; bounds: (DebuggerTools boundsFor: 520 @ 236); minExtent: 320 @ 150.
	window whenClosed: [browser windowClosed].
	window open.
	DebuggerTools ignore: window.
	^window
! !
