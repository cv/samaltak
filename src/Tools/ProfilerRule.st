Widget subclass: #ProfilerRule
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

ProfilerRule comment: 'I am a 1-point black rule between the Profiler window''s panes.'!

!ProfilerRule methodsFor: 'initialization'!
initialize
	super initialize.
	self fixed: 1
! !

!ProfilerRule methodsFor: 'drawing'!
drawSelfOn: aCanvas
	aCanvas fillRect: self localBounds color: self theme rule
! !

!ProfilerRule methodsFor: 'remote control'!
remoteIsTransparent
	^true
! !
