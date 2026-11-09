VMPlatformModule subclass: #PlatformVsync
	instanceVariableNames: 'pending vsyncSem running'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformVsync comment: 'The display-refresh semaphore: the host''s refresh thread (PlatformHost: a CVDisplayLink on macOS, a timer at the display''s refresh rate on Linux) flags each refresh; the next platform_interface_poll signals the semaphore (the compositor''s frame clock). Signaled at most once per poll, so a late compositor skips refreshes.'!

!PlatformVsync class methodsFor: 'declaring'!
declarations
	^#((pending atomic_int) (vsyncSem int32_t) (running bool))
! !

!PlatformVsync methodsFor: 'vsync'!
refreshed
	"The refresh thread: flag the refresh, wake the VM once."
	<export>
	(self atomicExchange: #pending value: 1) = 0 ifTrue: [
		scheduler requestInterruptCheck.
		sdlPlatform wake]
!
semaphore: index
	"Signal external semaphore index once per display refresh; 0 = stop."
	<export>
	platform init.
	vsyncSem := index.
	(index ~= 0 and: [running not]) ifTrue: [
		host vsyncStart ifFalse: [^false].
		running := true.
		^true].
	(index = 0 and: [running]) ifTrue: [
		host vsyncStop.
		running := false].
	^true
!
poll
	<function>
	(vsyncSem ~= 0 and: [(self atomicExchange: #pending value: 0) ~= 0]) ifTrue: [
		scheduler signalExternalSemaphore: vsyncSem]
!
pending
	<function>
	^vsyncSem ~= 0 and: [(self atomicLoad: #pending) ~= 0]
! !
