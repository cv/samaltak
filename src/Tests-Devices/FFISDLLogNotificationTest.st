TestCase subclass: #FFISDLLogNotificationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Devices'!

!FFISDLLogNotificationTest methodsFor: 'test support'!
probe: n
	"SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, ...), without initializing video."
	<primitive: 'ffiSDLLogProbe'>
	self fail: 'SDL log probe unavailable'
! !

!FFISDLLogNotificationTest methodsFor: 'tests'!
testRegisteredSDLLogQueue
	| subscription first second old next |
	subscription := FFI bind: #(notification sdlLog queued dropNewestAndCount 2 (category priority messageBytes) 240).
	[
		self assert: subscription poll isNil.
		self should: [FFI bind: #(notification sdlLog queued dropNewestAndCount 1 (category priority messageBytes) 4)] raise: FFIError.
		self probe: 1; probe: 2; probe: 3.
		self assert: subscription droppedCount equals: 1.
		first := subscription poll.
		self probe: 4.
		second := subscription poll.
		self assert: first equals: {0. 5. 'samaltak FFI SDL log probe 1 (100% ready)' utf8Encoded}.
		self assert: second equals: {0. 5. 'samaltak FFI SDL log probe 2 (100% ready)' utf8Encoded}.
		self assert: subscription poll third equals: 'samaltak FFI SDL log probe 4 (100% ready)' utf8Encoded.
		self assert: subscription poll isNil.
		self assert: subscription droppedCount equals: 1.
		self probe: 5.
		old := subscription shallowCopy
	] ensure: [subscription close].
	subscription close.
	self probe: 6.
	next := FFI bind: #(notification sdlLog queued dropNewestAndCount 1 (category priority messageBytes) 7).
	[
		self should: [old poll] raise: FFIError.
		old close.
		self assert: next droppedCount equals: 0.
		self assert: next poll isNil.
		self probe: 7.
		self assert: next poll equals: {0. 5. 'samalta' utf8Encoded}.
		self assert: next poll isNil.
		self assert: first third equals: 'samaltak FFI SDL log probe 1 (100% ready)' utf8Encoded
	] ensure: [next close]
!
testRepeatedBindsReuseSpecializations
	"More binds than there are process-lifetime publisher slots."
	| subscription |
	1 to: 1050 do: [:i |
		subscription := FFI bind: {#notification. #sdlLog. #queued. #dropNewestAndCount.
			(i odd ifTrue: [1] ifFalse: [64]). #(category priority messageBytes).
			(i odd ifTrue: [1] ifFalse: [12])}.
		subscription close].
	subscription := FFI bind: #(notification sdlLog queued dropNewestAndCount 1 (category priority messageBytes) 1).
	[self probe: 8. self assert: subscription poll third equals: #[115]]
		ensure: [subscription close].
	subscription := FFI bind: #(notification sdlLog queued dropNewestAndCount 64 (category priority messageBytes) 12).
	[self probe: 9. self assert: subscription poll third equals: 'samaltak FFI' utf8Encoded]
		ensure: [subscription close]
!
testRejectsUnverifiedDescriptors
	#(
		(notification sdlLog queued dropOldest 2 (category priority messageBytes) 4)
		(notification sdlLog queued dropNewestAndCount 65 (category priority messageBytes) 4)
		(notification sdlLog queued dropNewestAndCount 2 (category priority pointer) 4)
		(notification sdlLog queued dropNewestAndCount 2 (category priority messageBytes) 0)
		(notification sdlLog queued dropNewestAndCount 2 (category priority messageBytes) 241)
	) do: [:descriptor | self should: [FFI bind: descriptor] raise: FFIError]
! !
