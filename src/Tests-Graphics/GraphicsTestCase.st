TestCase subclass: #GraphicsTestCase
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GraphicsTestCase comment: 'I am the abstract superclass of tests that render with the real GPU (headless works: the platform starts SDL video for the GPU) and read the pixels back.'!

!GraphicsTestCase methodsFor: 'support'!
render: aBlock extent: aPoint
	"Draw with aBlock (receiving a Canvas) on white, render offscreen at scale 2, and answer the read-back Form."
	| canvas surface form |
	canvas := Canvas extent: aPoint scale: 2.
	aBlock value: canvas.
	surface := Surface extent: aPoint scale: 2.
	surface render: canvas displayList clear: Color white.
	form := surface readback.
	surface release.
	^form
!
rgbaAt: aPoint in: aForm
	"Answer {r. g. b. a} of the device pixel aPoint."
	| v |
	v := aForm pixelValueAt: aPoint.
	^Array with: (v bitAnd: 255) with: ((v bitShift: -8) bitAnd: 255) with: ((v bitShift: -16) bitAnd: 255) with: (v bitShift: -24)
!
assertPixel: aPoint in: aForm is: rgbaArray
	self assertPixel: aPoint in: aForm is: rgbaArray tolerance: 1
!
assertPixel: aPoint in: aForm is: rgbaArray tolerance: anInteger
	| actual |
	actual := self rgbaAt: aPoint in: aForm.
	1 to: 4 do: [:i |
		((actual at: i) - (rgbaArray at: i)) abs <= anInteger ifFalse: [
			^self fail: 'pixel ', aPoint printString, ' is ', actual printString, ', expected ', rgbaArray printString]]
!
grayAt: aPoint in: aForm
	^(aForm pixelValueAt: aPoint) bitAnd: 255
! !

!GraphicsTestCase class methodsFor: 'testing'!
isAbstract
	^self == GraphicsTestCase
! !
