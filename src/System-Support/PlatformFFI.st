Object subclass: #PlatformFFI
	instanceVariableNames: ''
	classVariableNames: 'Bindings'
	package: 'System-Support'!

PlatformFFI comment: 'Private downcalls for platform facades. Cache bindings by descriptor literal identity; the VM revalidates each binding. Use the primitive fallback only when FFI rejects the call before entering native code.'!

!PlatformFFI class methodsFor: 'calling'!
call: descriptor with: arguments ifUnavailable: fallback
	^[(self bindingFor: descriptor) invoke: arguments]
		on: FFIError do: [:error | fallback value]
! !

!PlatformFFI class methodsFor: 'private'!
bindingFor: descriptor
	| bindings binding updated |
	bindings := Bindings ifNil: [IdentityDictionary new].
	^bindings at: descriptor ifAbsent: [
		binding := FFI bind: descriptor.
		"Publish a complete copy: another Process may bind while we allocate."
		updated := bindings copy.
		updated at: descriptor put: binding.
		Bindings := updated.
		binding]
! !
