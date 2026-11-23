!SDLPlatform methodsFor: 'GPU FFI owned-output fixture'!
ffiGpuShaderOversizedFixture: receipt capacity: cap
	"Exercise actual adoption and copy of a payload beyond the original 64 MiB cap without video."
	<function>
	<approvedFFI: 1463 symbol: 'platform_gpu_test_shader_pages' arguments: #(9) result: 1>
	<approvedFFITest>
	<var: #receipt type: 'uint8_t *'>
	<var: #cap type: 'uint64_t'>
	<returns: 'int32_t'>
	| row payload size |
	self ffiGpuOnMainThread ifFalse: [^-1].
	row := gpu shaderOutputRoom: receipt capacity: cap.
	row isNull ifTrue: [^-1].
	size := 67108868 asUInt64.
	payload := self cCoerce: (libc calloc: size size: 1) to: 'uint8_t *'.
	payload isNull ifTrue: [^-1].
	payload at: 0 put: 17.
	payload at: size - 1 put: 93.
	(gpu adoptShaderOutput: row bytes: payload count: size receipt: receipt) ifTrue: [^1].
	libc free: payload.
	^-1
! !
