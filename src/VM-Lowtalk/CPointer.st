Object subclass: #CPointer
	instanceVariableNames: 'memory address type elementSize'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CPointer comment: 'I am a C pointer in the simulator: an address in a SimulatedMemory and the type I point to. Lowtalk code uses me as it uses pointers in C (p at: i, p + 1, p - q, p value: x); the translator turns the same messages into C. Pointers to structs are VMStruct views instead, pointers to functions FunctionPointers.'!

!CPointer class methodsFor: 'instance creation'!
memory: aMemory address: anAddress type: aCType
	^self new setMemory: aMemory address: anAddress type: aCType
!
null
	^self new setMemory: nil address: 0 type: CVoidType new
! !

!CPointer methodsFor: 'private'!
setMemory: aMemory address: anAddress type: aCType
	memory := aMemory.
	address := anAddress.
	type := aCType
!
elementSize
	^elementSize ifNil: [elementSize := type isVoid ifTrue: [1] ifFalse: [type size]]
!
setAddress: anAddress
	address := anAddress
! !

!CPointer methodsFor: 'accessing'!
address
	^address
!
type
	^type
!
memory
	^memory
!
simulatedAddressIn: aMemory
	^address
! !

!CPointer methodsFor: 'dereferencing'!
at: anInteger
	^type load: memory at: address + (anInteger * self elementSize)
!
at: anInteger put: aValue
	type store: aValue in: memory at: address + (anInteger * self elementSize).
	^aValue
!
value
	^self at: 0
!
value: aValue
	^self at: 0 put: aValue
! !

!CPointer methodsFor: 'arithmetic'!
+ anInteger
	^self shallowCopy setAddress: address + (anInteger * self elementSize)
!
- aPointerOrInteger
	aPointerOrInteger isInteger ifTrue: [^self + aPointerOrInteger negated].
	^address - (aPointerOrInteger simulatedAddressIn: memory) // self elementSize
! !

!CPointer methodsFor: 'comparing'!
< aPointer
	^address < (aPointer simulatedAddressIn: memory)
!
<= aPointer
	^address <= (aPointer simulatedAddressIn: memory)
!
> aPointer
	^address > (aPointer simulatedAddressIn: memory)
!
>= aPointer
	^address >= (aPointer simulatedAddressIn: memory)
!
= anObject
	^(anObject respondsTo: #simulatedAddressIn:) and: [address = (anObject simulatedAddressIn: memory)]
!
~= anObject
	^(self = anObject) not
!
hash
	^address hash
! !

!CPointer methodsFor: 'testing'!
isNull
	^address = 0
!
notNull
	^address ~= 0
! !

!CPointer methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '('; nextPutAll: type name; nextPutAll: ' *)16r'; nextPutAll: (address printStringBase: 16)
! !

Object subclass: #FunctionPointer
	instanceVariableNames: 'receiver selector'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

FunctionPointer comment: 'I am a pointer to a Lowtalk function in the simulator: a module (or library) and a selector. In memory I am a fake address (SimulatedMemory>>registerObject:).'!

!FunctionPointer class methodsFor: 'instance creation'!
receiver: aModule selector: aSymbol
	^self new setReceiver: aModule selector: aSymbol
!
null
	^self new setReceiver: nil selector: nil
! !

!FunctionPointer methodsFor: 'private'!
setReceiver: aModule selector: aSymbol
	receiver := aModule.
	selector := aSymbol
! !

!FunctionPointer methodsFor: 'accessing'!
receiver
	^receiver
!
selector
	^selector
!
simulatedAddressIn: aMemory
	selector isNil ifTrue: [^0].
	^aMemory registerObject: self
! !

!FunctionPointer methodsFor: 'calling'!
call
	^receiver perform: selector
!
call: a
	^receiver perform: selector with: a
!
call: a with: b
	^receiver perform: selector with: a with: b
!
call: a with: b with: c
	^receiver perform: selector with: a with: b with: c
!
call: a with: b with: c with: d
	^receiver perform: selector with: a with: b with: c with: d
!
callWithArguments: anArray
	^receiver perform: selector withArguments: anArray
! !

!FunctionPointer methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [receiver == anObject receiver and: [selector == anObject selector]]
!
hash
	^selector hash
! !

!FunctionPointer methodsFor: 'testing'!
isNull
	^selector isNil
!
notNull
	^selector notNil
! !

!FunctionPointer methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '&'; print: receiver class; nextPutAll: '>>'; nextPutAll: (selector ifNil: ['NULL'])
! !

Object subclass: #MachineCodeFunction
	instanceVariableNames: 'memory address type'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

MachineCodeFunction comment: 'I am a pointer to a function in machine code in the simulator: an address in a SimulatedMemory and the function''s type (a CFunctionType). Calling me runs the code with the memory''s machineCodeRunner.'!

!MachineCodeFunction class methodsFor: 'instance creation'!
memory: aMemory address: anAddress type: aCFunctionType
	^self new setMemory: aMemory address: anAddress type: aCFunctionType
! !

!MachineCodeFunction methodsFor: 'private'!
setMemory: aMemory address: anAddress type: aCFunctionType
	memory := aMemory.
	address := anAddress.
	type := aCFunctionType
! !

!MachineCodeFunction methodsFor: 'accessing'!
address
	^address
!
type
	^type
!
simulatedAddressIn: aMemory
	^address
! !

!MachineCodeFunction methodsFor: 'calling'!
call
	^self callWithArguments: #()
!
call: a
	^self callWithArguments: {a}
!
call: a with: b
	^self callWithArguments: {a. b}
!
call: a with: b with: c
	^self callWithArguments: {a. b. c}
!
call: a with: b with: c with: d
	^self callWithArguments: {a. b. c. d}
!
callWithArguments: anArray
	memory machineCodeRunner isNil ifTrue: [^memory simulationError: 'no machine code runner for a call to 16r' , (address printStringBase: 16)].
	^memory machineCodeRunner call: address type: type arguments: anArray
! !

!MachineCodeFunction methodsFor: 'comparing'!
= anObject
	^(anObject respondsTo: #simulatedAddressIn:) and: [address = (anObject simulatedAddressIn: memory)]
!
hash
	^address hash
! !

!MachineCodeFunction methodsFor: 'testing'!
isNull
	^address = 0
!
notNull
	^address ~= 0
! !

!MachineCodeFunction methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '(machine code)16r'; nextPutAll: (address printStringBase: 16)
! !
