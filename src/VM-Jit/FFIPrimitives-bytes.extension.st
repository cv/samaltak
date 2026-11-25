!FFIPrimitives methodsFor: 'bytes exports'!
nativeBytesMismatch: a size: aSize at: start with: b size: bSize at: otherStart count: n
	"ByteArray>>indexOfMismatchAt:with:at:size: (once primitive 119): the first i in 1 .. n where byte start + i - 1 of a and byte otherStart + i - 1 of b differ (ByteSearch, a block at a time), 0 if none does; -1 if a range is outside."
	<function>
	<approvedFFI: 119 symbol: 'core_bytes_mismatch' arguments: #(17 3 17 3 3) result: 3>
	<var: #a type: 'const uint8_t *'>
	<var: #aSize type: 'uint64_t'>
	<var: #start type: 'int64_t'>
	<var: #b type: 'const uint8_t *'>
	<var: #bSize type: 'uint64_t'>
	<var: #otherStart type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| k |
	((self range: start count: n within: aSize) and: [self range: otherStart count: n within: bSize]) ifFalse: [^-1].
	k := search
		mismatchOf: (self cCoerce: a to: 'uint8_t *') + (start - 1)
		with: (self cCoerce: b to: 'uint8_t *') + (otherStart - 1)
		from: 0
		size: n.
	^k = n ifTrue: [0] ifFalse: [k + 1]
!
nativeBytesLastMismatch: a size: aSize at: start with: b size: bSize at: otherStart count: n
	"ByteArray>>lastIndexOfMismatchAt:with:at:size: (once primitive 122): as nativeBytesMismatch:..., the last such i."
	<function>
	<approvedFFI: 122 symbol: 'core_bytes_last_mismatch' arguments: #(17 3 17 3 3) result: 3>
	<var: #a type: 'const uint8_t *'>
	<var: #aSize type: 'uint64_t'>
	<var: #start type: 'int64_t'>
	<var: #b type: 'const uint8_t *'>
	<var: #bSize type: 'uint64_t'>
	<var: #otherStart type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	((self range: start count: n within: aSize) and: [self range: otherStart count: n within: bSize]) ifFalse: [^-1].
	^(search
		lastMismatchOf: (self cCoerce: a to: 'uint8_t *') + (start - 1)
		with: (self cCoerce: b to: 'uint8_t *') + (otherStart - 1)
		size: n) + 1
!
range: start count: n within: size
	"Whether the n bytes from the 1-based start are inside size bytes."
	<function>
	<var: #start type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #size type: 'uint64_t'>
	<returns: 'bool'>
	^start >= 1 and: [n >= 0 and: [(start - 1) asUInt64 <= size and: [n asUInt64 <= (size - (start - 1) asUInt64)]]]
! !
