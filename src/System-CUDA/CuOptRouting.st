Object subclass: #CuOptRouting
	instanceVariableNames: 'depot stops vehicles capacity timeLimit result routes'
	classVariableNames: ''
	package: 'System-CUDA'!

CuOptRouting comment: 'I am a small vehicle-routing problem solved by cuOpt (CuOpt) as a mixed-integer program, as the cuOpt window edits it: a depot and stops (Points in the unit square), a number of vehicles, each visiting at most capacity stops, every stop visited once, the total distance driven least. cuOpt''s routing solver has no C API (only C++ and Python), so this is the classic formulation for its MILP solver: a binary x(i, j) for each leg from node i to node j (node 0 the depot), one leg into and one out of each stop, as many out of the depot as into it (at most vehicles), and the Miller-Tucker-Zemlin load u(i) of each stop (u(j) >= u(i) + 1 where a vehicle drives from i to j), which rules out tours that miss the depot. routes answers each vehicle''s stops in order (indices into stops).

	| r | r := CuOptRouting new.
	r depot: 0.5 @ 0.5.
	#(0.1 0.2 0.8 0.9 0.3 0.7) with: #(0.1 0.8 0.2 0.7 0.5 0.4) do: [:x :y | r addStop: x @ y].
	r vehicles: 2; solve; routes'!

!CuOptRouting class methodsFor: 'instance creation'!
example
	"A depot in the middle and ten stops around it."
	| r |
	r := self new.
	r depot: 0.5 @ 0.52.
	#(#(0.12 0.18) #(0.3 0.1) #(0.55 0.14) #(0.83 0.22) #(0.9 0.5) #(0.78 0.84) #(0.52 0.9) #(0.24 0.8) #(0.08 0.55) #(0.36 0.42))
		do: [:p | r addStop: p first @ p last].
	^r vehicles: 2; yourself
! !

!CuOptRouting methodsFor: 'initialization'!
initialize
	depot := 0.5 @ 0.5.
	stops := OrderedCollection new.
	vehicles := 2.
	timeLimit := 2
! !

!CuOptRouting methodsFor: 'accessing'!
depot
	^depot
!
depot: aPoint
	depot := aPoint.
	self changed
!
stops
	^stops
!
addStop: aPoint
	stops add: aPoint.
	self changed
!
removeStopAt: index
	stops removeIndex: index.
	self changed
!
stopAt: index put: aPoint
	stops at: index put: aPoint.
	self changed
!
vehicles
	^vehicles
!
vehicles: anInteger
	vehicles := anInteger max: 1.
	self changed
!
capacity
	"The stops a vehicle may visit: an even share, and one more (or what was set)."
	^capacity ifNil: [(stops size / vehicles) ceiling + 1 min: (stops size max: 1)]
!
capacity: anIntegerOrNil
	capacity := anIntegerOrNil.
	self changed
!
timeLimit
	^timeLimit
!
timeLimit: seconds
	timeLimit := seconds
!
result
	"The last CuOptResult (nil before a solve, or after a change)."
	^result
!
routes
	"Each used vehicle's stops in the order it visits them (indices into stops), from the last solve; nil without one."
	^routes
!
changed
	result := nil.
	routes := nil
!
nodeAt: index
	"Node 0 is the depot, node i the i-th stop."
	^index = 0 ifTrue: [depot] ifFalse: [stops at: index]
!
distanceFrom: i to: j
	^(self nodeAt: i) dist: (self nodeAt: j)
! !

!CuOptRouting methodsFor: 'formulation'!
legs
	"The legs (i -> j, i ~= j) over nodes 0..n in the order of their variables."
	| n legs |
	n := stops size.
	legs := OrderedCollection new.
	0 to: n do: [:i | 0 to: n do: [:j | i = j ifFalse: [legs add: i -> j]]].
	^legs asArray
!
program
	"{objective. rows. senses. rhs. lower. upper. types}: the legs' binaries, then a load for each stop."
	| n legs index nv rows senses rhs q objective row |
	n := stops size.
	legs := self legs.
	index := Dictionary new.
	legs doWithIndex: [:leg :k | index at: leg put: k].
	nv := legs size + n.
	q := self capacity.
	objective := Array new: nv withAll: 0.
	legs doWithIndex: [:leg :k | objective at: k put: (self distanceFrom: leg key to: leg value)].
	rows := OrderedCollection new.
	senses := WriteStream on: String new.
	rhs := OrderedCollection new.
	1 to: n do: [:j |
		"one leg into j, one out of j"
		row := Array new: nv withAll: 0.
		0 to: n do: [:i | i = j ifFalse: [row at: (index at: i -> j) put: 1]].
		rows add: row. senses nextPut: $E. rhs add: 1.
		row := Array new: nv withAll: 0.
		0 to: n do: [:i | i = j ifFalse: [row at: (index at: j -> i) put: 1]].
		rows add: row. senses nextPut: $E. rhs add: 1].
	"out of the depot: at least one, at most vehicles; as many back"
	row := Array new: nv withAll: 0.
	1 to: n do: [:j | row at: (index at: 0 -> j) put: 1].
	rows add: row. senses nextPut: $L. rhs add: vehicles.
	rows add: row copy. senses nextPut: $G. rhs add: 1.
	row := Array new: nv withAll: 0.
	1 to: n do: [:j | row at: (index at: 0 -> j) put: 1. row at: (index at: j -> 0) put: -1].
	rows add: row. senses nextPut: $E. rhs add: 0.
	"loads (Miller-Tucker-Zemlin): u(i) - u(j) + q x(i, j) <= q - 1"
	1 to: n do: [:i | 1 to: n do: [:j |
		i = j ifFalse: [
			row := Array new: nv withAll: 0.
			row at: legs size + i put: 1.
			row at: legs size + j put: -1.
			row at: (index at: i -> j) put: q.
			rows add: row. senses nextPut: $L. rhs add: q - 1]]].
	^{objective.
		rows asArray.
		senses contents.
		rhs asArray.
		self lowerBounds: nv legs: legs size.
		(1 to: nv) collect: [:k | k <= legs size ifTrue: [1] ifFalse: [q]].
		(String new: legs size withAll: $I) , (String new: n withAll: $C)}
!
lowerBounds: nv legs: m
	"0 for the legs, 1 for the loads."
	^(1 to: nv) collect: [:k | k <= m ifTrue: [0] ifFalse: [1]]
! !

!CuOptRouting methodsFor: 'solving'!
solve
	"Solve on the GPU (blocks for at most timeLimit seconds, a little more the first time); answer the CuOptResult."
	| p |
	stops isEmpty ifTrue: [routes := #(). ^result := nil].
	p := self program.
	result := CuOpt solve: (p at: 1) sense: #minimize rows: (p at: 2) senses: (p at: 3) rhs: (p at: 4)
		lower: (p at: 5) upper: (p at: 6) types: (p at: 7) timeLimit: timeLimit.
	routes := result hasSolution ifTrue: [self routesFrom: result values] ifFalse: [nil].
	^result
!
routesFrom: values
	"Follow the legs chosen (x > 0.5) from the depot."
	| legs next out list |
	legs := self legs.
	next := Dictionary new.
	out := OrderedCollection new.
	legs doWithIndex: [:leg :k |
		(values at: k) > 0.5 ifTrue: [
			leg key = 0 ifTrue: [out add: leg value] ifFalse: [next at: leg key put: leg value]]].
	^(out collect: [:first | | node seen |
		list := OrderedCollection new.
		seen := Set new.
		node := first.
		[node ~= 0 and: [(seen includes: node) not]] whileTrue: [
			list add: node. seen add: node.
			node := next at: node ifAbsent: [0]].
		list asArray]) asArray
!
distanceOf: aRoute
	| d prev |
	d := 0.
	prev := 0.
	aRoute do: [:i | d := d + (self distanceFrom: prev to: i). prev := i].
	^d + (self distanceFrom: prev to: 0)
!
totalDistance
	routes isNil ifTrue: [^nil].
	^routes inject: 0 into: [:sum :r | sum + (self distanceOf: r)]
!
visitsEveryStop
	"Whether the routes visit each stop exactly once."
	| all |
	routes isNil ifTrue: [^false].
	all := OrderedCollection new.
	routes do: [:r | all addAll: r].
	^all size = stops size and: [all asSet size = stops size]
! !
