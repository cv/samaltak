Object subclass: #FFINotification
	instanceVariableNames: 'session generation signalSemaphore signalIndex closeLock'
	classVariableNames: ''
	package: 'System-Devices'!

FFINotification comment: 'Bind #(notification vsync coalesce 2 step) to observe the native display-refresh source (on Linux, a timer at the display rate). The fixed ABI takes its native context in argument 2. Step is a power of two from 1 to 128, sampling every step refreshes. Poll reads and clears one pending bit. Use FFINotification bind: descriptor whenPendingSignal: aSemaphore to wake and signal once per pending edge (poll re-arms); plain bind: has no wake. Close explicitly (use ensure:); a saved registration is not valid in a new VM session. SDL log descriptors bind a separate queued notification.'!

!FFINotification class methodsFor: 'binding'!
bind: aDescriptor
	(aDescriptor class == Array and: [aDescriptor size >= 2 and: [aDescriptor first == #notification]])
		ifFalse: [^FFIError signal: 'Expected a notification descriptor'].
	(aDescriptor at: 2) == #sdlLog ifTrue: [
		^(Smalltalk at: #FFISDLLogNotification ifAbsent: [^FFIError signal: 'SDL log notifications are unavailable'])
			bind: aDescriptor].
	(aDescriptor at: 2) == #external ifTrue: [
		^(Smalltalk at: #FFIExternalNotification ifAbsent: [^FFIError signal: 'External notifications are unavailable'])
			bind: aDescriptor].
	^self bind: aDescriptor whenPendingSignal: nil
!
bind: aDescriptor whenPendingSignal: aSemaphore
	"With a Semaphore, each empty-to-pending transition wakes the VM, which signals on its own thread. Wait, then poll to re-arm."
	| index subscription ready |
	(aDescriptor class == Array and: [aDescriptor size = 5 and: [
		aDescriptor first == #notification and: [(aDescriptor at: 2) == #vsync and: [
		(aDescriptor at: 3) == #coalesce and: [(aDescriptor at: 4) == 2 and: [
			#(1 2 4 8 16 32 64 128) identityIncludes: (aDescriptor at: 5)]]]]]])
		ifFalse: [^FFIError signal: 'Expected #(notification vsync coalesce 2 step), with power-of-two step from 1 to 128'].
	(aSemaphore isNil or: [aSemaphore class == Semaphore])
		ifFalse: [^FFIError signal: 'A Semaphore is required for notification delivery'].
	subscription := self new.
	ready := false.
	^[
		index := aSemaphore isNil ifTrue: [0] ifFalse: [Smalltalk vm registerExternalSemaphore: aSemaphore].
		subscription
			signalSemaphore: aSemaphore index: index;
			initializeToken: (self primBindContext: (aDescriptor at: 4) step: (aDescriptor at: 5) semaphoreIndex: index).
		ready := true.
		subscription
	] ensure: [
		ready ifFalse: [subscription close]]
! !

!FFINotification class methodsFor: 'private'!
primBindContext: argumentPosition step: step semaphoreIndex: index
	<primitive: 'ffiVsyncBind'>
	^FFIError signal: 'Vsync notification unavailable or registration limit reached'
! !

!FFINotification methodsFor: 'initialization'!
initializeToken: token
	session := token first.
	generation := token second.
	^self
!
signalSemaphore: aSemaphore index: index
	aSemaphore notNil ifTrue: [
		closeLock := Semaphore forMutualExclusion.
		signalSemaphore := aSemaphore.
		signalIndex := index]
! !

!FFINotification methodsFor: 'notification'!
poll
	"A matching refresh since the last poll? Answer and clear the latch."
	^self primPollSession: session generation: generation
!
close
	"Revoke. Also safe for a previously closed or stale registration."
	closeLock
		ifNil: [self revoke]
		ifNotNil: [closeLock critical: [self revoke.
			signalIndex notNil ifTrue: [
				((Smalltalk vm externalObjects at: signalIndex ifAbsent: [nil]) == signalSemaphore) ifTrue: [
					Smalltalk vm unregisterExternalSemaphore: signalIndex].
				signalIndex := nil.
				signalSemaphore := nil]]]
! !

!FFINotification methodsFor: 'private'!
revoke
	generation notNil ifTrue: [
		self primCloseSession: session generation: generation.
		generation := nil]
!
primPollSession: aSession generation: aGeneration
	<primitive: 'ffiVsyncPoll'>
	^FFIError signal: 'Vsync notification is closed or stale'
!
primCloseSession: aSession generation: aGeneration
	<primitive: 'ffiVsyncClose'>
	^false
! !
