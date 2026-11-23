DamageProbe subclass: #SlowFrameProbe
	instanceVariableNames: 'milliseconds frames'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

SlowFrameProbe comment: 'A DamageProbe that only makes each frame of its compositor take milliseconds longer (a busy loop before the layers render), as a slow GPU or a loaded machine would, and counts the frames (CompositorTest).'!

!SlowFrameProbe methodsFor: 'accessing'!
milliseconds: anInteger
	milliseconds := anInteger
!
frames
	^frames ifNil: [0]
! !

!SlowFrameProbe methodsFor: 'probing'!
beforeRender: windows
	| end |
	frames := self frames + 1.
	end := Time millisecondClockValue + milliseconds.
	[Time millisecondClockValue < end] whileTrue.
	^nil
!
frame: aDisplayList rendered: before start: t0 draw: drawUs layers: layerUs show: showUs record: aFrameRecord
! !
