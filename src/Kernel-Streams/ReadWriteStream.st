WriteStream subclass: #ReadWriteStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Streams'!

ReadWriteStream comment: 'I am a WriteStream that can also read back what has been written (reset, then next).'!

!ReadWriteStream methodsFor: 'accessing'!
next
	position >= readLimit ifTrue: [^nil].
	position := position + 1.
	^collection at: position
!
contents
	readLimit := readLimit max: position.
	^collection copyFrom: 1 to: readLimit
!
atEnd
	^position >= (readLimit max: position)
! !
