VMStruct subclass: #BigIntegerNativeResult
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

BigIntegerNativeResult comment: 'The trusted wrapper owns one 64-byte, aligned record until the result boxer returns. The producer sets status (0 OK, 1 PRIM_ERR_NO_MEMORY, 2 division by zero), signed normalized count and data (zero/positive/negative). allocation is NULL or the one libc allocation that the boxer owns; data may point into that allocation or to small, never to either input. No oop or registration token crosses this ABI.'!

!BigIntegerNativeResult class methodsFor: 'declaring'!
fields
	^#((data 'const uint64_t *') (allocation 'uint64_t *') (count int64_t) (status int32_t) (small 'uint64_t[4]'))
! !
