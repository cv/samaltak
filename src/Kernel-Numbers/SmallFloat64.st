Float immediateSubclass: #SmallFloat64
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

SmallFloat64 comment: 'I am a Float encoded in the object pointer (tag 100, Spur encoding): every double whose exponent is moderate, which is nearly all of them. I have no instances in memory; all behavior is in Float.'!

!SmallFloat64 methodsFor: 'comparing'!
identityHash
	^self hash
! !
