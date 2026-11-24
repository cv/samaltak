!FFIPrimitives methodsFor: '*VM-Jit'!
nativeTestWritablePair: first length: firstLength marker: marker status: status second: second length: secondLength
	<function>
	<approvedFFI: 4095 symbol: 'ffi_test_writable_pair' arguments: #(9 6 1 9) result: 3>
	<approvedFFITest>
	<var: #first type: 'uint8_t *'>
	<var: #firstLength type: 'uint64_t'>
	<var: #marker type: 'double'>
	<var: #status type: 'int32_t'>
	<var: #second type: 'uint8_t *'>
	<var: #secondLength type: 'uint64_t'>
	<returns: 'int64_t'>
	"Every entered call increments the bytes, including one returning an error.
	The offset/length and lane checks are deliberately independent."
	0 to: firstLength asInt64 - 1 do: [:i | first at: i put: ((first at: i) + 1) asUInt8].
	0 to: secondLength asInt64 - 1 do: [:i | second at: i put: ((second at: i) + 2) asUInt8].
	marker = 1.25 ifFalse: [^-72].
	status = -71 ifTrue: [^status asInt64].
	^ -16r7000000000000000 + (firstLength asInt64 * 16) + secondLength asInt64 + status asInt64
! !
