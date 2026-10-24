"
Copyright 2011 Google Inc.

Licensed under the Apache License, Version 2.0 (the 'License');
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an 'AS IS' BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"!

Object subclass: #BasicBlock
	instanceVariableNames: 'inEdges outEdges name'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #BasicBlockEdge
	instanceVariableNames: 'from to'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #ControlFlowGraph
	instanceVariableNames: 'basicBlockMap startNode edgeList'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #Havlak
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #HavlakLoopFinder
	instanceVariableNames: 'cfg lsg nonBackPreds backPreds number maxSize header type last nodes'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #LoopStructureGraph
	instanceVariableNames: 'root loops loopCounter'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #LoopTesterApp
	instanceVariableNames: 'cfg lsg'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #SimpleLoop
	instanceVariableNames: 'counter depthLevel parent_ isRoot_ nestingLevel_ header isReducible basicBlocks children'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #UnionFindNode
	instanceVariableNames: 'parent_ bb_ dfsNumber_ loop'
	classVariableNames: ''
	package: 'AWFY'!

!BasicBlock methodsFor: 'benchmarking'!
init: aName
	inEdges  := Vector new: 2.
	outEdges := Vector new: 2.
	name     := aName
!
inEdges
	^ inEdges
!
outEdges
	^ outEdges
!
numPred
	^ inEdges size
!
addOutEdge: to
	outEdges append: to
!
addInEdge: from
	inEdges append: from
!
customHash
	^ name
! !

!BasicBlock class methodsFor: 'benchmarking'!
new: name
	^ self new init: name
! !

!BasicBlockEdge methodsFor: 'benchmarking'!
init: cfg from: fromName to: toName
	from := cfg createNode: fromName.
	to   := cfg createNode: toName.

	from addOutEdge: to.
	to   addInEdge:  from.
	cfg  addEdge:    self
! !

!BasicBlockEdge class methodsFor: 'benchmarking'!
for: cfg from: fromName to: toName
	^ self new init: cfg from: fromName to: toName
! !

!ControlFlowGraph methodsFor: 'benchmarking'!
initialize
	basicBlockMap := Vector new.
	edgeList := Vector new.
!
createNode: name
	| node |

	(basicBlockMap at: name)
	  ifNotNil: [ node := basicBlockMap at: name ]
	  ifNil: [
	    node := BasicBlock new: name.
	    basicBlockMap at: name put: node ].

	self numNodes = 1 ifTrue: [startNode := node].
	^ node
!
addEdge: edge
	edgeList append: edge
!
numNodes
	^ basicBlockMap size
!
startBasicBlock
	^ startNode
!
basicBlocks
	^ basicBlockMap
! !

!ControlFlowGraph class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

!Havlak methodsFor: 'benchmarking'!
innerBenchmarkLoop: innerIterations
	^ self verifyResult:
	   (LoopTesterApp new main: innerIterations loop: 50 p: 10 p: 10 p: 5)
	  iterations: innerIterations
!
verifyResult: result iterations: innerIterations
	innerIterations = 15000 ifTrue: [ ^ (result at: 1) = 46602 and: [(result at: 2) = 5213] ].
	innerIterations =  1500 ifTrue: [ ^ (result at: 1) =  6102 and: [(result at: 2) = 5213] ].
	innerIterations =   150 ifTrue: [ ^ (result at: 1) =  2052 and: [(result at: 2) = 5213] ].
	innerIterations =    15 ifTrue: [ ^ (result at: 1) =  1647 and: [(result at: 2) = 5213] ].
	innerIterations =     1 ifTrue: [ ^ (result at: 1) =  1605 and: [(result at: 2) = 5213] ].

	ScriptConsole println: ('No verification result for', innerIterations asString, ' found').
	ScriptConsole println: ('Result is ', (result at: 1) asString, ', ', (result at: 2) asString).
	^ false
! !

!HavlakLoopFinder methodsFor: 'benchmarking'!
init: aCfg lsg: aLsg
	cfg := aCfg.
	lsg := aLsg.

	nonBackPreds := Vector new.
	backPreds    := Vector new.
	number := SomIdentityDictionary new.

	maxSize := 0.
!
Unvisited
	^ 2147483647
!
MaxNonBackPreds
	^ 32 * 1024
!
isAncestor: w v: v
	^ (w <= v) and: [(v <= (last at: w))]
!
doDFS: currentNode current: current
	| lastId outerBlocks |

	(nodes at: current) initNode: currentNode dfs: current.
	number at: currentNode put: current.

	lastId := current.
	outerBlocks := currentNode outEdges.

	1 to: outerBlocks size do: [:i |
	  | target |
	  target := outerBlocks at: i.
	  (number at: target) = self Unvisited ifTrue: [
	    lastId := self doDFS: target current: lastId + 1 ] ].

	last at: current put: lastId.
	^ lastId
!
initAllNodes
	cfg basicBlocks forEach: [:bb |
	  number at: bb put: self Unvisited ].

	self doDFS: cfg startBasicBlock current: 1
!
identifyEdges: size
	1 to: size do: [:w |
	  | nodeW |
	  header at: w put: 1.
	  type   at: w put: #BBNonHeader.

	  nodeW := (nodes at: w) bb.
	  nodeW
	    ifNil:    [ type at: w put: #BBDead ]
	    ifNotNil: [ self processEdges: nodeW w: w ] ]
!
processEdges: nodeW w: w
	nodeW numPred > 0 ifTrue: [
	  nodeW inEdges forEach: [:nodeV |
	    | v |
	    v := number at: nodeV.
	    v ~= self Unvisited ifTrue: [
	      (self isAncestor: w v: v)
	        ifTrue:  [ (backPreds at: w) append: v ]
	        ifFalse: [ (nonBackPreds at: w) add: v ] ] ] ]
!
findLoops
	| size |
	cfg startBasicBlock ifNil: [ ^ self ].

	size := cfg numNodes.

	nonBackPreds removeAll.
	backPreds removeAll.
	number removeAll.

	size > maxSize ifTrue: [
	  header := Array new: size.
	  type   := Array new: size.
	  last   := Array new: size.
	  nodes  := Array new: size.
	  maxSize := size ].

	1 to: size do: [:i |
	  nonBackPreds append: SomSet new.
	  backPreds append: Vector new.
	  nodes at: i put: UnionFindNode new ].

	self initAllNodes.
	self identifyEdges: size.
	header at: 1 put: 1.

	size to: 1 by: -1 do: [:w |
	  | nodePool nodeW |
	  nodePool := Vector new.
	  nodeW := (nodes at: w) bb.

	  nodeW ifNotNil: [
	    | workList |
	    self stepD: w nodePool: nodePool.

	    workList := Vector new.
	    nodePool forEach: [:niter | workList append: niter ].

	    nodePool size ~= 0 ifTrue: [
	      type at: w put: #BBReducible.
	    ].

	    [ workList isEmpty ] whileFalse: [
	      | x nonBackSize |
	      x := workList removeFirst.

	      nonBackSize := (nonBackPreds at: x dfsNumber) size.
	      nonBackSize > self MaxNonBackPreds ifTrue: [ ^ self ].
	      self stepEProcessNonBackPreds: w nodePool: nodePool workList: workList x: x ].

	    (nodePool size > 0 or: [(type at: w) = #BBSelf]) ifTrue: [
	      | loop |
	      loop := lsg createNewLoop: nodeW reducible: ((type at: w) ~= #BBIrreducible).
	      self setLoopAttribute: w nodePool: nodePool loop: loop ] ] ]
!
stepEProcessNonBackPreds: w nodePool: nodePool workList: workList x: x
	(nonBackPreds at: x dfsNumber) forEach: [:iter |
	  | y ydash |
	  y := nodes at: iter.
	  ydash := y findSet.

	  (self isAncestor: w v: ydash dfsNumber) not
	    ifTrue: [
	      type at: w put: #BBIrreducible.
	      (nonBackPreds at: w) add: ydash dfsNumber ]
	    ifFalse: [
	      ydash dfsNumber ~= w ifTrue: [
	        (nodePool hasSome: [:e | e == ydash]) ifFalse: [
	          workList append: ydash.
	          nodePool append: ydash ] ] ] ]
!
setLoopAttribute: w nodePool: nodePool loop: loop
	(nodes at: w) loop: loop.

	nodePool forEach: [:node |
	  header at: node dfsNumber put: w.
	  node union: (nodes at: w).

	  node loop
	    ifNotNil: [ node loop parent: loop ]
	    ifNil:    [ loop addNode: node bb ] ]
!
stepD: w nodePool: nodePool
	(backPreds at: w) forEach: [:v |
	  v ~= w ifTrue: [ nodePool append: (nodes at: v) findSet ]
	         ifFalse: [ type at: w put: #BBSelf ] ]
! !

!HavlakLoopFinder class methodsFor: 'benchmarking'!
new: cfg lsg: lsg
	^ self new init: cfg lsg: lsg
! !

!LoopStructureGraph methodsFor: 'benchmarking'!
initialize
	root  := SimpleLoop basicBlock: nil reducible: false.
	loops := Vector new.
	loopCounter := 0.

	root nestingLevel: 0.
	root counter: loopCounter.
	loopCounter := loopCounter + 1.
	loops append: root
!
createNewLoop: bb reducible: isReducible
	| loop |
	loop := SimpleLoop basicBlock: bb reducible: isReducible.
	loop counter: loopCounter.
	loopCounter := loopCounter + 1.
	loops append: loop.
	^ loop
!
calculateNestingLevel
	loops forEach: [:liter |
	  liter isRoot ifFalse: [
	    liter parent ifNil: [
	      liter parent: root ] ] ].

	self calculateNestingLevelRec: root depth: 0
!
calculateNestingLevelRec: loop depth: depth
	loop depthLevel: depth.
	loop children forEach: [:liter |
	  self calculateNestingLevelRec: liter depth: depth + 1.
	  loop nestingLevel: (loop nestingLevel max: 1 + liter nestingLevel) ]
!
numLoops
	^ loops size
! !

!LoopStructureGraph class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

!LoopTesterApp methodsFor: 'benchmarking'!
initialize
	cfg := ControlFlowGraph new.
	lsg := LoopStructureGraph new.
	cfg createNode: 1.
!
buildDiamond: start
	| bb0 |
	bb0 := start.
	BasicBlockEdge for: cfg from: bb0 to: bb0 + 1.
	BasicBlockEdge for: cfg from: bb0 to: bb0 + 2.
	BasicBlockEdge for: cfg from: bb0 + 1 to: bb0 + 3.
	BasicBlockEdge for: cfg from: bb0 + 2 to: bb0 + 3.
	^ bb0 + 3
!
buildConnect: start end: end
	BasicBlockEdge for: cfg from: start to: end
!
buildStraight: start n: n
	0 to: n - 1 do: [:i |
	  self buildConnect: start + i end: start + i + 1 ].
	^ start + n
!
buildBaseLoop: from
	| header diamond1 d11 diamond2 footer |
	header   := self buildStraight: from n: 1.
	diamond1 := self buildDiamond: header.
	d11      := self buildStraight: diamond1 n: 1.
	diamond2 := self buildDiamond: d11.
	footer   := self buildStraight: diamond2 n: 1.

	self buildConnect: diamond2 end: d11.
	self buildConnect: diamond1 end: header.
	self buildConnect: footer   end: from.
	footer := self buildStraight: footer n: 1.
	^ footer
!
main: numDummyLoops loop: findLoopIterations p: parLoop p: pparLoops p: ppparLoops
	self constructSimpleCFG.
	self addDummyLoops: numDummyLoops.
	self constructCFG: parLoop p: pparLoops p: ppparLoops.

	self findLoops: lsg.
	findLoopIterations timesRepeat: [
	  self findLoops: LoopStructureGraph new ].

	lsg calculateNestingLevel.
	^ Array with: lsg numLoops with: cfg numNodes
!
constructCFG: parLoops p: pparLoops p: ppparLoops
	| n |
	n := 3.

	parLoops timesRepeat: [
	  cfg createNode: n + 1.
	  self buildConnect: 2 end: n + 1.
	  n := n + 1.

	  pparLoops timesRepeat: [
	    | top bottom |
	    top := n.
	    n := self buildStraight: n n:1.
	    ppparLoops timesRepeat: [ n := self buildBaseLoop: n ].
	    bottom := self buildStraight: n n: 1.
	    self buildConnect: n end: top.
	    n := bottom ].

	  self buildConnect: n end: 1 ]
!
addDummyLoops: numDummyLoops
	numDummyLoops timesRepeat: [
	  self findLoops: lsg ]
!
findLoops: loopStructure
	| finder |
	finder := HavlakLoopFinder new: cfg lsg: loopStructure.
	finder findLoops
!
constructSimpleCFG
	cfg createNode: 1.
	self buildBaseLoop: 1.
	cfg createNode: 2.
	BasicBlockEdge for: cfg from: 1 to:  3
! !

!LoopTesterApp class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

!SimpleLoop methodsFor: 'benchmarking'!
init: aBB reducible: aBool
	counter    := 0.
	depthLevel := 0.

	isRoot_ := false.
	nestingLevel_ := 0.
	header  := aBB.
	isReducible := aBool.
	basicBlocks := SomIdentitySet new.
	children    := SomIdentitySet new.

	aBB ifNotNil: [ basicBlocks add: aBB ]
!
counter
	^ counter
!
counter: val
	counter := val
!
depthLevel
	^ depthLevel
!
depthLevel: val
	depthLevel := val
!
children
	^ children
!
addNode: bb
	basicBlocks add: bb
!
addChildLoop: loop
	children add: loop
!
parent
	^ parent_
!
parent: val
	parent_ := val.
	parent_ addChildLoop: self
!
isRoot
	^ isRoot_
!
setIsRoot
	isRoot_ := true
!
nestingLevel
	^ nestingLevel_
!
nestingLevel: level
	nestingLevel_ := level.
	level = 0 ifTrue: [ self setIsRoot ]
! !

!SimpleLoop class methodsFor: 'benchmarking'!
basicBlock: bb reducible: isReducible
	^ self new init: bb reducible: isReducible
! !

!UnionFindNode methodsFor: 'benchmarking'!
initialize
	dfsNumber_ := 0.
!
initNode: bb dfs: dfsNumber
	parent_ := self.
	bb_ := bb.
	dfsNumber_ := dfsNumber.
!
loop
	^ loop
!
loop: aLoop
	loop := aLoop
!
findSet
	| nodeList node |
	nodeList := Vector new.

	node := self.

	[node ~= node parent] whileTrue: [
	  ((node parent) ~= (node parent parent)) ifTrue: [
	    nodeList append: node ].
	  node := node parent ].

	nodeList forEach: [:iter | iter union: parent_ ].
	^ node
!
union: basicBlock
	parent_ := basicBlock
!
parent
	^ parent_
!
bb
	^ bb_
!
dfsNumber
	^ dfsNumber_
! !

!UnionFindNode class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

