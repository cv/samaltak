!FFIPrimitives methodsFor: 'owned bigint arithmetic'!
ffiBigIntegerAdd: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 20 symbol: 'core_bigint_add' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 20 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerSub: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 21 symbol: 'core_bigint_sub' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 21 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerMul: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 22 symbol: 'core_bigint_mul' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 22 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerQuo: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 23 symbol: 'core_bigint_quo' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 23 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerRem: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 24 symbol: 'core_bigint_rem' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 24 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerFloorDiv: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 25 symbol: 'core_bigint_floordiv' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 25 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerMod: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 26 symbol: 'core_bigint_mod' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 26 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerBitAnd: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 28 symbol: 'core_bigint_bitand' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 28 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerBitOr: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 29 symbol: 'core_bigint_bitor' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 29 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerBitXor: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 30 symbol: 'core_bigint_bitxor' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 30 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
!
ffiBigIntegerBitShift: a signedCount: an with: b signedCount: bn out: out
	<function>
	<approvedFFI: 31 symbol: 'core_bigint_bitshift' arguments: #(10 10) result: 11>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'void'>
	bigint magnitudeOperation: 31 left: a signedCount: an right: b signedCount: bn maxHeap: gc maxHeapBytes into: out
! !
