!VirtualMachine methodsFor: '*System-Support-window'!
primDroppedEvents
	| binding result |
	binding := WindowPlatformFFI droppedCall.
	binding isNil ifTrue: [^0].
	result := binding tryInvoke0.
	^result == false ifTrue: [0] ifFalse: [result]
!
primPlatformHandleCounts
	| binding bytes result |
	binding := WindowPlatformFFI handleCountsCall.
	binding isNil ifTrue: [^nil].
	bytes := ByteArray new: 88.
	result := binding tryInvoke1: {bytes. 1. 88}.
	result == false ifTrue: [^nil].
	result = 0 ifTrue: [^nil].
	^(1 to: 11) collect: [:i | WindowPlatformFFI signed64At: (i - 1) * 8 + 1 in: bytes]
! !
