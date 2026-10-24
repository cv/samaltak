CType subclass: #CStructType
	instanceVariableNames: 'structClass fields size alignment'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CStructType comment: 'I am the C struct of a VMStruct or ExternStruct subclass. My fields (CFields) are laid out with C''s natural alignment; members of a (union ...) group share an offset. For an ExternStruct the C library''s header decides the real layout, mine only serves the simulator.'!

!CStructType class methodsFor: 'instance creation'!
forClass: aStructClass registry: aRegistry
	^self basicNew setClass: aStructClass registry: aRegistry
! !

!CStructType methodsFor: 'private'!
setClass: aStructClass registry: aRegistry
	structClass := aStructClass.
	name := aStructClass cName.
	fields := nil.
	aRegistry at: name put: self.
	self registry: aRegistry
!
registry: aRegistry
	"Fields are resolved lazily: a struct may point to itself or to structs declared later."
	fields := #lazy -> aRegistry
!
layout
	| registry offset maxAlign list |
	registry := fields value.
	list := OrderedCollection new.
	offset := 0.
	maxAlign := 1.
	structClass fields do: [:spec |
		(spec at: 1) == #union
			ifTrue: [
				| members unionSize unionAlign |
				members := spec allButFirst collect: [:m | Array with: (m at: 1) with: (registry parse: (m at: 2))].
				unionAlign := members inject: 1 into: [:a :m | a max: (m at: 2) alignment].
				unionSize := members inject: 0 into: [:a :m | a max: (m at: 2) size].
				offset := self align: offset to: unionAlign.
				members do: [:m | list add: (CField name: (m at: 1) cName: (structClass cNameOfField: (m at: 1)) type: (m at: 2) offset: offset)].
				offset := offset + unionSize.
				maxAlign := maxAlign max: unionAlign]
			ifFalse: [
				| t |
				t := registry parse: (spec at: 2).
				offset := self align: offset to: t alignment.
				list add: (CField name: (spec at: 1) cName: (structClass cNameOfField: (spec at: 1)) type: t offset: offset).
				offset := offset + t size.
				maxAlign := maxAlign max: t alignment]].
	alignment := maxAlign.
	size := self align: offset to: maxAlign.
	fields := list asArray
!
align: anInteger to: anAlignment
	^anInteger + anAlignment - 1 // anAlignment * anAlignment
!
ensureLayout
	(fields isNil or: [fields isArray not]) ifTrue: [self layout]
! !

!CStructType methodsFor: 'accessing'!
structClass
	^structClass
!
fields
	self ensureLayout.
	^fields
!
fieldNamed: aString ifAbsent: aBlock
	^self fields detect: [:f | f name = aString] ifNone: aBlock
!
size
	self ensureLayout.
	^size
!
alignment
	self ensureLayout.
	^alignment
!
isExtern
	^structClass isExtern
! !

!CStructType methodsFor: 'testing'!
isStruct
	^true
!
= anObject
	^self == anObject
!
hash
	^structClass hash
! !

!CStructType methodsFor: 'simulation'!
load: aMemory at: anAddress
	"A struct in memory is used through a view of it (a VMStruct instance, like a C lvalue)."
	^structClass memory: aMemory address: anAddress
!
store: aValue in: aMemory at: anAddress
	aMemory copy: self size from: (aMemory addressOf: aValue) to: anAddress
! !

Object subclass: #CField
	instanceVariableNames: 'name cName type offset'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

!CField class methodsFor: 'instance creation'!
name: aString cName: cString type: aCType offset: anInteger
	^self new setName: aString cName: cString type: aCType offset: anInteger
! !

!CField methodsFor: 'private'!
setName: aString cName: cString type: aCType offset: anInteger
	name := aString asString.
	cName := cString.
	type := aCType.
	offset := anInteger
! !

!CField methodsFor: 'accessing'!
name
	^name
!
cName
	^cName
!
type
	^type
!
offset
	^offset
! !

!CField methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'CField('; nextPutAll: name; nextPutAll: ' '; print: type; nextPutAll: ' @'; print: offset; nextPut: $)
! !

CType subclass: #CTypedefType
	instanceVariableNames: 'base'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CTypedefType comment: 'I am a typedef a C library declares (prim_fn, pthread_t): I behave like my base type but print my name.'!

!CTypedefType class methodsFor: 'instance creation'!
named: aString for: aCType
	^self basicNew setName: aString base: aCType
! !

!CTypedefType methodsFor: 'private'!
setName: aString base: aCType
	name := aString.
	base := aCType
! !

!CTypedefType methodsFor: 'accessing'!
base
	^base
!
size
	^base size
!
alignment
	^base alignment
!
target
	^base target
!
isSigned
	^base isSigned
!
rank
	^base rank
!
minimum
	^base minimum
!
maximum
	^base maximum
!
includes: anInteger
	^base includes: anInteger
!
wrap: anInteger
	^base wrap: anInteger
!
returnType
	^base returnType
!
parameterTypes
	^base parameterTypes
!
isVariadic
	^base isVariadic
!
fields
	^base fields
!
fieldNamed: aString ifAbsent: aBlock
	^base fieldNamed: aString ifAbsent: aBlock
! !

!CTypedefType methodsFor: 'testing'!
isArray
	^base isArray
!
isBool
	^base isBool
!
isFloat
	^base isFloat
!
isFunction
	^base isFunction
!
isInteger
	^base isInteger
!
isOpaque
	^base isOpaque
!
isPointer
	^base isPointer
!
isStruct
	^base isStruct
!
isVoid
	^base isVoid
!
sameAs: aCType
	^self = aCType or: [base sameAs: aCType]
! !

!CTypedefType methodsFor: 'simulation'!
load: aMemory at: anAddress
	^base load: aMemory at: anAddress
!
store: aValue in: aMemory at: anAddress
	^base store: aValue in: aMemory at: anAddress
!
load: aMemory zeroAt: anAddress
	^base load: aMemory zeroAt: anAddress
! !
