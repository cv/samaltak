Object subclass: #Simulator
	instanceVariableNames: 'process context startPc stopReason stopException session stepCount stepLimit'
	classVariableNames: 'PrimitiveNumbers SpecialPrimitives'
	package: 'System-Debugging'!

Simulator comment: 'I execute bytecodes in Smalltalk, exactly as the VM does, on real Context objects: the debugger steps a suspended Process with me while running in its own Process. I am the client of InstructionStream: each decoded instruction arrives as a message (pushTemporaryVariable:, send:super:numArgs:, ...) and I answer the context that is active afterwards.

Sends look up methods like the VM; primitives run through Context>>tryPrimitive:receiver:args:, except the ones that switch contexts or processes (perform, block evaluation, process and semaphore primitives), which I simulate. doesNotUnderstand:, mustBeBoolean, attemptToAssign:withIndex:, cannotReturn: and aboutToReturn:through: are sent where the VM sends them. Processor activeProcess (the message and the scheduler''s field) answers the simulated process.

When simulated code reaches an unhandled error (the send of handleUnhandledError: to Smalltalk) or would block (waiting on an unsignaled Semaphore, suspending itself) I stop before that instruction: stopReason is then #error (stopException is the exception), #blocked or #unsimulatable; #limit means stepLimit instructions ran. A DebugSession I work for can let a known exception pass (it then resumes with nil).

With a process, I also implement the debugger''s stepping operations on its stack: completeTo:, completeStep:, stepToSendOrReturn, stepInto:, stepOver:, stepThrough:, runToPc:in:, popTo:, return:from:, restart:.'!

!Simulator methodsFor: 'initialization'!
initialize
	stepCount := 0.
	stepLimit := 1000000
!
process: aProcess
	process := aProcess
!
session: aDebugSession
	session := aDebugSession
! !

!Simulator methodsFor: 'accessing'!
process
	^process
!
stopReason
	"nil, #error, #blocked, #unsimulatable or #limit."
	^stopReason
!
stopException
	^stopException
!
isStopped
	^stopReason notNil
!
resetStop
	stopReason := nil.
	stopException := nil.
	stepCount := 0
!
stepLimit
	^stepLimit
!
stepLimit: anInteger
	stepLimit := anInteger
!
stepCount
	^stepCount
! !

!Simulator methodsFor: 'stepping contexts'!
step: aContext
	"Execute the next instruction of aContext and answer the context that is active afterwards."
	aContext isDead ifTrue: [^self error: 'Cannot step a dead context'].
	context := aContext.
	startPc := aContext pc.
	stepCount := stepCount + 1.
	^aContext interpretNextInstructionFor: self
! !

!Simulator methodsFor: 'running simulated'!
runSimulated: aBlock
	"Evaluate aBlock (no arguments) entirely in the simulator and answer its value. Its contexts are not linked to the active process's stack: the block returns into a sentinel context."
	| sentinel ctx |
	sentinel := Context sender: nil receiver: self method: (Simulator >> #runSimulated:) arguments: (Array with: aBlock).
	ctx := aBlock asContextWithSender: sentinel.
	[ctx == sentinel] whileFalse: [
		ctx := self step: ctx.
		self isStopped ifTrue: [
			^self error: 'Simulation stopped (', stopReason, ')', (stopException isNil ifTrue: [''] ifFalse: [': ', stopException description])]].
	^sentinel pop
! !

!Simulator methodsFor: 'stepping the process'!
send: selector from: aContext numArgs: n
	"Send selector from aContext, whose stack ends with the receiver and n arguments, as a send bytecode would; answer the new active context."
	| rcvr |
	context := aContext.
	startPc := aContext pc.
	rcvr := self stackValue: n.
	^self send: selector to: rcvr lookupIn: rcvr class numArgs: n
!
top
	^process suspendedContext
!
stepProcess
	"Execute one instruction of the process; answer its new top context."
	| ctx |
	stepCount >= stepLimit ifTrue: [
		stopReason := #limit.
		^self top].
	ctx := self step: self top.
	process suspendedContext: ctx.
	^ctx
!
calleeOf: aContext
	| ctx |
	ctx := self top.
	[ctx notNil] whileTrue: [
		ctx sender == aContext ifTrue: [^ctx].
		ctx := ctx sender].
	^nil
!
completeTo: aContext
	"Run the process until aContext is its top context again (or aContext is dead, or I stop)."
	(self top hasContext: aContext) ifFalse: [^self error: 'The context is not on the process''s stack'].
	[self top == aContext or: [aContext isDead or: [self isStopped]]] whileFalse: [self stepProcess].
	^self top
!
completeStep: aContext
	"If aContext is not on top, run until it is. Otherwise execute its next instruction and, if that was a send, run until the callee has returned."
	| ctx |
	self top == aContext ifFalse: [^self completeTo: aContext].
	ctx := self stepProcess.
	(ctx == aContext or: [self isStopped or: [aContext isDead]]) ifTrue: [^ctx].
	^self completeTo: aContext
!
stepToSendOrReturn
	"Step the top context until its next instruction is a send, return, store or block creation."
	| ctx |
	ctx := self top.
	[self isStopped or: [ctx instructionStream willSendOrReturnOrStore]] whileFalse: [
		self stepProcess == ctx ifFalse: [^self top]].
	^ctx
!
stepInto: aContext
	"Into: if aContext is on top, execute its next instruction (entering a sent method); else run until aContext is on top. Then stop at the next send or return."
	| ctx |
	self resetStop.
	self top == aContext
		ifTrue: [
			ctx := self stepProcess.
			(ctx ~~ aContext and: [ctx sender == aContext]) ifTrue: [self skipBreakpointPrologueOf: ctx]]
		ifFalse: [self completeTo: aContext].
	self isStopped ifFalse: [self stepToSendOrReturn].
	^self top
!
stepOver: aContext
	"Over: complete the current instruction of aContext (a whole send) and stop at the next send or return in aContext."
	| ctx |
	self resetStop.
	ctx := self completeStep: aContext.
	(ctx == aContext and: [self isStopped not]) ifTrue: [self stepToSendOrReturn].
	^self top
!
stepThrough: aContext
	"Like stepOver:, but also stop when a block of aContext's method activation (its home) is entered, also from a method called meanwhile. When aContext is such a block and returns, run on to the next one (or until the home is on top again)."
	| ctx home |
	self resetStop.
	home := aContext home.
	[ctx := self stepProcess.
	 self isStopped
		or: [home isDead
		or: [ctx == aContext
		or: [ctx == home
		or: [ctx isBlockContext and: [ctx home == home and: [ctx pc = ctx startpc]]]]]]]
			whileFalse.
	self isStopped ifFalse: [self stepToSendOrReturn].
	^self top
!
runToPc: targetPc in: aContext
	"Run to here: run until aContext's activation (the context itself or one of its blocks) is about to execute the instruction at targetPc, or aContext returns."
	| ctx method home |
	self resetStop.
	method := aContext method.
	home := aContext home.
	ctx := self top == aContext
		ifTrue: [self stepProcess]
		ifFalse: [self completeTo: aContext].
	[self isStopped
		or: [aContext isDead
		or: [ctx method == method and: [ctx home == home and: [ctx pc = targetPc]]]]]
			whileFalse: [ctx := self stepProcess].
	^self top
!
popTo: aContext
	"Make aContext the top context, unwinding (and running the unwind blocks of) the contexts above it. aContext gets nil as the value of its pending send."
	| callee |
	self top == aContext ifTrue: [^aContext].
	callee := self calleeOf: aContext.
	callee isNil ifTrue: [^self error: 'The context is not on the process''s stack'].
	^self return: nil from: callee
!
return: value from: aContext
	"Return value from aContext to its sender, running the unwind blocks of the contexts above it and of aContext itself, as Context>>return: does in the process."
	| target |
	target := aContext sender.
	target isNil ifTrue: [^self error: 'Cannot return from the bottom context'].
	process suspendedContext: (Context
		sender: self top
		receiver: aContext
		method: (Context compiledMethodAt: #return:)
		arguments: (Array with: value)).
	^self completeTo: target
!
restart: aContext
	"Unwind to aContext and run it again from its start."
	self resetStop.
	self popTo: aContext.
	self isStopped ifTrue: [^self top].
	aContext privRefresh.
	self skipBreakpointPrologueOf: aContext.
	self stepToSendOrReturn.
	^self top
!
skipBreakpointPrologueOf: aContext
	"A freshly activated method with a breakpoint prologue starts after it: the debugger is already there."
	| size |
	(aContext isBlockContext or: [aContext pc ~= 0]) ifTrue: [^self].
	size := aContext method propertyAt: #breakpointPrologueSize.
	size isNil ifFalse: [aContext pc: size]
! !

!Simulator methodsFor: 'private'!
stopFor: aSymbol exception: anException
	"Leave the current context before the instruction being executed."
	context pc: startPc.
	stopReason := aSymbol.
	stopException := anException.
	^context
!
stackValue: offset
	"offset 0 is the top of the stack."
	^context basicAt: context stackp - offset
!
pop: n
	n timesRepeat: [context pop]
!
popArguments: n
	| args |
	args := Array new: n.
	n to: 1 by: -1 do: [:i | args at: i put: context pop].
	^args
!
object: anObject instVarAt: index
	^self primitive: 'instVarAt' receiver: anObject args: (Array with: index)
!
object: anObject instVarAt: index put: value
	^self primitive: 'instVarAtPut' receiver: anObject args: (Array with: index with: value)
!
isImmutable: anObject
	^(self primitive: 'isImmutable' receiver: anObject args: #()) == true
!
primitive: aString receiver: anObject args: anArray
	| result |
	result := thisContext tryPrimitive: (self class primitiveNumber: aString) receiver: anObject args: anArray.
	result == #primitiveFailed ifTrue: [^self error: 'Primitive ', aString, ' failed in the simulator'].
	^result
!
outerContext: depth
	| ctx |
	ctx := context.
	depth timesRepeat: [ctx := ctx closureOrNil outerContext].
	^ctx
! !

!Simulator methodsFor: 'instruction decoding'!
doAll: messages
	"A superinstruction: perform its parts in order, like the VM."
	| result |
	messages do: [:m | result := self perform: m selector withArguments: m arguments].
	^result
!
pushTemporaryVariable: index
	context push: (context basicAt: index + 1).
	^context
!
pushReceiverVariable: index
	"Processor's activeProcess (field 2) is the simulated process."
	(index = 1 and: [process notNil and: [context receiver == Processor]]) ifTrue: [
		context push: process.
		^context].
	context push: (self object: context receiver instVarAt: index + 1).
	^context
!
pushConstant: anObject
	context push: anObject.
	^context
!
pushLiteralVariable: anAssociation
	context push: (self object: anAssociation instVarAt: 2).
	^context
!
popIntoTemporaryVariable: index
	| value |
	value := context pop.
	context basicAt: index + 1 put: value.
	^context
!
storeIntoTemporaryVariable: index
	context basicAt: index + 1 put: context top.
	^context
!
storeIntoReceiverVariable: index
	"Like the VM: a store into a read-only receiver sends attemptToAssign:withIndex: instead, leaving its answer on the stack."
	| rcvr value |
	rcvr := context receiver.
	(self isImmutable: rcvr) ifTrue: [
		value := context pop.
		context push: rcvr; push: value; push: index + 1.
		^self send: #attemptToAssign:withIndex: to: rcvr lookupIn: rcvr class numArgs: 2].
	self object: rcvr instVarAt: index + 1 put: context top.
	^context
!
storeIntoLiteralVariable: anAssociation
	self object: anAssociation instVarAt: 2 put: context top.
	^context
!
popIntoLiteralVariable: anAssociation
	self object: anAssociation instVarAt: 2 put: context pop.
	^context
!
pushOuterTemp: index depth: depth
	context push: ((self outerContext: depth) basicAt: index + 1).
	^context
!
storeIntoOuterTemp: index depth: depth
	(self outerContext: depth) basicAt: index + 1 put: context top.
	^context
!
popIntoOuterTemp: index depth: depth
	| value |
	value := context pop.
	(self outerContext: depth) basicAt: index + 1 put: value.
	^context
!
pushReceiver
	context push: context receiver.
	^context
!
pushActiveContext
	context push: context.
	^context
!
doDup
	context push: context top.
	^context
!
doPop
	context pop.
	^context
!
pushNewArrayOfSize: n
	context push: (self popArguments: n).
	^context
!
pushClosureNumArgs: numArgs numTemps: numTemps frameSize: frameSize blockSize: size
	context push: (BlockClosure basicNew
		outerContext: context
		startpc: context pc
		numArgs: numArgs
		numTemps: numTemps
		frameSize: frameSize).
	context pc: context pc + size.
	^context
!
jump: offset
	context pc: context pc + offset.
	^context
!
jump: offset if: aBoolean
	| value |
	value := context pop.
	value == aBoolean ifTrue: [
		context pc: context pc + offset.
		^context].
	(value == true or: [value == false]) ifTrue: [^context].
	"Like the VM: back to the jump, which re-executes with the answer of mustBeBoolean."
	context pc: startPc.
	context push: value.
	^self send: #mustBeBoolean to: value lookupIn: value class numArgs: 0
! !

!Simulator methodsFor: 'returning'!
methodReturnTop
	^self return: context top
!
blockReturnTop
	^self return: context top
!
methodReturnReceiver
	context push: context receiver.
	^self return: context top
!
return: value
	| sender |
	sender := context sender.
	(sender isNil or: [sender isDead]) ifTrue: [^self cannotReturn: value].
	context pc: nil.
	context privSender: nil.
	sender push: value.
	^sender
!
nonLocalReturnTop
	"^ in a block: return from the home context, or let Smalltalk unwind if an ensure:/ifCurtailed: context is in between."
	| value home homeSender ctx marked next |
	value := context top.
	home := context home.
	home isDead ifTrue: [^self cannotReturn: value].
	homeSender := home sender.
	(homeSender isNil or: [homeSender isDead]) ifTrue: [^self cannotReturn: value].
	ctx := context.
	marked := nil.
	[ctx isNil ifTrue: [^self cannotReturn: value].
	 (marked isNil and: [ctx method isUnwindMarker]) ifTrue: [marked := ctx].
	 ctx == home] whileFalse: [ctx := ctx sender].
	marked notNil ifTrue: [
		context pop.
		context push: context; push: value; push: marked.
		^self send: #aboutToReturn:through: to: context lookupIn: context class numArgs: 2].
	ctx := context.
	[next := ctx sender.
	 ctx pc: nil.
	 ctx privSender: nil.
	 ctx == home] whileFalse: [ctx := next].
	homeSender push: value.
	^homeSender
!
cannotReturn: value
	context pop.
	context push: context; push: value.
	^self send: #cannotReturn: to: context lookupIn: context class numArgs: 1
! !

!Simulator methodsFor: 'sending'!
send: selector super: isSuper numArgs: n
	| rcvr cls intercepted |
	rcvr := self stackValue: n.
	intercepted := self intercept: selector receiver: rcvr numArgs: n.
	intercepted isNil ifFalse: [^intercepted].
	cls := isSuper
		ifTrue: [context method methodClass superclass]
		ifFalse: [rcvr class].
	^self send: selector to: rcvr lookupIn: cls numArgs: n
!
sendSpecial: index numArgs: n
	"The VM never sends == ~~ class, and reads x and y of a Point directly."
	| a b |
	index = 20 ifTrue: [
		b := context pop.
		a := context pop.
		context push: a == b.
		^context].
	index = 21 ifTrue: [
		b := context pop.
		a := context pop.
		context push: a ~~ b.
		^context].
	index = 30 ifTrue: [
		context push: context pop class.
		^context].
	((index = 28 or: [index = 29]) and: [context top class == Point]) ifTrue: [
		context push: (self object: context pop instVarAt: index - 27).
		^context].
	^self send: (CompiledMethod specialSelectorAt: index) super: false numArgs: n
!
intercept: selector receiver: rcvr numArgs: n
	"Sends the simulation treats specially; answer the new active context, or nil to send normally."
	| exception |
	(selector == #activeProcess and: [rcvr == Processor and: [process notNil]]) ifTrue: [
		context pop.
		context push: process.
		^context].
	(selector == #handleUnhandledError: and: [rcvr == Smalltalk]) ifTrue: [
		exception := context top.
		(session notNil and: [session isKnownException: exception]) ifTrue: [
			self pop: 2.
			context push: nil.
			^context].
		^self stopFor: #error exception: exception].
	^nil
!
send: selector to: rcvr lookupIn: aClass numArgs: n
	| method |
	method := aClass isNil ifTrue: [nil] ifFalse: [aClass lookupSelector: selector].
	method isNil ifTrue: [
		selector == #doesNotUnderstand: ifTrue: [^self error: 'Recursive doesNotUnderstand: in the simulator'].
		context push: (Message selector: selector arguments: (self popArguments: n)).
		^self send: #doesNotUnderstand: to: rcvr lookupIn: aClass numArgs: 1].
	^self invoke: method receiver: rcvr numArgs: n
!
invoke: method receiver: rcvr numArgs: n
	"Run method's primitive, if it has one; activate method if there is none or it fails."
	| prim result |
	prim := method primitiveNumber.
	method hasRunnablePrimitive ifTrue: [
		result := self primitive: prim receiver: rcvr numArgs: n.
		result isNil ifFalse: [^result]].
	^self activate: method receiver: rcvr numArgs: n
!
primitive: prim receiver: rcvr numArgs: n
	"Answer the active context after primitive prim succeeded (or the simulation stopped), nil if it failed."
	| special args result |
	special := self class specialPrimitives at: prim ifAbsent: [nil].
	special isNil ifFalse: [^self perform: special with: rcvr with: n].
	args := Array new: n.
	1 to: n do: [:i | args at: i put: (self stackValue: n - i)].
	result := thisContext tryPrimitive: prim receiver: rcvr args: args.
	result == #primitiveFailed ifTrue: [^nil].
	self pop: n + 1.
	context push: result.
	^context
!
activate: method receiver: rcvr numArgs: n
	"A new context for method, like the VM: receiver and arguments from the stack, temporaries nil, pc 0."
	| ctx numTemps |
	numTemps := method numTemps.
	ctx := Context basicNew: (method frameSize max: n + numTemps) + 2.
	ctx setSender: context receiver: rcvr method: method closure: nil startpc: 0.
	ctx stackp: n + numTemps.
	n to: 1 by: -1 do: [:i | ctx basicAt: i put: context pop].
	context pop.
	^ctx
!
activateBlock: aBlockClosure arguments: args
	"The receiver and arguments are already popped."
	| outer ctx |
	outer := aBlockClosure outerContext.
	ctx := Context basicNew: (aBlockClosure frameSize max: args size + aBlockClosure numTemps) + 2.
	ctx setSender: context receiver: outer receiver method: outer method closure: aBlockClosure startpc: aBlockClosure startpc.
	ctx stackp: args size + aBlockClosure numTemps.
	1 to: args size do: [:i | ctx basicAt: i put: (args at: i)].
	^ctx
! !

!Simulator methodsFor: 'simulated primitives'!
simulatePerform: rcvr numArgs: n
	| selector args |
	n < 1 ifTrue: [^nil].
	selector := self stackValue: n - 1.
	(selector isSymbol and: [selector numArgs = (n - 1)]) ifFalse: [^nil].
	args := self popArguments: n - 1.
	context pop.
	args do: [:each | context push: each].
	^self send: selector to: rcvr lookupIn: rcvr class numArgs: n - 1
!
simulatePerformWithArguments: rcvr numArgs: n
	| selector args |
	n = 2 ifFalse: [^nil].
	selector := self stackValue: 1.
	args := self stackValue: 0.
	(args class == Array and: [selector isSymbol and: [selector numArgs = args size]]) ifFalse: [^nil].
	context stackp - 2 + args size > context basicSize ifTrue: [^nil].
	self pop: 2.
	args do: [:each | context push: each].
	^self send: selector to: rcvr lookupIn: rcvr class numArgs: args size
!
simulateClosureValue: rcvr numArgs: n
	| args |
	(rcvr class == BlockClosure and: [rcvr numArgs = n]) ifFalse: [^nil].
	args := self popArguments: n.
	context pop.
	^self activateBlock: rcvr arguments: args
!
simulateClosureValueWithArguments: rcvr numArgs: n
	| args |
	n = 1 ifFalse: [^nil].
	args := self stackValue: 0.
	(rcvr class == BlockClosure and: [args class == Array and: [rcvr numArgs = args size]]) ifFalse: [^nil].
	self pop: 2.
	^self activateBlock: rcvr arguments: args
!
simulateProcessResume: rcvr numArgs: n
	(rcvr class == Process and: [rcvr ~~ process]) ifFalse: [^nil].
	(rcvr suspendedContext class == Context and: [rcvr suspendingList isNil and: [rcvr isActiveProcess not]])
		ifFalse: [^nil].
	rcvr primResume.
	self pop: n + 1.
	context push: rcvr.
	^context
!
simulateProcessSuspend: rcvr numArgs: n
	| list |
	rcvr class == Process ifFalse: [^nil].
	rcvr == process ifTrue: [^self stopFor: #blocked exception: nil].
	(rcvr isActiveProcess or: [rcvr suspendingList isNil]) ifTrue: [^nil].
	list := rcvr primSuspend.
	self pop: n + 1.
	context push: list.
	^context
!
simulateProcessorYield: rcvr numArgs: n
	self pop: n + 1.
	context push: rcvr.
	^context
!
simulateSemaphoreSignal: rcvr numArgs: n
	(rcvr class includesBehavior: Semaphore) ifFalse: [^nil].
	rcvr simulatorPrimSignal.
	self pop: n + 1.
	context push: rcvr.
	^context
!
simulateSemaphoreWait: rcvr numArgs: n
	| excess |
	(rcvr class includesBehavior: Semaphore) ifFalse: [^nil].
	excess := self object: rcvr instVarAt: 3.
	(excess isInteger and: [excess > 0]) ifFalse: [^self stopFor: #blocked exception: nil].
	self object: rcvr instVarAt: 3 put: excess - 1.
	self pop: n + 1.
	context push: rcvr.
	^context
!
simulateUnsimulatable: rcvr numArgs: n
	^self stopFor: #unsimulatable exception: nil
!
simulateTryPrimitive: rcvr numArgs: n
	| args result |
	n = 3 ifFalse: [^nil].
	args := self popArguments: 3.
	context pop.
	result := thisContext tryPrimitive: (args at: 1) receiver: (args at: 2) args: (args at: 3).
	context push: result.
	^context
! !

!Simulator class methodsFor: 'instance creation'!
onProcess: aProcess
	^self new process: aProcess; yourself
! !

!Simulator class methodsFor: 'evaluating'!
evaluate: aBlock
	"Evaluate aBlock in a new Simulator and answer its value."
	^self new runSimulated: aBlock
! !

!Simulator class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self
!
startUp: resuming
	"Primitive numbers belong to the VM that runs the image: look them up again."
	PrimitiveNumbers := nil.
	SpecialPrimitives := nil
! !

!Simulator class methodsFor: 'primitives'!
primitiveNumber: aString
	"Answer the number of the primitive named aString."
	PrimitiveNumbers isNil ifTrue: [self initializePrimitives].
	^PrimitiveNumbers at: aString ifAbsent: [self error: 'No primitive named ', aString]
!
specialPrimitives
	"Primitive number -> selector of the method simulating it (sent with the receiver and the argument count)."
	SpecialPrimitives isNil ifTrue: [self initializePrimitives].
	^SpecialPrimitives
!
initializePrimitives
	| names numbers specials |
	names := Smalltalk vm primitiveNames.
	numbers := Dictionary new.
	names doWithIndex: [:name :i | name isNil ifFalse: [numbers at: name put: i]].
	specials := Dictionary new.
	#(#('perform' #simulatePerform:numArgs:)
	  #('performWithArguments' #simulatePerformWithArguments:numArgs:)
	  #('closureValue' #simulateClosureValue:numArgs:)
	  #('closureValueWithArguments' #simulateClosureValueWithArguments:numArgs:)
	  #('processResume' #simulateProcessResume:numArgs:)
	  #('processSuspend' #simulateProcessSuspend:numArgs:)
	  #('processorYield' #simulateProcessorYield:numArgs:)
	  #('semaphoreSignal' #simulateSemaphoreSignal:numArgs:)
	  #('semaphoreWait' #simulateSemaphoreWait:numArgs:)
	  #('snapshot' #simulateUnsimulatable:numArgs:)
	  #('quit' #simulateUnsimulatable:numArgs:)
	  #('tryPrimitiveWithArgs' #simulateTryPrimitive:numArgs:)) do: [:pair |
		(numbers includesKey: (pair at: 1)) ifTrue: [
			specials at: (numbers at: (pair at: 1)) put: (pair at: 2)]].
	PrimitiveNumbers := numbers.
	SpecialPrimitives := specials
! !
