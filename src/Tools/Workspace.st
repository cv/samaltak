ToolPane subclass: #Workspace
	instanceVariableNames: 'editor evaluator footer showingBusy'
	classVariableNames: ''
	package: 'Tools'!

Workspace comment: 'I am a Workspace: a code editor where ⌘D do it, ⌘P print it and ⌘I inspect it evaluate the selection or the caret''s line (CodeEvaluator) in a Process of its own named ''Workspace doIt'', so my window stays responsive while it runs. Variables assigned without declaration persist in my bindings. Syntax errors are marked inline; runtime errors, halts and breakpoints stop the do-it Process and open the debugger (DebugSession).

While a do-it (or a Process it forked) runs, a footer shows it (''crunch'' running · 181/400 · ⌘. interrupts); the title bar shows the do-it or the forked Process busy, or ''suspended'' while all of them are stopped (in a debugger).

	Workspace openOn: ''3 + 4'' in: (100@100 extent: 500@300) focus: true'!

!Workspace methodsFor: 'initialization'!
initialize
	super initialize.
	editor := ToolTextEditor new name: 'text'; title: 'text'; yourself.
	evaluator := CodeEvaluator new.
	evaluator install: editor.
	footer := StatusBar new name: 'footer'; yourself.
	footer visible: false.
	self addAll: (Array with: editor with: footer)
!
minimumWindowExtent
	^240 @ 120
! !

!Workspace methodsFor: 'accessing'!
editor
	^editor
!
evaluator
	^evaluator
!
bindings
	^evaluator bindings
!
text
	^editor text
! !

!Workspace methodsFor: 'running'!
startWatching
	"Poll my do-its and their children (in my window's Process) for the footer and the busy indicator."
	self every: 150 do: [self updateFooter]
!
updateFooter
	| text w busy label suspended |
	text := evaluator statusText.
	text isEmpty
		ifTrue: [footer isVisible ifTrue: [footer visible: false]]
		ifFalse: [
			footer clear.
			footer add: text style: (evaluator allSuspended ifTrue: [#pillSuspended] ifFalse: [#pillBusy]).
			footer addRight: '⌘. interrupts' style: #text.
			footer isVisible ifFalse: [footer visible: true]].
	w := self window.
	w isNil ifTrue: [^self].
	"The title bar: busy while a do-it computes ('doIt') or a Process it forked runs (its name); suspended when all of them are stopped."
	label := evaluator isComputing
		ifTrue: ['doIt']
		ifFalse: [(evaluator children detect: [:p | p isSuspended not] ifNone: [nil]) ifNotNil: [:p | p name ifNil: ['busy']]].
	busy := label notNil.
	(busy = (showingBusy == true) and: [label = w busyLabel]) ifFalse: [
		showingBusy := busy.
		w busyLabel: label.
		w busy: busy].
	suspended := busy not and: [evaluator allSuspended].
	suspended = w showsSuspended ifFalse: [w showSuspended: suspended]
! !

!Workspace class methodsFor: 'opening'!
openOn: aString in: aRectangle focus: aBoolean
	| ws window |
	ws := self new.
	ws editor text: aString.
	window := ws openIn: aRectangle title: 'Workspace'.
	window do: [
		ws startWatching.
		aBoolean ifTrue: [ws editor focus]].
	^window
!
freshText
	^'"A fresh workspace. Variables persist between evaluations."

x := 6 * 7.
x factorial printString size
'
!
initialize
	ToolsMenu register: 'Workspace' order: 20 action: [:point |
		self openOn: self freshText in: (Tools placeAt: point extent: 560 @ 300) focus: true]
! !
