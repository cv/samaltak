Widget subclass: #ProfilerStatusBar
	instanceVariableNames: 'rangeText pickText clearButton browseButton'
	classVariableNames: ''
	package: 'Tools'!

ProfilerStatusBar comment: 'I am the Profiler window''s status bar: the range shown (whole ring and live, or the pinned range) with a "clear range" button while one is pinned, and on the right the picked method with a "browse" button.'!

!ProfilerStatusBar methodsFor: 'initialization'!
initialize
	super initialize.
	self fixed: (self theme metric: #statusBarHeight).
	rangeText := ''.
	pickText := ''.
	clearButton := Button label: 'clear range'.
	clearButton name: 'clear-range'; font: #small.
	clearButton setVisible: false.
	browseButton := Button label: 'browse'.
	browseButton name: 'browse'; font: #small; enabled: false.
	self addChild: clearButton; addChild: browseButton
! !

!ProfilerStatusBar methodsFor: 'accessing'!
clearButton
	^clearButton
!
browseButton
	^browseButton
!
rangeText: aString pinned: aBoolean
	(rangeText = aString and: [aBoolean = clearButton isVisible]) ifTrue: [^self].
	rangeText := aString.
	aBoolean = clearButton isVisible ifFalse: [clearButton setVisible: aBoolean].
	self layout.
	self invalidate
!
pickText: aString browsable: aBoolean
	(pickText = aString and: [aBoolean = browseButton isEnabled]) ifTrue: [^self].
	pickText := aString.
	browseButton enabled: aBoolean.
	self invalidate
!
fullText
	^rangeText, '  ', pickText
! !

!ProfilerStatusBar methodsFor: 'layout'!
layout
	| pad x w |
	pad := self theme metric: #statusBarPaddingX.
	x := pad + ((self theme font: #smallItalic) widthOf: rangeText) + 8.
	w := ((self theme font: #small) widthOf: 'clear range') + 12.
	clearButton bounds: (x @ 2 extent: w @ (self height - 3)).
	w := ((self theme font: #small) widthOf: 'browse') + 16.
	browseButton bounds: ((self width - pad - w) @ 2 extent: w @ (self height - 3))
! !

!ProfilerStatusBar methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| pad right |
	pad := self theme metric: #statusBarPaddingX.
	aCanvas fillRect: self localBounds color: self theme paper.
	aCanvas fillRect: (0 @ 0 corner: self width @ 1) color: self theme rule.
	aCanvas drawString: rangeText in: (pad @ 1 corner: self width @ self height) font: (self theme font: #smallItalic) color: (self theme color: #ink2) align: #left.
	right := browseButton bounds left - 8.
	aCanvas clip: ((self width / 2) @ 0 corner: right @ self height) during: [
		aCanvas drawString: pickText in: ((self width / 2) @ 1 corner: right @ self height) font: (self theme font: #mono11) color: self theme ink align: #right]
! !

!ProfilerStatusBar methodsFor: 'remote control'!
remoteRole
	^#status
!
remoteLabel
	^self fullText
! !
