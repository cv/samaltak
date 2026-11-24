Object subclass: #NvRtc
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-NV'!

NvRtc comment: 'I am NVIDIA''s runtime CUDA compiler, NVRTC (the CUDA toolkit''s libnvrtc), as the VM''s core_nvrtc_* exports give it (vm/native/nvrtc.h: dlopen on first use, a thread a compile): CUDA C++ to a cubin for the GB10 (-arch=sm_121), which NvCubin reads and NvCompute launches, with no CUDA driver library. isAvailable is false where the VM has no NVRTC (no toolkit; UEFI; a VM without the exports). compile:options: waits for the compile without blocking other Processes; NvShaderCompiler (Graphics-NV) uses me. docs/nv-shaders.md.

	NvRtc compile: cudaSource options: #(''-arch=sm_121'')     "an Array: the cubin (nil if it did not compile) and NVRTC''s log"'!

!NvRtc class methodsFor: 'testing'!
isAvailable
	^self version notNil
!
version
	"NVRTC's version as major * 100 + minor (1300 for CUDA 13.0), nil if there is none."
	| v |
	v := [self ffiVersion] on: Error do: [:e | false].
	(v == false or: [v isNil or: [v < 0]]) ifTrue: [^nil].
	^v
! !

!NvRtc class methodsFor: 'compiling'!
compile: aString options: anArray
	"Compile the CUDA C++ aString with NVRTC's options anArray (Strings): {cubin or nil. log}. Polls every few ms, so other Processes run meanwhile; an error where there is no NVRTC."
	| job r |
	job := self start: aString options: anArray.
	[[(r := self ffiPoll: job) = -2] whileTrue: [(Delay forMilliseconds: 4) wait].
	r < 0 ifTrue: [^self error: 'NVRTC lost the job'].
	^Array
		with: (r = 0 ifTrue: [self output: job kind: 1] ifFalse: [nil])
		with: (self output: job kind: 0) asString]
		ensure: [self ffiFree: job]
!
start: aString options: anArray
	"Start compiling aString: the job."
	| src opts job |
	src := aString asByteArray.
	opts := (String streamContents: [:s | anArray do: [:o | s nextPutAll: o; nextPut: (Character value: 0)]]) asByteArray.
	job := self ffiStart: (Array with: src with: 1 with: src size) options: (Array with: opts with: 1 with: opts size).
	job == false ifTrue: [^self error: 'this VM has no NVRTC exports'].
	job = -1 ifTrue: [^self error: 'no NVRTC here (the CUDA toolkit''s libnvrtc; SAMALTAK_NVRTC names it)'].
	job < 0 ifTrue: [^self error: 'NVRTC refused the compile (too many at once?)'].
	^job
!
output: job kind: kind
	"A done job's log (kind 0) or cubin (kind 1) as a ByteArray."
	| n bytes |
	n := self ffiOutput: job kind: kind into: (Array with: (ByteArray new: 0) with: 1 with: 0).
	(n == false or: [n < 0]) ifTrue: [^ByteArray new].
	bytes := ByteArray new: n.
	n > 0 ifTrue: [self ffiOutput: job kind: kind into: (Array with: bytes with: 1 with: n)].
	(kind = 0 and: [n > 0 and: [bytes last = 0]]) ifTrue: [^bytes copyFrom: 1 to: n - 1].
	^bytes
! !

!NvRtc class methodsFor: 'ffi'!
ffiVersion
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_nvrtc_version' () i64)) tryInvoke0
!
ffiStart: srcSlice options: optsSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_nvrtc_start' (bytesWithLength bytesWithLength) i64)) tryInvoke2: srcSlice with: optsSlice
!
ffiPoll: job
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_nvrtc_poll' (i64) i64)) tryInvoke1: job
!
ffiOutput: job kind: kind into: outSlice
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_nvrtc_output' (i64 i64 writableBytesWithLength) i64)) tryInvoke3: job with: kind with: outSlice
!
ffiFree: job
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_nvrtc_free' (i64) i64)) tryInvoke1: job
! !
