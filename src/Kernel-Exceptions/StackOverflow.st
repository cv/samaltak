Error subclass: #StackOverflow
	instanceVariableNames: 'context depth heapFull'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

StackOverflow comment: 'I am signaled in a Process whose stack grew beyond Process maxStackDepth activations (the VM checks, see Context>>stackOverflow:). context is the activation the check interrupted (my signalerContext), depth the stack''s depth there. I am resumable: the computation continues where it was interrupted, with maxStackDepth more activations of headroom (Process>>stackOverflowIn:depth:). Unless heapFull: signaled because the heap ran nearly full while the stack was deep (Process>>lowSpaceIn:depth:), I am not resumable.'!

!StackOverflow methodsFor: 'accessing'!
context
	^context
!
depth
	^depth
!
context: aContext depth: anInteger
	context := aContext.
	depth := anInteger
!
signalerContext
	^context
!
beHeapFull
	heapFull := true
!
description
	^'Stack overflow: ', depth printString, ' frames deep', (self isHeapFull ifTrue: [', the heap nearly full'] ifFalse: [''])
! !

!StackOverflow methodsFor: 'testing'!
isHeapFull
	^heapFull == true
!
isResumable
	^self isHeapFull not
! !
