Object subclass: #ArrayedCollection
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

ArrayedCollection variableSubclass: #Array
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

ArrayedCollection variableByteSubclass: #ByteArray
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

ArrayedCollection variableWordSubclass: #Bitmap
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

ArrayedCollection subclass: #String
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

String variableByteSubclass: #ByteString
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

String variableWordSubclass: #WideString
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

String subclass: #Symbol
	instanceVariableNames: ''
	classVariableNames: 'SymbolTable'
	package: 'Mini-Kernel'!

Symbol variableByteSubclass: #ByteSymbol
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

Symbol variableWordSubclass: #WideSymbol
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!

!ArrayedCollection methodsFor: 'enumerating'!
do: aBlock
	1 to: self size do: [:i | aBlock value: (self at: i)]
!
collect: aBlock
	| r |
	r := Array new: self size.
	1 to: self size do: [:i | r at: i put: (aBlock value: (self at: i))].
	^r
!
inject: v into: aBlock
	| acc |
	acc := v.
	self do: [:e | acc := aBlock value: acc value: e].
	^acc
!
includes: x
	self do: [:e | e = x ifTrue: [^true]].
	^false
!
isEmpty
	^self size = 0
!
first
	^self at: 1
!
last
	^self at: self size
!
replaceFrom: start to: stop with: src startingAt: repStart
	<primitive: 'replaceFromToWithStartingAt'>
	| j |
	j := repStart.
	start to: stop do: [:i | self at: i put: (src at: j). j := j + 1]
!
copyFrom: start to: stop
	| r |
	r := self species new: stop - start + 1.
	r replaceFrom: 1 to: stop - start + 1 with: self startingAt: start.
	^r
!
species
	^self class
!
= other
	self class == other class ifFalse: [^false].
	self size = other size ifFalse: [^false].
	1 to: self size do: [:i | (self at: i) = (other at: i) ifFalse: [^false]].
	^true
! !

!Array methodsFor: 'printing'!
printString
	| s |
	s := '#('.
	1 to: self size do: [:i | s := s , (self at: i) printString. i < self size ifTrue: [s := s , ' ']].
	^s , ')'
! !

!Array class methodsFor: 'instances'!
with: a
	^(self new: 1) at: 1 put: a; yourself
!
with: a with: b
	| r |
	r := self new: 2.
	r at: 1 put: a.
	r at: 2 put: b.
	^r
!
with: a with: b with: c
	^{a. b. c}
! !

!ByteArray methodsFor: 'printing'!
printString
	| s |
	s := '#['.
	1 to: self size do: [:i | s := s , (self at: i) printString. i < self size ifTrue: [s := s , ' ']].
	^s , ']'
! !

!String methodsFor: 'accessing'!
at: i
	<primitive: 'stringAt'>
	^self error: 'stringAt failed'
!
at: i put: c
	<primitive: 'stringAtPut'>
	^self error: 'stringAtPut failed'
!
isString
	^true
!
isWide
	^false
!
species
	^self isWide ifTrue: [WideString] ifFalse: [ByteString]
!
hash
	<primitive: 'stringHash'>
!
compare: aString
	<primitive: 'stringCompare'>
!
= aString
	aString isString ifFalse: [^false].
	^(self compare: aString) = 0
!
< aString
	^(self compare: aString) < 0
!
, aString
	| r n |
	n := self size.
	r := ((self isWide or: [aString isWide]) ifTrue: [WideString] ifFalse: [ByteString]) new: n + aString size.
	1 to: n do: [:i | r at: i put: (self at: i)].
	1 to: aString size do: [:i | r at: n + i put: (aString at: i)].
	^r
!
asString
	^self
!
asSymbol
	^Symbol intern: self
!
printString
	^'''' , self , ''''
!
displayString
	^self
!
displayNl
	self stdout: self , (Character lf asString)
! !

!WideString methodsFor: 'testing'!
isWide
	^true
! !

!WideSymbol methodsFor: 'testing'!
isWide
	^true
! !

!Symbol methodsFor: 'accessing'!
isSymbol
	^true
!
= other
	^self == other
!
asSymbol
	^self
!
asString
	| s |
	s := self species new: self size.
	1 to: self size do: [:i | s at: i put: (self at: i)].
	^s
!
printString
	^'#' , self
!
displayString
	^self asString
!
numArgs
	| n |
	(self at: 1) isLetter ifFalse: [^1].
	n := 0.
	self do: [:c | c = $: ifTrue: [n := n + 1]].
	^n
! !

!Symbol class methodsFor: 'interning'!
table
	^SymbolTable
!
intern: aString
	| arr i s n |
	arr := SymbolTable array.
	n := arr size.
	i := aString hash \\ n + 1.
	[(s := arr at: i) == nil] whileFalse: [
		(s compare: aString) = 0 ifTrue: [^s].
		i := i \\ n + 1].
	s := (aString isWide ifTrue: [WideSymbol] ifFalse: [ByteSymbol]) basicNew: aString size.
	1 to: aString size do: [:k | s privAt: k put: (aString at: k)].
	s beImmutable.
	SymbolTable add: s.
	^s
! !

!Symbol methodsFor: 'private'!
privAt: i put: c
	<primitive: 'stringAtPut'>
! !

!Character methodsFor: 'testing'!
isLetter
	| v |
	v := self value.
	^(v between: 65 and: 90) or: [v between: 97 and: 122]
! !

!ByteArray methodsFor: 'byte access'!
uint16At: i
	<primitive: 'bytesUint16At'>
	^self error: 'uint16At: failed'
!
int16At: i
	<primitive: 'bytesInt16At'>
	^self error: 'int16At: failed'
!
uint32At: i
	<primitive: 'bytesUint32At'>
	^self error: 'uint32At: failed'
!
uint32At: i put: v
	<primitive: 'bytesUint32AtPut'>
	^self error: 'uint32At:put: failed'
!
float32At: i
	<primitive: 'bytesFloat32At'>
!
float32At: i put: v
	<primitive: 'bytesFloat32AtPut'>
!
float64At: i
	<primitive: 'bytesFloat64At'>
!
float64At: i put: v
	<primitive: 'bytesFloat64AtPut'>
!
uint16BigEndianAt: i
	<primitive: 'bytesUint16BigEndianAt'>
!
int16BigEndianAt: i
	<primitive: 'bytesInt16BigEndianAt'>
!
uint32BigEndianAt: i
	<primitive: 'bytesUint32BigEndianAt'>
! !

!Symbol methodsFor: 'vm'!
flushCache
	<primitive: 'flushCacheForSelector'>
! !

Array weakSubclass: #WeakArray
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Mini-Kernel'!
