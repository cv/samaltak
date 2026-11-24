Object subclass: #FFIExternalNotification
	instanceVariableNames: 'session generation'
	classVariableNames: ''
	package: 'System-Devices'!

FFIExternalNotification comment: 'A single polling subscription to a trusted native library configured at launch. Example: #(notification external ''fixture'' ''subscribe'' (u32 context u64) i32). The callback sets one sticky bit and returns zero for i32 (or no result for void). Only integer argument types and exactly one native context slot are allowed. The image never sees the context. Use ensure: to close; close waits for native callbacks to finish. A saved subscription is invalid in a new VM process.'!

!FFIExternalNotification class methodsFor: 'binding'!
bind: descriptor
	| library symbol types tags result count instance |
	(descriptor class == Array and: [descriptor size = 6 and: [
		descriptor first == #notification and: [(descriptor at: 2) == #external]]])
		ifFalse: [^FFIError signal: 'Expected #(notification external library symbol argumentTypes resultType)'].
	library := FFI copyName: (descriptor at: 3).
	symbol := FFI copyName: (descriptor at: 4).
	types := descriptor at: 5.
	(types class == Array and: [types size between: 1 and: 6])
		ifFalse: [^FFIError signal: 'Expected one to six external notification argument types'].
	tags := ByteArray new: types size.
	count := 0.
	1 to: types size do: [:i |
		| tag |
		tag := #(i32 u32 i64 u64 context) identityIndexOf: (types at: i).
		tag = 0 ifTrue: [^FFIError signal: 'Expected integer scalars and one native context'].
		tag = 5 ifTrue: [count := count + 1. tag := 250].
		tags at: i put: tag].
	count = 1 ifFalse: [^FFIError signal: 'Expected exactly one native context'].
	result := descriptor at: 6.
	(result == #i32 or: [result == #void]) ifFalse: [^FFIError signal: 'Expected an i32 or void result'].
	instance := self new.
	^instance initializeToken: (self primBind: library symbol: symbol tags: tags result: (FFI typeTag: result))
!
primBind: library symbol: symbol tags: tags result: result
	<primitive: 260>
	^FFIError signal: 'External notification ungranted, busy or unavailable'
! !

!FFIExternalNotification methodsFor: 'initializing'!
initializeToken: token
	session := token first.
	generation := token second.
	^self
! !

!FFIExternalNotification methodsFor: 'notification'!
poll
	"Answer whether a callback set the latch since bind or the last poll. Clear atomically."
	^self pollSession: session generation: generation
!
pollSession: aSession generation: aGeneration
	<primitive: 261>
	^FFIError signal: 'External notification is closed or stale'
!
close
	"Idempotent, including for a stale handle."
	generation ifNotNil: [
		self closeSession: session generation: generation.
		generation := nil]
!
closeSession: aSession generation: aGeneration
	<primitive: 262>
	^false
! !
