VMStruct subclass: #PfOutputLease
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!PfOutputLease class methodsFor: 'declaring'!
fields
	^#((ticket uint64_t) (payload 'uint8_t *') (payloadBytes uint64_t))
! !
