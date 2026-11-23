!VirtualMachine methodsFor: '*System-Support-window'!
ffiCandidatePrimDroppedEvents
	| binding result |
	binding := WindowPlatformFFI droppedCall.
	binding isNil ifTrue: [^self primDroppedEvents].
	result := binding tryInvoke0.
	^result == false ifTrue: [self primDroppedEvents] ifFalse: [result]
!
ffiCandidatePrimPlatformHandleCounts
	| binding bytes result |
	binding := WindowPlatformFFI handleCountsCall.
	binding isNil ifTrue: [^self primPlatformHandleCounts].
	bytes := ByteArray new: 88.
	result := binding tryInvoke1: {bytes. 1. 88}.
	result == false ifTrue: [^self primPlatformHandleCounts].
	result = 0 ifTrue: [^nil].
	^(1 to: 11) collect: [:i | WindowPlatformFFI signed64At: (i - 1) * 8 + 1 in: bytes]
! !
