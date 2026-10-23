Object subclass: #ProfileTrack
	instanceVariableNames: 'process node root stacks truncated members label leaves'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileTrack comment: 'I am what a ProfileAggregate keeps per Process: its process node in the tree (below the aggregate''s root, or its idle root), the ProfilePaths of its samples by stack (stacks cut at the profiler''s depth separately), the self weight per innermost ProfileFrame (leaves), and the Processes counted in me (members: the Process, and the terminated ones with the same label merged into me). label is set once my Process has terminated.'!

!ProfileTrack methodsFor: 'accessing'!
process
	"Answer the Process I stand for (nil: samples of an unknown Process)."
	^process
!
node
	^node
!
root
	^root
!
members
	^members
!
label
	^label
!
weight
	^node weight
!
leaves
	"Answer an IdentityDictionary ProfileFrame -> weight of the samples ending in it."
	^leaves
!
addLeaf: aFrame weight: w
	| t |
	aFrame isNil ifTrue: [^self].
	t := (leaves at: aFrame ifAbsent: [0]) + w.
	t = 0 ifTrue: [leaves removeKey: aFrame ifAbsent: [nil]] ifFalse: [leaves at: aFrame put: t]
!
isRetired
	"Answer whether my Process terminated (and I was merged or became the one others merge into)."
	^label notNil
! !

!ProfileTrack methodsFor: 'paths'!
pathFor: aSample
	^self pathForStack: aSample stack truncated: aSample isTruncated
!
pathForStack: anArray truncated: aBoolean
	"Answer the ProfilePath of anArray (ProfileFrames, innermost first), making it and its nodes if needed."
	| dict |
	dict := aBoolean ifTrue: [truncated ifNil: [truncated := IdentityDictionary new]] ifFalse: [stacks].
	^dict at: anArray ifAbsent: [dict at: anArray put: (self newPath: anArray truncated: aBoolean)]
!
newPath: anArray truncated: aBoolean
	| nodes n i |
	nodes := Array new: anArray size + 2 + (aBoolean ifTrue: [1] ifFalse: [0]).
	nodes at: 1 put: root; at: 2 put: node.
	n := node.
	i := 2.
	aBoolean ifTrue: [
		n := n childAt: #truncated name: '…' frame: nil process: nil.
		nodes at: (i := i + 1) put: n].
	anArray size to: 1 by: -1 do: [:j | | f |
		f := anArray at: j.
		n := n childAt: f name: f label frame: f process: nil.
		nodes at: (i := i + 1) put: n].
	^ProfilePath new setTrack: self stack: anArray truncated: aBoolean nodes: nodes
!
forget: aPath
	(aPath isTruncated ifTrue: [truncated] ifFalse: [stacks]) removeKey: aPath stack ifAbsent: [nil]
!
pathsDo: aBlock
	stacks do: aBlock.
	truncated isNil ifFalse: [truncated do: aBlock]
! !

!ProfileTrack methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ProfileTrack('; nextPutAll: node name; space; print: node weight; nextPut: $)
! !

!ProfileTrack methodsFor: 'private'!
setProcess: aProcess node: aNode root: aRoot
	process := aProcess.
	node := aNode.
	root := aRoot.
	stacks := IdentityDictionary new.
	leaves := IdentityDictionary new.
	members := OrderedCollection with: (aProcess ifNil: [#unknown])
!
retire: aString
	label := aString
! !
