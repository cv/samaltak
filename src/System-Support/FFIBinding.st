Object subclass: #FFIBinding
	instanceVariableNames: 'id library symbol tags resultTag'
	classVariableNames: ''
	package: 'System-Support'!

FFIBinding comment: 'I am a bound downcall from FFI bind:. Send me invoke: with an Array of arguments. I keep the names and signature, not an address; the VM checks them against the current registry on every invocation.'!

!FFIBinding methodsFor: 'invoking'!
invoke: arguments
	"Invoke the bound export with the given Array, or signal FFIError."
	id isNil ifTrue: [^FFIError signal: 'Uninitialized FFI binding'].
	(arguments class == Array and: [arguments size = tags size]) ifFalse: [
		^FFIError signal: 'Expected an FFI argument Array of size ', tags size printString].
	^self primInvoke: id library: library symbol: symbol types: tags result: resultTag arguments: arguments
! !

!FFIBinding methodsFor: 'private'!
tryInvoke: arguments
	"Private to PlatformFFI. The VM checks the binding and arguments. Only pre-call rejection answers false; a completed native call may answer 0 or nil, but never false."
	^self tryPrimInvoke: id library: library symbol: symbol types: tags result: resultTag arguments: arguments
!
tryPrimInvoke: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag arguments: arguments
	<primitive: 'ffiInvoke'>
	^false
!
initializeID: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag
	id := anID.
	library := aLibrary.
	symbol := aSymbol.
	tags := argumentTags.
	resultTag := aResultTag.
	self beReadOnlyObject
!
primInvoke: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag arguments: arguments
	<primitive: 'ffiInvoke'>
	^FFIError signal: 'FFI invocation rejected: ', aLibrary, ' / ', aSymbol
! !
