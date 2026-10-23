PaneHeader subclass: #DebuggerPaneHeader
	instanceVariableNames: 'titleFont'
	classVariableNames: ''
	package: 'Tools'!

DebuggerPaneHeader comment: 'I am a PaneHeader whose title may use another font: the Debugger''s source pane shows the selected frame (SmallInteger(Integer)>>gcd:) in bold code type instead of tracked capitals.'!

!DebuggerPaneHeader methodsFor: 'accessing'!
titleFont: aFontOrSymbol
	titleFont := aFontOrSymbol.
	self invalidate
! !

!DebuggerPaneHeader methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| pad r right rw rf |
	titleFont isNil ifTrue: [^super drawSelfOn: aCanvas].
	pad := self theme metric: #paneHeaderPaddingX.
	r := 0 @ 0 corner: self width @ (self height - 1).
	aCanvas fillRect: r color: self theme paper.
	aCanvas fillRect: (0 @ (self height - 1) corner: self width @ self height) color: self theme rule.
	right := self rightText.
	rf := self fontFor: #smallItalic.
	rw := right isEmpty ifTrue: [0] ifFalse: [rf widthOf: right].
	right isEmpty ifFalse: [
		aCanvas drawString: right in: (pad @ 0 corner: (self width - pad) @ r bottom) font: rf color: self theme muted align: #right].
	aCanvas clip: (0 @ 0 corner: (self width - pad - rw - 10 max: 0) @ r bottom) during: [
		aCanvas drawString: self title in: (pad @ 0 corner: self width @ r bottom)
			font: (self fontFor: titleFont) color: self theme ink align: #left]
! !
