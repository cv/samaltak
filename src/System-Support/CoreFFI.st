Object subclass: #CoreFFI
	instanceVariableNames: ''
	classVariableNames: 'FloatPrintString StdoutWrite StderrWrite Getenv'
	package: 'System-Support'!

CoreFFI comment: 'Lazily prepared bindings for opt-in core facades. No binding is needed to build or start an image. Saved bindings reprepare by name in the new VM.'!

!CoreFFI class methodsFor: 'core bindings'!
floatPrintString
	^FloatPrintString ifNil: [FloatPrintString := PlatformFFI bind: #(call 'vm:core' 'core_float_print_string' (f64 writableBytesWithLength) i32)]
!
stdoutWrite
	^StdoutWrite ifNil: [StdoutWrite := PlatformFFI bind: #(call 'vm:core' 'core_stdout_write' (bytesWithLength) void)]
!
stderrWrite
	^StderrWrite ifNil: [StderrWrite := PlatformFFI bind: #(call 'vm:core' 'core_stderr_write' (bytesWithLength) void)]
!
getenv
	^Getenv ifNil: [Getenv := PlatformFFI bind: #(call 'vm:core' 'core_getenv' (bytesWithLength u64) i32)]
! !
