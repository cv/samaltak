Column subclass: #ToolPane
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

ToolPane comment: 'I am the abstract root widget of a tool window (System Browser, Workspace, Inspector, ...): a Column of panes that opens itself in a Window (openIn:title:), answers ? with the help overlay when no text editor has the keys and ⌘J with my Agent window (Tools open: #agent), and offers helpers my subclasses share (pane headers, timers that stop when my window closes).'!

!ToolPane methodsFor: 'opening'!
openIn: aRectangle title: aString
	"Open me in a new Window (with its own Process) framed by aRectangle; answer the Window."
	| w |
	w := Desktop newWindow title: aString; content: self; bounds: aRectangle; yourself.
	w minExtent: self minimumWindowExtent.
	w whenClosed: [self windowClosed].
	w open.
	^w
!
minimumWindowExtent
	^300 @ 200
!
windowClosed
	"My window closed (any Process): release listeners."
!
windowTitle: aString
	| w |
	w := self window.
	(w notNil and: [w title ~= aString]) ifTrue: [w title: aString]
! !

!ToolPane methodsFor: 'building'!
pane: aWidget title: aString
	^self pane: aWidget title: aString right: nil
!
pane: aWidget title: aString right: rightStringOrBlock
	"A Column with a PaneHeader above aWidget (the prototype's .pane with .pane-h)."
	| header |
	header := PaneHeader title: aString.
	rightStringOrBlock isNil ifFalse: [header rightText: rightStringOrBlock].
	^Column with: (Array with: header with: aWidget)
! !

!ToolPane methodsFor: 'timers'!
every: milliseconds do: aBlock
	"Run aBlock in my window's Process every milliseconds while my window is open (a Window timer)."
	| w |
	w := self window.
	w isNil ifTrue: [^nil].
	^w every: milliseconds do: aBlock
! !

!ToolPane methodsFor: 'events'!
keyDown: event
 (self isHelpKey: event) ifTrue: [Tools showHelp. ^true].
 ^super keyDown: event
!
isHelpKey: anEvent
	| key focus |
	key := anEvent key.
	anEvent modifiers commandKey ifTrue: [^false].
	(key = $? or: [key = $/ and: [anEvent modifiers shift]]) ifFalse: [^false].
	focus := self window isNil ifTrue: [nil] ifFalse: [self window keyboardFocus].
	^(focus isKindOf: TextEditor) not or: [focus isReadOnly]
! !
