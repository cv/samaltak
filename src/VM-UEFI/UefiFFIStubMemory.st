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
packsStackArguments
	<export>
	^false
!
publishFFIStub: bytes size: size
	<export>
	^0
!
staticCoreEntry: name signature: signature
	<export>
	(signature = 16r0606 and: [(libc strcmp: name with: 'core_float_fraction_part') = 0]) ifTrue: [
		^self cCoerce: (self functionPointer: #staticFractionPart:) to: 'uint64_t'].
	(signature = 16r060901 and: [(libc strcmp: name with: 'core_float_print_string') = 0]) ifTrue: [
		^self cCoerce: (self functionPointer: #staticFloatPrintString:) to: 'uint64_t'].
	signature = 3 ifTrue: [
		(libc strcmp: name with: 'core_utc_microseconds') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticUtcMicroseconds:) to: 'uint64_t'].
		(libc strcmp: name with: 'core_thread_cpu_microseconds') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticThreadCpuMicroseconds:) to: 'uint64_t']].
	signature = 16r0D07 ifTrue: [
		(libc strcmp: name with: 'core_stdout_text') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticStdout:) to: 'uint64_t'].
		(libc strcmp: name with: 'core_stderr_text') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticStderr:) to: 'uint64_t']].
	signature = 16r110311030303 ifTrue: [
		(libc strcmp: name with: 'core_bytes_mismatch') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticBytesMismatch:) to: 'uint64_t'].
		(libc strcmp: name with: 'core_bytes_last_mismatch') = 0 ifTrue: [
			^self cCoerce: (self functionPointer: #staticBytesLastMismatch:) to: 'uint64_t']].
	(signature = 16r110303031203 and: [(libc strcmp: name with: 'core_png_filter') = 0]) ifTrue: [
		^self cCoerce: (self functionPointer: #staticPngFilter:) to: 'uint64_t'].
	(signature = 16r120303110303 and: [(libc strcmp: name with: 'core_raw_bytes_replace') = 0]) ifTrue: [
		^self cCoerce: (self functionPointer: #staticRawBytesReplace:) to: 'uint64_t'].
	^0
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
staticBytesMismatch: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^self staticMismatch: args last: false
!
staticBytesLastMismatch: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^self staticMismatch: args last: true
!
staticMismatch: args last: last
	"(rawBytesWithLength i64 rawBytesWithLength i64 i64) i64: core_bytes_mismatch or core_bytes_last_mismatch."
	<function>
	<var: #args type: 'const oop *'>
	<var: #last type: 'bool'>
	<returns: 'oop'>
	| a aSize b bSize s t n |
	a := self local: 'uint64_t'.
	aSize := self local: 'uint64_t'.
	b := self local: 'uint64_t'.
	bSize := self local: 'uint64_t'.
	s := self local: 'int64_t'.
	t := self local: 'int64_t'.
	n := self local: 'int64_t'.
	((wrappers ffiBorrowRawBytes: (args at: 0) into: a length: aSize)
		and: [(wrappers ffiUnboxI64: (args at: 1) into: s)
		and: [(wrappers ffiBorrowRawBytes: (args at: 2) into: b length: bSize)
		and: [(wrappers ffiUnboxI64: (args at: 3) into: t)
		and: [wrappers ffiUnboxI64: (args at: 4) into: n]]]]) ifFalse: [^0].
	last ifTrue: [
		^wrappers ffiBoxI64: (core
			nativeBytesLastMismatch: (self cCoerce: a value to: 'const uint8_t *') size: aSize value at: s value
			with: (self cCoerce: b value to: 'const uint8_t *') size: bSize value at: t value count: n value)].
	^wrappers ffiBoxI64: (core
		nativeBytesMismatch: (self cCoerce: a value to: 'const uint8_t *') size: aSize value at: s value
		with: (self cCoerce: b value to: 'const uint8_t *') size: bSize value at: t value count: n value)
!
staticPngFilter: args
	"(rawBytesWithLength i64 i64 i64 writableRawBytesWithLength) i64: core_png_filter."
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| rgba rgbaSize w h n raw rawSize |
	rgba := self local: 'uint64_t'.
	rgbaSize := self local: 'uint64_t'.
	w := self local: 'int64_t'.
	h := self local: 'int64_t'.
	n := self local: 'int64_t'.
	raw := self local: 'uint64_t'.
	rawSize := self local: 'uint64_t'.
	((wrappers ffiBorrowRawBytes: (args at: 0) into: rgba length: rgbaSize)
		and: [(wrappers ffiUnboxI64: (args at: 1) into: w)
		and: [(wrappers ffiUnboxI64: (args at: 2) into: h)
		and: [(wrappers ffiUnboxI64: (args at: 3) into: n)
		and: [wrappers ffiBorrowWritableRawBytes: (args at: 4) into: raw length: rawSize]]]]) ifFalse: [^0].
	^wrappers ffiBoxI64: (core
		nativePngFilter: (self cCoerce: rgba value to: 'const uint8_t *') size: rgbaSize value
		width: w value height: h value channels: n value
		into: (self cCoerce: raw value to: 'uint8_t *') size: rawSize value)
!
staticRawBytesReplace: args
	"(writableRawBytesWithLength i64 i64 rawBytesWithLength i64) i64: core_raw_bytes_replace."
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| dst dstSize start stop src srcSize s |
	dst := self local: 'uint64_t'.
	dstSize := self local: 'uint64_t'.
	start := self local: 'int64_t'.
	stop := self local: 'int64_t'.
	src := self local: 'uint64_t'.
	srcSize := self local: 'uint64_t'.
	s := self local: 'int64_t'.
	((wrappers ffiBorrowWritableRawBytes: (args at: 0) into: dst length: dstSize)
		and: [(wrappers ffiUnboxI64: (args at: 1) into: start)
		and: [(wrappers ffiUnboxI64: (args at: 2) into: stop)
		and: [(wrappers ffiBorrowRawBytes: (args at: 3) into: src length: srcSize)
		and: [wrappers ffiUnboxI64: (args at: 4) into: s]]]]) ifFalse: [^0].
	^wrappers ffiBoxI64: (core
		nativeRawBytesReplace: (self cCoerce: dst value to: 'uint8_t *') size: dstSize value from: start value to: stop value
		with: (self cCoerce: src value to: 'const uint8_t *') size: srcSize value at: s value)
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
