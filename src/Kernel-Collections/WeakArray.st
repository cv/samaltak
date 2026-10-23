Array weakSubclass: #WeakArray
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

WeakArray comment: 'I am an Array whose elements do not keep their referents alive. When the garbage collector finds an element referenced only from weak objects, it replaces the element with nil and signals the finalization Semaphore (special object 36), which WeakRegistry waits on.'!

!WeakArray methodsFor: 'copying'!
species
	^Array
! !
