VMStruct subclass: #GpuShaderOutput
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!GpuShaderOutput class methodsFor: 'declaring'!
fields
	^#((ticket uint64_t) (payload 'uint8_t *') (payloadBytes uint64_t))
! !
