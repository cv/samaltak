Object subclass: #AllocationSite
	instanceVariableNames: 'frame allocatedClass bytes count processes'
	classVariableNames: ''
	package: 'System-Profiling'!

AllocationSite comment: 'I summarize the allocation samples of one site: the allocating frame (instance-creation methods of Behavior skipped) and the allocated class, with the estimated bytes (samples × sampling interval), the sample count and the Process that allocated most.'!

!AllocationSite methodsFor: 'accessing'!
frame
	^frame
!
method
	^frame isNil ifTrue: [nil] ifFalse: [frame method]
!
allocatedClass
	^allocatedClass
!
bytes
	^bytes
!
count
	^count
!
process
	"Answer the Process that allocated most here."
	| best |
	processes keysAndValuesDo: [:p :b | (best isNil or: [b > (processes at: best)]) ifTrue: [best := p]].
	^best
!
processes
	^processes keys asArray
! !

!AllocationSite methodsFor: 'building'!
addSample: aSample
	bytes := bytes + aSample weight.
	count := count + 1.
	aSample process isNil ifFalse: [
		processes at: aSample process put: (processes at: aSample process ifAbsent: [0]) + aSample weight]
!
removeSample: aSample
	"Undo addSample: aSample (ProfileAggregate, when the sample leaves the ring)."
	| b |
	bytes := bytes - aSample weight.
	count := count - 1.
	aSample process isNil ifFalse: [
		b := (processes at: aSample process ifAbsent: [0]) - aSample weight.
		b <= 0
			ifTrue: [processes removeKey: aSample process ifAbsent: [nil]]
			ifFalse: [processes at: aSample process put: b]]
!
restrictedTo: aCollection
	"Answer a copy counting only the bytes of the Processes in aCollection (nil if none of them allocated here)."
	| site |
	site := AllocationSite frame: frame allocatedClass: allocatedClass.
	aCollection do: [:p | | b |
		b := processes at: p ifAbsent: [0].
		b > 0 ifTrue: [site addBytes: b count: ((b * count / bytes) rounded max: 1) process: p]].
	^site bytes = 0 ifTrue: [nil] ifFalse: [site]
! !

!AllocationSite methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an AllocationSite('; print: frame; nextPutAll: ' allocates '; print: allocatedClass;
		space; nextPutAll: (Profiler printBytes: bytes); nextPut: $)
! !

!AllocationSite methodsFor: 'private'!
addBytes: anInteger count: n process: aProcess
	bytes := bytes + anInteger.
	count := count + n.
	processes at: aProcess put: (processes at: aProcess ifAbsent: [0]) + anInteger
!
setFrame: aFrame allocatedClass: aClass
	frame := aFrame.
	allocatedClass := aClass.
	bytes := 0.
	count := 0.
	processes := IdentityDictionary new
! !

!AllocationSite class methodsFor: 'instance creation'!
frame: aFrame allocatedClass: aClass
	^self new setFrame: aFrame allocatedClass: aClass
! !
