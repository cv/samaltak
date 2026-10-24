"
Ported from the adapted JavaScript and Java versions.

Copyright (c) 2001-2010, Purdue University. All rights reserved.
Copyright (C) 2015 Apple Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
 * Neither the name of the Purdue University nor the
   names of its contributors may be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 'AS IS' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"!

Object subclass: #Aircraft
	instanceVariableNames: 'callsign position'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #CD
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #CallSign
	instanceVariableNames: 'value'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Collision
	instanceVariableNames: 'aircraftA aircraftB position'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #CollisionDetector
	instanceVariableNames: 'state'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Constants
	instanceVariableNames: ''
	classVariableNames: 'horizontal vertical'
	package: 'AWFY'!

Object subclass: #InsertResult
	instanceVariableNames: 'isNewEntry newNode oldValue'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Motion
	instanceVariableNames: 'callsign posOne posTwo'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Node
	instanceVariableNames: 'key value left right parent color'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RbtEntry
	instanceVariableNames: 'key value'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #RedBlackTree
	instanceVariableNames: 'root'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #CDSimulator
	instanceVariableNames: 'aircrafts'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Vector2D
	instanceVariableNames: 'x y'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Vector3D
	instanceVariableNames: 'x y z'
	classVariableNames: ''
	package: 'AWFY'!

!Aircraft methodsFor: 'benchmarking'!
init: aCallsign pos: aPosition
	callsign := aCallsign.
	position := aPosition.
!
callsign
	^ callsign
!
position
	^ position
! !

!Aircraft class methodsFor: 'benchmarking'!
new: callsign pos: position
	^ self new init: callsign pos: position
! !

!CD methodsFor: 'benchmarking'!
benchmark: numAircrafts
	| numFrames simulator detector actualCollisions |
	numFrames := 200.

	simulator := CDSimulator new: numAircrafts.
	detector  := CollisionDetector new.

	actualCollisions := 0.

	0 to: numFrames - 1 do: [:i |
	  | time collisions |
	  time := i / 10.0.
	  collisions := detector handleNewFrame: (simulator simulate: time).
	  actualCollisions := actualCollisions + collisions size ].

	^ actualCollisions
!
innerBenchmarkLoop: innerIterations
	^ self verify: (self benchmark: innerIterations) resultFor: innerIterations
!
verify: actualCollisions resultFor: numAircrafts
	numAircrafts = 1000 ifTrue: [ ^ actualCollisions = 14484 ].
	numAircrafts =  500 ifTrue: [ ^ actualCollisions = 14484 ].
	numAircrafts =  250 ifTrue: [ ^ actualCollisions = 10830 ].
	numAircrafts =  200 ifTrue: [ ^ actualCollisions =  8655 ].
	numAircrafts =  100 ifTrue: [ ^ actualCollisions =  4305 ].
	numAircrafts =   10 ifTrue: [ ^ actualCollisions =   390 ].
	numAircrafts =    2 ifTrue: [ ^ actualCollisions =    42 ].

	ScriptConsole println: ('No verification result for ', numAircrafts asString, ' found.').
	ScriptConsole println: ('Result is: ', actualCollisions asString).
	^ false
! !

!CD class methodsFor: 'benchmarking'!
new
	Constants initialize.
	^ super new
! !

!CallSign methodsFor: 'benchmarking'!
init: val
	value := val
!
value
	^ value
!
compareTo: other
	^ value = other value
	    ifTrue:  [ 0 ]
	    ifFalse: [
	      value < other value ifTrue: [ -1 ] ifFalse: [ 1 ]]
! !

!CallSign class methodsFor: 'benchmarking'!
new: val
	^ self new init: val
! !

!Collision methodsFor: 'benchmarking'!
init: anA b: aB pos: aPos
	aircraftA := anA.
	aircraftB := aB.
	position  := aPos
!
aircraftA
	^ aircraftA
!
aircraftB
	^ aircraftB
!
position
	^ position
! !

!Collision class methodsFor: 'benchmarking'!
a: aircraftA b: aircraftB pos: position
	^ self new init: aircraftA b: aircraftB pos: position
! !

!CollisionDetector methodsFor: 'benchmarking'!
initialize
	state := RedBlackTree new
!
handleNewFrame: frame
	| motions seen toRemove allReduced collisions |
	motions := Vector new.
	seen := RedBlackTree new.

	frame forEach: [:aircraft |
	  | oldPosition newPosition |
	  oldPosition := state at: aircraft callsign put: aircraft position.
	  newPosition := aircraft position.
	  seen at: aircraft callsign put: true.

	  oldPosition ifNil: [
	    "Treat newly introduced aircraft as if they were stationary"
	    oldPosition := newPosition ].

	  motions append: (Motion new: aircraft callsign old: oldPosition new: newPosition) ].

	" Remove aircraft that are no longer present "
	toRemove := Vector new.
	state forEach: [:e |
	  (seen at: e key) ifFalse: [ toRemove append: e key ] ].

	toRemove forEach: [:e | state remove: e ].

	allReduced := self reduceCollisionSet: motions.
	collisions := Vector new.
	allReduced forEach: [:reduced |
	  1 to: reduced size do: [:i |
	    | motion1 |
	    motion1 := reduced at: i.
	    i + 1 to: reduced size do: [:j |
	      | motion2 collision |
	      motion2 := reduced at: j.
	      collision := motion1 findIntersection: motion2.
	      collision ifNotNil: [
	        collisions append: (Collision a: motion1 callsign b: motion2 callsign pos: collision) ] ] ] ].

	^ collisions
!
isInVoxel: voxel motion: motion
	| init fin v_s r v_x x0 xv v_y y0 yv low_x high_x low_y high_y |
	(voxel x > Constants MaxX or: [
	 voxel x < Constants MinX or: [
	 voxel y > Constants MaxY or: [
	 voxel y < Constants MinY ]]]) ifTrue: [ ^ false ].

	init := motion posOne.
	fin  := motion posTwo.

	v_s := Constants GoodVoxelSize.
	r   := Constants ProximityRadius / 2.0.

	v_x := voxel x.
	x0  := init x.
	xv  := fin x - init x.

	v_y := voxel y.
	y0  := init y.
	yv  := fin y - init y.

	xv = 0.0 "follow IEEE floating point semantics"
	  ifTrue:  [
	    low_x  := Float infinity.
	    high_x := Float infinity ]
	  ifFalse: [
	    low_x := (v_x - r - x0) / xv.
	    high_x := (v_x + v_s + r - x0) / xv ].

	xv < 0.0 ifTrue: [
	  | tmp |
	  tmp    := low_x.
	  low_x  := high_x.
	  high_x := tmp ].

	yv = 0.0 "follow IEEE floating point semantics"
	  ifTrue: [
	    low_y  := Float infinity.
	    high_y := Float infinity ]
	  ifFalse: [
	    low_y  := (v_y - r - y0) / yv.
	    high_y := (v_y + v_s + r - y0) / yv ].

	yv < 0.0 ifTrue: [
	  | tmp |
	  tmp    := low_y.
	  low_y  := high_y.
	  high_y := tmp ].

	^ (((xv = 0.0 and: [v_x <= (x0 + r) and: [(x0 - r) <= (v_x + v_s)]]) or: [ "no motion in x"
	    (low_x <= 1.0 and: [1.0 <= high_x]) or: [
	    (low_x <= 0.0 and: [0.0 <= high_x]) or: [
	    (0.0 <= low_x and: [high_x <= 1.0])]]]) and: [

	    (yv = 0.0 and: [v_y <= (y0 + r) and: [(y0 - r) <= (v_y + v_s)]]) or: [ "no motion in y"
	      (low_y <= 1.0 and: [1.0 <= high_y]) or: [
	      (low_y <= 0.0 and: [0.0 <= high_y]) or: [
	      (0.0   <= low_y and: [high_y <= 1.0])]]]]) and: [

	     xv = 0.0 or: [
	     yv = 0.0 or: [ "no motion in x or y or both"
	     (low_y <= high_x and: [high_x <= high_y]) or: [
	     (low_y <= low_x  and: [low_x <= high_y]) or: [
	     (low_x <= low_y  and: [high_y <= high_x]) ]]]]]
!
put: motion and: voxel into: voxelMap
	| array |
	array := voxelMap at: voxel.
	array ifNil: [
	  array := Vector new.
	  voxelMap at: voxel put: array ].
	array append: motion
!
recurse: voxelMap seen: seen voxel: nextVoxel motion: motion
	(self isInVoxel: nextVoxel motion: motion) ifFalse: [ ^ self ].
	(seen at: nextVoxel put: true) = true ifTrue: [ ^ self ].

	self put: motion and: nextVoxel into: voxelMap.

	self recurse: voxelMap seen: seen voxel: (nextVoxel minus: Constants horizontal) motion: motion.
	self recurse: voxelMap seen: seen voxel: (nextVoxel plus:  Constants horizontal) motion: motion.
	self recurse: voxelMap seen: seen voxel: (nextVoxel minus: Constants vertical)   motion: motion.
	self recurse: voxelMap seen: seen voxel: (nextVoxel plus:  Constants vertical)   motion: motion.
	self recurse: voxelMap seen: seen voxel: ((nextVoxel minus: Constants horizontal) minus: Constants vertical) motion: motion.
	self recurse: voxelMap seen: seen voxel: ((nextVoxel minus: Constants horizontal) plus:  Constants vertical) motion: motion.
	self recurse: voxelMap seen: seen voxel: ((nextVoxel plus:  Constants horizontal) minus: Constants vertical) motion: motion.
	self recurse: voxelMap seen: seen voxel: ((nextVoxel plus:  Constants horizontal) plus:  Constants vertical) motion: motion.
!
reduceCollisionSet: motions
	| voxelMap result |
	voxelMap := RedBlackTree new.
	motions forEach: [:motion | self draw: motion on: voxelMap ].

	result := Vector new.
	voxelMap forEach: [:e |
	  e value size > 1 ifTrue: [ result append: e value ] ].
	^ result
!
voxelHash: position
	| xDiv yDiv x y |
	xDiv := (position x / Constants GoodVoxelSize) asInteger.
	yDiv := (position y / Constants GoodVoxelSize) asInteger.

	x := Constants GoodVoxelSize * xDiv.
	y := Constants GoodVoxelSize * yDiv.

	position x < 0 ifTrue: [ x := x - Constants GoodVoxelSize ].
	position y < 0 ifTrue: [ y := y - Constants GoodVoxelSize ].

	^ Vector2D x: x y: y
!
draw: motion on: voxelMap
	| seen |
	seen := RedBlackTree new.
	self recurse: voxelMap seen: seen voxel: (self voxelHash: motion posOne) motion: motion
! !

!CollisionDetector class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

!Constants class methodsFor: 'benchmarking'!
initialize
	horizontal := Vector2D x: self GoodVoxelSize y: 0.0.
	vertical   := Vector2D x: 0.0 y: self GoodVoxelSize.
!
MinX
	^ 0.0
!
MinY
	^ 0.0
!
MaxX
	^ 1000.0
!
MaxY
	^ 1000.0
!
MinZ
	^ 0.0
!
MaxZ
	^ 10.0
!
ProximityRadius
	^ 1.0
!
GoodVoxelSize
	"ProximityRadius *" ^ 2.0
!
horizontal
	^ horizontal
!
vertical
	^ vertical
! !

!InsertResult methodsFor: 'benchmarking'!
init: aBool node: aNode value: val
	isNewEntry := aBool.
	newNode    := aNode.
	oldValue   := val.
!
isNewEntry
	^ isNewEntry
!
newNode
	^ newNode
!
oldValue
	^ oldValue
! !

!InsertResult class methodsFor: 'benchmarking'!
new: isNewEntry node: newNode value: oldValue
	^ self new init: isNewEntry node: newNode value: oldValue
! !

!Motion methodsFor: 'benchmarking'!
init: aCallsign old: aPosOne new: aPosTwo
	callsign := aCallsign.
	posOne   := aPosOne.
	posTwo   := aPosTwo.
!
callsign
	^ callsign
!
posOne
	^ posOne
!
posTwo
	^ posTwo
!
delta
	^ posTwo minus: posOne
!
findIntersection: other
	| init1 init2 vec1 vec2 radius a dist |
	init1 := posOne.
	init2 := other posOne.
	vec1  := self delta.
	vec2  := other delta.
	radius := Constants ProximityRadius.

	" this test is not geometrical 3-d intersection test, it takes the fact that the aircraft move
	   into account ; so it is more like a 4d test
	   (it assumes that both of the aircraft have a constant speed over the tested interval)

	   we thus have two points, each of them moving on its line segment at constant speed ; we are looking
	   for times when the distance between these two points is smaller than r

	   vec1 is vector of aircraft 1
	   vec2 is vector of aircraft 2

	   a = (V2 - V1)^T * (V2 - V1)"
	a := (vec2 minus: vec1) squaredMagnitude.

	a ~= 0.0 ifTrue: [
	  | b c discr v1 v2 |
	  "  we are first looking for instances of time when the planes are exactly r from each other
	     at least one plane is moving ; if the planes are moving in parallel, they do not have constant speed

	     if the planes are moving in parallel, then
	       if the faster starts behind the slower, we can have 2, 1, or 0 solutions
	       if the faster plane starts in front of the slower, we can have 0 or 1 solutions

	     if the planes are not moving in parallel, then

	     point P1 = I1 + vV1
	     point P2 = I2 + vV2
	       - looking for v, such that dist(P1,P2) = || P1 - P2 || = r

	     it follows that || P1 - P2 || = sqrt( < P1-P2, P1-P2 > )
	       0 = -r^2 + < P1 - P2, P1 - P2 >
	      from properties of dot product
	       0 = -r^2 + <I1-I2,I1-I2> + v * 2<I1-I2, V1-V2> + v^2 *<V1-V2,V1-V2>
	       so we calculate a, b, c - and solve the quadratic equation
	       0 = c + bv + av^2

	   b = 2 * <I1-I2, V1-V2>"
	  b := 2.0 * ((init1 minus: init2) dot: (vec1 minus: vec2)).

	  "c = -r^2 + (I2 - I1)^T * (I2 - I1)"
	  c := ((0.0 - radius) * radius) + ((init2 minus: init1) squaredMagnitude).

	  discr := (b * b) - (4.0 * a * c).
	  discr < 0.0 ifTrue: [ ^ nil ].

	  v1 := ((0.0 - b) - discr sqrt) / (2.0 * a).
	  v2 := ((0.0 - b) + discr sqrt) / (2.0 * a).

	  (v1 <= v2 and: [((v1  <= 1.0 and: [1.0 <= v2]) or: [
	                   (v1  <= 0.0 and: [0.0 <= v2]) or: [
	                   (0.0 <= v1  and: [v2  <= 1.0])]])]) ifTrue: [
	    "Pick a good 'time' at which to report the collision"
	    | v result1 result2 result |
	    v1 <= 0.0
	      ifTrue: [
	        "The collision started before this frame. Report it at the start of the frame"
	        v := 0.0 ]
	      ifFalse: [
	        "The collision started during this frame. Report it at that moment"
	        v := v1 ].

	    result1 := init1 plus: (vec1 times: v).
	    result2 := init2 plus: (vec2 times: v).

	    result := (result1 plus: result2) times: 0.5.

	    (result x >= Constants MinX and: [
	     result x <= Constants MaxX and: [
	     result y >= Constants MinY and: [
	     result y <= Constants MaxY and: [
	     result z >= Constants MinZ and: [
	     result z <= Constants MaxZ ]]]]]) ifTrue: [ ^ result ] ].

	  ^ nil ].

	"  the planes have the same speeds and are moving in parallel (or they are not moving at all)
	   they  thus have the same distance all the time ; we calculate it from the initial point

	   dist = || i2 - i1 || = sqrt(  ( i2 - i1 )^T * ( i2 - i1 ) )"
	dist := (init2 minus: init1) magnitude.
	dist <= radius ifTrue: [
	  ^ (init1 plus: init2) times: 0.5 ].

	^ nil
! !

!Motion class methodsFor: 'benchmarking'!
new: callsign old: posOne new: posTwo
	^ self new init: callsign old: posOne new: posTwo
! !

!Node methodsFor: 'benchmarking'!
init: aKey value: aValue
	key   := aKey.
	value := aValue.
	color := #red.
!
key
	^ key
!
value
	^ value
!
value: val
	value := val
!
left
	^ left
!
left: n
	left := n
!
right
	^ right
!
right: n
	right := n
!
parent
	^ parent
!
parent: n
	parent := n
!
color
	^ color
!
color: sym
	color := sym
!
successor
	| x y |
	x := self.
	x right ifNotNil: [
	  ^ RedBlackTree treeMinimum: x right ].

	y := x parent.
	[ y notNil and: [ x == y right ]] whileTrue: [
	  x := y.
	  y := y parent ].
	^ y
! !

!Node class methodsFor: 'benchmarking'!
key: key value: value
	^ self new init: key value: value
! !

!RbtEntry methodsFor: 'benchmarking'!
init: aKey value: val
	key   := aKey.
	value := val.
!
key
	^ key
!
value
	^ value
! !

!RbtEntry class methodsFor: 'benchmarking'!
key: key value: value
	^ self new init: key value: value
! !

!RedBlackTree methodsFor: 'benchmarking'!
at: key put: value
	| insertionResult x |
	insertionResult := self treeAt: key insert: value.
	insertionResult isNewEntry ifFalse: [
	  ^ insertionResult oldValue ].

	x := insertionResult newNode.

	[ x ~= root and: [ x parent color = #red ]] whileTrue: [
	  x parent == x parent parent left
	    ifTrue: [
	      | y |
	      y := x parent parent right.
	      (y notNil and: [ y color = #red ])
	        ifTrue: [
	          "Case 1"
	          x parent color: #black.
	          y color: #black.
	          x parent parent color: #red.
	          x := x parent parent ]
	        ifFalse: [
	          x == x parent right ifTrue: [
	            "Case 2"
	            x := x parent.
	            self leftRotate: x ].

	          "Case 3"
	          x parent color: #black.
	          x parent parent color: #red.
	          self rightRotate: x parent parent ] ]
	    ifFalse: [
	      "Same as 'then' clause with 'right' and 'left' exchanged"
	      | y |
	      y := x parent parent left.
	      (y notNil and: [ y color = #red ])
	        ifTrue: [
	          "Case 1"
	          x parent color: #black.
	          y color: #black.
	          x parent parent color: #red.
	          x := x parent parent ]
	        ifFalse: [
	          x == x parent left ifTrue: [
	            "Case 2"
	            x := x parent.
	            self rightRotate: x ].

	          "Case 3"
	          x parent color: #black.
	          x parent parent color: #red.
	          self leftRotate: x parent parent ] ] ].

	root color: #black.
	^ nil
!
remove: key
	| x y z xParent |
	z := self findNode: key.
	z ifNil: [ ^ nil ].

	"Y is the node to be unlinked from the tree."
	(z left isNil or: [ z right isNil ])
	  ifTrue:  [ y := z ]
	  ifFalse: [ y := z successor ].

	"Y is guaranteed to be non-null at this point."
	y left
	  ifNotNil: [ x := y left ]
	  ifNil:    [ x := y right ].

	"X is the child of y which might potentially replace y in the tree.
	 X might be null at this point."
	x ifNotNil: [
	    x parent: y parent.
	    xParent := x parent ]
	  ifNil: [
	    xParent := y parent ].

	y parent
	  ifNil: [ root := x ]
	  ifNotNil: [
	    y == y parent left
	      ifTrue:  [ y parent left: x ]
	      ifFalse: [ y parent right: x ] ].

	y ~= z ifTrue: [
	  y color = #black ifTrue: [
	    self remove: x andFixup: xParent ].

	  y parent: z parent.
	  y color:  z color.
	  y left:   z left.
	  y right:  z right.

	  z left ifNotNil: [
	    z left parent: y ].
	  x right ifNotNil: [
	    z right parent: y ].

	  z parent
	    ifNotNil: [
	      z parent left == z
	        ifTrue:  [ z parent left: y ]
	        ifFalse: [ z parent right: y ] ]
	    ifNil: [ root := y ] ]
	  ifFalse: [
	    y color = #black ifTrue: [
	      self remove: x andFixup: xParent ] ].

	^ z value
!
at: key
	| node |
	node := self findNode: key.
	node ifNil: [ ^ nil ].
	^ node value
!
forEach: block
	| current |
	root ifNil: [ ^ self ].
	current := RedBlackTree treeMinimum: root.
	[ current notNil ] whileTrue: [
	  block value: (RbtEntry key: current key value: current value).
	  current := current successor ].
!
findNode: key
	| current |
	current := root.
	[ current notNil ] whileTrue: [
	  | comparisonResult |
	  comparisonResult := key compareTo: current key.
	  comparisonResult = 0 ifTrue: [ ^ current ].
	  comparisonResult < 0
	    ifTrue:  [ current := current left ]
	    ifFalse: [ current := current right ] ].
	^ nil
!
treeAt: key insert: value
	| x y z |
	y := nil.
	x := root.

	[ x notNil ] whileTrue: [
	  | comparisonResult |
	  y := x.
	  comparisonResult := key compareTo: x key.
	  comparisonResult < 0
	    ifTrue:  [ x := x left ]
	    ifFalse: [
	      comparisonResult > 0
	        ifTrue: [ x := x right ]
	        ifFalse: [
	          | oldValue |
	          oldValue := x value.
	          x value: value.
	          ^ InsertResult new: false node: nil value: oldValue ] ] ].

	z := Node key: key value: value.
	z parent: y.
	y ifNil: [ root := z ]
	  ifNotNil: [
	    (key compareTo: y key) < 0
	      ifTrue:  [ y left: z ]
	      ifFalse: [ y right: z ] ].

	^ InsertResult new: true node: z value: nil
!
leftRotate: x
	| y |
	y := x right.

	"Turn y's left subtree into x's right subtree"
	x right: y left.
	y left ifNotNil: [
	  y left parent: x ].

	"Link x's parent to y"
	y parent: x parent.
	x parent
	  ifNil: [ root := y ]
	  ifNotNil: [
	    x == x parent left ifTrue:  [ x parent left: y ]
	                       ifFalse: [ x parent right: y ] ].

	"Put x on y's left"
	y left: x.
	x parent: y.
	^ y
!
rightRotate: y
	| x |
	x := y left.

	"Turn x's right subtree into y's left subtree"
	y left: x right.
	x right ifNotNil: [ x right parent: y ].

	"Link y's parent to x"
	x parent: y parent.
	y parent
	  ifNil: [ root := x ]
	  ifNotNil: [
	    y == y parent left
	      ifTrue: [ y parent left: x ]
	      ifFalse: [ y parent right: x ] ].

	x right: y.
	y parent: x.
	^ x
!
remove: anX andFixup: anXParent
	| x xParent |
	x := anX.
	xParent := anXParent.

	(x ~= root and: [ x isNil or: [ x color = #black ]]) whileTrue: [
	  x == xParent left
	    ifTrue: [
	      | w |
	       "Note: the text points out that w cannot be null. The reason is not obvious from
	        simply looking at the code; it comes about from the properties of the red-black
	        tree."
	      w := xParent right.
	      w color = #red ifTrue: [
	        "Case 1"
	        w color: #black.
	        xParent color: #red.
	        self leftRotate: xParent.
	        w := xParent right ].

	      ((w left isNil or: [ w left color = #black ]) and: [
	        w right isNil or: [ w right color = #black ]])
	        ifTrue:  [
	          "Case 2"
	          w color: #red.
	          x := xParent.
	          xParent := x parent ]
	        ifFalse: [
	          (w right isNil or: [ w right color = #black ]) ifTrue: [
	            "Case 3"
	            w left color: #black.
	            w color: #red.
	            self rightRotate: w.
	            w := xParent right ].

	          "Case 4"
	          w color: xParent color.
	          xParent color: #black.
	          w right ifNotNil: [
	            w right color: #black ].

	          self leftRotate: xParent.
	          x := root.
	          xParent := x parent ] ]
	    ifFalse: [
	      | w |
	      "Same as 'then' clause with 'right' and 'left' exchanged"
	      w := xParent left.
	      w color = #red ifTrue: [
	        "Case 1"
	        w color: #black.
	        xParent color: #red.
	        self rightRotate: xParent.
	        w := xParent left ].

	      ((w right isNil or: [ w right color = #black ]) and: [
	       (w left isNil or: [ w left color = #black ])])
	        ifTrue: [
	          "Case 2"
	          w color: #red.
	          x := xParent.
	          xParent := x parent ]
	        ifFalse: [
	          w left isNil or: [ w left color = #black ] ifTrue: [
	            "Case 3"
	            w right color: #black.
	            w color: #red.
	            self leftRotate: w.
	            w := xParent left ].

	          "Case 4"
	          w color: xParent color.
	          xParent color: #black.
	          w left ifNotNil: [
	            w left color: #black ].

	          self rightRotate: xParent.
	          x := root.
	          xParent = x parent ] ] ].

	x ifNotNil: [ x color: #black ]
! !

!RedBlackTree class methodsFor: 'benchmarking'!
treeMinimum: x
	| current |
	current := x.
	[ current left notNil ] whileTrue: [
	  current := current left ].
	^ current
! !

!CDSimulator methodsFor: 'benchmarking'!
init: numAircrafts
	aircrafts := Vector new.

	0 to: numAircrafts - 1 do: [:i |
	  aircrafts append: (CallSign new: i)]
!
simulate: time
	| frame |
	frame := Vector new.
	0 to: aircrafts size - 2 by: 2 do: [:i |
	  frame append: (Aircraft new: (aircrafts at: i + 1)
	                          pos: (Vector3D x: time
	                                         y: (time cos * 2.0) + (i * 3.0)
	                                         z: 10.0)).
	  frame append: (Aircraft new: (aircrafts at: i + 2)
	                          pos: (Vector3D x: time
	                                         y: (time sin * 2.0) + (i * 3.0)
	                                         z: 10.0)) ].
	^ frame
! !

!CDSimulator class methodsFor: 'benchmarking'!
new: numAircrafts
	^ self new init: numAircrafts
! !

!Vector2D methodsFor: 'benchmarking'!
x
	^ x
!
y
	^ y
!
initX: anX y: aY
	x := anX.
	y := aY
!
plus: other
	^ Vector2D x: x + other x
	           y: y + other y
!
minus: other
	^ Vector2D x: x - other x
	           y: y - other y
!
compareTo: other
	| result |
	result := self compare: x and: other x.
	result ~= 0 ifTrue: [ ^ result ].
	^ self compare: y and: other y
!
compare: a and: b
	a = b ifTrue: [ ^  0 ].
	a < b ifTrue: [ ^ -1 ].
	a > b ifTrue: [ ^  1 ].

	"We say that NaN is smaller than non-NaN."
	a = a ifTrue: [ ^ 1 ].
	^ -1
! !

!Vector2D class methodsFor: 'benchmarking'!
x: anX y: aY
	^ self new initX: anX y: aY
! !

!Vector3D methodsFor: 'benchmarking'!
x
	^ x
!
y
	^ y
!
z
	^ z
!
initX: anX y: aY z: aZ
	x := anX.
	y := aY.
	z := aZ
!
plus: other
	^ Vector3D x: x + other x
	           y: y + other y
	           z: z + other z
!
minus: other
	^ Vector3D x: x - other x
	           y: y - other y
	           z: z - other z
!
dot: other
	^ (x * other x) + (y * other y) + (z * other z)
!
squaredMagnitude
	^ self dot: self
!
magnitude
	^ self squaredMagnitude sqrt
!
times: amount
	^ Vector3D x: x * amount
	           y: y * amount
	           z: z * amount
! !

!Vector3D class methodsFor: 'benchmarking'!
x: x y: y z: z
	^ self new initX: x y: y z: z
! !

