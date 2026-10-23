Float variableDoubleWordSubclass: #BoxedFloat64
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

BoxedFloat64 comment: 'I am a Float stored in a heap object with one 64-bit slot of IEEE bits. The VM uses me for doubles that do not fit the SmallFloat64 encoding: infinities, NaNs, and very large or very small magnitudes. All behavior is in Float.'!
