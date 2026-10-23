Widget subclass: #DebuggerHeader
	instanceVariableNames: 'iconKind title message link'
	classVariableNames: ''
	package: 'Tools'!

DebuggerHeader comment: 'I am the reason strip at the top of the Debugger and the Notifier (prototype .nt-head): a 22-point icon tile (DebuggerGlyphs), the title in bold (Breakpoint: Integer>>gcd:) and below it the message in italics, wrapped to at most two lines. An optional link (DebuggerLink) sits at the top right: the debugged Process and its state.'!

!DebuggerHeader methodsFor: 'accessing'!
iconKind: aSymbol title: aString message: anotherString
	iconKind := aSymbol.
	title := aString.
	message := anotherString.
	self invalidate
!
title
	^title ifNil: ['']
!
message
	^message ifNil: ['']
!
link
	^link
!
link: aWidget
	link isNil ifFalse: [self removeChild: link].
	link := aWidget.
	aWidget isNil ifFalse: [self addChild: aWidget]
! !

!DebuggerHeader methodsFor: 'layout'!
layout
	| w |
	link isNil ifTrue: [^self].
	w := (link preferredExtent x min: self width * 0.4) max: 0.
	link bounds: ((self width - w - 8) @ 7 extent: w @ 18)
!
textRight
	^link isNil ifTrue: [self width - 12] ifFalse: [link bounds left - 10]
! !

!DebuggerHeader methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| titleFont msgFont x lines y |
	aCanvas fillRect: self localBounds color: self theme paper.
	DebuggerGlyphs drawIcon: (iconKind ifNil: [#error]) in: (12 @ 10 extent: 22 @ 22) on: aCanvas.
	titleFont := self theme font: #uiBold.
	msgFont := self theme font: #smallItalic.
	x := 44.
	aCanvas clip: (x @ 0 corner: self textRight @ self height) during: [
		aCanvas drawString: self title at: x @ 8 font: titleFont color: self theme ink].
	lines := self wrap: self message width: self width - x - 12 font: msgFont lines: 2.
	y := 8 + titleFont lineHeight.
	lines do: [:each |
		aCanvas drawString: each at: x @ y font: msgFont color: (self theme color: #ink2).
		y := y + msgFont lineHeight]
!
wrap: aString width: w font: aFont lines: max
	"Greedy word wrap into at most max lines; the last one ends with … when cut."
	| words lines current |
	words := aString substrings: ' '.
	lines := OrderedCollection new.
	current := ''.
	words do: [:word | | candidate |
		candidate := current isEmpty ifTrue: [word] ifFalse: [current, ' ', word].
		((aFont widthOf: candidate) <= w or: [current isEmpty])
			ifTrue: [current := candidate]
			ifFalse: [lines add: current. current := word]].
	current isEmpty ifFalse: [lines add: current].
	lines size > max ifTrue: [
		lines := lines copyFrom: 1 to: max.
		lines at: max put: (self fit: (lines at: max), '…' font: aFont width: w)].
	^lines
!
fit: aString font: aFont width: w
	| s |
	s := aString.
	[s size > 1 and: [(aFont widthOf: s) > w]] whileTrue: [s := (s first: s size - 2), '…'].
	^s
! !

!DebuggerHeader methodsFor: 'remote control'!
remoteRole
	^#header
!
remoteLabel
	^self title
!
remoteName
	^name ifNil: ['reason']
!
remoteState
	^Array with: 'message=', (self remoteQuote: self message)
! !
