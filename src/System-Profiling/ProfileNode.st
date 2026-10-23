Object subclass: #ProfileNode
	instanceVariableNames: 'name frame process parent children weight selfWeight sampleCount key order'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileNode comment: 'I am a node of a profile call tree (MessageTally tree, flame graph). The root stands for all samples, its children for Processes, below them ProfileFrames from the outermost frame inwards (stacks cut at maxDepth hang below a "…" node). weight counts the samples that pass through me (bytes for allocation trees), selfWeight those that end in me; so the weights of my children add up to weight - selfWeight. sampleCount is the number of samples regardless of their weight.

A ProfileAggregate keeps its trees live (add:count: with negative counts, removeChild:); its process nodes are named Process ''label'' after their Process, and stableChildren keeps the order of near-equal siblings from one call to the next, so live views do not swap rows on every refresh.'!

!ProfileNode methodsFor: 'accessing'!
name
	"Answer my label (process nodes of a ProfileAggregate: 'Process ''label''', following the Process's window title)."
	^name ifNil: [process isNil ifTrue: ['?'] ifFalse: ['Process ''', (Profiler labelFor: process), '''']]
!
key
	"Answer what identifies me among my siblings (my frame, Process, #unknown or #truncated); zoom paths and expansion state survive refreshes by it."
	^key
!
frame
	"Answer my ProfileFrame (nil for the root, process and truncation nodes)."
	^frame
!
method
	^frame isNil ifTrue: [nil] ifFalse: [frame method]
!
process
	^process
!
parent
	^parent
!
weight
	^weight
!
samples
	"Answer the weight of the samples passing through me (sample count for CPU trees, bytes for allocation trees)."
	^weight
!
bytes
	^weight
!
selfWeight
	^selfWeight
!
selfSamples
	^selfWeight
!
sampleCount
	^sampleCount
!
children
	"Answer my children, heaviest first."
	children isNil ifTrue: [^#()].
	^children values asArray sort: [:a :b | a weight > b weight or: [a weight = b weight and: [a name <= b name]]]
!
childFor: aKey
	^children isNil ifTrue: [nil] ifFalse: [children at: aKey ifAbsent: [nil]]
!
childAtKey: aKey
	^self childFor: aKey
!
stableChildren
	"Answer my children heaviest first, but keep the previous call's order among siblings whose weights differ by less than about 6% (a sibling overtakes another only by more), so live views stay calm. The order is kept between calls."
	| a n |
	children isNil ifTrue: [^#()].
	order isNil ifTrue: [order := self children asOrderedCollection].
	a := order.
	n := a size.
	2 to: n do: [:i | | x w j |
		x := a at: i.
		w := x weight.
		j := i - 1.
		[j >= 1 and: [w > ((a at: j) weight + ((a at: j) weight // 16 max: 1))]] whileTrue: [
			a at: j + 1 put: (a at: j).
			j := j - 1].
		a at: j + 1 put: x].
	^a
!
depth
	^parent isNil ifTrue: [0] ifFalse: [parent depth + 1]
!
path
	"Answer the nodes from the root down to me."
	^parent isNil ifTrue: [Array with: self] ifFalse: [parent path copyWith: self]
!
percentOf: total
	^total = 0 ifTrue: [0.0] ifFalse: [weight * 100.0 / total]
!
fractionOfParent
	^(parent isNil or: [parent weight = 0]) ifTrue: [1.0] ifFalse: [weight asFloat / parent weight]
! !

!ProfileNode methodsFor: 'testing'!
isLeaf
	^children isNil or: [children isEmpty]
!
isProcessNode
	^process notNil and: [frame isNil]
!
isMethodNode
	^frame notNil
! !

!ProfileNode methodsFor: 'enumerating'!
do: aBlock
	"Evaluate aBlock with me and every node below me, depth first."
	aBlock value: self.
	children isNil ifFalse: [children do: [:each | each do: aBlock]]
! !

!ProfileNode methodsFor: 'building'!
childAt: aKey name: aString frame: aFrame process: aProcess
	| node |
	children isNil ifTrue: [children := IdentityDictionary new].
	^children at: aKey ifAbsent: [
		node := ProfileNode new setName: aString frame: aFrame process: aProcess parent: self.
		node setKey: aKey.
		order isNil ifFalse: [order add: node].
		children at: aKey put: node]
!
removeChild: aNode
	"Forget aNode (its samples were all removed)."
	children isNil ifTrue: [^self].
	children removeKey: aNode key ifAbsent: [nil].
	order isNil ifFalse: [order remove: aNode ifAbsent: [nil]]
!
add: aWeight count: n
	"Count n samples weighing aWeight together (negative: remove them)."
	weight := weight + aWeight.
	sampleCount := sampleCount + n
!
add: aWeight
	weight := weight + aWeight.
	sampleCount := sampleCount + 1
!
addSelf: aWeight
	selfWeight := selfWeight + aWeight
!
addSample: aSample
	"Count aSample along its process and stack below me (I am a root)."
	| w node stack |
	w := aSample weight.
	self add: w.
	node := self childAt: (aSample process ifNil: [#unknown]) name: (Profiler labelFor: aSample process) frame: nil process: aSample process.
	node add: w.
	stack := aSample stack.
	aSample isTruncated ifTrue: [
		node := node childAt: #truncated name: '…' frame: nil process: nil.
		node add: w].
	stack size to: 1 by: -1 do: [:i | | f |
		f := stack at: i.
		node := node childAt: f name: f label frame: f process: nil.
		node add: w].
	node addSelf: w
! !

!ProfileNode methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ProfileNode('; nextPutAll: name; space; print: weight; nextPut: $)
! !

!ProfileNode methodsFor: 'private'!
setKey: anObject
	key := anObject
!
setName: aString frame: aFrame process: aProcess parent: aNode
	name := aString.
	frame := aFrame.
	process := aProcess.
	parent := aNode.
	weight := 0.
	selfWeight := 0.
	sampleCount := 0
! !

!ProfileNode class methodsFor: 'instance creation'!
root
	^self new setName: 'all' frame: nil process: nil parent: nil
!
name: aString process: aProcessOrNil
	"Answer a root without samples."
	^self new setName: aString frame: nil process: aProcessOrNil parent: nil
! !
