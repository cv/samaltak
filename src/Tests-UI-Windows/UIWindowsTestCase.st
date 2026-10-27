TestCase subclass: #UIWindowsTestCase
	instanceVariableNames: 'world previous'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

UIWindowsTestCase comment: 'I am the abstract superclass of the window-system integration tests: each test runs a real World on a hidden host window (real GPU), opens windows with test views, injects platform events (the path real and remote input take) and checks routing, the window manager, compositing (screenshot readback), FrameRecords, animations and remote control.'!

!UIWindowsTestCase methodsFor: 'running'!
setUp
	previous := World current.
	world := World openHidden: 1000 @ 700
!
tearDown
	world isNil ifFalse: [world stop].
	World current: previous
!
timeLimitMilliseconds
	^30000
! !

!UIWindowsTestCase methodsFor: 'support'!
open: aView title: aString at: aRectangle
	| w |
	w := Window new title: aString; content: aView; bounds: aRectangle; yourself.
	w openIn: world.
	self settle.
	^w
!
settle
	self assert: (world waitUntilSettled: 5000) description: 'the World did not settle'
!
inject: type at: aPoint button: button count: count modifiers: mods
	DisplayWindow injectEvent: {type. nil. aPoint x. aPoint y. button. mods. count. world displayWindow windowId}
!
moveTo: aPoint
	self inject: UIEvent evMouseMove at: aPoint button: 0 count: nil modifiers: 0
!
down: aPoint
	self inject: UIEvent evMouseDown at: aPoint button: 1 count: 1 modifiers: 0
!
up: aPoint
	self inject: UIEvent evMouseUp at: aPoint button: 1 count: 1 modifiers: 0
!
click: aPoint
	self moveTo: aPoint; down: aPoint; up: aPoint.
	self settle
!
rightClick: aPoint
	self moveTo: aPoint.
	self inject: UIEvent evMouseDown at: aPoint button: 3 count: 1 modifiers: 0.
	self inject: UIEvent evMouseUp at: aPoint button: 3 count: 1 modifiers: 0.
	self settle
!
doubleClick: aPoint
	self moveTo: aPoint; down: aPoint; up: aPoint.
	self inject: UIEvent evMouseDown at: aPoint button: 1 count: 2 modifiers: 0.
	self inject: UIEvent evMouseUp at: aPoint button: 1 count: 2 modifiers: 0.
	self settle
!
click: aPoint platformCount: n
	"A click the platform counted as the nth of a multi-click (within its double-click interval)."
	self moveTo: aPoint.
	self inject: UIEvent evMouseDown at: aPoint button: 1 count: n modifiers: 0.
	self inject: UIEvent evMouseUp at: aPoint button: 1 count: n modifiers: 0.
	self settle
!
drag: from to: to
	self moveTo: from; down: from.
	1 to: 8 do: [:i | self inject: UIEvent evMouseMove at: from + (to - from * i / 8.0) button: 1 count: nil modifiers: 0].
	self up: to.
	self settle
!
key: aKey modifiers: mods
	| code |
	code := UIEvent keyCodeFor: aKey.
	self inject: UIEvent evKeyDown at: 0 @ 0 button: code count: false modifiers: mods.
	self inject: UIEvent evKeyUp at: 0 @ 0 button: code count: false modifiers: mods
!
type: aString
	DisplayWindow injectEvent: {UIEvent evTextInput. nil. 0. 0. 0. 0. aString. world displayWindow windowId}.
	self settle
!
screenshot
	^world compositor sync: [:c | c screenshotScale: 1]
!
rgbAt: aPoint in: aForm
	| v |
	v := aForm pixelValueAt: aPoint.
	^Array with: (v bitAnd: 255) with: ((v bitShift: -8) bitAnd: 255) with: ((v bitShift: -16) bitAnd: 255)
!
assertColor: aColor at: aPoint in: aForm
	| actual expected |
	actual := self rgbAt: aPoint in: aForm.
	expected := Array with: (aColor red * 255) rounded with: (aColor green * 255) rounded with: (aColor blue * 255) rounded.
	1 to: 3 do: [:i |
		((actual at: i) - (expected at: i)) abs <= 3 ifFalse: [
			^self fail: 'pixel ', aPoint printString, ' is ', actual printString, ', expected ', expected printString]]
! !

!UIWindowsTestCase class methodsFor: 'testing'!
isAbstract
	^self == UIWindowsTestCase
! !
