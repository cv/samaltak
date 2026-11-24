FFIStubMemory subclass: #SimulatedFFIStubMemory
	instanceVariableNames: 'core helpers heap'
	classVariableNames: ''
	package: 'VM-Jit'!

SimulatedFFIStubMemory comment: 'The simulator reauthorizes a closed set of vm:core signatures via the static prepared-call path. Its entries are Smalltalk FunctionPointers, never executable memory.'!

!DarwinFFIStubMemory class methodsFor: 'simulation'!
simulationClass
	^SimulatedFFIStubMemory
! !

!SimulatedFFIStubMemory class methodsFor: 'declaring'!
isAbstractModule
	"Exclude me from VM translation. VMSimulation instantiates me directly."
	^true
!
declarations
	^#((core FFIPrimitives) (helpers FFIWrapperHelpers) (heap ObjectMemory))
! !

!SimulatedFFIStubMemory methodsFor: 'publication'!
canMapFFIStubs
	^false
!
publishFFIStub: bytes size: size
	^0
!
staticCoreEntry: name signature: signature
	| symbol row |
	symbol := sim memory stringAt: name.
	row := #(
		('core_float_fraction_part' 16r66 fractionPart:)
		('core_float_print_string' 16r691 printFloat:)
		('core_utc_microseconds' 16r3 utcMicroseconds:)
		('core_thread_cpu_microseconds' 16r3 threadCpuMicroseconds:)
		('core_stdout_text' 16rD7 stdout:)
		('core_stderr_text' 16rD7 stderr:)
		('core_getenv_text' 16rEF getenv:)
	) detect: [:r | (r at: 1) = symbol and: [(r at: 2) = signature]] ifNone: [^0].
	^self cCoerce: (self functionPointer: (row at: 3)) to: 'uint64_t'
! !

!SimulatedFFIStubMemory methodsFor: 'static wrappers'!
fractionPart: args
	| value x fraction |
	value := self local: 'double'.
	(helpers ffiUnboxF64: args value into: value) ifFalse: [^0].
	x := value value.
	x isNaN ifTrue: [^helpers ffiBoxF64: x].
	fraction := x abs >= 4503599627370496.0
		ifTrue: [0.0]
		ifFalse: [x - x truncated asFloat].
	fraction = 0.0 ifTrue: [
		"Preserve the input sign for integral values, including infinities and signed zero."
		fraction := self doubleFromBits: ((self bitsOfDouble: x) bitAnd: 16r8000000000000000)].
	^helpers ffiBoxF64: fraction
!
printFloat: args
	| value address length count |
	value := self local: 'double'.
	(helpers ffiUnboxF64: args value into: value) ifFalse: [^0].
	address := self local: 'uint64_t'.
	length := self local: 'uint64_t'.
	(helpers ffiBorrowWritableSlice: (args at: 1) into: address length: length) ifFalse: [^0].
	count := core nativeFloatPrintString: value value
		into: (self cCoerce: address value to: 'uint8_t *') capacity: length value.
	^heap int64Oop: count
!
utcMicroseconds: args
	^helpers ffiBoxI64: core nativeUtcMicroseconds
!
threadCpuMicroseconds: args
	^helpers ffiBoxI64: core nativeThreadCpuMicroseconds
!
stdout: args
	^self write: args value stderr: false
!
stderr: args
	^self write: args value stderr: true
!
write: text stderr: isError
	| buf |
	buf := self local: 'FFITextBuffer'.
	(helpers ffiPrepareCountedText: text into: buf) ifFalse: [^0].
	[isError
		ifTrue: [core nativeTextStderr: buf data size: buf count]
		ifFalse: [core nativeTextStdout: buf data size: buf count]]
		ensure: [helpers ffiReleaseCountedText: buf].
	^heap nilOop
!
getenv: args
	| input output |
	input := self local: 'FFITextBuffer'.
	(helpers ffiPrepareCText: args value into: input) ifFalse: [^0].
	output := self local: 'FFITextBuffer'.
	[core nativeTextGetenv: input data size: input count into: output]
		ensure: [helpers ffiReleaseCountedText: input].
	^helpers ffiBoxOwnedText: output
! !
