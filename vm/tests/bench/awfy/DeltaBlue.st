"This benchmark is derived from Mario Wolczko's Smalltalk version of DeltaBlue.

It is modified to use the SOM class library.
License details:

http://web.archive.org/web/20050825101121/http://www.sunlabs.com/people/mario/java_benchmarking/index.html
"!

"
This benchmark is derived from Mario Wolczko's Smalltalk version of DeltaBlue.

It is modified to use the SOM class library.
License details:

http://web.archive.org/web/20050825101121/http://www.sunlabs.com/people/mario/java_benchmarking/index.html

Original comment.
	NAME		DeltaBlue benchmark
	AUTHOR		John Maloney, heavily modified by Mario Wolczko	(Mario.Wolczko@sun.com)
	FUNCTION	Language implementation benchmark
	ST-VERSION	4.1
	PREREQUISITES	
	CONFLICTS	
	DISTRIBUTION	world
	VERSION		1
	DATE	 	2 Oct 1996
SUMMARY
This benchmark is an implementation of the DeltaBlue Constraint Solver
described in `The DeltaBlue Algorithm: An Incremental Constraint
Hierarchy Solver', by Bjorn N. Freeman-Benson and John Maloney,
Communications of the ACM, January 1990 (also as University of
Washington TR 89-08-06)
"!

"
Copyright (c) 2016 see AUTHORS.md file

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the 'Software'), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
"!

Object subclass: #AbstractConstraint
	instanceVariableNames: 'strength'
	classVariableNames: ''
	package: 'AWFY'!

AbstractConstraint subclass: #BinaryConstraint
	instanceVariableNames: 'v1 v2 direction'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #DBVariable
	instanceVariableNames: 'value constraints determinedBy walkStrength stay mark'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #DeltaBlue
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

AbstractConstraint subclass: #UnaryConstraint
	instanceVariableNames: 'output satisfied'
	classVariableNames: ''
	package: 'AWFY'!

UnaryConstraint subclass: #EditConstraint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

BinaryConstraint subclass: #EqualityConstraint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Vector subclass: #Plan
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Planner
	instanceVariableNames: 'currentMark'
	classVariableNames: ''
	package: 'AWFY'!

BinaryConstraint subclass: #ScaleConstraint
	instanceVariableNames: 'scale offset'
	classVariableNames: ''
	package: 'AWFY'!

UnaryConstraint subclass: #StayConstraint
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Strength
	instanceVariableNames: 'symbolicValue arithmeticValue'
	classVariableNames: 'AbsoluteStrongest AbsoluteWeakest Required StrengthConstants StrengthTable SymAbsoluteStrongest SymRequired SymStrongPreferred SymPreferred SymStrongDefault SymDefault SymWeakDefault SymAbsoluteWeakest'
	package: 'AWFY'!

Object subclass: #Sym
	instanceVariableNames: 'hash'
	classVariableNames: ''
	package: 'AWFY'!

!AbstractConstraint methodsFor: 'benchmarking'!
initialize: strengthSymbol
	strength := Strength of: strengthSymbol
!
strength
	"Answer my strength."
	^ strength
!
isInput
	"Normal constraints are not input constraints. An input constraint is
	 one that depends on external state, such as the mouse, the keyboard,
	 a clock, or some arbitrary piece of imperative code."
	^ false
!
isSatisfied
	"Answer true if this constraint is satisfied in the current solution."
	self subclassResponsibility
!
addConstraint: planner
	"Activate this constraint and attempt to satisfy it."

	self addToGraph.
	planner incrementalAdd: self.
!
addToGraph
	"Add myself to the constraint graph."
	self subclassResponsibility
!
destroyConstraint: planner
	"Deactivate this constraint, remove it from the constraint graph,
	 possibly causing other constraints to be satisfied, and destroy it."

	self isSatisfied ifTrue: [planner incrementalRemove: self].
	self removeFromGraph.
!
removeFromGraph
	"Remove myself from the constraint graph."
	self subclassResponsibility
!
chooseMethod: mark
	"Decide if I can be satisfied and record that decision. The output of
	 the chosen method must not have the given mark and must have a
	 walkabout strength less than that of this constraint."
	self subclassResponsibility
!
execute
	"Enforce this constraint. Assume that it is satisfied."
	self subclassResponsibility
!
inputsDo: aBlock
	"Assume that I am satisfied. Evaluate the given block on all my current
	 input variables."
	self subclassResponsibility
!
inputsKnown: mark
	"Assume that I am satisfied. Answer true if all my current inputs are
	 known. A variable is known if either a) it is 'stay' (i.e. it is a
	 constant at plan execution time), b) it has the given mark (indicating
	 that it has been computed by a constraint appearing earlier in the
	 plan), or c) it is not determined by any constraint."

	^ (self inputsHasOne: [:v |
	   (v mark = mark or: [v stay or: [v determinedBy == nil]]) not ]) not
!
markUnsatisfied
	"Record the fact that I am unsatisfied."
	self subclassResponsibility
!
output
	"Answer my current output variable. Raise an error if I am not
	 currently satisfied."
	self subclassResponsibility
!
recalculate
	"Calculate the walkabout strength, the stay flag, and, if it is 'stay',
	 the value for the current output of this constraint. Assume this
	 constraint is satisfied."
	self subclassResponsibility
!
satisfy: mark propagate: planner
	"Attempt to find a way to enforce this (still unsatisfied) constraint.
	 If successful, record the solution, perhaps modifying the current
	 dataflow graph.  Answer the constraint that this constraint overrides,
	 if there is one, or nil, if there isn't."

	| overridden |
	self chooseMethod: mark.
	self isSatisfied
	    ifTrue:         "constraint can be satisfied"
	        ["mark inputs to allow cycle detection in addPropagate"
	         | out |
	         self inputsDo: [: in | in mark: mark].
	         out := self output.
	         overridden := out determinedBy.
	         (overridden == nil) ifFalse: [overridden markUnsatisfied].
	         out determinedBy: self.
	         (planner addPropagate: self mark: mark) ifFalse:
	            [self error: 'Cycle encountered adding:\tConstraint removed.'.
	             ^nil].
	         out mark: mark]
	    ifFalse:            "constraint cannot be satisfied"
	        [overridden := nil.
	         (strength sameAs: (Strength required)) ifTrue:
	            [self error: 'Failed to satisfy a required constraint']].
	^ overridden
! !

!BinaryConstraint methodsFor: 'benchmarking'!
initializeVar: variable1 var: variable2 strength: strengthSymbol addTo: planner
	"Initialize myself with the given variables and strength."
	super initialize: strengthSymbol.

	v1 := variable1.
	v2 := variable2.
	direction := nil.
!
isSatisfied
	"Answer true if this constraint is satisfied in the current solution."

	^ direction notNil
!
addToGraph
	"Add myself to the constraint graph."
	v1 addConstraint: self.
	v2 addConstraint: self.
	direction := nil
!
removeFromGraph
	"Remove myself from the constraint graph."
	(v1 == nil) ifFalse: [v1 removeConstraint: self].
	(v2 == nil) ifFalse: [v2 removeConstraint: self].
	direction := nil.
!
chooseMethod: mark
	"Decide if I can be satisfied and which way I should flow based on
	 the relative strength of the variables I relate, and record that
	 decision."

	(v1 mark = mark) ifTrue:       "forward or nothing"
	    [((v2 mark ~= mark) and: [strength stronger: v2 walkStrength])
	        ifTrue:  [ ^ direction := #forward ]
	        ifFalse: [ ^ direction := nil ] ].

	(v2 mark = mark) ifTrue:       "backward or nothing"
	    [((v1 mark ~= mark) and: [strength stronger: v1 walkStrength])
	        ifTrue:  [ ^ direction := #backward ]
	        ifFalse: [ ^ direction := nil ] ].

	"if we get here, neither variable is marked, so we have choice"
	(v1 walkStrength weaker: v2 walkStrength)
	    ifTrue:
	        [(strength stronger: v1 walkStrength)
	            ifTrue:  [ ^ direction := #backward ]
	            ifFalse: [ ^ direction := nil ] ]
	    ifFalse:
	        [(strength stronger: v2 walkStrength)
	            ifTrue:  [ ^ direction := #forward ]
	            ifFalse: [ ^ direction := nil ] ].
!
execute
	"Enforce this constraint. Assume that it is satisfied."
	self subclassResponsibility
!
inputsDo: aBlock
	"Evaluate the given block on my current input variable."
	direction = #forward
	  ifTrue:  [ aBlock value: v1 ]
	  ifFalse: [ aBlock value: v2 ].
!
inputsHasOne: aBlock
	^ direction = #forward
	    ifTrue:  [ aBlock value: v1 ]
	    ifFalse: [ aBlock value: v2 ]
!
markUnsatisfied
	"Record the fact that I am unsatisfied."
	direction := nil.
!
output
	"Answer my current output variable."
	(direction == #forward)
	    ifTrue:  [ ^ v2 ]
	    ifFalse: [ ^ v1 ]
!
recalculate
	"Calculate the walkabout strength, the stay flag, and, if it is 'stay',
	     the value for the current output of this constraint. Assume this
	 constraint is satisfied."

	| in out |
	(direction = #forward)
	    ifTrue:  [ in := v1. out := v2 ]
	    ifFalse: [ in := v2. out := v1 ].
	out walkStrength: (strength weakest: in walkStrength).
	out stay: in stay.
	out stay ifTrue: [self execute].      "stay optimization"
! !

!DBVariable methodsFor: 'benchmarking'!
initialize
	value := 0.
	constraints  := Vector new: 2.
	determinedBy := nil.
	walkStrength := Strength absoluteWeakest.
	stay := true.
	mark := 0.
!
addConstraint: aConstraint
	"Add the given constraint to the set of all constraints that refer
	 to me."

	constraints append: aConstraint.
!
constraints
	"Answer the set of constraints that refer to me."
	^ constraints
!
determinedBy
	"Answer the constraint that determines my value in the current
	 dataflow."
	^ determinedBy
!
determinedBy: aConstraint
	"Record that the given constraint determines my value in the current
	 data flow."
	determinedBy := aConstraint.
!
mark
	"Answer my mark value."
	^ mark
!
mark: markValue
	"Set my mark value."
	mark := markValue.
!
removeConstraint: c
	"Remove all traces of c from this variable."
	constraints remove: c.
	determinedBy == c ifTrue: [ determinedBy := nil ].
!
stay
	"Answer my stay flag."
	^ stay
!
stay: aBoolean
	"Set my stay flag."
	stay := aBoolean
!
value
	"Answer my value."
	^ value
!
value: anObject
	"Set my value."
	value := anObject.
!
walkStrength
	"Answer my walkabout strength in the current dataflow."
	^ walkStrength
!
walkStrength: aStrength
	"Set my walkabout strength in the current dataflow."
	walkStrength := aStrength.
! !

!DBVariable class methodsFor: 'benchmarking'!
new
	^ super new initialize
!
value: aValue
	| o |
	o := self new.
	o value: aValue.
	^ o
! !

!DeltaBlue methodsFor: 'benchmarking'!
innerBenchmarkLoop: innerIterations
	Planner chainTest: innerIterations.
	Planner projectionTest: innerIterations.
	^ true
! !

!DeltaBlue class methodsFor: 'benchmarking'!
new
	Strength initialize.
	^ super new
! !

!UnaryConstraint methodsFor: 'benchmarking'!
initializeVar: aDBVariable strength: strengthSymbol addTo: planner
	"Initialize myself with the given variable and strength."
	super initialize: strengthSymbol.
	output := aDBVariable.
	satisfied := false.
	self addConstraint: planner.
!
isSatisfied
	"Answer true if this constraint is satisfied in the current solution."
	^ satisfied
!
addToGraph
	"Add myself to the constraint graph."
	output addConstraint: self.
	satisfied := false.
!
removeFromGraph
	"Remove myself from the constraint graph."
	output == nil ifFalse: [output removeConstraint: self].
	satisfied := false.
!
chooseMethod: mark
	"Decide if I can be satisfied and record that decision."

	satisfied :=
	    output mark ~= mark and:
	    [strength stronger: output walkStrength].
	^ nil
!
execute
	"Enforce this constraint. Assume that it is satisfied."
	self subclassResponsibility
!
inputsDo: aBlock
	"I have no input variables."
!
inputsHasOne: aBlock
	^ false
!
markUnsatisfied
	"Record the fact that I am unsatisfied."
	satisfied := false.
!
output
	"Answer my current output variable."
	^ output
!
recalculate
	"Calculate the walkabout strength, the stay flag, and, if it is 'stay',
	 the value for the current output of this constraint. Assume this
	 constraint is satisfied."

	output walkStrength: strength.
	output stay: self isInput not.
	output stay ifTrue: [self execute].   "stay optimization"
! !

!EditConstraint methodsFor: 'benchmarking'!
isInput
	"I indicate that a variable is to be changed by imperative code."
	^ true
!
execute
	"Edit constraints do nothing."
! !

!EditConstraint class methodsFor: 'benchmarking'!
var: aDBVariable strength: strengthSymbol addTo: planner
	"Install an edit constraint with the given strength on the given
	 variable."

	^ self new initializeVar: aDBVariable strength: strengthSymbol addTo: planner
! !

!EqualityConstraint methodsFor: 'benchmarking'!
initializeVar: variable1 var: variable2 strength: strengthSymbol addTo: planner
	super initializeVar: variable1 var: variable2 strength: strengthSymbol addTo: planner.
	self addConstraint: planner.
!
execute
	"Enforce this constraint. Assume that it is satisfied."
	direction = #forward
	  ifTrue:  [ v2 value: v1 value ]
	  ifFalse: [ v1 value: v2 value ].
! !

!EqualityConstraint class methodsFor: 'benchmarking'!
var: variable1 var: variable2 strength: strengthSymbol addTo: planner
	"Install a constraint with the given strength equating the given
	 variables."

	^ self new initializeVar: variable1 var: variable2 strength: strengthSymbol addTo: planner
! !

!Plan methodsFor: 'benchmarking'!
execute
	"Execute my constraints in order."

	self forEach: [: c | c execute ]
! !

!Plan class methodsFor: 'benchmarking'!
new
	^ self new: 15
! !

!Planner methodsFor: 'benchmarking'!
initialize
	currentMark := 1
!
incrementalAdd: c
	"Attempt to satisfy the given constraint and, if successful,
	 incrementally update the dataflow graph.

	 Details: If satifying the constraint is successful, it may override a
	 weaker constraint on its output. The algorithm attempts to resatisfy
	 that constraint using some other method. This process is repeated
	 until either a) it reaches a variable that was not previously
	 determined by any constraint or b) it reaches a constraint that
	 is too weak to be satisfied using any of its methods. The variables
	 of constraints that have been processed are marked with a unique mark
	 value so that we know where we've been. This allows the algorithm to
	 avoid getting into an infinite loop even if the constraint graph has
	 an inadvertent cycle."

	| mark overridden |
	mark := self newMark.
	overridden := c satisfy: mark propagate: self.
	[overridden == nil] whileFalse:
	    [overridden := overridden satisfy: mark propagate: self]
!
incrementalRemove: c
	"Entry point for retracting a constraint. Remove the given constraint,
	 which should be satisfied, and incrementally update the dataflow
	 graph.

	 Details: Retracting the given constraint may allow some currently
	 unsatisfiable downstream constraint be satisfied. We thus collect a
	 list of unsatisfied downstream constraints and attempt to satisfy
	 each one in turn. This list is sorted by constraint strength,
	 strongest first, as a heuristic for avoiding unnecessarily adding
	 and then overriding weak constraints."

	| out unsatisfied |
	out := c output.
	c markUnsatisfied.
	c removeFromGraph.
	unsatisfied := self removePropagateFrom: out.
	unsatisfied forEach: [: u | self incrementalAdd: u]
!
extractPlanFromConstraints: constraints
	"Extract a plan for resatisfaction starting from the outputs of the
	 given constraints, usually a set of input constraints."

	| sources |
	sources := Vector new.
	constraints forEach: [: c |
	  (c isInput and: [c isSatisfied]) ifTrue: [sources append: c]].
	^ self makePlan: sources
!
makePlan: sources
	"Extract a plan for resatisfaction starting from the given satisfied
	 source constraints, usually a set of input constraints. This method
	 assumes that stay optimization is desired; the plan will contain only
	 constraints whose output variables are not stay. Constraints that do
	 no computation, such as stay and edit constraints, are not included
	 in the plan.

	 Details: The outputs of a constraint are marked when it is added to
	 the plan under construction. A constraint may be appended to the plan
	 when all its input variables are known. A variable is known if either
	 a) the variable is marked (indicating that has been computed by a
	 constraint appearing earlier in the plan), b) the variable is 'stay'
	 (i.e. it is a constant at plan execution time), or c) the variable
	 is not determined by any constraint. The last provision is for past
	 states of history variables, which are not stay but which are also
	 not computed by any constraint."

	| mark plan todo c |
	mark := self newMark.
	plan := Plan new.
	todo := sources.
	[todo isEmpty] whileFalse:
	    [c := todo removeFirst.
	     ((c output mark ~= mark) and:      "not in plan already and..."
	      [c inputsKnown: mark]) ifTrue:    "eligible for inclusion"
	        [plan append: c.
	         c output mark: mark.
	         self addConstraintsConsuming: c output to: todo]].
	^ plan
!
propagateFrom: v
	"The given variable has changed. Propagate new values downstream."
	| todo c |
	todo := Vector new.
	self addConstraintsConsuming: v to: todo.
	[todo isEmpty] whileFalse:
	  [c := todo removeFirst.
	   c execute.
	   self addConstraintsConsuming: c output to: todo].
!
addConstraintsConsuming: v to: aCollection
	| determiningC |
	determiningC := v determinedBy.
	v constraints forEach: [: c |
	  ((c == determiningC) or: [c isSatisfied not]) ifFalse:
	    [aCollection append: c]].
!
addPropagate: c mark: mark
	"Recompute the walkabout strengths and stay flags of all variables
	 downstream of the given constraint and recompute the actual values
	 of all variables whose stay flag is true. If a cycle is detected,
	 remove the given constraint and answer false. Otherwise, answer true.

	 Details: Cycles are detected when a marked variable is encountered
	 downstream of the given constraint. The sender is assumed to have
	 marked the inputs of the given constraint with the given mark. Thus,
	 encountering a marked node downstream of the output constraint means
	 that there is a path from the constraint's output to one of its
	 inputs."

	| todo d |
	todo := Vector with: c.
	[todo isEmpty] whileFalse:
	  [d := todo removeFirst.
	   (d output mark = mark) ifTrue:
	    [self incrementalRemove: c.
	     ^ false].
	   d recalculate.
	   self addConstraintsConsuming: d output to: todo].
	^ true
!
changeVar: aDBVariable newValue: newValue
	| editConstraint plan |
	editConstraint := EditConstraint var: aDBVariable strength: Strength SymPreferred addTo: self.
	plan := self extractPlanFromConstraints: (Vector with: editConstraint).
	10 timesRepeat: [
	  aDBVariable value: newValue.
	  plan execute ].
	editConstraint destroyConstraint: self.
!
constraintsConsuming: v do: aBlock
	| determiningC |
	determiningC := v determinedBy.
	v constraints forEach: [: c |
	 (c == determiningC or: [c isSatisfied not]) ifFalse:
	  [aBlock value: c]].
!
newMark
	"Select a previously unused mark value.

	 Details: We just keep incrementing. If necessary, the counter will
	 turn into a LargePositiveInteger. In that case, it will be a bit
	 slower to compute the next mark but the algorithms will all behave
	 correctly. We reserve the value '0' to mean 'unmarked'. Thus, this
	 generator starts at '1' and will never produce '0' as a mark value."

	^ currentMark := currentMark + 1
!
removePropagateFrom: out
	"Update the walkabout strengths and stay flags of all variables
	 downstream of the given constraint. Answer a collection of unsatisfied
	 constraints sorted in order of decreasing strength."

	| unsatisfied todo v |
	unsatisfied := Vector new.

	out determinedBy: nil.
	out walkStrength: Strength absoluteWeakest.
	out stay: true.
	todo := Vector with: out.
	[todo isEmpty] whileFalse: [
	  v := todo removeFirst.
	   v constraints forEach: [:c |
	     c isSatisfied ifFalse: [unsatisfied append: c]].
	   self constraintsConsuming: v do: [:c |
	     c recalculate.
	     todo append: c output]].

	unsatisfied sort: [:c1 :c2 | c1 strength stronger: c2 strength].
	^ unsatisfied
! !

!Planner class methodsFor: 'benchmarking'!
new
	^ super new initialize
!
chainTest: n
	"Do chain-of-equality-constraints performance tests."
	| vars editConstraint plan planner |

	planner := Planner new.
	vars := Array new: n+1.
	1 to: n+1 do: [:i |
	  vars at: i put: DBVariable new ].

	"thread a chain of equality constraints through the variables"
	1 to: n do: [ :i |
	  | v1 v2 |
	  v1 := vars at: i.
	  v2 := vars at: i + 1.
	  EqualityConstraint var: v1 var: v2 strength: Strength SymRequired addTo: planner].

	StayConstraint var: vars last strength: Strength SymStrongDefault addTo: planner.
	editConstraint := EditConstraint var: vars first strength: Strength SymPreferred addTo: planner.
	plan := planner extractPlanFromConstraints: (Vector with: editConstraint).

	1 to: 100 do: [ :v |
	  vars first value: v.
	  plan execute.
	  vars last value ~= v ifTrue: [self error: 'Chain test failed!!!!']].

	editConstraint destroyConstraint: planner
!
projectionTest: n
	"This test constructs a two sets of variables related to each other by
	 a simple linear transformation (scale and offset)."

	| scale offset src dst planner dests |
	planner := Planner new.
	dests   := Vector new.
	scale   := DBVariable value: 10.
	offset  := DBVariable value: 1000.

	1 to: n do: [ :i |
	  src := DBVariable value: i.
	  dst := DBVariable value: i.
	  dests append: dst.
	  StayConstraint  var: src strength: Strength SymDefault addTo: planner.
	  ScaleConstraint var: src var: scale var: offset var: dst strength: Strength SymRequired addTo: planner
	].

	planner changeVar: src newValue: 17.
	dst value ~= 1170 ifTrue: [self error: 'Projection test 1 failed!!!!'].

	planner changeVar: dst newValue: 1050.
	src value ~= 5 ifTrue: [self error: 'Projection test 2 failed!!!!'].

	planner changeVar: scale newValue: 5.
	1 to: n - 1 do: [ :i |
	    (dests at: i) value ~= (i*5 + 1000)
	        ifTrue: [self error: 'Projection test 3 failed!!!!']].

	planner changeVar: offset newValue: 2000.
	1 to: n - 1 do: [ :i |
	    (dests at: i) value ~= (i*5 + 2000)
	        ifTrue: [self error: 'Projection test 4 failed!!!!']]
! !

!ScaleConstraint methodsFor: 'benchmarking'!
initializeSrc: srcVar scale: scaleVar offset: offsetVar dst: dstVar strength: strengthSymbol addTo: planner
	"Initialize myself with the given variables and strength."

	super initializeVar: srcVar var: dstVar strength: strengthSymbol addTo: planner.
	scale  := scaleVar.
	offset := offsetVar.

	self addConstraint: planner.
!
addToGraph
	"Add myself to the constraint graph."
	v1 addConstraint: self.
	v2 addConstraint: self.
	scale  addConstraint: self.
	offset addConstraint: self.
	direction := nil.
!
removeFromGraph
	"Remove myself from the constraint graph."
	v1 == nil ifFalse: [ v1 removeConstraint: self ].
	v2 == nil ifFalse: [ v2 removeConstraint: self ].
	scale  == nil ifFalse: [ scale removeConstraint: self ].
	offset == nil ifFalse: [ offset removeConstraint: self ].
	direction := nil.
!
execute
	"Enforce this constraint. Assume that it is satisfied."
	direction = #forward
	    ifTrue:  [ v2 value: (v1 value * scale value) + offset value ]
	    ifFalse: [ v1 value: (v2 value - offset value) // scale value ].
!
inputsDo: aBlock
	"Evaluate the given block on my current input variable."
	direction = #forward
	    ifTrue: [aBlock value: v1.
	             aBlock value: scale.
	             aBlock value: offset]
	    ifFalse: [aBlock value: v2.
	              aBlock value: scale.
	              aBlock value: offset].
!
recalculate
	"Calculate the walkabout strength, the stay flag, and, if it is 'stay',
	 the value for the current output of this constraint. Assume this
	 constraint is satisfied."

	| in out |
	direction = #forward
	    ifTrue:  [in  := v1. out := v2]
	    ifFalse: [out := v1. in  := v2].
	out walkStrength: (strength weakest: in walkStrength).
	out stay: (in stay and: [scale stay and: [offset stay]]).
	out stay ifTrue: [self execute].      "stay optimization"
! !

!ScaleConstraint class methodsFor: 'benchmarking'!
var: src var: scale var: offset var: dst strength: strengthSymbol addTo: planner
	"Install a scale constraint with the given strength on the given
	 variables."
	^ self new initializeSrc: src scale: scale offset: offset dst: dst strength: strengthSymbol addTo: planner
! !

!StayConstraint methodsFor: 'benchmarking'!
execute
	"Stay constraints do nothing."
! !

!StayConstraint class methodsFor: 'benchmarking'!
var: aDBVariable strength: strengthSymbol addTo: planner
	"Install a stay constraint with the given strength on the given variable."

	^ self new initializeVar: aDBVariable strength: strengthSymbol addTo: planner
! !

!Strength methodsFor: 'benchmarking'!
initializeWith: symVal
	symbolicValue   := symVal.
	arithmeticValue := Strength strengthTable at: symVal
!
sameAs: aStrength
	"Answer true if I am the same strength as the given Strength."
	^ arithmeticValue = aStrength arithmeticValue
!
stronger: aStrength
	"Answer true if I am stronger than the given Strength."
	^ arithmeticValue < aStrength arithmeticValue
!
weaker: aStrength
	"Answer true if I am weaker than the given Strength."
	^ arithmeticValue > aStrength arithmeticValue
!
strongest: aStrength
	"Answer the stronger of myself and aStrength."

	(aStrength stronger: self)
	  ifTrue:  [ ^ aStrength ]
	  ifFalse: [ ^ self ].
!
weakest: aStrength
	"Answer the weaker of myself and aStrength."

	(aStrength weaker: self)
	  ifTrue:  [ ^ aStrength ]
	  ifFalse: [ ^ self ].
!
arithmeticValue
	"Answer my arithmetic value. Used for comparisons. Note that
	 STRONGER constraints have SMALLER arithmetic values."

	^ arithmeticValue
! !

!Strength class methodsFor: 'benchmarking'!
new: symVal
	^ self new initializeWith: symVal
!
strengthTable
	^ StrengthTable
!
createStrengthTable
	| table |
	table := SomIdentityDictionary new.
	table at: SymAbsoluteStrongest put: -10000.
	table at: SymRequired          put: -800.
	table at: SymStrongPreferred   put: -600.
	table at: SymPreferred         put: -400.
	table at: SymStrongDefault     put: -200.
	table at: SymDefault           put: 0.
	table at: SymWeakDefault       put: 500.
	table at: SymAbsoluteWeakest   put: 10000.
	^ table
!
createStrengthConstants
	| constants |
	constants := SomIdentityDictionary new.
	StrengthTable keys forEach: [:strengthSymbol |
	  constants
	    at: strengthSymbol
	    put: (self new: strengthSymbol)].
	^ constants
!
initialize
	SymAbsoluteStrongest := Sym new: 0.
	SymRequired          := Sym new: 1.
	SymStrongPreferred   := Sym new: 2.
	SymPreferred         := Sym new: 3.
	SymStrongDefault     := Sym new: 4.
	SymDefault           := Sym new: 5.
	SymWeakDefault       := Sym new: 6.
	SymAbsoluteWeakest   := Sym new: 7.

	StrengthTable := self createStrengthTable.
	StrengthConstants := self createStrengthConstants.

	AbsoluteStrongest := Strength of: SymAbsoluteStrongest.
	AbsoluteWeakest := Strength of: SymAbsoluteWeakest.
	Required := Strength of: SymRequired.
!
of: aSymbol
	"Answer an instance with the specified strength."
	^ StrengthConstants at: aSymbol
!
absoluteStrongest
	^ AbsoluteStrongest
!
absoluteWeakest
	^ AbsoluteWeakest
!
required
	^ Required
!
SymAbsoluteStrongest
	^ SymAbsoluteStrongest
!
SymRequired
	^ SymRequired
!
SymStrongPreferred
	^ SymStrongPreferred
!
SymPreferred
	^ SymPreferred
!
SymStrongDefault
	^ SymStrongDefault
!
SymDefault
	^ SymDefault
!
SymWeakDefault
	^ SymWeakDefault
!
SymAbsoluteWeakest
	^ SymAbsoluteWeakest
! !

!Sym methodsFor: 'benchmarking'!
init: aHash
	hash := aHash
!
customHash
	^ hash
! !

!Sym class methodsFor: 'benchmarking'!
new: aHash
	^ self new init: aHash
! !

