MandelbrotView subclass: #GatedMandelbrotView
	instanceVariableNames: 'gate atGate mostQueued'
	classVariableNames: ''
	package: 'Tests-Tools'!

GatedMandelbrotView comment: 'A MandelbrotView for DesktopTest: its first rendering stops after the first row until the test opens the gate, so that clicks made meanwhile wait in the window''s queue however loaded the machine is, and it remembers the most clicks a publish counted as queued (the count drops again as the queued clicks are handled, one zoom each).'!

!GatedMandelbrotView methodsFor: 'initialization'!
initialize
	super initialize.
	gate := Semaphore new.
	atGate := false.
	mostQueued := 0
! !

!GatedMandelbrotView methodsFor: 'testing'!
isAtGate
	^atGate
!
mostQueued
	^mostQueued
!
openGate
	"Let the first rendering go on (any Process)."
	gate isNil ifFalse: [gate signal]
! !

!GatedMandelbrotView methodsFor: 'rendering'!
renderRow: y
	(y = 1 and: [gate notNil]) ifTrue: [
		atGate := true.
		gate wait.
		atGate := false.
		gate := nil].
	super renderRow: y
!
publish
	super publish.
	mostQueued := mostQueued max: self queuedClicks
! !
