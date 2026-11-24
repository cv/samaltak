!FFIPrimitives methodsFor: 'approved integers'!
ffiBigIntegerCompare: a signedCount: an with: b signedCount: bn
	"Read-only sign/magnitude inputs, with NULL limbs denoting a SmallInteger
	decoded by the wrapper. The values (including those of heap operands) may
	span any representable size. No VM state or primitive dispatch here."
	<function>
	<approvedFFI: 27 symbol: 'core_bigint_compare' arguments: #(10 10) result: 1>
	<var: #a type: 'const uint64_t *'>
	<var: #an type: 'int64_t'>
	<var: #b type: 'const uint64_t *'>
	<var: #bn type: 'int64_t'>
	<returns: 'int32_t'>
	| aSmall bSmall aa bb na nb c |
	(an < 0) ~= (bn < 0) ifTrue: [^an < 0 ifTrue: [-1] ifFalse: [1]].
	(a isNull and: [b isNull]) ifTrue: [^an < bn ifTrue: [-1] ifFalse: [an = bn ifTrue: [0] ifFalse: [1]]].
	aa := a.
	bb := b.
	na := an < 0 ifTrue: [0 - an] ifFalse: [an].
	nb := bn < 0 ifTrue: [0 - bn] ifFalse: [bn].
	a isNull ifTrue: [
		aSmall := self local: 'uint64_t'.
		aSmall value: na asUInt64.
		aa := aSmall.
		na := na = 0 ifTrue: [0] ifFalse: [1]].
	b isNull ifTrue: [
		bSmall := self local: 'uint64_t'.
		bSmall value: nb asUInt64.
		bb := bSmall.
		nb := nb = 0 ifTrue: [0] ifFalse: [1]].
	c := self compare: aa count: na with: bb count: nb.
	^an < 0 ifTrue: [0 - c] ifFalse: [c]
! !
