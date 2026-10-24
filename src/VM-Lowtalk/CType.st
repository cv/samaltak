Object subclass: #CType
	instanceVariableNames: 'name'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CType comment: 'I am a C type, as the translator checks it and the simulator stores it. CTypeRegistry parses C type names (''uint8_t *'', ''Frame *'', ''void (*)(void)'') into my subclasses. The simulator reads and writes values of my kind in a SimulatedMemory (load:at: and store:in:at:).'!

!CType methodsFor: 'accessing'!
name
	"Answer my C spelling without a declarator (''oop'', ''frame_t *'')."
	^name
!
size
	self subclassResponsibility
!
alignment
	^self size
! !

!CType methodsFor: 'testing'!
isArithmetic
	^self isInteger or: [self isFloat]
!
isArray
	^false
!
isBool
	^false
!
isConst
	^false
!
isFloat
	^false
!
isFunction
	^false
!
isInteger
	^false
!
isOpaque
	^false
!
isPointer
	^false
!
isPointerLike
	"Pointers and arrays (which decay to pointers)."
	^self isPointer or: [self isArray]
!
isScalar
	^self isArithmetic or: [self isPointer or: [self isBool]]
!
isStruct
	^false
!
isVoid
	^false
!
isVoidPointer
	^self isPointer and: [self target isVoid]
! !

!CType methodsFor: 'declaring'!
declare: aString
	"Answer a C declaration of aString with my type (''oop cstack[65536]'', ''void (*fn)(void)'')."
	^self declarator: aString
!
declarator: aString
	"Answer my C spelling around the declarator aString (empty for an abstract declarator)."
	aString isEmpty ifTrue: [^name].
	^name , ' ' , aString
!
pointer
	^CPointerType to: self
! !

!CType methodsFor: 'simulation'!
load: aMemory at: anAddress
	self subclassResponsibility
!
store: aValue in: aMemory at: anAddress
	self subclassResponsibility
!
zeroValueIn: aMemory
	"The value of a zero-filled variable of my type."
	^self load: aMemory zeroAt: 0
!
load: aMemory zeroAt: anAddress
	^0
! !

!CType methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [self name = anObject name]
!
hash
	^name hash
!
sameAs: aCType
	"Answer whether values of aCType need no conversion to become mine."
	aCType isConst ifTrue: [^self sameAs: aCType base].
	^self = aCType
! !

!CType methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'CType('; nextPutAll: name; nextPut: $)
! !

CType subclass: #CVoidType
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CVoidType class methodsFor: 'instance creation'!
new
	^self basicNew setName: 'void'
! !

!CVoidType methodsFor: 'private'!
setName: aString
	name := aString
! !

!CVoidType methodsFor: 'accessing'!
size
	^1
! !

!CVoidType methodsFor: 'testing'!
isVoid
	^true
! !

CType subclass: #CBoolType
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CBoolType class methodsFor: 'instance creation'!
new
	^self basicNew setName: 'bool'
!
named: aString
	^self basicNew setName: aString
! !

!CBoolType methodsFor: 'private'!
setName: aString
	name := aString
! !

!CBoolType methodsFor: 'accessing'!
size
	^1
! !

!CBoolType methodsFor: 'testing'!
isBool
	^true
! !

!CBoolType methodsFor: 'simulation'!
load: aMemory at: anAddress
	^(aMemory uint8At: anAddress) ~= 0
!
store: aValue in: aMemory at: anAddress
	(aValue == true or: [aValue == false]) ifFalse: [^aMemory simulationError: 'not a Boolean: ' , aValue printString].
	aMemory uint8At: anAddress put: (aValue ifTrue: [1] ifFalse: [0])
!
load: aMemory zeroAt: anAddress
	^false
! !

CType subclass: #CIntegerType
	instanceVariableNames: 'size signed minimum maximum'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CIntegerType comment: 'I am a C integer type of size bytes. Typedefs (oop, size_t, int64_t) are instances with their own name: oop is an unsigned 64-bit word.'!

!CIntegerType class methodsFor: 'instance creation'!
named: aString size: anInteger signed: aBoolean
	^self basicNew setName: aString size: anInteger signed: aBoolean
! !

!CIntegerType methodsFor: 'private'!
setName: aString size: anInteger signed: aBoolean
	name := aString.
	size := anInteger.
	signed := aBoolean.
	minimum := signed ifTrue: [(1 bitShift: size * 8 - 1) negated] ifFalse: [0].
	maximum := signed ifTrue: [(1 bitShift: size * 8 - 1) - 1] ifFalse: [(1 bitShift: size * 8) - 1]
! !

!CIntegerType methodsFor: 'accessing'!
size
	^size
!
isSigned
	^signed
!
rank
	"Conversion rank by width (LP64: long and long long are the same)."
	^size
!
minimum
	^minimum
!
maximum
	^maximum
!
includes: anInteger
	^anInteger isInteger and: [anInteger >= minimum and: [anInteger <= maximum]]
!
wrap: anInteger
	"Answer anInteger reduced to my range (two's complement), as a C cast does."
	| bits v |
	(anInteger >= minimum and: [anInteger <= maximum]) ifTrue: [^anInteger].
	bits := size * 8.
	v := anInteger bitAnd: (1 bitShift: bits) - 1.
	(signed and: [v >= (1 bitShift: bits - 1)]) ifTrue: [v := v - (1 bitShift: bits)].
	^v
! !

!CIntegerType methodsFor: 'testing'!
isInteger
	^true
!
sameAs: aCType
	^aCType isInteger and: [aCType size = size and: [aCType isSigned = signed]]
! !

!CIntegerType methodsFor: 'simulation'!
load: aMemory at: anAddress
	| v |
	v := aMemory unsignedAt: anAddress size: size.
	(signed and: [v > maximum]) ifTrue: [v := v - (maximum - minimum + 1)].
	^v
!
store: aValue in: aMemory at: anAddress
	(self includes: aValue) ifFalse: [
		^aMemory simulationError: aValue printString , ' does not fit ' , name].
	aMemory unsignedAt: anAddress size: size put: (aValue < 0 ifTrue: [aValue + (maximum - minimum + 1)] ifFalse: [aValue])
! !

CType subclass: #CFloatType
	instanceVariableNames: 'size'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CFloatType class methodsFor: 'instance creation'!
named: aString size: anInteger
	^self basicNew setName: aString size: anInteger
! !

!CFloatType methodsFor: 'private'!
setName: aString size: anInteger
	name := aString.
	size := anInteger
! !

!CFloatType methodsFor: 'accessing'!
size
	^size
! !

!CFloatType methodsFor: 'testing'!
isFloat
	^true
! !

!CFloatType methodsFor: 'simulation'!
load: aMemory at: anAddress
	^size = 8
		ifTrue: [aMemory float64At: anAddress]
		ifFalse: [aMemory float32At: anAddress]
!
store: aValue in: aMemory at: anAddress
	aValue isNumber ifFalse: [^aMemory simulationError: 'not a number: ' , aValue printString].
	size = 8
		ifTrue: [aMemory float64At: anAddress put: aValue asFloat]
		ifFalse: [aMemory float32At: anAddress put: aValue asFloat]
!
load: aMemory zeroAt: anAddress
	^0.0
! !

CType subclass: #CPointerType
	instanceVariableNames: 'target'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CPointerType class methodsFor: 'instance creation'!
to: aCType
	^self basicNew setTarget: aCType
! !

!CPointerType methodsFor: 'private'!
setTarget: aCType
	target := aCType.
	name := self declarator: ''
! !

!CPointerType methodsFor: 'accessing'!
target
	^target
!
size
	^8
!
declarator: aString
	(target isArray or: [target isFunction]) ifTrue: [^target declarator: '(*' , aString , ')'].
	^target declarator: '*' , aString
! !

!CPointerType methodsFor: 'testing'!
isPointer
	^true
!
sameAs: aCType
	^aCType isPointerLike and: [
		target isVoid or: [aCType target isVoid or: [target sameAs: aCType target]]]
! !

!CPointerType methodsFor: 'simulation'!
load: aMemory at: anAddress
	^aMemory pointerTo: target at: (aMemory uint64At: anAddress)
!
store: aValue in: aMemory at: anAddress
	aMemory uint64At: anAddress put: (aMemory addressOf: aValue)
!
load: aMemory zeroAt: anAddress
	^aMemory pointerTo: target at: 0
! !

CType subclass: #CArrayType
	instanceVariableNames: 'element count'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CArrayType class methodsFor: 'instance creation'!
of: aCType count: anInteger
	^self basicNew setElement: aCType count: anInteger
! !

!CArrayType methodsFor: 'private'!
setElement: aCType count: anInteger
	element := aCType.
	count := anInteger.
	name := self declarator: ''
! !

!CArrayType methodsFor: 'accessing'!
element
	^element
!
target
	"As a pointer to my first element."
	^element
!
count
	^count
!
size
	^element size * count
!
alignment
	^element alignment
!
declarator: aString
	^element declarator: aString , '[' , count printString , ']'
!
decayed
	^CPointerType to: element
! !

!CArrayType methodsFor: 'testing'!
isArray
	^true
!
= anObject
	^self class == anObject class and: [element = anObject element and: [count = anObject count]]
!
hash
	^element hash bitXor: count
! !

!CArrayType methodsFor: 'simulation'!
load: aMemory at: anAddress
	"An array decays to a pointer to its first element."
	^aMemory pointerTo: element at: anAddress
!
store: aValue in: aMemory at: anAddress
	aMemory copy: self size from: (aMemory addressOf: aValue) to: anAddress
! !

CType subclass: #CFunctionType
	instanceVariableNames: 'returnType parameterTypes parameterNames variadic'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CFunctionType class methodsFor: 'instance creation'!
returning: aCType parameters: typeArray names: nameArray variadic: aBoolean
	^self basicNew setReturnType: aCType parameterTypes: typeArray names: nameArray variadic: aBoolean
! !

!CFunctionType methodsFor: 'private'!
setReturnType: aCType parameterTypes: typeArray names: nameArray variadic: aBoolean
	returnType := aCType.
	parameterTypes := typeArray.
	parameterNames := nameArray.
	variadic := aBoolean.
	name := self declarator: ''
! !

!CFunctionType methodsFor: 'accessing'!
returnType
	^returnType
!
parameterTypes
	^parameterTypes
!
parameterNames
	^parameterNames
!
isVariadic
	^variadic
!
size
	^8
!
declarator: aString
	"With parameter names when declaring a function, without for a type."
	^returnType declarator: aString , '(' , (self parameterListNamed: false) , ')'
!
parameterListNamed: aBoolean
	| s |
	(parameterTypes isEmpty and: [variadic not]) ifTrue: [^'void'].
	s := WriteStream on: String new.
	parameterTypes doWithIndex: [:t :i |
		i > 1 ifTrue: [s nextPutAll: ', '].
		s nextPutAll: (t declarator: (aBoolean ifTrue: [parameterNames at: i] ifFalse: ['']))].
	variadic ifTrue: [
		parameterTypes isEmpty ifFalse: [s nextPutAll: ', '].
		s nextPutAll: '...'].
	^s contents
!
prototypeNamed: aString
	"Answer a C prototype of a function aString with my type and parameter names."
	^returnType declarator: aString , '(' , (self parameterListNamed: true) , ')'
! !

!CFunctionType methodsFor: 'testing'!
isFunction
	^true
!
= anObject
	^self class == anObject class and: [self name = anObject name]
! !

CType subclass: #COpaqueType
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Lowtalk'!

COpaqueType comment: 'I am a C type the VM only handles through pointers (FILE, SDL_Window, DIR).'!

!COpaqueType class methodsFor: 'instance creation'!
named: aString
	^self basicNew setName: aString
! !

!COpaqueType methodsFor: 'private'!
setName: aString
	name := aString
! !

!COpaqueType methodsFor: 'accessing'!
size
	^8
! !

!COpaqueType methodsFor: 'testing'!
isOpaque
	^true
! !
