VMStruct subclass: #FFITextBuffer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

FFITextBuffer comment: 'One wrapper-owned record. Input data is borrowed only until the native call returns. For an owned result the target replaces the input fields with an independent copy in small or allocation; null data represents no result. The wrapper releases allocation exactly once. No oop crosses this ABI.'!

!FFITextBuffer class methodsFor: 'declaring'!
fields
	^#((data 'const uint8_t *') (count uint64_t) (allocation 'void *') (small 'uint8_t[512]'))
! !
