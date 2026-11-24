!FFIPrimitives methodsFor: 'nvrtc exports'!
nativeNvrtcVersion
	<function>
	<approvedFFI: 740 symbol: 'core_nvrtc_version' arguments: #() result: 3>
	<returns: 'int64_t'>
	^nvrtcBackend version
!
nativeNvrtcStart: src length: srcLen options: opts length: optsLen
	<function>
	<approvedFFI: 741 symbol: 'core_nvrtc_start' arguments: #(8 8) result: 3>
	<var: #src type: 'const uint8_t *'>
	<var: #srcLen type: 'uint64_t'>
	<var: #opts type: 'const uint8_t *'>
	<var: #optsLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nvrtcBackend start: src length: srcLen options: opts length: optsLen
!
nativeNvrtcPoll: job
	<function>
	<approvedFFI: 742 symbol: 'core_nvrtc_poll' arguments: #(3) result: 3>
	<var: #job type: 'int64_t'>
	<returns: 'int64_t'>
	^nvrtcBackend poll: job
!
nativeNvrtcOutput: job kind: kind into: out length: outLen
	<function>
	<approvedFFI: 743 symbol: 'core_nvrtc_output' arguments: #(3 3 9) result: 3>
	<var: #job type: 'int64_t'>
	<var: #kind type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #outLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nvrtcBackend output: job kind: kind into: out length: outLen
!
nativeNvrtcFree: job
	<function>
	<approvedFFI: 744 symbol: 'core_nvrtc_free' arguments: #(3) result: 3>
	<var: #job type: 'int64_t'>
	<returns: 'int64_t'>
	^nvrtcBackend free: job
! !
