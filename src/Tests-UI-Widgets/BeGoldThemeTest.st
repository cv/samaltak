TestCase subclass: #BeGoldThemeTest
	instanceVariableNames: 'saved'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

BeGoldThemeTest comment: 'I test the be-gold theme: its colors, its bevel metric and the window chrome it selects, restoring the theme that was current.'!

!BeGoldThemeTest methodsFor: 'running'!
setUp
	saved := Theme current
!
tearDown
	Theme use: saved
! !

!BeGoldThemeTest methodsFor: 'tests'!
testColors
	| t |
	t := Theme beGold.
	self assert: (t color: #desk) equals: (Color hex: 16r336698).
	self assert: (t color: #ultramarine) equals: (Color hex: 16r336698).
	self assert: t paper equals: Color white.
	self assert: t panel equals: (Color hex: 16rD8D8D8).
	self assert: (t color: #tab) equals: (Color hex: 16rFFCB00).
	self assert: t selectionColor equals: (Color hex: 16rBEBEBE).
	self deny: t invertsSelection.
	self assert: t isBevelled.
	self deny: Theme blueBook isBevelled.
	self assert: Theme blueBook invertsSelection.
	self assert: Theme blueBook panel equals: Theme blueBook paper
!
testRefreshKeepsColors
	| t |
	t := Theme beGold.
	t refresh.
	self assert: (t color: #desk) equals: (Color hex: 16r336698).
	self assert: t isBevelled
!
testTabGeometry
	| w |
	Window chromeStyle: #tab.
	[w := Window new title: 'Tab'; bounds: (100 @ 100 extent: 400 @ 300); yourself.
	 self assert: w contentRectInWindow equals: (5 @ 29 corner: 395 @ 295).
	 self assert: w tabRect right < 400.
	 self assert: (w zoneAt: 100 @ 100 + w closeBoxRect center) equals: #close.
	 self assert: (w zoneAt: 100 @ 100 + w collapseBoxRect center) equals: #collapse.
	 self assert: (w zoneAt: 100 @ 100 + ((w closeBoxRect right + 8) @ 10)) equals: #title.
	 self assert: (w zoneAt: 100 @ 100 + ((w tabRect right + 10) @ 10)) isNil.
	 self assert: (w zoneAt: 100 @ 100 + (200 @ 100)) equals: #content.
	 self assert: (w zoneAt: 100 @ 100 + (2 @ 100)) equals: #resizeL]
		ensure: [Window chromeStyle: saved chromeStyle]
!
testToggle
	Theme use: Theme blueBook.
	Theme toggle.
	self assert: Theme current isBevelled.
	Theme toggle.
	self deny: Theme current isBevelled
!
testUseSubstitutesTheUIFace
	(Font imageFaceNamed: 'NotoSans-Regular') isNil ifTrue: [^self skip: 'the image has no Noto Sans'].
	Theme use: Theme beGold.
	self assert: (Font faceNamed: 'IosevkaEtoile-Regular') equals: (Font imageFaceNamed: 'NotoSans-Regular').
	self assert: (Font faceNamed: 'JetBrainsMono-Regular') equals: (Font imageFaceNamed: 'JetBrainsMono-Regular').
	Theme use: Theme blueBook.
	self assert: (Font faceNamed: 'IosevkaEtoile-Regular') equals: (Font imageFaceNamed: 'IosevkaEtoile-Regular')
!
testUseSwitchesChrome
	Theme use: Theme beGold.
	self assert: Window chromeStyle equals: #tab.
	self assert: (Color named: #desk) equals: (Color hex: 16r336698).
	self assert: (Color named: #panel) equals: (Color hex: 16rD8D8D8).
	Theme use: Theme blueBook.
	self assert: Window chromeStyle equals: #classic.
	self assert: (Color named: #desk) equals: Color white.
	self assert: (Color named: #panel) equals: Color white
! !
