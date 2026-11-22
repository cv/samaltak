Error subclass: #OutOfMemory
	instanceVariableNames: 'requestedClass requestedSize heapFull'
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

OutOfMemory comment: 'I am signaled when an allocation can never fit in the heap, even after a full garbage collection: requestedSize indexable fields of requestedClass. heapFull: signaled because a full GC found the heap nearly full, in the process that was running (Process>>lowSpaceIn:depth:), with no allocation of its own.'!

!OutOfMemory methodsFor: 'accessing'!
requestedClass
	^requestedClass
!
requestedClass: aClass
	requestedClass := aClass
!
requestedSize
	^requestedSize
!
requestedSize: anInteger
	requestedSize := anInteger
!
beHeapFull
	| stats |
	heapFull := true.
	stats := Smalltalk vm statistics.
	messageText := 'Out of memory: the heap is nearly full (', (stats oldBytesUsed // 1048576) printString, ' MB of ', (stats maxHeapBytes // 1048576) printString, ' MB)'
!
isHeapFull
	^heapFull == true
!
messageText
	^messageText ifNil: ['Out of memory: ', requestedClass printString, ' with ', requestedSize printString, ' indexable fields']
! !

!OutOfMemory class methodsFor: 'signaling'!
signalForClass: aClass size: anInteger
	^self new requestedClass: aClass; requestedSize: anInteger; signal
! !
