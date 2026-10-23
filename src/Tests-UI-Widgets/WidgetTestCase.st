TestCase subclass: #WidgetTestCase
	instanceVariableNames: 'window'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

WidgetTestCase comment: 'I am the abstract superclass of the widget tests: I open a widget tree in a WidgetTestWindow, drive it with pointer, key and text events, and render it with the GPU into an offscreen Surface to check pixels (device scale 2: point p is device pixel 2p).'!

!WidgetTestCase methodsFor: 'running'!
setUp
	window := WidgetTestWindow new
! !

!WidgetTestCase methodsFor: 'opening'!
open: aWidget extent: aPoint
	window content: aWidget extent: aPoint.
	^aWidget
! !

!WidgetTestCase methodsFor: 'events'!
modifiers: anArray
	"anArray of #shift #control #option #command."
	| bits |
	bits := 0.
	(anArray includes: #shift) ifTrue: [bits := bits + 1].
	(anArray includes: #control) ifTrue: [bits := bits + 2].
	(anArray includes: #option) ifTrue: [bits := bits + 4].
	(anArray includes: #command) ifTrue: [bits := bits + 8].
	^Modifiers bits: bits
!
pointer: type at: aPoint button: button clicks: count modifiers: mods
	^window pointer: (PointerEvent type: type at: aPoint
		button: (type == #move ifTrue: [0] ifFalse: [button])
		buttons: (type == #move ifTrue: [1] ifFalse: [0])
		clickCount: count delta: nil modifiers: (self modifiers: mods) time: Time millisecondClockValue)
!
down: aPoint
	^self pointer: #down at: aPoint button: 1 clicks: 1 modifiers: #()
!
up: aPoint
	^self pointer: #up at: aPoint button: 1 clicks: 1 modifiers: #()
!
move: aPoint
	^self pointer: #move at: aPoint button: 1 clicks: 1 modifiers: #()
!
click: aPoint
	self down: aPoint.
	^self up: aPoint
!
click: aPoint modifiers: mods
	self pointer: #down at: aPoint button: 1 clicks: 1 modifiers: mods.
	^self pointer: #up at: aPoint button: 1 clicks: 1 modifiers: mods
!
click: aPoint count: n
	1 to: n do: [:i |
		self pointer: #down at: aPoint button: 1 clicks: i modifiers: #().
		self pointer: #up at: aPoint button: 1 clicks: i modifiers: #()]
!
rightClick: aPoint
	^self pointer: #down at: aPoint button: 2 clicks: 1 modifiers: #()
!
drag: from to: to
	self down: from.
	self move: (from + to) / 2.
	self move: to.
	^self up: to
!
wheel: aPoint by: deltaY
	^window pointer: (PointerEvent type: #wheel at: aPoint button: 0 buttons: 0 clickCount: 0
		delta: 0 @ deltaY modifiers: (self modifiers: #()) time: Time millisecondClockValue)
!
key: aKey
	^self key: aKey modifiers: #()
!
key: aKey modifiers: mods
	^window key: (KeyEvent type: #down keyCode: (UIEvent keyCodeFor: aKey) key: aKey repeat: false
		modifiers: (self modifiers: mods) time: Time millisecondClockValue)
!
cmd: aKey
	^self key: aKey modifiers: #(#command)
!
type: aString
	^window text: (TextEvent string: aString modifiers: Modifiers none time: Time millisecondClockValue)
! !

!WidgetTestCase methodsFor: 'rendering'!
render
	"Draw the window content on white and answer the read-back Form (device scale 2)."
	| canvas surface form |
	canvas := Canvas extent: window content extent scale: 2.
	canvas fillRect: (0 @ 0 extent: window content extent) color: Color white.
	window content drawOn: canvas.
	surface := Surface extent: window content extent scale: 2.
	surface render: canvas displayList clear: Color white.
	form := surface readback.
	surface release.
	^form
!
grayAt: aPoint in: aForm
	"Red channel of the device pixel at aPoint (points, scaled by 2), rounded down."
	^((aForm pixelValueAt: (aPoint * 2) floor) bitAnd: 255)
!
rgbAt: aPoint in: aForm
	| v |
	v := aForm pixelValueAt: (aPoint * 2) floor.
	^Array with: (v bitAnd: 255) with: ((v bitShift: -8) bitAnd: 255) with: ((v bitShift: -16) bitAnd: 255)
!
assertBlackAt: aPoint in: aForm
	self assert: (self grayAt: aPoint in: aForm) < 40 description: 'expected black at ', aPoint printString, ' got ', (self rgbAt: aPoint in: aForm) printString
!
assertWhiteAt: aPoint in: aForm
	self assert: (self grayAt: aPoint in: aForm) > 215 description: 'expected white at ', aPoint printString, ' got ', (self rgbAt: aPoint in: aForm) printString
!
inkIn: aRectangle of: aForm
	"Count the dark device pixels (red < 128) inside aRectangle (points)."
	| n |
	n := 0.
	(aRectangle top * 2) floor to: (aRectangle bottom * 2) ceiling - 1 do: [:y |
		(aRectangle left * 2) floor to: (aRectangle right * 2) ceiling - 1 do: [:x |
			((aForm pixelValueAt: x @ y) bitAnd: 255) < 128 ifTrue: [n := n + 1]]].
	^n
!
fractionDarkIn: aRectangle of: aForm
	| area |
	area := ((aRectangle width * 2) ceiling * (aRectangle height * 2) ceiling) max: 1.
	^(self inkIn: aRectangle of: aForm) / area
! !

!WidgetTestCase methodsFor: 'remote'!
remoteChildrenOf: aWidget
	^aWidget remoteChildren asArray
!
remoteLabelsOf: aWidget
	^(aWidget remoteChildren reject: [:each | each isString]) collect: [:each | each remoteLabel]
! !

!WidgetTestCase class methodsFor: 'testing'!
isAbstract
	^self == WidgetTestCase
! !
