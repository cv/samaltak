Collection subclass: #SampleSet
	instanceVariableNames: 'samples unit'
	classVariableNames: ''
	package: 'System-Profiling'!

SampleSet comment: 'I am a collection of ProfileSamples (oldest first) — what a Profile answers for samples and allocations. Besides the usual enumeration I build call trees (tallyTree, flameRoot), leaves, per-process counts and groups (groupBy: #method, #process, #class or a block). unit is #samples for CPU samples and #bytes for allocation samples (each counts for the sampling interval in bytes).'!

!SampleSet methodsFor: 'accessing'!
unit
	^unit
!
size
	^samples size
!
first
	^samples first
!
last
	^samples last
!
asArray
	^samples asArray
!
totalWeight
	"Answer the sample count (CPU) or the estimated bytes (allocations)."
	^samples inject: 0 into: [:sum :each | sum + each weight]
!
totalBytes
	^self totalWeight
!
duration
	"Answer the microseconds between my first and last sample."
	^samples isEmpty ifTrue: [0] ifFalse: [samples last time - samples first time]
! !

!SampleSet methodsFor: 'adding'!
add: aSample
	^samples add: aSample
! !

!SampleSet methodsFor: 'enumerating'!
do: aBlock
	samples do: aBlock
!
select: aBlock
	| result |
	result := self copyEmpty.
	samples do: [:each | (aBlock value: each) ifTrue: [result add: each]].
	^result
!
collect: aBlock
	^samples collect: aBlock
!
copyEmpty
	^self class unit: unit
! !

!SampleSet methodsFor: 'filtering'!
samplesFor: aProcess
	^self select: [:each | each process == aProcess]
!
from: startMicroseconds to: stopMicroseconds
	^self select: [:each | each time between: startMicroseconds and: stopMicroseconds]
!
withoutIdle
	^self reject: [:each | each isIdle]
!
idle
	^self select: [:each | each isIdle]
!
including: aProfileFrame
	"Answer the samples whose stack contains aProfileFrame."
	^self select: [:each | each includesFrame: aProfileFrame]
! !

!SampleSet methodsFor: 'analysis'!
tallyTree
	"Answer the root ProfileNode of the call tree: root, then one node per Process, then frames from the outermost inwards."
	| root |
	root := ProfileNode root.
	samples do: [:each | root addSample: each].
	^root
!
flameRoot
	^self tallyTree
!
leaves
	"Answer Associations ProfileFrame -> self weight (samples ending in that frame), heaviest first."
	| totals |
	totals := IdentityDictionary new.
	samples do: [:each | | leaf |
		leaf := each leaf.
		leaf isNil ifFalse: [totals at: leaf put: (totals at: leaf ifAbsent: [0]) + each weight]].
	^self sortedAssociations: totals
!
groupBy: aSymbolOrBlock
	"Answer a Dictionary from key to SampleSet. #method groups by the innermost frame, #homeMethod by its CompiledMethod, #process by Process, #class by allocated class (allocations) or the innermost frame's class (CPU); a block computes the key from a sample."
	| key groups |
	key := aSymbolOrBlock isSymbol
		ifTrue: [
			aSymbolOrBlock == #class
				ifTrue: [unit == #bytes
					ifTrue: [[:s | s allocatedClass]]
					ifFalse: [[:s | s methodClass]]]
				ifFalse: [[:s | s perform: aSymbolOrBlock]]]
		ifFalse: [aSymbolOrBlock].
	groups := Dictionary new.
	samples do: [:each | | k |
		k := key value: each.
		(groups at: k ifAbsent: [groups at: k put: self copyEmpty]) add: each].
	^groups
!
processes
	"Answer the Processes of my samples, most samples first."
	^(self processWeights collect: [:each | each key]) asArray
!
processWeights
	"Answer Associations Process -> weight, heaviest first."
	| totals |
	totals := IdentityDictionary new.
	samples do: [:each | | p |
		p := each process.
		p isNil ifFalse: [totals at: p put: (totals at: p ifAbsent: [0]) + each weight]].
	^self sortedAssociations: totals
!
weightFor: aProcess
	^samples inject: 0 into: [:sum :each | each process == aProcess ifTrue: [sum + each weight] ifFalse: [sum]]
!
percentFor: aProcess
	"Answer the percentage of my samples (or bytes) attributed to aProcess."
	| total |
	total := self totalWeight.
	^total = 0 ifTrue: [0.0] ifFalse: [(self weightFor: aProcess) * 100.0 / total]
!
topSites
	^self topSites: 20
!
topSites: n
	"Answer the heaviest AllocationSites (allocating frame and class), at most n."
	| sites result |
	sites := Dictionary new.
	samples do: [:each | | frame perFrame site |
		frame := each allocationSite.
		perFrame := sites at: (frame ifNil: [#none]) ifAbsent: [sites at: (frame ifNil: [#none]) put: IdentityDictionary new].
		site := perFrame at: each allocatedClass ifAbsent: [
			perFrame at: each allocatedClass put: (AllocationSite frame: frame allocatedClass: each allocatedClass)].
		site addSample: each].
	result := OrderedCollection new.
	sites do: [:perFrame | result addAll: perFrame values].
	result := result asArray sort: [:a :b | a bytes > b bytes].
	^result copyFrom: 1 to: (n min: result size)
! !

!SampleSet methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a SampleSet('.
	unit == #bytes
		ifTrue: [aStream print: self size; nextPutAll: ' samples, '; nextPutAll: (Profiler printBytes: self totalWeight)]
		ifFalse: [aStream print: self size; nextPutAll: ' samples'].
	aStream nextPut: $)
! !

!SampleSet methodsFor: 'private'!
setUnit: aSymbol
	unit := aSymbol.
	samples := OrderedCollection new
!
setSamples: anOrderedCollection
	samples := anOrderedCollection
!
sortedAssociations: aDictionary
	^aDictionary associations asArray sort: [:a :b | a value > b value]
! !

!SampleSet class methodsFor: 'instance creation'!
new
	^self unit: #samples
!
unit: aSymbol
	^self basicNew setUnit: aSymbol
!
unit: aSymbol samples: anOrderedCollection
	"Answer a SampleSet of anOrderedCollection (not copied)."
	^(self basicNew setUnit: aSymbol) setSamples: anOrderedCollection
! !
