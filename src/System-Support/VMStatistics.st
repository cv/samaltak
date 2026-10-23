Object subclass: #VMStatistics
	instanceVariableNames: 'counters'
	classVariableNames: ''
	package: 'System-Support'!

VMStatistics comment: 'I am a snapshot of the VM''s counters (Smalltalk vm statistics), over the Array the vmStats primitive answers (vm/src/prims.def), with a named accessor per counter. A - b answers the differences. Counters the VM does not report answer 0; ones I have no accessor for are kept.'!

!VMStatistics methodsFor: 'accessing'!
counters
	"Answer the raw Array, in vmStats order."
	^counters
!
counterAt: anInteger
	^anInteger <= counters size ifTrue: [counters at: anInteger] ifFalse: [0]
!
scavenges
	^self counterAt: 1
!
fullGCs
	^self counterAt: 2
!
scavengeMicroseconds
	^self counterAt: 3
!
fullGCMicroseconds
	^self counterAt: 4
!
oldBytesUsed
	^self counterAt: 5
!
oldBudget
	^self counterAt: 6
!
edenBytes
	^self counterAt: 7
!
bytesAllocated
	^self counterAt: 8
!
rememberedSetSize
	^self counterAt: 9
!
processSwitches
	^self counterAt: 10
!
bytesTenured
	^self counterAt: 11
!
weakSlotsCleared
	^self counterAt: 12
!
gcCount
	"Answer the scavenges plus the full GCs."
	^self scavenges + self fullGCs
!
gcMicroseconds
	^self scavengeMicroseconds + self fullGCMicroseconds
! !

!VMStatistics methodsFor: 'arithmetic'!
- aVMStatistics
	"Answer the counter differences (gauges such as oldBytesUsed become differences too)."
	^self class counters: ((1 to: (counters size min: aVMStatistics counters size))
		collect: [:i | (counters at: i) - (aVMStatistics counters at: i)])
! !

!VMStatistics methodsFor: 'printing'!
printOn: aStream
	"One counter per line."
	self class counterNames do: [:each |
		aStream nextPutAll: each; nextPutAll: ': '; print: (self perform: each); nextPut: Character lf]
! !

!VMStatistics methodsFor: 'private'!
setCounters: anArray
	counters := anArray
! !

!VMStatistics class methodsFor: 'instance creation'!
counters: anArray
	^self new setCounters: anArray
! !

!VMStatistics class methodsFor: 'accessing'!
counterNames
	"Answer my counter accessors in vmStats order."
	^#(#scavenges #fullGCs #scavengeMicroseconds #fullGCMicroseconds #oldBytesUsed #oldBudget #edenBytes #bytesAllocated #rememberedSetSize #processSwitches #bytesTenured #weakSlotsCleared)
! !
