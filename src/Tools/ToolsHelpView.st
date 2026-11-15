Widget subclass: #ToolsHelpView
	instanceVariableNames: ''
	classVariableNames: 'Current'
	package: 'Tools'!

ToolsHelpView comment: 'I am the help overlay (? or World menu › Help…): a Blue Book card "Samaltak — how to drive it" listing the keys and gestures (prototypes/1-classic/main.js buildHelp), centered on the screen. The World hosts me as an overlay (with its hard shadow); a click, Escape or ? closes me, as does a click outside.'!

!ToolsHelpView methodsFor: 'accessing'!
preferredExtent
	^self cardExtent
!
sections
	^#(
		#('Evaluate (any text pane)' #(
			#('⌘D' 'do it — selection, or the current line')
			#('⌘P' 'print it — result inserted, selected')
			#('⌘I' 'inspect it — opens an Inspector')
			#('⌘B' 'browse it — class or implementor')
			#('⌘J' 'agent — a conversation on this tool''s context')
			#('⌘S' 'accept — compile method in a Browser')
			#('⌘F' 'filter a Browser by class and method names')
			#('right-click' 'the same, as a menu')))
		#('Processes' #(
			#('⌘.' 'user interrupt — stops the busy Process')
			#('…forkNamed:' 'evaluate the ''crunch'' line in the Workspace')
			#('click' 'Mandelbrot: zoom (renders in its Process)')
			#('dbl-click' 'Process Browser row: debug it')))
		#('Windows & desktop' #(
			#('drag' 'title bar moves; edges and corner resize')
			#('dbl-click' 'title bar collapses / expands')
			#('click' 'empty desktop: World menu')
			#('?' 'this help · Esc closes'))))
!
lede
	^'Every window runs in its own green thread (Process). A busy window never freezes the others; the compositor keeps dragging smooth. The title-bar dot is the window''s Process.'
!
cardExtent
	^560 @ 545
!
cardRect
	^self localBounds
! !

!ToolsHelpView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| card ink title font tw x0 x1 y keysX textX |
	ink := self theme ink.
	card := self cardRect.
	aCanvas fillRect: card color: self theme paper.
	aCanvas strokeRect: card color: ink width: 1.
	"title bar"
	title := 'Samaltak — how to drive it'.
	font := self theme font: #title.
	tw := font widthOf: title.
	x0 := card left + ((card width - tw) / 2) floor.
	x1 := x0 + tw.
	aCanvas strokeRect: (card left + 7 @ (card top + 6) extent: 11 @ 11) color: ink width: 1.
	aCanvas pattern: #stripes in: ((card left + 24) @ (card top + 6) corner: (x0 - 12) @ (card top + 17)).
	aCanvas pattern: #stripes in: ((x1 + 12) @ (card top + 6) corner: (card right - 7) @ (card top + 17)).
	aCanvas fillRect: ((x0 - 8) @ (card top + 4) corner: (x1 + 8) @ (card top + 20)) color: ink.
	aCanvas drawString: title at: x0 @ (card top + 4) font: font color: self theme paper.
	aCanvas fillRect: (card left @ (card top + 22) corner: card right @ (card top + 23)) color: ink.
	y := card top + 38.
	y := self drawParagraph: self lede at: (card left + 22) @ y width: card width - 44 font: (self theme font: #uiItalic) on: aCanvas.
	keysX := card left + 22.
	textX := card left + 150.
	self sections do: [:section |
		y := y + 12.
		aCanvas drawString: section first at: keysX @ y font: (self theme font: #header) color: ink.
		y := y + 17.
		aCanvas fillRect: (keysX @ y corner: (card right - 22) @ (y + 1)) color: ink.
		y := y + 5.
		section last do: [:row |
			self drawKey: row first at: keysX @ y on: aCanvas.
			aCanvas drawString: row last at: textX @ (y + 1) font: (self theme font: #ui) color: ink.
			y := y + 21]]
!
drawKey: aString at: aPoint on: aCanvas
	| font w r |
	font := self theme font: #mono11.
	w := (font widthOf: aString) + 10.
	r := aPoint extent: w @ 17.
	aCanvas fillRect: r color: self theme paper.
	aCanvas strokeRect: r color: self theme ink width: 1.
	aCanvas fillRect: (r left + 1 @ (r bottom - 1) corner: r right @ r bottom) color: self theme ink.
	aCanvas drawString: aString in: r font: font color: self theme ink align: #center
!
drawParagraph: aString at: aPoint width: width font: aFont on: aCanvas
	"Draw aString wrapped at word boundaries; answer the y below it."
	| words line y |
	words := aString substrings.
	line := ''.
	y := aPoint y.
	words do: [:w |
		| candidate |
		candidate := line isEmpty ifTrue: [w] ifFalse: [line, ' ', w].
		(aFont widthOf: candidate) > width
			ifTrue: [
				aCanvas drawString: line at: aPoint x @ y font: aFont color: self theme ink.
				y := y + aFont lineHeight + 2.
				line := w]
			ifFalse: [line := candidate]].
	line isEmpty ifFalse: [
		aCanvas drawString: line at: aPoint x @ y font: aFont color: self theme ink.
		y := y + aFont lineHeight + 2].
	^y
! !

!ToolsHelpView methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
mouseDown: anEvent
	self close.
	^true
!
keyDown: anEvent
	(anEvent key == #escape or: [anEvent key = $? or: [anEvent key = $/ or: [anEvent key == #return]]])
		ifTrue: [self close. ^true].
	^true
!
textInput: anEvent
	^true
!
close
	Current == self ifTrue: [Current := nil].
	self worldDo: [:world | world closeMenu: self]
! !

!ToolsHelpView methodsFor: 'remote control'!
remoteRole
	^#help
!
remoteLabel
	^'Samaltak — how to drive it'
!
remoteName
	^'help'
! !

!ToolsHelpView class methodsFor: 'opening'!
open
	"Show the help overlay (or close it when it is showing)."
	| world view |
	world := Desktop current.
	world isNil ifTrue: [^nil].
	(Current notNil and: [Current window notNil and: [Current window isOpen]]) ifTrue: [
		Current close.
		^nil].
	view := self new.
	Current := view.
	world openMenu: view at: (world extent - view cardExtent) // 2.
	^view
!
isShowing
	^Current notNil and: [Current window notNil and: [Current window isOpen]]
! !
