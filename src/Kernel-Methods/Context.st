Object variableSubclass: #Context
	instanceVariableNames: 'sender pc stackp method closureOrNil receiver'
	classVariableNames: ''
	package: 'Kernel-Methods'!

Context comment: 'I am an activation of a method or block: an ordinary heap object, so every frame can be inspected, changed and restarted from Smalltalk. My indexable fields hold arguments, then temporaries, then the operand stack; stackp counts the used ones; the garbage collector clears the slots above stackp, so raise stackp before storing into a new slot. pc is the 0-based index of the next bytecode, nil once I have returned. My field order is fixed by the VM.

While my activation runs in one of the VM''s frames I may be married to it (sender holds the frame''s index): the VM answers for me from the frame. The compiler gives my methods the bytecodes the VM mediates for reading sender, pc and stackp and for storing into my fields; at:, at:put:, instVarAt: and instVarAt:put: reach the frame''s slots.

I implement exception handling and unwinding: handler contexts are activations of BlockClosure>>on:do: (marker primitive onDoMarker), unwind contexts those of ensure:/ifCurtailed: (ensureMarker). Their arguments and temporaries are read by position (tempAt:). nextHandlerContext, findNextUnwindContextUpTo: and terminateTo: are primitives that walk the frames. The VM sends me aboutToReturn:through: for a non-local return that passes an unwind context, cannotReturn: when the home context is already dead, and stackOverflow: when my process''s stack is too deep.'!

!Context methodsFor: 'accessing'!
sender
	^sender
!
pc
	^pc
!
stackp
	^stackp
!
method
	^method
!
closure
	^closureOrNil
!
closureOrNil
	^closureOrNil
!
receiver
	^receiver
!
selector
	^method isNil ifTrue: [nil] ifFalse: [method selector]
!
methodClass
	^method isNil ifTrue: [nil] ifFalse: [method methodClass]
!
home
	"Answer the method context my (possibly nested) block belongs to."
	^closureOrNil isNil
		ifTrue: [self]
		ifFalse: [closureOrNil outerContext home]
!
methodReturnContext
	^self home
!
outerContext
	^closureOrNil isNil ifTrue: [nil] ifFalse: [closureOrNil outerContext]
!
numArgs
	^closureOrNil isNil ifTrue: [method numArgs] ifFalse: [closureOrNil numArgs]
!
numTemps
	"Answer the number of arguments and temporaries of this frame."
	^closureOrNil isNil
		ifTrue: [method numArgs + method numTemps]
		ifFalse: [closureOrNil numArgs + closureOrNil numTemps]
!
arguments
	^(1 to: self numArgs) collect: [:i | self tempAt: i]
!
tempAt: index
	"Answer argument or temporary number index (arguments first)."
	^self basicAt: index
!
tempAt: index put: value
	^self basicAt: index put: value
!
tempNames
	"Answer the names of my arguments and temporaries; the compiler knows them, else t1, t2..."
	(method respondsTo: #tempNamesForContext:) ifTrue: [^method tempNamesForContext: self].
	^(1 to: self numTemps) collect: [:i | 't', i printString]
!
tempNamed: aString
	^self tempAt: (self tempNames indexOf: aString)
!
tempNamed: aString put: value
	^self tempAt: (self tempNames indexOf: aString) put: value
!
contextTag
	^self
!
size
	^stackp
!
startpc
	^closureOrNil isNil ifTrue: [method initialPC] ifFalse: [closureOrNil startpc]
! !

!Context methodsFor: 'copying'!
shallowCopy
	"The primitive fails for a married Context, whose fields and slots are its frame's: copy them as Smalltalk reads them."
	<primitive: 'shallowCopy'>
	| copy |
	copy := self class basicNew: self basicSize.
	1 to: self class instSize do: [:i | copy instVarAt: i put: (self instVarAt: i)].
	1 to: self basicSize do: [:i | copy basicAt: i put: (self basicAt: i)].
	^copy
! !

!Context methodsFor: 'private'!
setSender: aContext receiver: anObject method: aCompiledMethod closure: aClosureOrNil startpc: anInteger
	sender := aContext.
	receiver := anObject.
	method := aCompiledMethod.
	closureOrNil := aClosureOrNil.
	pc := anInteger.
	stackp := 0
!
privSender: aContext
	sender := aContext
!
pc: anInteger
	pc := anInteger
!
stackp: newStackp
	"Set the stack pointer, clearing slots that become unused."
	stackp isNil ifTrue: [stackp := 0].
	newStackp + 1 to: stackp do: [:i | self basicAt: i put: nil].
	stackp := newStackp
!
method: aCompiledMethod
	method := aCompiledMethod
!
receiver: anObject
	receiver := anObject
!
swapReceiver: anObject
	receiver := anObject
!
push: anObject
	stackp := stackp + 1.
	self basicAt: stackp put: anObject
!
pop
	| value |
	value := self basicAt: stackp.
	self basicAt: stackp put: nil.
	stackp := stackp - 1.
	^value
!
top
	^self basicAt: stackp
!
privRefresh
	"Reset me to the state of a fresh activation: pc at the start, temporaries nil, empty stack."
	| nArgs |
	pc := self startpc.
	nArgs := self numArgs.
	self stackp: self numTemps.
	nArgs + 1 to: stackp do: [:i | self basicAt: i put: nil]
! !

!Context methodsFor: 'testing'!
isContext
	^true
!
isDead
	"Answer whether I have returned (or been terminated)."
	^pc isNil
!
isBlockContext
	^closureOrNil notNil
!
isHandlerContext
	^closureOrNil isNil and: [method notNil and: [method isHandlerMarker]]
!
isUnwindContext
	^closureOrNil isNil and: [method notNil and: [method isUnwindMarker]]
!
isBottomContext
	^sender isNil
!
hasSender: aContext
	"Answer whether aContext is one of my senders."
	| ctx |
	self == aContext ifTrue: [^false].
	ctx := sender.
	[ctx == nil] whileFalse: [
		ctx == aContext ifTrue: [^true].
		ctx := ctx sender].
	^false
!
hasContext: aContext
	"Answer whether aContext is me or one of my senders."
	^self == aContext or: [self hasSender: aContext]
! !

!Context methodsFor: 'querying'!
findContextSuchThat: aBlock
	"Answer the first context in my sender chain (starting with me) satisfying aBlock, or nil."
	| ctx |
	ctx := self.
	[ctx == nil] whileFalse: [
		(aBlock value: ctx) ifTrue: [^ctx].
		ctx := ctx sender].
	^nil
!
bottomContext
	| ctx |
	ctx := self.
	[ctx sender == nil] whileFalse: [ctx := ctx sender].
	^ctx
!
stack
	"Answer my sender chain, me first."
	^self stackOfSize: SmallInteger maxVal
!
stackOfSize: limit
	| result ctx |
	result := OrderedCollection new.
	ctx := self.
	[ctx == nil or: [result size >= limit]] whileFalse: [
		result add: ctx.
		ctx := ctx sender].
	^result asArray
!
copyStackUpTo: aContext
	"Answer a copy of me and my senders up to aContext (excluded, or to the bottom); the last copy has no sender."
	| top copy prev ctx |
	ctx := self.
	[ctx == nil or: [ctx == aContext]] whileFalse: [
		copy := ctx copy.
		prev isNil ifTrue: [top := copy] ifFalse: [prev privSender: copy].
		prev := copy.
		ctx := ctx sender].
	prev isNil ifFalse: [prev privSender: nil].
	^top
!
depthBelow: aContext
	| ctx depth |
	ctx := self.
	depth := 0.
	[ctx == nil or: [ctx == aContext]] whileFalse: [ctx := ctx sender. depth := depth + 1].
	^depth
! !

!Context methodsFor: 'exception handling'!
exceptionClass
	"I am an on:do: context: my first argument."
	^self tempAt: 1
!
exceptionHandlerBlock
	^self tempAt: 2
!
handlerActive
	^self tempAt: 3
!
findNextHandlerContext
	"Answer the first on:do: context starting with me, or nil."
	| ctx |
	ctx := self.
	[ctx == nil] whileFalse: [
		ctx isHandlerContext ifTrue: [^ctx].
		ctx := ctx sender].
	^nil
!
nextHandlerContext
	"Answer the first on:do: context among my senders, or nil."
	<primitive: 'nextHandlerContext'>
	^sender isNil ifTrue: [nil] ifFalse: [sender findNextHandlerContext]
!
handleSignal: exception
	"I am an on:do: context. If my exception class handles exception and I am not already running my handler, run the handler block and return its value from on:do:; otherwise pass exception to the next handler."
	| value |
	((self tempAt: 3) == true and: [(self tempAt: 1) handles: exception])
		ifFalse: [^self nextHandlerContext handleSignal: exception].
	exception privHandlerContext: self.
	self tempAt: 3 put: false.
	value := [(self tempAt: 2) cull: exception]
		ensure: [self tempAt: 3 put: true].
	"on:do: answers what its protected block answers: resuming me returns value from on:do:"
	self resume: value
!
findNextUnwindContextUpTo: aContext
	"Answer the next ensure:/ifCurtailed: context among my senders, stopping before aContext."
	<primitive: 'findNextUnwindContext'>
	| ctx |
	ctx := sender.
	[ctx == nil or: [ctx == aContext]] whileFalse: [
		ctx isUnwindContext ifTrue: [^ctx].
		ctx := ctx sender].
	^nil
! !

!Context methodsFor: 'controlling'!
return: value
	"Unwind thisContext to me and return value to my sender, running unwind blocks on the way."
	sender isNil ifTrue: [^self cannotReturn: value to: sender].
	sender resume: value
!
return: value through: firstUnwindContext
	sender isNil ifTrue: [^self cannotReturn: value to: sender].
	sender resume: value through: firstUnwindContext
!
resume: value
	"Unwind thisContext to me and continue me with value as the result of my pending send."
	self resume: value through: (thisContext findNextUnwindContextUpTo: self)
!
resume: value through: firstUnwindContext
	"Unwind thisContext to me, running the unwind blocks from firstUnwindContext on, then continue me with value."
	| ctx unwindBlock |
	self isDead ifTrue: [^self cannotReturn: value to: self].
	ctx := firstUnwindContext.
	[ctx isNil] whileFalse: [
		(ctx tempAt: 2) isNil ifTrue: [
			ctx tempAt: 2 put: true.
			unwindBlock := ctx tempAt: 1.
			thisContext terminateTo: ctx.
			unwindBlock value].
		ctx := ctx findNextUnwindContextUpTo: self].
	thisContext terminateTo: self.
	^value
!
aboutToReturn: result through: firstUnwindContext
	"Sent by the VM: a non-local return from my block passes an unwind context. Return from my home, running the unwind blocks."
	self methodReturnContext return: result through: firstUnwindContext
!
cannotReturn: result
	"Sent by the VM: my block's home context has already returned. If the error is resumed, answer the value from the block instead."
	| value |
	value := self cannotReturn: result to: self home sender.
	sender isNil ifTrue: [^Processor terminateActive].
	self return: value
!
cannotReturn: result to: aContext
	^BlockCannotReturn new
		result: result;
		deadHome: aContext;
		signal: 'Block cannot return'
!
stackOverflow: depth
	"Sent by the VM at a safepoint of mine (between two instructions) when my process is depth activations deep, beyond Process maxStackDepth. Let the process signal StackOverflow, then continue me where I was: a return would push a value onto my stack."
	Processor activeProcess stackOverflowIn: self depth: depth.
	stackp > 0 ifTrue: [^self jump].
	Processor activeProcess continueAt: self
!
terminate
	"Make me unresumable."
	sender := nil.
	pc := nil
!
terminateTo: previousContext
	"Terminate the contexts between me and previousContext (if it is one of my senders) and make it my sender."
	<primitive: 'terminateTo'>
	| ctx next |
	(self hasSender: previousContext) ifTrue: [
		ctx := sender.
		[ctx == previousContext] whileFalse: [
			next := ctx sender.
			ctx terminate.
			ctx := next]].
	sender := previousContext
!
unwindTo: aContext
	"Run the unwind blocks between me and aContext without terminating anything."
	| ctx unwindBlock |
	ctx := self.
	[(ctx := ctx findNextUnwindContextUpTo: aContext) isNil] whileFalse: [
		(ctx tempAt: 2) isNil ifTrue: [
			ctx tempAt: 2 put: true.
			unwindBlock := ctx tempAt: 1.
			unwindBlock value]]
!
restart
	"Unwind thisContext to me and run me again from the start."
	| ctx |
	self isDead ifTrue: [^self cannotReturn: nil to: self].
	self privRefresh.
	ctx := thisContext.
	[(ctx := ctx findNextUnwindContextUpTo: self) isNil] whileFalse: [
		(ctx tempAt: 2) isNil ifTrue: [
			ctx tempAt: 2 put: true.
			thisContext terminateTo: ctx.
			(ctx tempAt: 1) value]].
	thisContext terminateTo: self.
	self jump
!
restartWithNewReceiver: anObject
	self swapReceiver: anObject; restart
!
jump
	"Abandon thisContext and continue me in the current process. My top stack value is popped here and pushed back by the return, so I continue exactly where my pc says."
	| top |
	stackp = 0 ifTrue: [^self error: 'Cannot jump into a context with an empty frame'].
	top := self pop.
	thisContext privSender: self.
	^top
! !

!Context methodsFor: 'printing'!
printOn: aStream
	| mclass |
	method isNil ifTrue: [^aStream nextPutAll: 'a Context (no method)'].
	closureOrNil isNil ifFalse: [aStream nextPutAll: '[] in '].
	mclass := method methodClass.
	(closureOrNil isNil and: [mclass notNil and: [receiver class ~~ mclass]])
		ifTrue: [aStream nextPutAll: receiver class name; nextPut: $(; nextPutAll: mclass name; nextPut: $)]
		ifFalse: [aStream nextPutAll: (mclass isNil ifTrue: ['nil'] ifFalse: [mclass name])].
	aStream nextPutAll: '>>'; nextPutAll: (method selector ifNil: ['?']).
	pc isNil ifTrue: [aStream nextPutAll: ' (dead)']
!
printStackOn: aStream limit: limit
	"Print my sender chain, one context per line."
	| ctx count |
	ctx := self.
	count := 0.
	[ctx == nil or: [count >= limit]] whileFalse: [
		aStream print: ctx; nextPut: Character lf.
		ctx := ctx sender.
		count := count + 1].
	ctx isNil ifFalse: [aStream nextPutAll: '...'; nextPut: Character lf]
!
stackString
	^String new: 1000 streamContents: [:s | self printStackOn: s limit: 100]
! !

!Context class methodsFor: 'instance creation'!
newForMethod: aCompiledMethod
	"Answer an empty context big enough for aCompiledMethod, with the VM's headroom for synthesized sends (attemptToAssign:withIndex:, aboutToReturn:through:)."
	^self basicNew: aCompiledMethod frameSize + VMConstants ctxSlack
!
sender: aContext receiver: anObject method: aCompiledMethod arguments: anArray
	"Answer a context that will run aCompiledMethod with anObject and anArray when control returns to it."
	| ctx |
	ctx := self newForMethod: aCompiledMethod.
	ctx setSender: aContext receiver: anObject method: aCompiledMethod closure: nil startpc: aCompiledMethod initialPC.
	ctx stackp: aCompiledMethod numArgs + aCompiledMethod numTemps.
	1 to: anArray size do: [:i | ctx tempAt: i put: (anArray at: i)].
	^ctx
! !
