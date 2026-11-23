VMStruct subclass: #FFIOwnedRow
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

!FFIOwnedRow class methodsFor: 'declaring'!
fields
	"State: 0 reserved, 1 claimed by the one producer, 2 ready to copy."
	^#((ticket uint64_t) (state uint32_t) (capacity uint32_t)
		(bytes 'uint8_t *') (payloadBytes uint32_t))
! !
