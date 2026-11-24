VMPlatformModule subclass: #PlatformVsync
	instanceVariableNames: 'pending vsyncSem running semaphoreArmed notifying notification'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformVsync comment: 'The display-refresh semaphore: the host''s refresh thread (PlatformHost: a CVDisplayLink on macOS, a timer at the display''s refresh rate on Linux) flags each refresh; the next platform_interface_poll signals the semaphore (the compositor''s frame clock). Signaled at most once per poll, so a late compositor skips refreshes.'!

!PlatformVsync class methodsFor: 'declaring'!
declarations
	^#((pending atomic_int) (vsyncSem int32_t) (running bool) (semaphoreArmed atomic_bool)
		(notifying bool) (notification FFIVsyncNotification))
! !

!PlatformVsync methodsFor: 'vsync'!
refreshed
	"The refresh thread. The notification dispatcher writes only native state."
	<export>
	notification refreshed.
	((self atomicLoad: #semaphoreArmed) and: [(self atomicExchange: #pending value: 1) = 0]) ifTrue: [
		scheduler requestInterruptCheck.
		sdlPlatform wake]
!
semaphore: index
	"Signal external semaphore index once per display refresh; 0 = detach."
	<export>
	platform init.
	index ~= 0 ifTrue: [self ensureRunning ifFalse: [^false]].
	vsyncSem := index.
	self atomicStore: #semaphoreArmed value: index ~= 0.
	index = 0 ifTrue: [
		self atomicExchange: #pending value: 0.
		self stopIfUnused].
	^true
!
notifications: enabled
	"VM thread, called on first bind and last close. Shares the host source with the semaphore."
	<export>
	<var: #enabled type: 'bool'>
	platform init.
	enabled ifTrue: [self ensureRunning ifFalse: [^false]].
	notifying := enabled.
	self stopIfUnused.
	^true
!
ensureRunning
	running ifTrue: [^true].
	notification prepare ifFalse: [
		common setError: 'cannot initialize vsync notification lock'.
		^false].
	host vsyncStart ifFalse: [^false].
	running := true.
	^true
!
stopIfUnused
	(running and: [vsyncSem = 0 and: [notifying not]]) ifTrue: [
		host vsyncStop.
		running := false]
!
poll
	<function>
	(vsyncSem ~= 0 and: [(self atomicExchange: #pending value: 0) ~= 0]) ifTrue: [
		scheduler signalExternalSemaphore: vsyncSem]
!
signalNotifications
	"Scheduler poll only: signal before the next image activation."
	<function>
	notification signalReady
!
pending
	<function>
	^(vsyncSem ~= 0 and: [(self atomicLoad: #pending) ~= 0]) or: [notification pendingSignals]
! !
