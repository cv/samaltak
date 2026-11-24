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
	self assert: (t color: #l3) equals: (Color hex: 16r76B900).
	self assert: (t color: #paper) equals: (Color hex: 16rDEDEDE).
	self assert: (t color: #tab) equals: (Color hex: 16rFFD75A).
	self assert: t isBevelled.
	self deny: Theme blueBook isBevelled
!
testRefreshKeepsColors
	| t |
	t := Theme beGold.
	t refresh.
	self assert: (t color: #desk) equals: (Color hex: 16r5E9400).
	self assert: t isBevelled
!
testToggle
	Theme use: Theme blueBook.
	Theme toggle.
	self assert: Theme current isBevelled.
	Theme toggle.
	self deny: Theme current isBevelled
!
testUseSwitchesChrome
	Theme use: Theme beGold.
	self assert: Window chromeStyle equals: #tab.
	self assert: (Color named: #desk) equals: (Color hex: 16r5E9400).
	Theme use: Theme blueBook.
	self assert: Window chromeStyle equals: #classic.
	self assert: (Color named: #desk) equals: Color white
! !
