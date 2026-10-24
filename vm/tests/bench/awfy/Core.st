"
Copyright (c) 2001-2016 see AUTHORS.md file

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

Object subclass: #Benchmark
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #DictEntry
	instanceVariableNames: 'hash key value next'
	classVariableNames: ''
	package: 'AWFY'!

DictEntry subclass: #DictIdEntry
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Pair
	instanceVariableNames: 'key value'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #SomDictionary
	instanceVariableNames: 'buckets size_'
	classVariableNames: ''
	package: 'AWFY'!

SomDictionary subclass: #SomIdentityDictionary
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #SomSet
	instanceVariableNames: 'items'
	classVariableNames: ''
	package: 'AWFY'!

SomSet subclass: #SomIdentitySet
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #SomRandom
	instanceVariableNames: 'seed'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Vector
	instanceVariableNames: 'first last storage'
	classVariableNames: ''
	package: 'AWFY'!

!Benchmark methodsFor: 'benchmarking'!
innerBenchmarkLoop: innerIterations
	1 to: innerIterations do: [:i |
	  (self verifyResult: self benchmark) ifFalse: [ ^ false ].
	].
	^ true
!
benchmark
	self subclassResponsibility
!
verifyResult: result
	self subclassResponsibility
! !

!DictEntry methodsFor: 'benchmarking'!
init: aHash key: aKey value: val next: anEntry
	hash  := aHash.
	key   := aKey.
	value := val.
	next  := anEntry.
!
hash
	^ hash
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
next
	^ next
!
next: e
	next := e
!
match: aHash key: aKey
	^ hash = aHash and: [key = aKey]
! !

!DictEntry class methodsFor: 'benchmarking'!
new: hash key: key value: val next: next
	^ self new init: hash key: key value: val next: next
! !

!DictIdEntry methodsFor: 'benchmarking'!
match: aHash key: aKey
	^ hash = aHash and: [key == aKey]
! !

!DictIdEntry class methodsFor: 'benchmarking'!
new: hash key: key value: val next: next
	^ self new init: hash key: key value: val next: next
! !

!Pair methodsFor: 'benchmarking'!
initialize: aKey and: aValue
	key   := aKey.
	value := aValue.
!
key
	^ key
!
value
	^ value
!
key: aKey
	key   := aKey
!
value: aValue
	value := aValue
! !

!Pair class methodsFor: 'benchmarking'!
withKey: aKey andValue: aValue
	^ self new initialize: aKey and: aValue
! !

!SomDictionary methodsFor: 'benchmarking'!
initialize: size
	buckets := Array new: size.
	size_   := 0
!
hash: key
	| hash |
	key ifNil: [ ^ 0 ].
	hash := key customHash.
	^ hash bitXor: (hash >> 16)
!
bucketIdx: hash
	^ 1 + ((buckets size - 1) & hash)
!
bucket: hash
	^ buckets at: (self bucketIdx: hash)
!
at: aKey
	| hash e |
	hash := self hash: aKey.
	e    := self bucket: hash.

	[ e notNil ] whileTrue: [
	  (e match: hash key: aKey)
	    ifTrue: [ ^ e value ].
	  e := e next ].
	^ nil
!
containsKey: aKey
	| hash e |
	hash := self hash: aKey.
	e    := self bucket: hash.

	[ e notNil ] whileTrue: [
	  (e match: hash key: aKey)
	    ifTrue: [ ^ true ].
	  e := e next ].
	^ false
!
at: aKey put: aVal
	| hash i current |
	hash := self hash: aKey.
	i    := self bucketIdx: hash.
	current := buckets at: i.

	current
	  ifNil: [
	    buckets at: i put: (self newEntry: aKey value: aVal hash: hash).
	    size_ := size_ + 1 ]
	  ifNotNil: [
	    self insertBucketEntry: aKey value: aVal hash: hash head: current ].

	size_ > buckets size ifTrue: [ self resize ]
!
newEntry: aKey value: value hash: hash
	^ DictEntry new: hash key: aKey value: value next: nil
!
insertBucketEntry: key value: value hash: hash head: head
	| current |
	current := head.

	[true] whileTrue: [
	  (current match: hash key: key) ifTrue: [
	    current value: value.
	    ^ self ].
	  current next ifNil: [
	    size_ := size_ + 1.
	    current next: (self newEntry: key value: value hash: hash).
	    ^ self ].
	  current := current next ]
!
resize
	| oldStorage |
	oldStorage := buckets.
	buckets := Array new: oldStorage size * 2.
	self transferEntries: oldStorage
!
transferEntries: oldStorage
	1 to: oldStorage size do: [:i |
	  | current |
	  current := oldStorage at: i.
	  current ifNotNil: [
	    oldStorage at: i put: nil.
	    current next
	      ifNil: [
	        buckets at: 1 + (current hash & (buckets size - 1)) put: current ]
	      ifNotNil: [
	        self splitBucket: oldStorage bucket: i head: current ] ] ]
!
splitBucket: oldStorage bucket: i head: head
	| loHead loTail hiHead hiTail current |
	loHead := nil. loTail := nil.
	hiHead := nil. hiTail := nil.
	current := head.

	[current notNil] whileTrue: [
	  (current hash & oldStorage size) = 0
	    ifTrue: [
	      loTail
	        ifNil:  [ loHead := current ]
	        ifNotNil: [ loTail next: current ].
	      loTail := current ]
	    ifFalse: [
	      hiTail
	        ifNil:  [ hiHead := current ]
	        ifNotNil: [ hiTail next: current ].
	      hiTail := current ].
	  current := current next ].

	loTail ifNotNil: [
	  loTail next: nil.
	  buckets at: i put: loHead ].
	hiTail ifNotNil: [
	  hiTail next: nil.
	  buckets at: i + oldStorage size put: hiHead ]
!
size
	^ size_
!
isEmpty
	^ size_ = 0
!
removeAll
	buckets := Array new: buckets size.
	size_ := 0.
!
keys
	| keys |
	keys := Vector new: size_.
	buckets do: [:b |
	  | current |
	  current := b.
	  [ current notNil ] whileTrue: [
	    keys append: current key.
	    current := current next ] ].
	^ keys
!
values
	| values |
	values := Vector new: size_.
	buckets do: [:b |
	  | current |
	  current := b.
	  [ current notNil ] whileTrue: [
	    values append: current value.
	    current := current next ] ].
	^ values
! !

!SomDictionary class methodsFor: 'benchmarking'!
new: size
	^ super new initialize: size
!
new
	^ self new: 16
! !

!SomIdentityDictionary methodsFor: 'benchmarking'!
newEntry: aKey value: value hash: hash
	^ DictIdEntry new: hash key: aKey value: value next: nil
! !

!SomIdentityDictionary class methodsFor: 'benchmarking'!
new: size
	^ self new: size
!
new
	^ super new: 16
! !

!SomSet methodsFor: 'benchmarking'!
initialize: size
	items := Vector new: size.
!
forEach: block
	items forEach: block
!
hasSome: block
	^ items hasSome: block
!
getOne: block
	^ items getOne:  block
!
add: anObject
	(self contains: anObject)
	    ifFalse: [ items append: anObject ]
!
collect: block
	| coll |
	   coll := Vector new.
	   self forEach: [ :e | coll append: (block value: e) ].
	   ^ coll
!
contains: anObject
	^ self hasSome: [ :it | it = anObject ]
!
size
	^ items size
!
removeAll
	^ items removeAll
! !

!SomSet class methodsFor: 'benchmarking'!
new
	^ super new initialize: 10.
! !

!SomIdentitySet methodsFor: 'benchmarking'!
contains: anObject
	^ self hasSome: [ :it |  it == anObject ]
! !

!SomIdentitySet class methodsFor: 'benchmarking'!
new: size
	^ super new initialize: size.
! !

!SomRandom methodsFor: 'benchmarking'!
initialize
	seed := 74755
!
next
	seed := ((seed * 1309) + 13849) & 65535.
	^ seed
! !

!SomRandom class methodsFor: 'benchmarking'!
new
	^ super new initialize
! !

!Vector methodsFor: 'benchmarking'!
initialize: size
	first := 1.
	last  := 1.

	size = 0
	  ifFalse: [ storage := Array new: size ]
!
at: index
	(storage == nil or: [ index > storage size ]) ifTrue: [ ^ nil ].
	^ storage at: index
!
at: index put: val
	storage == nil ifTrue: [
	  storage := Array new: (index max: 10)
	] ifFalse: [
	  index > storage size ifTrue: [
	    | newLength newStorage |
	    newLength := storage size.
	    [ newLength < index ] whileTrue: [
	      newLength := newLength * 2 ].
	    newStorage := Array new: newLength.
	    1 to: storage size do: [:i | newStorage at: i put: (storage at: i) ].
	    storage := newStorage ] ].

	storage at: index put: val.
	last < (index + 1) ifTrue: [
	  last := index + 1 ]
!
append: element
	storage == nil ifTrue: [
	  storage := Array new: 10
	] ifFalse: [
	  (last > storage size) ifTrue: [
	    "Need to expand capacity first"
	    | newStorage |
	    newStorage := Array new: (2 * storage size).
	    1 to: storage size do: [:i | newStorage at: i put: (storage at: i) ].
	    storage := newStorage ] ].

	storage at: last put: element.
	last := last + 1.
	^ self
!
isEmpty
	^ last = first
!
forEach: block
	first to: last - 1 do: [ :i | block value: (storage at: i) ]
!
hasSome: block
	first to: last - 1 do: [ :i |
	  (block value: (storage at: i))
	    ifTrue: [ ^ true ] ].
	^ false
!
getOne: block
	first to: last - 1 do: [ :i |
	  | e |
	  e := storage at: i.
	  (block value: e)
	    ifTrue: [ ^ e ] ].
	^ nil
!
removeFirst
	self isEmpty ifTrue: [ ^ nil ].
	first := first + 1.
	^ storage at: first - 1
!
removeAll
	first := 1.
	last  := 1.

	storage == nil ifFalse: [
	  storage  := Array new: storage size
	]
!
remove: object
	| newArray newLast found |
	(storage == nil or: [ self isEmpty ]) ifTrue: [ ^ false ].

	newArray := Array new: self capacity.
	newLast := 1.
	found := false.

	self forEach: [ :it |
	  it == object
	      ifTrue:  [ found := true ]
	      ifFalse: [
	          newArray at: newLast put: it.
	          newLast := newLast + 1 ] ].

	storage := newArray.
	last := newLast.
	first := 1.
	^ found
!
size
	^ last - first
!
capacity
	storage == nil ifTrue: [ ^ 0 ] ifFalse: [ ^ storage size ]
!
sort: aBlock
	" Make the argument, aBlock, be the criterion for ordering elements of
	   the receiver.
	   sortBlocks with side effects may not work right "
	self size > 0 ifTrue: [
	  self sort: first
	         to: last - 1
	       with: aBlock ]
!
sort: i to: j with: sortBlock
	" Sort elements i through j of self to be non-descending according to
	   sortBlock. "
	| di dij dj tt ij k l n |
	sortBlock ifNil: [ ^ self defaultSort: i to: j ].

	"The prefix d means the data at that index."
	(n := j + 1  - i) <= 1 ifTrue: [ ^ self ]. "Nothing to sort."
	" Sort di,dj. "
	di := storage at: i.
	dj := storage at: j.

	"i.e., should di precede dj?"
	(sortBlock value: di with: dj) ifFalse: [
	  storage swap: i with: j.
	  tt := di.
	  di := dj.
	  dj := tt
	].

	n > 2 ifTrue: [ " More than two elements. "
	  ij := (i + j) // 2.  " ij is the midpoint of i and j. "
	  dij := storage at: ij.  " Sort di,dij,dj.  Make dij be their median. "
	  (sortBlock value: di with: dij)
	    ifTrue: [ " i.e. should di precede dij? "
	      (sortBlock value: dij with: dj) ifFalse: [ " i.e., should dij precede dj? "
	        storage swap: j with: ij.
	        dij := dj]]
	    ifFalse: [ " i.e. di should come after dij "
	      storage swap: i with: ij.
	      dij := di].

	  n > 3 ifTrue: [
	    " More than three elements.
	      Find k>i and l<j such that dk,dij,dl are in reverse order.
	      Swap k and l.  Repeat this procedure until k and l pass each other. "
	    k := i.
	    l := j.
	    [ [l := l - 1.  k <= l and: [sortBlock value: dij with: (storage at: l)]]
	        whileTrue.  " i.e. while dl succeeds dij "
	      [k := k + 1.  k <= l and: [sortBlock value: (storage at: k) with: dij]]
	        whileTrue.  " i.e. while dij succeeds dk "
	      k <= l]
	        whileTrue:
	          [ storage swap: k with: l ].

	    " Now l<k (either 1 or 2 less), and di through dl are all less than or equal to dk
	      through dj.  Sort those two segments. "
	    self sort: i to: l with: sortBlock.
	    self sort: k to: j with: sortBlock
	  ]
	]
! !

!Vector class methodsFor: 'benchmarking'!
new
	^ self new: 0
!
new: initialSize
	^ super new initialize: initialSize
!
with: elem
	| newVector |
	newVector := self new: 1.
	newVector append: elem.
	^ newVector
! !

