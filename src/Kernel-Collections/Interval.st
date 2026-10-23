SequenceableCollection subclass: #Interval
	instanceVariableNames: 'start stop step'
	classVariableNames: ''
	package: 'Kernel-Collections'!

Interval comment: 'I am an arithmetic progression from start to stop by step, computed on demand (1 to: 10, 1 to: 10 by: 2). Collecting or selecting over me answers an Array.'!

!Interval methodsFor: 'accessing'!
first
	^start
!
last
	^stop - ((stop - start) \\ step)
!
increment
	^step
!
size
	step > 0 ifTrue: [stop < start ifTrue: [^0]].
	step < 0 ifTrue: [start < stop ifTrue: [^0]].
	^(stop - start) // step + 1
!
at: index
	(index between: 1 and: self size) ifFalse: [^self errorSubscriptBounds: index].
	^start + (step * (index - 1))
!
at: index put: anObject
	^self shouldNotImplement
!
setFrom: startNumber to: stopNumber by: stepNumber
	start := startNumber.
	stop := stopNumber.
	step := stepNumber
! !

!Interval methodsFor: 'adding'!
add: anObject
	^self shouldNotImplement
!
remove: anObject ifAbsent: aBlock
	^self shouldNotImplement
! !

!Interval methodsFor: 'enumerating'!
do: aBlock
	| i |
	i := start.
	step > 0
		ifTrue: [[i <= stop] whileTrue: [aBlock value: i. i := i + step]]
		ifFalse: [[i >= stop] whileTrue: [aBlock value: i. i := i + step]]
!
reverseDo: aBlock
	| i |
	i := self last.
	step > 0
		ifTrue: [[i >= start] whileTrue: [aBlock value: i. i := i - step]]
		ifFalse: [[i <= start] whileTrue: [aBlock value: i. i := i - step]]
!
collect: aBlock
	| result i |
	result := Array new: self size.
	i := 0.
	self do: [:each | result at: (i := i + 1) put: (aBlock value: each)].
	^result
! !

!Interval methodsFor: 'testing'!
isInterval
	^true
!
includes: aNumber
	aNumber isNumber ifFalse: [^false].
	step > 0
		ifTrue: [(aNumber between: start and: stop) ifFalse: [^false]]
		ifFalse: [(aNumber between: stop and: start) ifFalse: [^false]].
	^((aNumber - start) \\ step) = 0
! !

!Interval methodsFor: 'comparing'!
= anObject
	(anObject isKindOf: Interval) ifTrue: [
		^self size = anObject size
			and: [self size = 0 or: [start = anObject first and: [step = anObject increment]]]].
	^super = anObject
! !

!Interval methodsFor: 'copying'!
copy
	^Interval from: start to: stop by: step
!
reversed
	self isEmpty ifTrue: [^Interval from: stop to: start by: step negated].
	^Interval from: self last to: start by: step negated
! !

!Interval methodsFor: 'printing'!
printOn: aStream
	aStream nextPut: $(; print: start; nextPutAll: ' to: '; print: stop.
	step = 1 ifFalse: [aStream nextPutAll: ' by: '; print: step].
	aStream nextPut: $)
!
storeOn: aStream
	self printOn: aStream
! !

!Interval methodsFor: 'private'!
species
	^Array
! !

!Interval class methodsFor: 'instance creation'!
from: startNumber to: stopNumber
	^self basicNew setFrom: startNumber to: stopNumber by: 1
!
from: startNumber to: stopNumber by: stepNumber
	stepNumber = 0 ifTrue: [^self error: 'Interval step must not be zero'].
	^self basicNew setFrom: startNumber to: stopNumber by: stepNumber
! !
