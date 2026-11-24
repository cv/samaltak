TestCase subclass: #FFIVsyncNotificationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Devices'!

!FFIVsyncNotificationTest methodsFor: 'tests'!
testInvalidDescriptors
	#((notification)
	  (notification vsync)
	  (notification vsync queue 2 1)
	  (notification vsync coalesce 1 1)
	  (notification vsync coalesce 2 3)
	  (notification vsync coalesce 2 0)
	  (notification vsync coalesce 2 256)
	  (notification unknown coalesce 2 1)) do: [:descriptor |
		self should: [FFI bind: descriptor] raise: FFIError]
!
testNativeRefreshCadence
	| fast slow fastCount slowCount deadline |
	fast := FFI bind: #(notification vsync coalesce 2 1).
	[
		slow := FFI bind: {#notification. #vsync. #coalesce. 2. 8}.
		[
			fastCount := slowCount := 0.
			deadline := Time millisecondClockValue + 3000.
			[slowCount < 3 and: [Time millisecondClockValue < deadline]] whileTrue: [
				fast poll ifTrue: [fastCount := fastCount + 1].
				slow poll ifTrue: [slowCount := slowCount + 1].
				(Delay forMilliseconds: 2) wait].
			self assert: slowCount equals: 3.
			self assert: fastCount > (slowCount * 2)
		] ensure: [slow close].
		"Closing a second subscriber must not stop the host source."
		self assertNextRefresh: fast
	] ensure: [fast close]
!
testStaleSessionAndRevokedGeneration
	| notification epoch generation old stale next |
	notification := FFI bind: #(notification vsync coalesce 2 1).
	[
		epoch := notification instVarNamed: 'session'.
		generation := notification instVarNamed: 'generation'.
		stale := FFINotification new initializeToken: {0. generation}.
		self should: [stale poll] raise: FFIError.
		stale close.
		self assertNextRefresh: notification
	] ensure: [notification close].
	notification close.
	self should: [notification poll] raise: FFIError.
	old := FFINotification new initializeToken: {epoch. generation}.
	next := FFI bind: #(notification vsync coalesce 2 1).
	[
		self should: [old poll] raise: FFIError.
		old close.
		self assertNextRefresh: next
	] ensure: [next close]
!
testWakeCoalescesUntilPoll
	| notification sem index |
	sem := Semaphore new.
	notification := FFINotification bind: #(notification vsync coalesce 2 1) whenPendingSignal: sem.
	[
		index := notification instVarNamed: 'signalIndex'.
		self deny: (sem waitTimeoutMSecs: 2000).
		(Delay forMilliseconds: 130) wait.
		self assert: sem excessSignals equals: 0.
		self assert: notification poll.
		self deny: (sem waitTimeoutMSecs: 2000).
		self assert: notification poll
	] ensure: [notification close].
	self assert: (Smalltalk vm externalObjects at: index) isNil
!
testRegistrationLimitAndReuse
	| subscriptions |
	subscriptions := OrderedCollection new.
	[
		16 timesRepeat: [subscriptions add: (FFI bind: #(notification vsync coalesce 2 2))].
		self should: [FFI bind: #(notification vsync coalesce 2 2)] raise: FFIError.
		subscriptions removeFirst close.
		subscriptions add: (FFI bind: #(notification vsync coalesce 2 2)).
		self assertNextRefresh: subscriptions last
	] ensure: [subscriptions do: [:n | n close]]
! !

!FFIVsyncNotificationTest methodsFor: 'private'!
assertNextRefresh: notification
	| deadline fired |
	deadline := Time millisecondClockValue + 2000.
	fired := false.
	[fired not and: [Time millisecondClockValue < deadline]] whileTrue: [
		fired := notification poll.
		fired ifFalse: [(Delay forMilliseconds: 2) wait]].
	self assert: fired
! !
