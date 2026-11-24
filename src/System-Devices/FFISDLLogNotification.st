Object subclass: #FFISDLLogNotification
	instanceVariableNames: 'session generation'
	classVariableNames: ''
	package: 'System-Devices'!

FFISDLLogNotification comment: 'Bind #(notification sdlLog queued dropNewestAndCount capacity (category priority messageBytes) byteLimit) with FFI bind:. The only admitted source is SDL3 log output; capacity is 1..64 and byteLimit is 1..240. On hosted SDL VMs there is one process-wide subscription. Poll answers nil when empty or an Array of category, priority and owned message bytes in FIFO order. The bytes are capped, excluding the NUL; a message may end mid UTF-8 character. A full queue drops new messages and increments droppedCount (saturating at 2147483647). Always close explicitly: it discards pending messages and leaves SDL output unchanged. A subscription cannot be used in another VM process.'!

!FFISDLLogNotification class methodsFor: 'binding'!
bind: descriptor
	| capacity byteLimit fields token |
	(descriptor class == Array and: [descriptor size = 7 and: [
		(descriptor at: 1) == #notification and: [(descriptor at: 2) == #sdlLog and: [
		(descriptor at: 3) == #queued and: [(descriptor at: 4) == #dropNewestAndCount]]]]])
			ifFalse: [^FFIError signal: 'Invalid SDL log notification descriptor'].
	capacity := descriptor at: 5.
	fields := descriptor at: 6.
	byteLimit := descriptor at: 7.
	(capacity class == SmallInteger and: [(capacity between: 1 and: 64) and: [
		byteLimit class == SmallInteger and: [(byteLimit between: 1 and: 240) and: [
		fields class == Array and: [fields size = 3 and: [
		fields first == #category and: [fields second == #priority and: [fields third == #messageBytes]]]]]]]])
			ifFalse: [^FFIError signal: 'SDL log needs capacity 1..64, (category priority messageBytes), and byte limit 1..240'].
	token := self primBindCapacity: capacity byteLimit: byteLimit.
	^self new initializeSession: token first generation: token second
!
primBindCapacity: capacity byteLimit: byteLimit
	<primitive: 'ffiSDLLogBind'>
	^FFIError signal: 'SDL log notification unavailable or already bound'
! !

!FFISDLLogNotification methodsFor: 'private'!
initializeSession: aSession generation: aGeneration
	session := aSession.
	generation := aGeneration
!
primPoll: aSession generation: aGeneration
	<primitive: 'ffiSDLLogPoll'>
	^FFIError signal: 'SDL log notification is closed or stale'
!
primDropped: aSession generation: aGeneration
	<primitive: 'ffiSDLLogDropped'>
	^FFIError signal: 'SDL log notification is closed or stale'
!
primClose: aSession generation: aGeneration
	<primitive: 'ffiSDLLogClose'>
	"Closing an already closed or stale subscription is harmless."
	^nil
! !

!FFISDLLogNotification methodsFor: 'notifying'!
poll
	^self primPoll: session generation: generation
!
droppedCount
	^self primDropped: session generation: generation
!
close
	"Idempotent, including after resuming in another VM."
	session ifNotNil: [
		self primClose: session generation: generation.
		session := nil]
! !
