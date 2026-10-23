Object subclass: #ProfilePath
	instanceVariableNames: 'track stack truncated nodes count weight pending pendingCount'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfilePath comment: 'I count the samples of one Process (a ProfileTrack) with one stack in a ProfileAggregate: nodes are the tree''s nodes from the root down to the stack''s innermost frame, count and weight what my samples add to each of them. Samples added and removed during an update accumulate in pending (nil while untouched) and are applied along my nodes once, by apply.'!

!ProfilePath methodsFor: 'accessing'!
track
	^track
!
stack
	^stack
!
isTruncated
	^truncated
!
nodes
	^nodes
!
count
	^count
!
weight
	^weight
!
pending
	"Answer the weight added since the last apply, or nil if none was."
	^pending
! !

!ProfilePath methodsFor: 'counting'!
addPending: aWeight count: n
	pending := (pending ifNil: [0]) + aWeight.
	pendingCount := (pendingCount ifNil: [0]) + n
!
apply
	"Add the pending change to my nodes (the innermost one's self weight too)."
	| w n |
	w := pending.
	n := pendingCount.
	pending := pendingCount := nil.
	(w isNil or: [w = 0 and: [n = 0]]) ifTrue: [^self].
	1 to: nodes size do: [:i | (nodes at: i) add: w count: n].
	nodes last addSelf: w.
	track addLeaf: nodes last frame weight: w.
	count := count + n.
	weight := weight + w
!
count: n weight: w
	count := n.
	weight := w
! !

!ProfilePath methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ProfilePath('; print: nodes last; nextPutAll: ' ×'; print: count; nextPut: $)
! !

!ProfilePath methodsFor: 'private'!
setTrack: aTrack stack: anArray truncated: aBoolean nodes: anArrayOfNodes
	track := aTrack.
	stack := anArray.
	truncated := aBoolean.
	nodes := anArrayOfNodes.
	count := 0.
	weight := 0
! !
