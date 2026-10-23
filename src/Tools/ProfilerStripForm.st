Form subclass: #ProfilerStripForm
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

ProfilerStripForm comment: 'I am the bitmap of a ProfilerStrip: one pixel per point, sampled without filtering, so it stays crisp when drawn at the display scale.'!

!ProfilerStripForm methodsFor: 'rendering'!
isLinearFiltered
	^false
! !
