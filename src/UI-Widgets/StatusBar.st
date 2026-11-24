Widget subclass: #StatusBar
	instanceVariableNames: 'items'
	classVariableNames: ''
	package: 'UI-Widgets'!

StatusBar comment: 'I am the strip at the bottom of a window (Blue Book .statusbar): a 1-point rule on top, items left to right and right-aligned items, 20 points high.

	status := StatusBar new.
	status add: ''Window>>open'' style: #mono; add: ''3'' style: #chip; add: ''Windows · UI-Windows · opening''.
	status addRight: ''unsaved'' style: #pillDirty.

Styles: #text (italic, the default), #plain, #strong, #mono, #muted, #chip (a layer chip; the text is the layer number), #pillDirty #pillOk #pillBusy #pillSuspended. Texts may be blocks (evaluated at draw time). text: replaces everything with one text item.'!

!StatusBar methodsFor: 'initialization'!
initialize
	super initialize.
	items := OrderedCollection new.
	self fixed: (self theme metric: #statusBarHeight)
! !

!StatusBar methodsFor: 'accessing'!
items
	^items
!
clear
	items := OrderedCollection new.
	self invalidate
!
text: aStringOrBlock
	items := OrderedCollection new.
	self add: aStringOrBlock style: #text
!
add: aStringOrBlock
	^self add: aStringOrBlock style: #text
!
add: aStringOrBlock style: aSymbol
	items add: (Array with: aStringOrBlock with: aSymbol with: false).
	self invalidate
!
addRight: aStringOrBlock style: aSymbol
	items add: (Array with: aStringOrBlock with: aSymbol with: true).
	self invalidate
!
textOf: anItem
	| t |
	t := anItem first.
	t := t isBlock ifTrue: [t value] ifFalse: [t].
	^t isNil ifTrue: [''] ifFalse: [t asString]
!
fullText
	^String new: 80 streamContents: [:s |
		items do: [:each | | t |
			t := self textOf: each.
			t isEmpty ifFalse: [s position > 0 ifTrue: [s space]. s nextPutAll: t]]]
! !

!StatusBar methodsFor: 'drawing'!
fontForStyle: aStyle
	aStyle == #mono ifTrue: [^self theme font: #mono11].
	aStyle == #plain ifTrue: [^self theme font: #small].
	aStyle == #strong ifTrue: [^self theme font: #buttonBold].
	aStyle == #chip ifTrue: [^self theme font: #chip].
	(#(#pillDirty #pillOk #pillBusy #pillSuspended) includes: aStyle) ifTrue: [^self theme font: #buttonBold].
	aStyle isSymbol ifFalse: [^aStyle].
	^self theme font: #smallItalic
!
widthOf: anItem
	| style t |
	style := anItem at: 2.
	t := self textOf: anItem.
	style == #chip ifTrue: [^14].
	(#(#pillDirty #pillOk #pillBusy #pillSuspended) includes: style) ifTrue: [^((self fontForStyle: style) widthOf: t) + 12].
	^(self fontForStyle: style) widthOf: t
!
drawSelfOn: aCanvas
	| pad x right gap |
	pad := self theme metric: #statusBarPaddingX.
	gap := 8.
	aCanvas fillRect: self localBounds color: self theme panel.
	aCanvas fillRect: (0 @ 0 corner: self width @ 1) color: self theme rule.
	right := self width - pad.
	(items select: [:each | each last]) reverseDo: [:each |
		| w |
		w := self widthOf: each.
		self drawItem: each at: right - w on: aCanvas.
		right := right - w - gap].
	x := pad.
	aCanvas clip: (0 @ 0 corner: (right max: 0) @ self height) during: [
		(items reject: [:each | each last]) do: [:each |
			| t |
			t := self textOf: each.
			(t isEmpty and: [(each at: 2) ~~ #chip]) ifFalse: [
				self drawItem: each at: x on: aCanvas.
				x := x + (self widthOf: each) + gap]]]
!
drawItem: anItem at: x on: aCanvas
	| style t font r top color |
	style := anItem at: 2.
	t := self textOf: anItem.
	font := self fontForStyle: style.
	r := x @ 1 corner: (x + (self widthOf: anItem)) @ self height.
	style == #chip ifTrue: [^self drawChip: t in: r on: aCanvas].
	(#(#pillDirty #pillOk #pillBusy #pillSuspended) includes: style) ifTrue: [
		top := (self height + 1 - 15) / 2.
		r := x @ top extent: r width @ 15.
		color := self theme ink.
		style == #pillDirty ifTrue: [aCanvas fillRect: r color: self theme ultramarine. color := self theme paper].
		style == #pillOk ifTrue: [aCanvas strokeRect: r color: self theme ink width: 1].
		style == #pillBusy ifTrue: [aCanvas strokeRect: r color: self theme ultramarine width: 1. color := self theme ultramarine].
		style == #pillSuspended ifTrue: [aCanvas fillRect: r color: self theme ink. color := self theme paper].
		^aCanvas drawString: t in: r font: font color: color align: #center].
	color := style == #text ifTrue: [self theme color: #ink2] ifFalse: [style == #muted ifTrue: [self theme muted] ifFalse: [self theme ink]].
	aCanvas drawString: t in: r font: font color: color align: #left
!
drawChip: aString in: aRectangle on: aCanvas
	"A 14-point layer chip: the layer number on its layer color (ultramarine fading through grey)."
	| n r c fg |
	n := aString isEmpty ifTrue: [0] ifFalse: [(aString first digitValue max: 0) min: 5].
	r := aRectangle left @ ((self height + 1 - 14) / 2) extent: 14 @ 14.
	c := self theme layerColor: n.
	aCanvas fillRect: r color: c.
	n = 5 ifTrue: [aCanvas strokeRect: r color: self theme ink width: 1].
	fg := n >= 4 ifTrue: [self theme ink] ifFalse: [self theme paper].
	aCanvas drawString: aString in: r font: (self theme font: #chip) color: fg align: #center
! !

!StatusBar methodsFor: 'remote control'!
remoteRole
	^#status
!
remoteLabel
	^self fullText
! !
