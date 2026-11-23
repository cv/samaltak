"Evaluate on an SDL-hosted SAMALTAK_FFI_TEST_EXPORTS build with display denied."
[ | producer copy release receipt ticket length bytes result invocations |
	producer := PlatformFFI bind: #(call 'platform' 'platform_gpu_test_shader_pages' (writableBytesWithLength) i32).
	copy := PlatformFFI bind: #(call 'platform' 'platform_gpu_shader_copy' (u64 u64 writableBytesWithLength) i32).
	release := PlatformFFI bind: #(call 'platform' 'platform_gpu_shader_release' (u64) i32).
	(producer isNil or: [copy isNil or: [release isNil]]) ifTrue: [self error: 'Missing paged shader exports'].
	receipt := ByteArray new: 16.
	bytes := ByteArray new: 6.
	[
		(producer tryInvoke1: {receipt. 1. 16}) = 1 ifFalse: [self error: 'Cannot adopt oversized result'].
		ticket := FFIWire uint64At: 1 in: receipt.
		length := FFIWire uint64At: 9 in: receipt.
		length = 67108868 ifFalse: [self error: 'Wrong result length'].
		(copy tryInvoke3: ticket with: 0 with: {bytes. 2. 4}) = 1 ifFalse: [self error: 'Cannot read first page'].
		bytes = #[0 17 0 0 0 0] ifFalse: [self error: 'Wrong bytes at start'].
		(copy tryInvoke3: ticket with: length - 4 with: {bytes. 2. 4}) = 1 ifFalse: [self error: 'Cannot read beyond original cap'].
		bytes = #[0 0 0 0 93 0] ifFalse: [self error: 'Wrong oversized tail'].
		(copy tryInvoke3: ticket with: length - 3 with: {bytes. 2. 4}) = 0 ifFalse: [self error: 'Out-of-range page accepted'].
		bytes = #[0 0 0 0 93 0] ifFalse: [self error: 'Rejected page changed output']
	] ensure: [
		ticket := FFIWire uint64At: 1 in: receipt.
		ticket = 0 ifFalse: [
			(release tryInvoke1: ticket) = 1 ifFalse: [self error: 'Cannot release owned shader result']]].
	(release tryInvoke1: ticket) = 0 ifFalse: [self error: 'Double release accepted'].
	(copy tryInvoke3: ticket with: 0 with: {bytes. 1. 6}) = 0 ifFalse: [self error: 'Stale read accepted'].
	invocations := 0.
	result := GPUPlatformFFI shaderOutputFrom: [:out |
		invocations := invocations + 1.
		producer tryInvoke1: {out. 1. 16}].
	(invocations = 1 and: [result class == ByteArray and: [result size = length]])
		ifFalse: [self error: 'Facade did not adopt exact oversized output once'].
	(result first = 17 and: [(result at: 1048577) = 0 and: [result last = 93]])
		ifFalse: [self error: 'Facade paged copy truncated or damaged output'].
	true] value
