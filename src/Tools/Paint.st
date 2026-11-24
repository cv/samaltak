ToolPane subclass: #Paint
	instanceVariableNames: 'canvas palette toolButtons status'
	classVariableNames: ''
	package: 'Tools'!

Paint comment: 'I am a paint program after Windows 95 Paint: a toolbox of tools at the left, the picture (a PaintCanvas), the color box (a PaintPalette) and a status bar below, and New, Undo, Redo, Save… (a PNG), the brush size and outline/filled shapes above. ⌘Z undoes, ⇧⌘Z or ⌘Y redoes, ⌘N clears, ⌘S saves.

	Paint open   "also from the World menu"'!

!Paint methodsFor: 'building'!
build
	| toolbox sizes fills |
	canvas := PaintCanvas new.
	canvas name: 'picture'.
	palette := PaintPalette new.
	palette name: 'palette'; fixed: palette preferredExtent y.
	status := PaintStatusBar new.
	status name: 'status'; fixed: status preferredExtent y; pictureExtent: canvas form extent.
	canvas onHover: [:p | status position: p].
	canvas onPick: [:color :isForeground | self syncPalette. self selectTool: #pencil].
	canvas onHistory: [self syncHistory].
	palette onChange: [:p | canvas foreground: p foreground; background: p background].
	toolButtons := Dictionary new.
	self tools do: [:each |
		toolButtons at: each value put: ((PaintToolButton tool: each value label: each key action: [self selectTool: each value])
			name: each key; fixed: 26; yourself)].
	toolbox := Column with: (((1 to: self tools size by: 2) collect: [:i |
		(Row with: ((self tools copyFrom: i to: (i + 1 min: self tools size)) collect: [:each | toolButtons at: each value]))
			spacing: 2; fixed: 26; yourself]) asArray, (Array with: Widget new)).
	toolbox spacing: 2; fixed: 54.
	sizes := ToggleGroup options: #('1' '3' '5' '9') selected: 2.
	sizes name: 'size'; fixed: 120.
	sizes onChange: [:k | canvas brushSize: k asNumber].
	fills := ToggleGroup options: #('outline' 'filled') selected: 1.
	fills name: 'shapes'; fixed: 140.
	fills onChange: [:k | canvas filled: k = 'filled'].
	self addAll: (Array
		with: ((Row with: {
			((Button label: 'New' action: [self newPicture]) name: 'New'; fixed: 60; yourself).
			((Button label: 'Undo' action: [canvas undo]) name: 'Undo'; fixed: 60; yourself).
			((Button label: 'Redo' action: [canvas redo]) name: 'Redo'; fixed: 60; yourself).
			((Button label: 'Save…' action: [self save]) name: 'Save'; fixed: 70; yourself).
			Widget new.
			(Label text: 'size' font: #ui) color: #ink3; sizeToContent; yourself.
			sizes.
			fills}) spacing: 8; fixed: 24; yourself)
		with: ((Row with: (Array with: toolbox with: canvas)) spacing: 8; yourself)
		with: palette
		with: status).
	self spacing: 8; padding: (10 @ 10 corner: 10 @ 8).
	self syncHistory
!
tools
	"label -> tool, in the toolbox's order"
	^#('Pencil' 'Brush' 'Airbrush' 'Eraser' 'Fill' 'Pick color' 'Line' 'Rectangle' 'Ellipse')
		with: #(#pencil #brush #spray #eraser #fill #picker #line #rectangle #ellipse)
		collect: [:label :tool | label -> tool]
! !

!Paint methodsFor: 'accessing'!
canvas
	^canvas
!
palette
	^palette
! !

!Paint methodsFor: 'initialize-release'!
initialize
	super initialize.
	self build.
	self selectTool: #pencil
! !

!Paint methodsFor: 'events'!
keyDown: anEvent
	"⌘Z undoes, ⇧⌘Z or ⌘Y redoes, ⌘N clears, ⌘S saves."
	| key |
	anEvent modifiers commandKey ifTrue: [
		key := anEvent key isCharacter ifTrue: [anEvent key asLowercase] ifFalse: [anEvent key].
		key = $z ifTrue: [anEvent modifiers shift ifTrue: [canvas redo] ifFalse: [canvas undo]. ^true].
		key = $y ifTrue: [canvas redo. ^true].
		key = $n ifTrue: [self newPicture. ^true].
		key = $s ifTrue: [self save. ^true]].
	^super keyDown: anEvent
!
wantsKeyboardFocus
	^true
! !

!Paint methodsFor: 'opening'!
minimumWindowExtent
	^400 @ 300
! !

!Paint methodsFor: 'actions'!
newPicture
	canvas clear.
	status pictureExtent: canvas form extent
!
save
	Tools request: 'Save the picture as PNG:' initialAnswer: 'untitled.png' then: [:path |
		[File writeBytes: canvas form pngBytes to: path.
		 self toast: 'Saved ' , path]
			on: Error do: [:e | self toast: 'Could not save: ' , e messageText]]
!
selectTool: aSymbol
	canvas tool: aSymbol.
	toolButtons keysAndValuesDo: [:tool :button | button on: tool == aSymbol].
	status toolName: (self tools detect: [:each | each value == aSymbol]) key
!
syncPalette
	palette foreground: canvas foreground; background: canvas background
!
syncHistory
	(self widgetNamed: 'Undo') enabled: canvas canUndo.
	(self widgetNamed: 'Redo') enabled: canvas canRedo
! !

!Paint class methodsFor: 'class initialization'!
initialize
	ToolsMenu register: 'Paint' description: 'pencil · shapes · fill' group: #apps order: 58 action: [:point | self openAt: point].
	Tools registerOpener: #paint with: [:argOrNil | self open]
! !

!Paint class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	| paint window |
	paint := self new.
	window := paint openIn: (Tools placeAt: aPointOrNil extent: 640 @ 520) title: 'Paint'.
	window do: [paint focus].
	^window
! !
