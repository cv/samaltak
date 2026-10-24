!Context methodsFor: '*System-Debugging'!
interpretNextInstructionFor: client
	"Decode my next instruction, move my pc past it and send client the message describing it (see InstructionStream). Answer the client's answer."
	| stream message |
	stream := InstructionStream on: method pc: pc.
	message := stream nextInstruction.
	pc := stream pc.
	^client perform: message selector withArguments: message arguments
!
step
	"Execute my next instruction with the Simulator; answer the context that is active afterwards."
	^Simulator new step: self
!
instructionStream
	"An InstructionStream at my pc."
	^InstructionStream on: method pc: pc
!
willSend
	^self instructionStream willSend
!
willReturn
	^self instructionStream willReturn
!
returnValue
	"The value my next instruction returns (when I willReturn): the receiver for a return of self, else the top of my stack."
	^self instructionStream nextOpcode = 16r7A ifTrue: [self receiver] ifFalse: [self top]
!
willStore
	^self instructionStream willStore
!
tryPrimitive: index receiver: anObject args: anArray
	"Run primitive index with anObject and anArray as if a method with it was sent; answer its result, or #primitiveFailed. Primitives that switch contexts or processes always fail."
	<primitive: 'tryPrimitiveWithArgs'>
	^#primitiveFailed
!
isTopOf: aProcess
	^aProcess suspendedContext == self
!
sourceCode
	^method isNil ifTrue: [nil] ifFalse: [method sourceCode]
!
sourceIntervalAsTop: aBoolean
	"Answer the source Interval of my current position: the next instruction to run when I am the top context (aBoolean), else the send I wait for. Answer nil if unknown."
	| interval |
	(method isNil or: [pc isNil or: [(method respondsTo: #sourceIntervalAt:) not]]) ifTrue: [^nil].
	aBoolean ifFalse: [interval := method sourceIntervalBefore: pc].
	interval isNil ifTrue: [interval := method sourceIntervalAt: pc].
	^interval
!
tempsAndValues
	"Answer name -> value Associations for my arguments and temporaries in scope at my pc, then those of my outer contexts (closest first) not shadowed by mine."
	| result seen ctx names |
	result := OrderedCollection new.
	seen := Set new.
	ctx := self.
	[ctx notNil] whileTrue: [
		names := ctx tempNames.
		1 to: (names size min: ctx stackp) do: [:i | | name |
			name := (names at: i) asString.
			((seen includes: name) or: [ctx isTempSlotHidden: i]) ifFalse: [
				seen add: name.
				result add: name -> (ctx tempAt: i)]].
		ctx := ctx outerContext].
	^result asArray
!
isTempSlotHidden: anIndex
	"Whether my temporary anIndex belongs to an inlined block my pc is not in (its name is out of scope)."
	^(method respondsTo: #isTempSlot:hiddenAt:)
		and: [method isTempSlot: anIndex - 1 hiddenAt: (pc ifNil: [0])]
!
tempSlots
	"Answer Arrays {name. context. index} for every argument and temporary visible here (mine, then my outer contexts')."
	| result seen ctx names |
	result := OrderedCollection new.
	seen := Set new.
	ctx := self.
	[ctx notNil] whileTrue: [
		names := ctx tempNames.
		1 to: (names size min: ctx stackp) do: [:i | | name |
			name := (names at: i) asString.
			(seen includes: name) ifFalse: [
				seen add: name.
				result add: (Array with: name with: ctx with: i)]].
		ctx := ctx outerContext].
	^result asArray
!
evaluateInFrame: aString
	"Evaluate aString with self bound to my receiver and my temporaries (and those of my outer contexts) as variables; assignments to them change this frame."
	| slots bindings result |
	slots := self tempSlots.
	bindings := Dictionary new.
	slots do: [:slot |
		bindings at: (slot at: 1) asSymbol put: (slot at: 1) asSymbol -> ((slot at: 2) tempAt: (slot at: 3))].
	result := Compiler evaluate: aString for: receiver bindings: bindings.
	slots do: [:slot | | value |
		value := (bindings at: (slot at: 1) asSymbol) value.
		((slot at: 2) tempAt: (slot at: 3)) == value ifFalse: [(slot at: 2) tempAt: (slot at: 3) put: value]].
	^result
! !

!Context class methodsFor: '*System-Debugging'!
executeMethod: aCompiledMethod receiver: anObject arguments: anArray
	"Run aCompiledMethod with anObject and anArray as if it had been sent (primitive first), and answer its result. aCompiledMethod need not be installed."
	| prim result ctx |
	prim := aCompiledMethod primitiveNumber.
	aCompiledMethod hasRunnablePrimitive ifTrue: [
		result := thisContext tryPrimitive: prim receiver: anObject args: anArray.
		result == #primitiveFailed ifFalse: [^result]].
	ctx := self sender: thisContext receiver: anObject method: aCompiledMethod arguments: anArray.
	"jump pops my top value and pushes it back; give it one to pop."
	ctx push: nil.
	^ctx jump
! !
