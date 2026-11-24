!FFIWrapperHelpers methodsFor: 'owned integer results'!
ffiBoxOwnedInteger: out
	"Input borrows ended at native return. No result uses GC-managed backing storage."
	<function>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'oop'>
	<var: #m type: 'uint64_t'>
	<var: #top type: 'uint64_t'>
	| answer n neg data m top used |
	answer := memory nilOop.
	out status = 2 ifTrue: [answer := memory trueOop].
	out status = 0 ifTrue: [
		neg := out count < 0.
		n := neg ifTrue: [0 - out count] ifFalse: [out count].
		data := out data.
		m := n = 1 ifTrue: [data at: 0] ifFalse: [0 asUInt64].
		(n <= 1 and: [m <= (neg ifTrue: [VM_INT_MAX asUInt64 + 1] ifFalse: [VM_INT_MAX asUInt64])])
			ifTrue: [answer := self intOop: (neg ifTrue: [(0 - m) asInt64] ifFalse: [m asInt64])]
			ifFalse: [
				(n <= 16rFFFFFFFF and: [(16 + (8 * n)) asUInt64 <= gc maxHeapBytes]) ifTrue: [
					top := data at: n - 1.
					used := 1.
					[used < 8 and: [(top >> (8 * used)) ~= 0]] whileTrue: [used := used + 1].
					jit syncPendingBoundFrame.
					answer := memory
						allocUnfilledTry: (memory special: (neg ifTrue: [SO_LARGENEG] ifFalse: [SO_LARGEPOS]))
						format: F_BYTES + (8 - used) asInt32
						slots: n asUInt64.
					answer = 0
						ifTrue: [answer := memory nilOop]
						ifFalse: [libc memcpy: (self bytesOf: answer) from: data size: (n * 8) asUInt64]]]].
	out allocation notNull ifTrue: [libc free: out allocation].
	^answer
!
ffiBoxOwnedIntegerWithGC: out
	<function>
	<var: #out type: 'BigIntegerNativeResult *'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	gc fullGC.
	^self ffiBoxOwnedInteger: out
! !
