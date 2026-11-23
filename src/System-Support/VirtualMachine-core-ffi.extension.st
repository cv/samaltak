!VirtualMachine methodsFor: 'core FFI candidates'!
ffiCandidateThreadCpuMicroseconds
	<ffiSite>
	| answer |
	answer := (self ffiSite: #(call 'vm:core' 'core_thread_cpu_microseconds' () i64)) tryInvoke0.
	answer == false ifTrue: [^self threadCpuMicroseconds].
	answer = -4611686018427387904 ifTrue: [^self primitiveFailed].
	^answer
!
ffiCandidateStdoutWrite: text
	| binding bytes |
	binding := CoreFFI stdoutWrite.
	binding isNil ifTrue: [^self stdoutWrite: text].
	bytes := PlatformFFI textBytes: text.
	bytes isNil ifTrue: [^self stdoutWrite: text].
	(binding tryInvoke1: {bytes. 1. bytes size}) == false ifTrue: [^self stdoutWrite: text].
	^self
!
ffiCandidateStderrWrite: text
	| binding bytes |
	binding := CoreFFI stderrWrite.
	binding isNil ifTrue: [^self stderrWrite: text].
	bytes := PlatformFFI textBytes: text.
	bytes isNil ifTrue: [^self stderrWrite: text].
	(binding tryInvoke1: {bytes. 1. bytes size}) == false ifTrue: [^self stderrWrite: text].
	^self
!
ffiCandidateGetenv: name
	| binding bytes slice result |
	binding := CoreFFI getenv.
	(binding isNil or: [name isString not]) ifTrue: [^self getenv: name].
	bytes := PlatformFFI cTextBytes: name.
	bytes isNil ifTrue: [^self getenv: name].
	slice := {bytes. 1. bytes size}.
	result := FFIOwnedOutput captureUpTo: 67108864 do: [:ticket | binding tryInvoke2: slice with: ticket].
	result == false ifTrue: [^self getenv: name].
	(result isNil or: [result class == SmallInteger]) ifTrue: [^nil].
	^PlatformFFI textFromBytes: result
! !
