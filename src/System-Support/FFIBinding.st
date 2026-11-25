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
!
tryInvoke7: a with: b with: c with: d with: e with: f with: g
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke7: a with: b with: c with: d with: e with: f with: g
!
tryInvoke8: a with: b with: c with: d with: e with: f with: g with: h
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke8: a with: b with: c with: d with: e with: f with: g with: h
!
tryInvoke9: a with: b with: c with: d with: e with: f with: g with: h with: i
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke9: a with: b with: c with: d with: e with: f with: g with: h with: i
!
tryInvoke10: a with: b with: c with: d with: e with: f with: g with: h with: i with: j
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke10: a with: b with: c with: d with: e with: f with: g with: h with: i with: j
!
tryInvoke11: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke11: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k
!
tryInvoke12: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke12: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l
!
tryInvoke13: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke13: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m
!
tryInvoke14: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke14: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n
!
tryInvoke15: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n with: o
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke15: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n with: o
!
tryInvoke16: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n with: o with: p
	<primitive: 'ffiBoundInvoke'>
	self prepare ifFalse: [^false].
	^self retryInvoke16: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n with: o with: p
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
!
retryInvoke7: a with: b with: c with: d with: e with: f with: g
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke8: a with: b with: c with: d with: e with: f with: g with: h
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke9: a with: b with: c with: d with: e with: f with: g with: h with: i
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke10: a with: b with: c with: d with: e with: f with: g with: h with: i with: j
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke11: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke12: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke13: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke14: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke15: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n with: o
	<primitive: 'ffiBoundInvoke'>
	^false
!
retryInvoke16: a with: b with: c with: d with: e with: f with: g with: h with: i with: j with: k with: l with: m with: n with: o with: p
	<primitive: 'ffiBoundInvoke'>
	^false
! !
