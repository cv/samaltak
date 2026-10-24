VMConstants subclass: #VMStruct
	instanceVariableNames: 'memory address'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

VMStruct comment: 'I am the abstract class of the VM''s C structs. A subclass declares its fields on the class side:

	fields
		^#((method oop) (fp ''oop *'') (pc int32_t) (pad ''oop[2]'') (union (prim prim_fn) (qconst oop)))

In the simulator my instances are pointers to a struct in a SimulatedMemory: they answer its fields (fr method, fr method: m) and do pointer arithmetic (fr + 1, fr - frames). In C a field access is fr->method.'!

!VMStruct class methodsFor: 'declaring'!
fields
	^#()
!
cName
	"The C type name: snake case of my name."
	^LowtalkNames snake: self name
!
cNameOfField: aSymbol
	^LowtalkNames snake: aSymbol
!
isExtern
	^false
!
ctype
	^CTypeRegistry default at: self name asString
! !

!VMStruct class methodsFor: 'instance creation'!
memory: aMemory address: anAddress
	^self basicNew setMemory: aMemory address: anAddress
! !

!VMStruct methodsFor: 'private'!
setMemory: aMemory address: anAddress
	memory := aMemory.
	address := anAddress
!
ctype
	^self class ctype
!
fieldFor: aSelector
	| sel |
	sel := aSelector asString.
	(sel endsWith: ':') ifTrue: [sel := sel allButLast].
	^self ctype fieldNamed: sel ifAbsent: [nil]
! !

!VMStruct methodsFor: 'fields'!
doesNotUnderstand: aMessage
	"Field accessors: fr method, fr method: m."
	| field |
	field := self fieldFor: aMessage selector.
	field isNil ifTrue: [^super doesNotUnderstand: aMessage].
	address = 0 ifTrue: [^memory simulationError: 'NULL ' , self class name , ' pointer dereferenced'].
	aMessage arguments isEmpty ifTrue: [^field type load: memory at: address + field offset].
	aMessage arguments size = 1 ifTrue: [
		field type store: aMessage arguments first in: memory at: address + field offset.
		^aMessage arguments first].
	^super doesNotUnderstand: aMessage
!
respondsTo: aSymbol
	^(super respondsTo: aSymbol) or: [(self fieldFor: aSymbol) notNil]
! !

!VMStruct methodsFor: 'pointer'!
address
	^address
!
fieldAddress: aSymbol
	"&p->field"
	| field |
	field := self ctype fieldNamed: aSymbol asString ifAbsent: [^self error: 'no field ' , aSymbol].
	^memory pointerTo: field type at: address + field offset
!
memory
	^memory
!
simulatedAddressIn: aMemory
	^address
!
at: anInteger
	^self class memory: memory address: address + (anInteger * self ctype size)
!
value
	^self
!
value: aStructPointer
	"*p = *q"
	self copyStructFrom: aStructPointer.
	^aStructPointer
!
copyStructFrom: aStructPointer
	memory copy: self ctype size from: aStructPointer address to: address
!
+ anInteger
	^self at: anInteger
!
- aPointerOrInteger
	aPointerOrInteger isInteger ifTrue: [^self at: aPointerOrInteger negated].
	^address - aPointerOrInteger address // self ctype size
!
< aPointer
	^address < aPointer address
!
<= aPointer
	^address <= aPointer address
!
> aPointer
	^address > aPointer address
!
>= aPointer
	^address >= aPointer address
!
= anObject
	^(anObject respondsTo: #simulatedAddressIn:) and: [address = (anObject simulatedAddressIn: memory)]
!
~= anObject
	^(self = anObject) not
!
hash
	^address hash
!
isNull
	^address = 0
!
notNull
	^address ~= 0
! !

!VMStruct methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '('; nextPutAll: self class name; nextPutAll: ' *)16r'; nextPutAll: (address printStringBase: 16)
! !

VMStruct subclass: #ExternStruct
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Lowtalk'!

ExternStruct comment: 'I am the abstract class of C library structs the VM uses (struct timespec, SDL_GPUShaderCreateInfo). A subclass answers its C name (cName) and the fields the VM touches, by their C names; the library''s header defines the real layout. In the simulator the fields get a layout of their own.'!

!ExternStruct class methodsFor: 'declaring'!
cName
	^self subclassResponsibility
!
cNameOfField: aSymbol
	^aSymbol asString
!
isExtern
	^true
! !
