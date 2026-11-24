Object subclass: #FFIBinding
	instanceVariableNames: 'descriptor bindingToken'
	classVariableNames: ''
	package: 'System-Support'!

FFIBinding comment: 'I am a bound downcall from FFI bind:. Send me invoke: with an Array of arguments. My immutable descriptor keeps the names and signature. My token selects a prepared call only in the current VM; after restoring, I prepare against the new host registry.'!

!FFIBinding methodsFor: 'invoking'!
invoke: arguments
	"Invoke the bound export with the given Array, or signal FFIError."
	| result |
	result := self tryInvoke: arguments.
	result == false ifFalse: [^result].
	descriptor isNil ifTrue: [^FFIError signal: 'Uninitialized FFI binding'].
	^FFIError signal: 'FFI invocation rejected: ', descriptor first, ' / ', descriptor second
! !

!FFIBinding methodsFor: 'platform invoking'!
tryInvoke: arguments
	"Only pre-entry rejection answers false. A completed call may answer zero or nil."
	<primitive: 'ffiBoundInvokeArray'>
	self prepare ifFalse: [^false].
	^self retryInvoke: arguments
!
tryInvoke0
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke0
!
tryInvoke1: a
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke1: a
!
tryInvoke2: a with: b
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke2: a with: b
!
tryInvoke3: a with: b with: c
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke3: a with: b with: c
!
tryInvoke4: a with: b with: c with: d
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke4: a with: b with: c with: d
!
tryInvoke5: a with: b with: c with: d with: e
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke5: a with: b with: c with: d with: e
!
tryInvoke6: a with: b with: c with: d with: e with: f
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke6: a with: b with: c with: d with: e with: f
! !

!FFIBinding methodsFor: 'private'!
descriptor
	^descriptor
!
initializeDescriptor: aDescriptor
	descriptor := aDescriptor.
	self beReadOnlyObject
!
prepare
	"Resolve and prepare in the current process. Only a stale or missing token
	falls through from the invoke primitives to this cold path."
	<primitive: 'ffiPrepare'>
	^false
!
retryInvoke: arguments
	<primitive: 'ffiBoundInvokeArray'>
	^false
!
retryInvoke0
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke1: a
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke2: a with: b
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke3: a with: b with: c
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke4: a with: b with: c with: d
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke5: a with: b with: c with: d with: e
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke6: a with: b with: c with: d with: e with: f
	<primitive: 'ffiBoundInvoke'>
	^false
! !
