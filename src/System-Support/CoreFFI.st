Object subclass: #CoreFFI
	instanceVariableNames: ''
	classVariableNames: 'FloatPrintString'
	package: 'System-Support'!

CoreFFI comment: 'Lazily prepared bindings for opt-in core facades. No binding is needed to build or start an image. Saved bindings reprepare by name in the new VM.'!

!CoreFFI class methodsFor: 'core bindings'!
floatPrintString
	^FloatPrintString ifNil: [FloatPrintString := PlatformFFI bind: #(call 'vm:core' 'core_float_print_string' (f64 writableBytesWithLength) i32)]
! !
