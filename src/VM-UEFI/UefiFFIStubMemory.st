FFIStubMemory subclass: #UefiFFIStubMemory
	instanceVariableNames: 'core wrappers'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiFFIStubMemory comment: 'UEFI does not publish FFI code. Trusted vm:core descriptors can select a small set of statically linked, typed wrappers. The wrappers consume VM values internally; native targets see only scalars and bounded buffers.'!

!UefiFFIStubMemory class methodsFor: 'declaring'!
declarations
	^#((core FFIPrimitives) (wrappers FFIWrapperHelpers))
!
targetOS
	^#uefi
!
isSimulated
	^false
! !

!UefiFFIStubMemory methodsFor: 'publication'!
canMapFFIStubs
	<export>
	^false
!
publishFFIStub: bytes size: size
	<export>
	^0
!
staticCoreEntry: name signature: signature
	<export>
	(signature = 16r66 and: [(libc strcmp: name with: 'core_float_fraction_part') = 0]) ifTrue: [
		^self cCoerce: (self functionPointer: #staticFractionPart:) to: 'uint64_t'].
	(signature = 16r691 and: [(libc strcmp: name with: 'core_float_print_string') = 0]) ifTrue: [
		^self cCoerce: (self functionPointer: #staticFloatPrintString:) to: 'uint64_t'].
	signature = 3 ifTrue: [
		(libc strcmp: name with: 'core_utc_microseconds') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticUtcMicroseconds:) to: 'uint64_t'].
		(libc strcmp: name with: 'core_thread_cpu_microseconds') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticThreadCpuMicroseconds:) to: 'uint64_t']].
	signature = 16rD7 ifTrue: [
		(libc strcmp: name with: 'core_stdout_text') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticStdout:) to: 'uint64_t'].
		(libc strcmp: name with: 'core_stderr_text') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticStderr:) to: 'uint64_t']].
	^self staticTlsEntry: name signature: signature
! !

!UefiFFIStubMemory methodsFor: 'static core wrappers'!
staticFractionPart: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| x |
	x := self local: 'double'.
	(wrappers ffiUnboxF64: (args at: 0) into: x) ifFalse: [^0].
	^wrappers ffiBoxF64: (core nativeFloatFractionPart: x value)
!
staticFloatPrintString: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| x bytes capacity n |
	x := self local: 'double'.
	bytes := self local: 'uint64_t'.
	capacity := self local: 'uint64_t'.
	(wrappers ffiUnboxF64: (args at: 0) into: x) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: bytes length: capacity) ifFalse: [^0].
	n := core nativeFloatPrintString: x value into: (self cCoerce: bytes value to: 'uint8_t *') capacity: capacity value.
	^wrappers ffiBoxI64: n asInt64
!
staticUtcMicroseconds: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^wrappers ffiBoxI64: core nativeUtcMicroseconds
!
staticThreadCpuMicroseconds: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^wrappers ffiBoxI64: core nativeThreadCpuMicroseconds
!
staticStdout: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^self staticWrite: (args at: 0) stderr: false
!
staticStderr: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^self staticWrite: (args at: 0) stderr: true
!
staticWrite: text stderr: useStderr
	<function>
	<var: #text type: 'oop'>
	<var: #useStderr type: 'bool'>
	<returns: 'oop'>
	| buf |
	buf := self local: 'FFITextBuffer'.
	(wrappers ffiPrepareCountedText: text into: buf) ifFalse: [^0].
	useStderr
		ifTrue: [core nativeTextStderr: buf data size: buf count]
		ifFalse: [core nativeTextStdout: buf data size: buf count].
	^wrappers ffiReleaseCountedText: buf
! !
