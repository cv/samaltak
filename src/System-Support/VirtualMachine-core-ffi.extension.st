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
	<ffiSite>
	((self ffiSite: #(call 'vm:core' 'core_stdout_text' (countedText) void)) tryInvoke1: text) == false
		ifTrue: [^self stdoutWrite: text].
	^self
!
ffiCandidateStderrWrite: text
	<ffiSite>
	((self ffiSite: #(call 'vm:core' 'core_stderr_text' (countedText) void)) tryInvoke1: text) == false
		ifTrue: [^self stderrWrite: text].
	^self
!
ffiCandidateGetenv: name
	<ffiSite>
	| answer |
	answer := (self ffiSite: #(call 'vm:core' 'core_getenv_text' (cText) ownedText)) tryInvoke1: name.
	answer == false ifTrue: [^self getenv: name].
	^answer
! !
