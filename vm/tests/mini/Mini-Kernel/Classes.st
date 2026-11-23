Object subclass: #Behavior
	instanceVariableNames: 'superclass methodDict format'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Behavior subclass: #ClassDescription
	instanceVariableNames: 'instanceVariables organization'
	classVariableNames: ''
	package: 'Mini-Kernel'!

ClassDescription subclass: #Class
	instanceVariableNames: 'subclasses name classPool sharedPools package comment'
	classVariableNames: ''
	package: 'Mini-Kernel'!

ClassDescription subclass: #Metaclass
	instanceVariableNames: 'thisClass'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #MethodDictionary
	instanceVariableNames: 'tally keys values'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #CompiledMethod
	instanceVariableNames: 'selector methodClass literals bytecodes numArgs numTemps frameSize primitive source category pragmas sourceMap properties'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #HashedCollection
	instanceVariableNames: 'tally array'
	classVariableNames: ''
	package: 'Mini-Kernel'!

HashedCollection subclass: #Set
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

HashedCollection subclass: #Dictionary
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Dictionary subclass: #SystemDictionary
	instanceVariableNames: ''
	classVariableNames: 'PackageList'
	package: 'Mini-Kernel'!

Smalltalk at: #SnapCounter put: 0!

!Behavior methodsFor: 'instances'!
basicNew
	<primitive: 'basicNew'>
	^self error: 'basicNew failed'
!
basicNew: n
	<primitive: 'basicNew:' error: ec>
	^self error: 'basicNew: failed ' , ec printString
!
new
	^self basicNew
!
new: n
	^self basicNew: n
!
allInstances
	<primitive: 'allInstances'>
!
superclass
	^superclass
!
methodDict
	^methodDict
!
format
	^format
!
printString
	^self name
!
lookup: aSymbol
	| c m |
	c := self.
	[c == nil] whileFalse: [
		m := c methodDict at: aSymbol.
		m == nil ifFalse: [^m].
		c := c superclass].
	^nil
! !

!Class methodsFor: 'accessing'!
name
	^name
!
classPool
	^classPool
! !

!Metaclass methodsFor: 'accessing'!
name
	^thisClass name , ' class'
!
thisClass
	^thisClass
! !

!MethodDictionary methodsFor: 'accessing'!
at: aSymbol
	| i cap k |
	cap := keys size.
	i := (aSymbol identityHash bitAnd: cap - 1) + 1.
	[(k := keys at: i) == nil] whileFalse: [
		k == aSymbol ifTrue: [^values at: i].
		i := i \\ cap + 1].
	^nil
!
size
	^tally
! !

!CompiledMethod methodsFor: 'accessing'!
selector
	^selector
!
methodClass
	^methodClass
!
primitive
	^primitive
!
numArgs
	^numArgs
!
numTemps
	^numTemps
!
frameSize
	^frameSize
!
literals
	^literals
!
bytecodes
	^bytecodes
!
source
	^source
!
category
	^category
!
pragmas
	^pragmas
!
printString
	^methodClass name , '>>' , selector
! !

!HashedCollection methodsFor: 'accessing'!
init: n
	tally := 0.
	array := Array new: n
!
array
	^array
!
size
	^tally
!
indexFor: key
	| i n e |
	n := array size.
	i := key hash \\ n + 1.
	[(e := array at: i) == nil] whileFalse: [
		(self keyOf: e) = key ifTrue: [^i].
		i := i \\ n + 1].
	^i
!
keyOf: element
	^element
!
grow
	| old |
	old := array.
	array := Array new: old size * 2.
	tally := 0.
	old do: [:e | e == nil ifFalse: [self addElement: e]]
!
addElement: e
	| i |
	(tally + 1) * 2 > array size ifTrue: [self grow].
	i := self indexFor: (self keyOf: e).
	(array at: i) == nil ifTrue: [tally := tally + 1].
	array at: i put: e.
	^e
!
do: aBlock
	array do: [:e | e == nil ifFalse: [aBlock value: e]]
! !

!HashedCollection class methodsFor: 'instances'!
new
	^self basicNew init: 8
! !

!Set methodsFor: 'accessing'!
add: anObject
	^self addElement: anObject
!
includes: anObject
	^(array at: (self indexFor: anObject)) ~~ nil
! !

!Dictionary methodsFor: 'accessing'!
keyOf: assoc
	^assoc key
!
associationAt: key
	^array at: (self indexFor: key)
!
at: key
	| a |
	a := self associationAt: key.
	^a == nil ifTrue: [nil] ifFalse: [a value]
!
at: key put: value
	| a |
	a := self associationAt: key.
	a == nil ifTrue: [self addElement: key -> value] ifFalse: [a value: value].
	^value
!
includesKey: key
	^(self associationAt: key) ~~ nil
!
do: aBlock
	array do: [:a | a == nil ifFalse: [aBlock value: a value]]
! !

!SystemDictionary methodsFor: 'vm'!
quit
	self quit: 0
!
quit: code
	<primitive: 'quit'>
!
snapshot: path
	<primitive: 'snapshot'>
	^self error: 'snapshot failed'
!
vmArguments
	<primitive: 'vmArguments'>
!
imagePath
	<primitive: 'imagePath'>
!
vmBanner
	<primitive: 'vmBanner'>
!
getenv: name
	<ffiSite>
	| result |
	result := (self ffiSite: #(call 'vm:core' 'core_getenv_text' (cText) ownedText)) tryInvoke1: name.
	^result == false ifTrue: [nil] ifFalse: [result]
!
gc
	<primitive: 'gc'>
!
scavenge
	<primitive: 'scavenge'>
!
vmStats
	<primitive: 'vmStats'>
!
stackLimit: n
	<primitive: 'stackLimit'>
!
flushMethodCache
	<primitive: 'flushMethodCache'>
!
millisecondClock
	<primitive: 'millisecondClock'>
!
microsecondClock
	<primitive: 'microsecondClock'>
!
utcMicroseconds
	<ffiSite>
	^(self ffiSite: #(call 'vm:core' 'core_utc_microseconds' () i64)) tryInvoke0
!
primitiveNames
	<primitive: 'primitiveNames'>
!
specialObjectsArray
	<primitive: 'specialObjectsArray'>
!
registerExternal: aSemaphore at: index
	(self specialObjectsArray at: 33) at: index put: aSemaphore
!
samplerInterval: us index: i
	<primitive: 'samplerInterval'>
!
allocationSampling: bytes index: i
	<primitive: 'allocationSampling'>
!
allocationSampleInfo
	<primitive: 'allocationSampleInfo'>
!
packageList
	^PackageList
! !

!SystemDictionary methodsFor: 'startup'!
bootstrapStartUp
	| args |
	args := self vmArguments.
	args do: [:a | (a at: 1) = $- ifFalse: [MiniTests run: a]].
	self quit
! !

!MethodDictionary methodsFor: 'accessing'!
at: aSymbol put: aMethod
	| i cap k |
	cap := keys size.
	i := (aSymbol identityHash bitAnd: cap - 1) + 1.
	[(k := keys at: i) == nil or: [k == aSymbol]] whileFalse: [i := i \\ cap + 1].
	k == nil ifTrue: [tally := tally + 1].
	keys at: i put: aSymbol.
	values at: i put: aMethod.
	^aMethod
! !
