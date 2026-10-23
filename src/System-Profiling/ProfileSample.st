Object subclass: #ProfileSample
	instanceVariableNames: 'serial time process flags stack weight allocatedClass allocationSize'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileSample comment: 'I am one decoded sample: the microsecond time, the Process it was attributed to and its stack (ProfileFrames, innermost first, at most the profiler''s maxDepth). weight is what I count for in trees: 1 for a CPU sample, the sampling interval in bytes for an allocation sample, which also knows the class and byte size of the sampled allocation.'!

!ProfileSample methodsFor: 'accessing'!
serial
	^serial
!
time
	"Answer the microsecond clock value when I was taken."
	^time
!
process
	^process
!
flags
	^flags
!
stack
	"Answer my ProfileFrames, innermost first."
	^stack
!
leaf
	"Answer the innermost ProfileFrame (or nil for an empty stack)."
	^stack isEmpty ifTrue: [nil] ifFalse: [stack first]
!
method
	"Answer the innermost frame (method or block) — the code that was running."
	^self leaf
!
homeMethod
	| leaf |
	leaf := self leaf.
	^leaf isNil ifTrue: [nil] ifFalse: [leaf method]
!
methodClass
	| leaf |
	leaf := self leaf.
	^leaf isNil ifTrue: [nil] ifFalse: [leaf methodClass]
!
weight
	^weight ifNil: [1]
!
weight: anInteger
	weight := anInteger
!
allocatedClass
	"Answer the class of the sampled allocation (nil for a CPU sample)."
	^allocatedClass
!
allocationSize
	"Answer the byte size of the sampled allocation (nil for a CPU sample)."
	^allocationSize
!
processName
	^Profiler labelFor: process
!
allocationSite
	"Answer the frame that allocated: the innermost one, or its sender if the innermost had just been activated (the VM samples at the activation after the allocation), skipping instance-creation methods of Behavior (new, basicNew: ...)."
	(self isFreshLeaf ifTrue: [2] ifFalse: [1]) to: stack size do: [:i | | frame |
		frame := stack at: i.
		(frame isBlock not and: [frame methodClass == Behavior]) ifFalse: [^frame]].
	^self leaf
! !

!ProfileSample methodsFor: 'testing'!
isIdle
	^(flags bitAnd: 1) ~= 0
!
isTruncated
	"Answer whether my stack was deeper than the profiler's maxDepth (the outermost frames are missing)."
	^(flags bitAnd: 2) ~= 0
!
isUnattributed
	"Answer whether the VM could not tell which process was interrupted (I am then counted as idle)."
	^(flags bitAnd: 4) ~= 0
!
isFreshLeaf
	"Answer whether my innermost frame had just been activated (its first bytecode not yet run)."
	^(flags bitAnd: 8) ~= 0
!
isAllocation
	^allocatedClass notNil
!
includesFrame: aProfileFrame
	^stack identityIncludes: aProfileFrame
! !

!ProfileSample methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ProfileSample('; nextPutAll: self processName.
	self leaf isNil ifFalse: [aStream space; print: self leaf].
	allocatedClass isNil ifFalse: [aStream nextPutAll: ' allocating '; print: allocatedClass].
	aStream nextPut: $)
! !

!ProfileSample methodsFor: 'private'!
setSerial: k time: microseconds process: aProcess flags: flagBits stack: anArray
	serial := k.
	time := microseconds.
	process := aProcess.
	flags := flagBits.
	stack := anArray
!
setAllocatedClass: aClass size: byteCount
	allocatedClass := aClass.
	allocationSize := byteCount
! !
