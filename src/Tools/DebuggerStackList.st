ListView subclass: #DebuggerStackList
	instanceVariableNames: 'moreText'
	classVariableNames: ''
	package: 'Tools'!

DebuggerStackList comment: 'I am the stack list of the Debugger and the Notifier: one row per Context in code type (frames of the signaling machinery and below the evaluated code muted), a breakpoint mark in the leading cell, and, when frames are hidden, a last row "… 5 more frames — Full stack" drawn as an ultramarine italic link (the item #more).'!

!DebuggerStackList methodsFor: 'initialization'!
initialize
	super initialize.
	self font: #codeSmall.
	self cellWidth: 9.
	self remoteNameBlock: [:item | item == #more ifTrue: ['more'] ifFalse: [self labelOf: item]]
! !

!DebuggerStackList methodsFor: 'accessing'!
moreText: aString
	moreText := aString
! !

!DebuggerStackList methodsFor: 'drawing'!
drawItem: anItem in: r on: aCanvas inverted: inverted
	| f x color w |
	anItem == #more ifFalse: [^super drawItem: anItem in: r on: aCanvas inverted: inverted].
	f := self theme font: #smallItalic.
	x := r left + self paddingX.
	color := inverted ifTrue: [self theme paper] ifFalse: [self theme ultramarine].
	aCanvas drawString: (moreText ifNil: ['']) in: (x @ r top corner: r corner) font: f color: color align: #left.
	w := f widthOf: (moreText ifNil: ['']).
	aCanvas fillRect: (x @ (r bottom - 4) extent: w @ 1) color: color
!
labelOf: anItem
	anItem == #more ifTrue: [^moreText ifNil: ['']].
	^super labelOf: anItem
! !
