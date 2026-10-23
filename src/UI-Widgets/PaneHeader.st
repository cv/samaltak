Widget subclass: #PaneHeader
	instanceVariableNames: 'title rightText rightFont'
	classVariableNames: ''
	package: 'UI-Widgets'!

PaneHeader comment: 'I am the header strip of a pane (Blue Book .pane-h): a tracked-capitals title on the left, muted italic text on the right, a 1-point rule below. 20 points high (Theme metric #paneHeaderHeight). title: and rightText: take Strings or blocks.'!

!PaneHeader methodsFor: 'initialization'!
initialize
	super initialize.
	self fixed: (self theme metric: #paneHeaderHeight)
! !

!PaneHeader methodsFor: 'accessing'!
title
	^title isBlock ifTrue: [title value asString] ifFalse: [title ifNil: ['']]
!
title: aStringOrBlock
	title := aStringOrBlock.
	self invalidate
!
rightText
	^rightText isBlock ifTrue: [rightText value asString] ifFalse: [rightText ifNil: ['']]
!
rightText: aStringOrBlock
	rightText := aStringOrBlock.
	self invalidate
!
rightFont: aFontOrSymbol
	rightFont := aFontOrSymbol
!
preferredExtent
	^100 @ (self theme metric: #paneHeaderHeight)
! !

!PaneHeader methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| pad r right rw |
	rightText isBlock ifTrue: [aCanvas noteVolatile].
	pad := self theme metric: #paneHeaderPaddingX.
	r := 0 @ 0 corner: self width @ (self height - 1).
	aCanvas fillRect: r color: self theme paper.
	aCanvas fillRect: (0 @ (self height - 1) corner: self width @ self height) color: self theme rule.
	right := self rightText.
	rw := 0.
	right isEmpty ifFalse: [
		rw := (self fontFor: (rightFont ifNil: [#smallItalic])) widthOf: right.
		aCanvas drawString: right in: ((pad @ 0) corner: (self width - pad) @ r bottom)
			font: (self fontFor: (rightFont ifNil: [#smallItalic])) color: self theme muted align: #right].
	aCanvas clip: (0 @ 0 corner: (self width - pad - rw - 6 max: 0) @ r bottom) during: [
		aCanvas drawString: self title in: (pad @ 0 corner: self width @ r bottom)
			font: (self theme font: #header) color: self theme ink align: #left]
! !

!PaneHeader methodsFor: 'remote control'!
remoteRole
	^#header
!
remoteLabel
	^self title
!
remoteName
	"Not the title alone: that slug belongs to the pane's list or editor."
	^name ifNil: ['header-', self title]
!
remoteState
	| r |
	r := self rightText.
	^r isEmpty ifTrue: [#()] ifFalse: [Array with: 'right=', (self remoteQuote: r)]
! !

!PaneHeader class methodsFor: 'instance creation'!
title: aString
	^self new title: aString; yourself
!
title: aString right: anotherString
	^self new title: aString; rightText: anotherString; yourself
! !
