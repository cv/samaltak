!FFIPrimitives methodsFor: 'native core exports'!
nativeFloatFractionPart: x
	<function>
	<approvedFFI: 52 symbol: 'core_float_fraction_part' arguments: #(6) result: 6>
	<var: #x type: 'double'>
	<returns: 'double'>
	| integral |
	integral := self local: 'double'.
	^libm modf: x integralPart: integral
!
nativeUtcMicroseconds
	<function>
	<approvedFFI: 152 symbol: 'core_utc_microseconds' arguments: #() result: 3>
	<returns: 'int64_t'>
	| tv |
	tv := self local: 'Timeval'.
	(posix gettimeofday: tv zone: self null) ~= 0 ifTrue: [^VM_INT_MIN].
	^self checkedMicroseconds: tv tv_sec plus: tv tv_usec
!
nativeThreadCpuMicroseconds
	"Read real host CPU time, not the work clock's virtual charge."
	<function>
	<approvedFFI: 153 symbol: 'core_thread_cpu_microseconds' arguments: #() result: 3>
	<returns: 'int64_t'>
	| ts |
	ts := self local: 'Timespec'.
	(posix clockGettime: posix CLOCK_THREAD_CPUTIME_ID into: ts) ~= 0 ifTrue: [^VM_INT_MIN].
	^self checkedMicroseconds: ts tv_sec plus: (ts tv_nsec quo: 1000)
!
checkedMicroseconds: seconds plus: fraction
	"Reserve VM_INT_MIN for completed clock failures, outside practical clock dates."
	| us |
	(seconds < -4611686018428 or: [seconds > 4611686018427]) ifTrue: [^VM_INT_MIN].
	us := (seconds * 1000000) + fraction.
	^(self intFits: us) ifTrue: [us] ifFalse: [VM_INT_MIN]
!
nativeWriteStdout: bytes size: n
	<function>
	<approvedFFI: 169 symbol: 'core_stdout_write' arguments: #(8) result: 7>
	<var: #bytes type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'void'>
	n ~= 0 ifTrue: [libc fwrite: bytes size: 1 count: n file: libc stdout].
	libc fflush: libc stdout
!
nativeWriteStderr: bytes size: n
	<function>
	<approvedFFI: 170 symbol: 'core_stderr_write' arguments: #(8) result: 7>
	<var: #bytes type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<returns: 'void'>
	n ~= 0 ifTrue: [libc fwrite: bytes size: 1 count: n file: libc stderr].
	libc fflush: libc stderr
!
nativeFloatPrintString: x into: bytes capacity: capacity
	"Return the written ASCII byte count (no terminator in the caller's slice)."
	<function>
	<approvedFFI: 61 symbol: 'core_float_print_string' arguments: #(6 9) result: 1>
	<var: #x type: 'double'>
	<var: #bytes type: 'uint8_t *'>
	<var: #capacity type: 'uint64_t'>
	<returns: 'int32_t'>
	| buf negative |
	x ~= x ifTrue: [^self copyFloatDecimal: 'nan' size: 3 into: bytes capacity: capacity].
	(x - x = 0.0) ifFalse: [
		^x < 0.0
			ifTrue: [self copyFloatDecimal: '-inf' size: 4 into: bytes capacity: capacity]
			ifFalse: [self copyFloatDecimal: 'inf' size: 3 into: bytes capacity: capacity]].
	x = 0.0 ifTrue: [
		negative := ((self bitsOfDouble: x) >> 63) ~= 0.
		^negative
			ifTrue: [self copyFloatDecimal: '-0.0' size: 4 into: bytes capacity: capacity]
			ifFalse: [self copyFloatDecimal: '0.0' size: 3 into: bytes capacity: capacity]].
	buf := self local: 'char[64]'.
	self finiteFloatDecimal: x in: buf.
	^self copyFloatDecimal: buf size: (libc strlen: buf) into: bytes capacity: capacity
!
copyFloatDecimal: source size: n into: bytes capacity: capacity
	n > capacity ifTrue: [^-1].
	libc memcpy: bytes from: source size: n.
	^n asInt32
!
nativeGetenv: bytes size: n ticket: ticket
	"A successful getenv publishes one copy before returning; nil and empty are distinct."
	<function>
	<approvedFFI: 172 symbol: 'core_getenv' arguments: #(8 4) result: 1>
	<var: #bytes type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<var: #ticket type: 'uint64_t'>
	<returns: 'int32_t'>
	| key val |
	(self ownedCanProduce: ticket) ifFalse: [^-1].
	key := nativeCountedText copyTerminated: bytes size: n.
	key isNull ifTrue: [^-1].
	val := libc getenv: key.
	libc free: key.
	val isNull ifTrue: [^0].
	(self ownedPublish: ticket from: (self cCoerce: val to: 'const uint8_t *') size: (libc strlen: val)) ifFalse: [^-1].
	^1
! !
