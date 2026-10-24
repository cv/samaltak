ToolsTestCase subclass: #ShannonJugglerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

ShannonJugglerTest comment: 'I test the juggler''s window: its stage shows the 3D scene rendered on the GPU, it changes while the act runs and stays the same picture once the act halts.'!

!ShannonJugglerTest methodsFor: 'support'!
pictureOf: aView
	self settle.
	^world compositor sync: [:c | c screenshotOf: aView scale: 1]
!
colorsIn: aForm
	"The distinct pixel values in a coarse grid over aForm."
	| seen |
	seen := Set new.
	0 to: aForm height - 1 by: 7 do: [:y |
		0 to: aForm width - 1 by: 7 do: [:x | seen add: (aForm pixelValueAt: x @ y)]].
	^seen size
! !

!ShannonJugglerTest methodsFor: 'tests'!
testRendersAndAnimates
	| w juggler stage first frame halted |
	w := self open: [ShannonJuggler openIn: (100 @ 100 extent: 504 @ 500)].
	juggler := w content.
	stage := juggler widgetNamed: 'stage'.
	self assert: (self waitFor: [juggler frame > 5]) description: 'the act does not run'.
	first := self pictureOf: stage.
	self assert: (self colorsIn: first) > 200 description: 'the stage shows no scene'.
	self assert: (self waitFor: [(self pictureOf: stage) bits ~= first bits] timeout: 3000) description: 'the picture does not change while the act runs'.
	self in: w do: [juggler windowClosed].
	frame := juggler frame.
	halted := self pictureOf: stage.
	(Delay forMilliseconds: 300) wait.
	self assert: juggler frame equals: frame.
	self assert: (self pictureOf: stage) bits = halted bits description: 'a halted act changes its picture'
! !
