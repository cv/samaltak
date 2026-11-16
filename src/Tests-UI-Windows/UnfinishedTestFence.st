Object subclass: #UnfinishedTestFence
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

UnfinishedTestFence comment: 'I stand in for the fence of a frame the GPU never finishes (GPUTimer>>fence:submittedAt:record:), for tests of the Compositor''s backpressure.'!

!UnfinishedTestFence methodsFor: 'waiting'!
elapsedMicroseconds
	^nil
!
release
! !
