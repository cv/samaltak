Object subclass: #DebugSession
	instanceVariableNames: 'process exception kind label interruptedContext listeners knownExceptions state stopReason statementMaps statementContext statement pendingStore'
	classVariableNames: 'OpenerBlock OpenerProcesses Shown ProcessListeners'
	package: 'System-Debugging'!

DebugSession comment: 'I am the model of a debugger on one suspended Process: its stack, the source and current interval of each frame, receiver fields and temporaries, evaluation in a frame, stepping (with the Simulator, in the debugger''s own process), stepping Over by statements and the pc highlight that goes with it, edit-and-continue, creating a missing method for a doesNotUnderstand:, proceeding and abandoning. The debugger window (UI) is built on me; I notify it through blocks registered with when:.

Sessions come from the unhandled-error hook: when DebugSession openerBlock is set, an unhandled error, halt, breakpoint (BreakpointHalt), watchpoint (WatchpointHit), doesNotUnderstand: or user interrupt (Process>>interrupt) in any process suspends that process and calls the opener block with a new session, in a new process. Without an opener block (headless) the kernel''s default applies: print the error and the stack, terminate the process. DebugSession debugProcess: opens a session on a process that is not stopped by an error.

kind is #halt #breakpoint #watchpoint #interrupt #dnu #error or #suspended. interruptedContext is the frame of interest, the top of the stack: halts and breakpoints are run up to the halted frame before the opener is called; for errors and watchpoints the frames above the signal context (handler search, the unhandled-error machinery, the debugger''s opening) are unwound (their unwind blocks run, simulated) so that the signal answers into it, and for a doesNotUnderstand: (its frame is the top) the frames above the doesNotUnderstand: frame. A watchpoint''s store is performed when the process continues (proceed, or a step). Events announced: #stepped #stopped #restarted #recompiled #methodCreated #evaluated #proceeded #terminated.'!

!DebugSession methodsFor: 'accessing'!
process
	^process
!
exception
	"The exception that stopped the process (or the last one hit while stepping), nil if none."
	^exception
!
kind
	^kind
!
label
	^label
!
interruptedContext
	^interruptedContext
!
topContext
	^interruptedContext
!
breakpoint
	^kind == #breakpoint ifTrue: [exception breakpoint] ifFalse: [nil]
!
watchpoint
	^kind == #watchpoint ifTrue: [exception watchpoint] ifFalse: [nil]
!
stopReason
	"Why the last step ended early: nil, #error (see exception), #blocked (the process would wait or suspend: proceed instead), #unsimulatable or #limit."
	^stopReason
!
state
	"#suspended, #running (proceeded) or #terminated."
	^state
!
isSuspended
	^state == #suspended and: [process isSuspended]
!
isKnownException: anException
	^knownExceptions includes: anException
! !

!DebugSession methodsFor: 'stack'!
stack
	"The frames from the interrupted context down."
	^interruptedContext isNil ifTrue: [#()] ifFalse: [interruptedContext stack]
!
stackOfSize: anInteger
	^interruptedContext isNil ifTrue: [#()] ifFalse: [interruptedContext stackOfSize: anInteger]
!
fullStack
	"All frames of the process, including the signaling machinery above the interrupted context."
	^process suspendedContext isNil ifTrue: [#()] ifFalse: [process suspendedContext stack]
!
fullStackOfSize: anInteger
	"The top anInteger frames of fullStack."
	^process suspendedContext isNil ifTrue: [#()] ifFalse: [process suspendedContext stackOfSize: anInteger]
!
fullStackDepth
	"fullStack size, without collecting the frames (a runaway recursion has a million)."
	^process suspendedContext isNil ifTrue: [0] ifFalse: [process suspendedContext depthBelow: nil]
!
hasFrame: aContext
	"Whether aContext is one of the process's frames."
	^process suspendedContext notNil and: [process suspendedContext hasContext: aContext]
!
isTop: aContext
	^process suspendedContext == aContext
! !

!DebugSession methodsFor: 'frames'!
sourceOf: aContext
	^aContext sourceCode
!
intervalOf: aContext
	"The source Interval to highlight in aContext: its next instruction if it is the top context, else the send it is waiting for. nil if unknown."
	^aContext sourceIntervalAsTop: (self isTop: aContext)
!
pcIntervalOf: aContext
	"The source Interval to highlight as aContext's pc: the statement being stepped over (see stepOverStatement:) if aContext is the frame stepped in and its next instruction lies in it, else intervalOf:."
	| raw current |
	raw := self intervalOf: aContext.
	current := self statementIn: aContext.
	(current notNil and: [raw notNil and: [current first <= raw first and: [raw last <= current last]]])
		ifTrue: [^current].
	^raw
!
selectedSourceOf: aContext
	| source interval |
	source := self sourceOf: aContext.
	interval := self intervalOf: aContext.
	(source isNil or: [interval isNil]) ifTrue: [^''].
	^source copyFrom: interval first to: (interval last min: source size)
!
pcOfSourcePosition: anInteger in: aContext
	"The pc of the innermost mapped instruction of aContext's method whose source interval contains anInteger (for Run to here), or nil."
	| map best bestSize |
	map := aContext method sourceMap.
	map isNil ifTrue: [^nil].
	best := nil.
	bestSize := SmallInteger maxVal.
	1 to: map size by: 3 do: [:i | | start stop |
		start := map at: i + 1.
		stop := map at: i + 2.
		(anInteger between: start and: stop) ifTrue: [
			stop - start < bestSize ifTrue: [
				best := map at: i.
				bestSize := stop - start]]].
	^best
!
receiverOf: aContext
	^aContext receiver
!
receiverFieldsOf: aContext
	"name -> value Associations for the receiver's instance variables, then its first 100 indexed fields."
	| rcvr cls result |
	rcvr := aContext receiver.
	cls := rcvr class.
	result := OrderedCollection new.
	cls allInstVarNames doWithIndex: [:name :i |
		result add: name asString -> (thisContext tryPrimitive: (Simulator primitiveNumber: 'instVarAt') receiver: rcvr args: (Array with: i))].
	(cls isVariable and: [cls isPointers]) ifTrue: [
		1 to: (rcvr basicSize min: 100) do: [:i | result add: i printString -> (rcvr basicAt: i)]].
	^result asArray
!
tempsOf: aContext
	"name -> value Associations for aContext's arguments and temporaries (and those of its outer contexts)."
	^aContext tempsAndValues
!
where
	"Answer a one-line description of where the process is."
	| text |
	interruptedContext isNil ifTrue: [^process printString].
	text := self selectedSourceOf: interruptedContext.
	^interruptedContext printString, (text isEmpty ifTrue: [''] ifFalse: [': ', text])
! !

!DebugSession methodsFor: 'evaluating'!
evaluate: aString inFrame: aContext
	"Evaluate aString with self = aContext's receiver and its temporaries as variables (assignments change the frame), in the active (debugger's) process with breakpoints ignored. Answer the value."
	| value |
	value := Breakpoint ignoreDuring: [aContext evaluateInFrame: aString].
	self announce: #evaluated.
	^value
!
evaluate: aString
	^self evaluate: aString inFrame: interruptedContext
! !

!DebugSession methodsFor: 'stepping'!
stepInto
	^self stepInto: interruptedContext
!
stepOver
	^self stepOver: interruptedContext
!
stepThrough
	^self stepThrough: interruptedContext
!
stepInto: aContext
	"Into: enter the next send of aContext (or run until aContext is on top)."
	^self simulate: [:sim | sim stepInto: aContext] announcing: #stepped
!
stepOver: aContext
	"Over: complete the current send of aContext and stop at its next send, store or return."
	^self simulate: [:sim | sim stepOver: aContext] announcing: #stepped
!
stepThrough: aContext
	"Through: like Over, but stop when a block of aContext's method activation is entered."
	^self simulate: [:sim | sim stepThrough: aContext] announcing: #stepped
!
stepOverStatement
	^self stepOverStatement: interruptedContext
!
stepOverStatement: aContext
	"Over by statements: if the highlighted statement of aContext contains a nested one at its pc (the condition of a loop), highlight that without running. Else run aContext (stepOver:) until it reaches another statement and highlight the outermost statement entered, or until it returns, stops or another frame is on top. Answer the frame to show."
	| raw map chain current i before innerBefore steps finished inner k |
	map := self statementMapFor: aContext.
	raw := self intervalOf: aContext.
	chain := map chainAt: raw.
	current := self statementIn: aContext.
	i := current isNil ifTrue: [0] ifFalse: [chain indexOf: current].
	(i > 0 and: [i < chain size]) ifTrue: [
		statementContext := aContext.
		statement := chain at: i + 1.
		self announce: #stepped.
		^aContext].
	before := chain.
	innerBefore := chain isEmpty ifTrue: [raw] ifFalse: [chain last].
	steps := 0.
	finished := false.
	[finished] whileFalse: [
		self stepOver: aContext.
		steps := steps + 1.
		(stopReason notNil or: [aContext isDead or: [interruptedContext ~~ aContext]])
			ifTrue: [finished := true]
			ifFalse: [
				raw := self intervalOf: aContext.
				chain := map chainAt: raw.
				inner := chain isEmpty ifTrue: [raw] ifFalse: [chain last].
				finished := ((self isMapped: aContext) and: [inner ~= innerBefore]) or: [steps >= 2000 or: [aContext willReturn]]]].
	(interruptedContext == aContext and: [chain notEmpty])
		ifTrue: [
			k := 1.
			[k <= chain size and: [k <= before size and: [(chain at: k) = (before at: k)]]] whileTrue: [k := k + 1].
			statementContext := aContext.
			statement := chain at: (k min: chain size)]
		ifFalse: [self highlightStatementOfTop].
	^interruptedContext
!
runToPc: anInteger inFrame: aContext
	"Run to here: until aContext's activation reaches the instruction at anInteger."
	^self simulate: [:sim | sim runToPc: anInteger in: aContext] announcing: #stepped
!
runToSourcePosition: anInteger inFrame: aContext
	| pc |
	pc := self pcOfSourcePosition: anInteger in: aContext.
	pc isNil ifTrue: [^self error: 'No code at this position'].
	^self runToPc: pc inFrame: aContext
!
restart: aContext
	"Unwind to aContext and run it again from its first statement."
	^self simulate: [:sim | sim restart: aContext] from: nil announcing: #restarted
!
return: value from: aContext
	"Make aContext return value to its sender (unwind blocks run)."
	^self simulate: [:sim | sim return: value from: aContext. sim isStopped ifFalse: [sim stepToSendOrReturn]] announcing: #stepped
! !

!DebugSession methodsFor: 'changing code'!
recompileDoIt: aString inFrame: aContext
	"Edit and continue in a do-it: compile aString as the do-it again (on the same receiver class, with the workspace variables it uses) and restart aContext on the new code. For the do-it's own frame it runs again from its first statement. For a block frame the rest of the do-it must be unchanged (same blocks, same variables, same code outside the edited block): the do-it's live frames and closures are moved to the new code (pcs mapped instruction by instruction), so later evaluations of the block run the new code too, and aContext restarts at the new block's first statement. Answer the new CompiledMethod."
	| old new |
	self checkSuspended.
	old := aContext method.
	old selector == #DoIt ifFalse: [^self error: 'Not a do-it frame'].
	new := Compiler compileDoIt: aString in: old methodClass bindings: (self bindingsOf: old).
	aContext closureOrNil isNil ifTrue: [^self restartDoIt: aContext on: new].
	^self restartBlock: aContext of: old on: new
!
bindingsOf: aDoIt
	"The workspace variables aDoIt uses (Symbol -> its Association), so the new do-it shares them."
	| bindings |
	bindings := Dictionary new.
	aDoIt literals do: [:each |
		((each isKindOf: Association) and: [each key isSymbol and: [each key notEmpty and: [each key first isLowercase
			and: [(Smalltalk associationAt: each key ifAbsent: [nil]) ~~ each]]]])
				ifTrue: [bindings at: each key put: each]].
	^bindings
!
restartDoIt: home on: aMethod
	| sim fresh |
	sim := self newSimulator.
	sim popTo: home.
	sim isStopped ifTrue: [self handleStop: sim. ^aMethod].
	fresh := Context sender: home sender receiver: home receiver method: aMethod arguments: #().
	home pc: nil; privSender: nil.
	process suspendedContext: fresh.
	sim stepToSendOrReturn.
	self afterSimulation: sim from: nil announcing: #recompiled.
	^aMethod
!
restartBlock: aContext of: old on: new
	| closure oldBlocks newBlocks k oldBlock newBlock oldIns newIns pcMap closures contexts sim fresh |
	closure := aContext closureOrNil.
	oldBlocks := self blocksOf: old.
	newBlocks := self blocksOf: new.
	k := oldBlocks findFirst: [:b | (b at: 2) = closure startpc].
	(k = 0 or: [oldBlocks size ~= newBlocks size]) ifTrue: [^self cannotRestartDoIt].
	(self tempNameListsOf: old) = (self tempNameListsOf: new) ifFalse: [^self cannotRestartDoIt].
	oldBlock := oldBlocks at: k.
	newBlock := newBlocks at: k.
	oldIns := self instructionsOf: old outside: oldBlock.
	newIns := self instructionsOf: new outside: newBlock.
	oldIns size = newIns size ifFalse: [^self cannotRestartDoIt].
	pcMap := Dictionary new.
	1 to: oldIns size do: [:i |
		(self instruction: (oldIns at: i) last matches: (newIns at: i) last) ifFalse: [^self cannotRestartDoIt].
		pcMap at: (oldIns at: i) first put: (newIns at: i) first].
	pcMap at: (oldBlock at: 2) put: (newBlock at: 2).
	pcMap at: old bytecodes size put: new bytecodes size.
	"Everything that runs the old do-it: its closures and the frames of this process and of the closures' homes."
	closures := BlockClosure allInstances select: [:c | c outerContext notNil and: [c outerContext method == old]].
	contexts := IdentitySet new.
	aContext sender ifNotNil: [:below | below stack do: [:c | c method == old ifTrue: [contexts add: c]]].
	closures do: [:c | | ctx |
		ctx := c outerContext.
		[ctx notNil] whileTrue: [
			ctx method == old ifTrue: [contexts add: ctx].
			ctx := ctx closureOrNil isNil ifTrue: [nil] ifFalse: [ctx closureOrNil outerContext]]].
	contexts remove: aContext ifAbsent: [nil].
	(closures allSatisfy: [:c | c == closure or: [pcMap includesKey: c startpc]]) ifFalse: [^self cannotRestartDoIt].
	(contexts allSatisfy: [:c | c pc isNil or: [c closureOrNil ~~ closure and: [pcMap includesKey: c pc]]]) ifFalse: [^self cannotRestartDoIt].
	sim := self newSimulator.
	sim popTo: aContext.
	sim isStopped ifTrue: [self handleStop: sim. ^new].
	closures do: [:c |
		c == closure
			ifTrue: [c instVarAt: 2 put: (newBlock at: 2); instVarAt: 4 put: (newBlock at: 4); instVarAt: 5 put: (newBlock at: 5)]
			ifFalse: [c instVarAt: 2 put: (pcMap at: c startpc)]].
	contexts do: [:c |
		c instVarAt: 4 put: new.
		c pc isNil ifFalse: [c pc: (pcMap at: c pc)]].
	fresh := closure asContextWithSender: aContext sender.
	1 to: closure numArgs do: [:i | fresh at: i put: (aContext at: i)].
	aContext pc: nil; privSender: nil.
	process suspendedContext: fresh.
	sim stepToSendOrReturn.
	self afterSimulation: sim from: nil announcing: #recompiled.
	^new
!
cannotRestartDoIt
	^self error: 'This change alters the do-it outside the block (its variables, its other blocks or code): Abandon and evaluate it again'
!
blocksOf: aMethod
	"{closure push pc. body start. body end. numArgs. numTemps. frameSize} of every block, in pc order."
	| is result pc msg |
	is := InstructionStream on: aMethod pc: 0.
	result := OrderedCollection new.
	[is atEnd] whileFalse: [
		pc := is pc.
		msg := is nextInstruction.
		msg selector == #pushClosureNumArgs:numTemps:frameSize:blockSize: ifTrue: [
			result add: (Array with: pc with: is pc with: is pc + (msg arguments at: 4)
				with: (msg arguments at: 1) with: (msg arguments at: 2) with: (msg arguments at: 3))]].
	^result asArray
!
instructionsOf: aMethod outside: aBlock
	"{pc. Message} of the instructions of aMethod not in aBlock's body."
	| is result pc msg |
	is := InstructionStream on: aMethod pc: 0.
	result := OrderedCollection new.
	[is atEnd] whileFalse: [
		pc := is pc.
		msg := is nextInstruction.
		(pc >= (aBlock at: 2) and: [pc < (aBlock at: 3)]) ifFalse: [result add: (Array with: pc with: msg)]].
	^result
!
instruction: aMessage matches: anotherMessage
	"The same instruction in the old and the new do-it: jump distances and the size of a block around the edited one may differ."
	aMessage selector == anotherMessage selector ifFalse: [^false].
	(#(#jump: #jump:if:) includes: aMessage selector) ifTrue: [^aMessage arguments allButFirst = anotherMessage arguments allButFirst].
	aMessage selector == #pushClosureNumArgs:numTemps:frameSize:blockSize: ifTrue: [^(aMessage arguments first: 2) = (anotherMessage arguments first: 2)].
	^aMessage arguments = anotherMessage arguments
!
tempNameListsOf: aMethod
	| map result |
	map := (aMethod propertyAt: #tempNames) ifNil: [#()].
	result := OrderedCollection new.
	3 to: map size by: 3 do: [:i | result add: (map at: i) asArray].
	^result asArray
!
recompile: aString inFrame: aContext
	"Edit and continue: compile aString in the class of aContext's method and install it. If it defines the same selector, rewind aContext's home frame onto the new method from its start. Answer the new CompiledMethod."
	| home oldMethod cls newMethod bp sim fresh |
	self checkSuspended.
	home := aContext home.
	oldMethod := home method.
	cls := oldMethod methodClass.
	(cls notNil and: [self isInstalled: oldMethod]) ifFalse: [^self error: 'This frame''s method is not installed in a class'].
	bp := Breakpoint forMethod: oldMethod.
	newMethod := Compiler compileMethod: aString in: cls classified: oldMethod category.
	(bp notNil and: [newMethod selector == oldMethod selector]) ifTrue: [bp remove].
	cls addSelector: newMethod selector withMethod: newMethod.
	newMethod selector == oldMethod selector ifFalse: [
		self announce: #recompiled.
		^newMethod].
	sim := self newSimulator.
	sim popTo: home.
	sim isStopped ifTrue: [self handleStop: sim. ^newMethod].
	fresh := Context sender: home sender receiver: home receiver method: newMethod arguments: home arguments.
	home pc: nil; privSender: nil.
	process suspendedContext: fresh.
	sim stepToSendOrReturn.
	self afterSimulation: sim from: nil announcing: #recompiled.
	^newMethod
!
createMissingMethodIn: aClass
	"For a doesNotUnderstand: session: define the missing method in aClass as a stub (a comment and ^self shouldBeImplemented, with argument names from the arguments' classes), resend the message and stop at the start of the new method. Answer the new method."
	| message method |
	message := self dnuMessage.
	message isNil ifTrue: [^self error: 'Not stopped at a doesNotUnderstand:'].
	method := Compiler compile: (self stubSourceFor: message) in: aClass classified: 'as yet unclassified'.
	self resend: true.
	self announce: #methodCreated.
	^method
!
isInstalled: aCompiledMethod
	"Is aCompiledMethod (or the original of a breakpointed copy) the method of its class for its selector?"
	| installed |
	installed := aCompiledMethod methodClass compiledMethodAt: aCompiledMethod selector ifAbsent: [^false].
	^installed == aCompiledMethod
		or: [installed == (aCompiledMethod propertyAt: #originalMethod)
		or: [(installed propertyAt: #originalMethod) == aCompiledMethod]]
!
stubSourceFor: aMessage
	| sel names lf |
	sel := aMessage selector.
	names := self argumentNamesFor: aMessage arguments.
	lf := String with: Character lf.
	^String new: 100 streamContents: [:s |
		sel numArgs = 0 ifTrue: [s nextPutAll: sel].
		(sel numArgs = 1 and: [sel first isLetter not]) ifTrue: [s nextPutAll: sel; space; nextPutAll: names first].
		(sel numArgs > 0 and: [sel first isLetter]) ifTrue: [
			sel keywords doWithIndex: [:k :i |
				i > 1 ifTrue: [s space].
				s nextPutAll: k; space; nextPutAll: (names at: i)]].
		s nextPutAll: lf; tab; nextPutAll: '"Created in the Debugger. Write it, accept (⌘S), then Proceed."'.
		s nextPutAll: lf; nextPutAll: lf; tab; nextPutAll: '^self shouldBeImplemented']
!
argumentNamesFor: anArray
	"anInteger, aString, ... with digits added to repeated names."
	| names |
	names := OrderedCollection new.
	anArray do: [:arg | | base name n |
		base := arg class name asString.
		#('Small' 'Byte' 'Wide') do: [:prefix |
			((base beginsWith: prefix) and: [base size > prefix size and: [(base at: prefix size + 1) isUppercase]])
				ifTrue: [base := base copyFrom: prefix size + 1 to: base size]].
		base := ((base first isVowel) ifTrue: ['an'] ifFalse: ['a']), base.
		name := base.
		n := 1.
		[names includes: name] whileTrue: [n := n + 1. name := base, n printString].
		names add: name].
	^names asArray
! !

!DebugSession methodsFor: 'proceeding'!
proceed
	"Resume the process. After a halt it continues after the halt; after a watchpoint the store is performed; after a doesNotUnderstand: the message is sent again; after other errors the signal answers nil."
	process isTerminated ifTrue: [
		state := #terminated.
		^self announce: #terminated].
	self checkSuspended.
	self completePendingStore.
	self isAtPendingError ifTrue: [self newSimulator stepProcess].
	self dnuContext notNil ifTrue: [self resend: false].
	state := #running.
	self announce: #proceeded.
	self class process: process changed: #released.
	process resume
!
abandon
	"Terminate the process (its unwind blocks run)."
	state := #terminated.
	process terminate.
	self announce: #terminated.
	self class process: process changed: #released
!
terminate
	self abandon
!
removeBreakpoint
	"Remove the breakpoint or watchpoint that stopped the process."
	self breakpoint ifNotNil: [:bp | bp remove].
	self watchpoint ifNotNil: [:wp | wp unwatch]
! !

!DebugSession methodsFor: 'notification'!
when: aBlock
	"aBlock (optionally taking the event Symbol and me) is evaluated after every change."
	listeners add: aBlock
!
onChange: aBlock
	self when: aBlock
!
removeListener: aBlock
	listeners remove: aBlock ifAbsent: [nil]
!
announce: anEvent
	listeners copy do: [:each | each cull: anEvent cull: self]
! !

!DebugSession methodsFor: 'preparing'!
prepare
	"Run in the debugger's process before the session is shown: halts, breakpoints and interrupts are completed up to the halted frame, which then is the top context, stopped at its next send."
	| sim |
	self cutsToSignal ifTrue: [^self cutToSignalContext].
	(self isHaltKind and: [interruptedContext notNil and: [self waitingInterrupt not]]) ifFalse: [^self].
	(process suspendedContext hasContext: interruptedContext) ifFalse: [^self].
	kind == #interrupt ifTrue: [^self cutToInterruptedContext].
	sim := self newSimulator.
	sim completeTo: interruptedContext.
	sim isStopped ifFalse: [sim stepToSendOrReturn].
	sim isStopped ifTrue: [^self handleStop: sim].
	interruptedContext := process suspendedContext
!
isHaltKind
	^#(#halt #breakpoint #interrupt) includes: kind
!
cutsToSignal
	^#(#watchpoint #error #dnu) includes: kind
!
signalTop
	"The frame the debugged stack starts at: the store's signal (Exception>>signal of the ModificationForbidden) for a watchpoint, the doesNotUnderstand: frame for a dnu, else the exception's signal context."
	kind == #watchpoint ifTrue: [^exception modification signalContext].
	kind == #dnu ifTrue: [^self dnuContext].
	^exception signalContext
!
cutToSignalContext
	"Unwind the frames above signalTop as if the send it is in answered nil (simulated, so their unwind blocks run); signalTop becomes the top. Leaves the stack as it is if that cannot be simulated."
	| top above ctx sim |
	top := self signalTop.
	(top isNil or: [top isDead or: [(process suspendedContext hasContext: top) not]]) ifTrue: [^self].
	ctx := process suspendedContext.
	[ctx notNil and: [ctx sender ~~ top]] whileTrue: [ctx := ctx sender].
	above := ctx.
	above isNil ifTrue: [^self].
	sim := self newSimulator.
	sim return: nil from: above.
	sim isStopped ifTrue: [^self].
	kind == #watchpoint ifTrue: [pendingStore := top -> exception modification].
	interruptedContext := process suspendedContext.
	self highlightStatementOfTop
!
completePendingStore
	"A watchpoint's store waits until the process continues: perform it now (the signal then answers the stored value), unless its frame is gone."
	| top modification |
	pendingStore isNil ifTrue: [^self].
	top := pendingStore key.
	modification := pendingStore value.
	pendingStore := nil.
	top isDead ifTrue: [^self].
	Watchpoint performStore: modification.
	top pop.
	top push: modification newValue
!
cutToInterruptedContext
	"Proceeding an interrupt continues the interrupted context as it is (see Process>>pvtSignal:list:); the frames above it hold no unwind blocks. Do that here without running them."
	| ctx next |
	ctx := process suspendedContext.
	[ctx == interruptedContext] whileFalse: [
		next := ctx sender.
		ctx pc: nil; privSender: nil.
		ctx := next].
	process suspendedContext: interruptedContext
!
waitingInterrupt
	"An interrupt of a process that was waiting on a Semaphore: completing it would wait again."
	| ctx list |
	kind == #interrupt ifFalse: [^false].
	ctx := self pvtSignalContext.
	ctx isNil ifTrue: [^false].
	list := ctx tempAt: 2.
	^list notNil and: [list class ~~ LinkedList]
! !

!DebugSession methodsFor: 'private'!
setProcess: aProcess exception: anException
	process := aProcess.
	exception := anException.
	listeners := OrderedCollection new.
	knownExceptions := IdentitySet new.
	statementMaps := IdentityDictionary new.
	anException isNil ifFalse: [knownExceptions add: anException].
	state := #suspended.
	self updateFromException
!
updateFromException
	kind := self kindFor: exception.
	label := self labelFor: exception.
	interruptedContext := self interruptedContextFor: exception
!
kindFor: anException
	anException isNil ifTrue: [^#suspended].
	(anException isKindOf: BreakpointHalt) ifTrue: [^#breakpoint].
	(anException isKindOf: WatchpointHit) ifTrue: [^#watchpoint].
	(anException isKindOf: UserInterrupt) ifTrue: [^#interrupt].
	(anException isKindOf: Halt) ifTrue: [^#halt].
	(anException isKindOf: MessageNotUnderstood) ifTrue: [^#dnu].
	^#error
!
labelFor: anException
	| message |
	kind == #suspended ifTrue: [^'Suspended: ', process name].
	kind == #breakpoint ifTrue: [^'Breakpoint: ', anException breakpoint description].
	kind == #watchpoint ifTrue: [^anException watchpoint label].
	kind == #interrupt ifTrue: [^'User interrupt'].
	kind == #dnu ifTrue: [
		message := anException message.
		^'MessageNotUnderstood: ', anException receiver class name, '>>#', (message isNil ifTrue: ['?'] ifFalse: [message selector])].
	^[anException printString] on: Error do: [:e | e return: anException class name asString]
!
interruptedContextFor: anException
	| ctx |
	anException isNil ifTrue: [^process suspendedContext].
	kind == #breakpoint ifTrue: [^anException context].
	kind == #interrupt ifTrue: [
		ctx := self pvtSignalContext.
		ctx notNil ifTrue: [^ctx sender]].
	ctx := anException signalerContext.
	[ctx notNil and: [self isPlumbing: ctx]] whileTrue: [ctx := ctx sender].
	^ctx
!
isPlumbing: aContext
	"Frames of the halting and store-checking machinery, hidden above the interesting one."
	| cls sel |
	cls := aContext receiver class.
	(cls includesBehavior: Exception) ifTrue: [^true].
	(aContext receiver == Watchpoint or: [aContext receiver == Breakpoint]) ifTrue: [^true].
	sel := aContext selector.
	^aContext methodClass == Object
		and: [#(#halt #halt: #attemptToAssign:withIndex: #modificationForbiddenFor:index:value: #modificationForbiddenFor:value: #checkedAt:put:retrying:) includes: sel]
!
pvtSignalContext
	| ctx |
	ctx := exception signalContext.
	[ctx notNil] whileTrue: [
		(ctx methodClass == Process and: [ctx selector == #pvtSignal:list:]) ifTrue: [^ctx].
		ctx := ctx sender].
	^nil
!
checkSuspended
	process isSuspended ifFalse: [^self error: 'The process is not suspended']
!
newSimulator
	self checkSuspended.
	^process simulator session: self; yourself
!
simulate: aBlock announcing: anEvent
	^self simulate: aBlock from: interruptedContext announcing: anEvent
!
simulate: aBlock from: oldTop announcing: anEvent
	| sim |
	self completePendingStore.
	sim := self newSimulator.
	aBlock value: sim.
	^self afterSimulation: sim from: oldTop announcing: anEvent
!
afterSimulation: aSimulator from: oldTop announcing: anEvent
	aSimulator isStopped ifTrue: [^self handleStop: aSimulator from: oldTop].
	stopReason := nil.
	interruptedContext := process suspendedContext.
	self highlightStatementFrom: oldTop.
	self announce: anEvent.
	^interruptedContext
!
handleStop: aSimulator
	^self handleStop: aSimulator from: nil
!
handleStop: aSimulator from: oldTop
	"The simulation stopped before an unhandled error, or because the process would block."
	| sim |
	stopReason := aSimulator stopReason.
	stopReason == #error ifFalse: [
		interruptedContext := process suspendedContext.
		self highlightStatementFrom: oldTop.
		self announce: #stopped.
		^interruptedContext].
	exception := aSimulator stopException.
	knownExceptions add: exception.
	self updateFromException.
	(self cutsToSignal and: [self isAtPendingError]) ifTrue: [
		self cutToSignalContext.
		self announce: #stopped.
		^interruptedContext].
	self isHaltKind ifTrue: [
		sim := self newSimulator.
		sim completeTo: interruptedContext.
		sim isStopped ifFalse: [sim stepToSendOrReturn].
		sim isStopped ifTrue: [^self handleStop: sim].
		interruptedContext := process suspendedContext].
	self highlightStatementFrom: oldTop.
	self announce: #stopped.
	^interruptedContext
!
isAtPendingError
	"Is the top context about to send handleUnhandledError: for an error the simulation stopped at?"
	| top message |
	top := process suspendedContext.
	(top isNil or: [top isDead]) ifTrue: [^false].
	top instructionStream willSend ifFalse: [^false].
	message := top instructionStream peekInstruction.
	^message selector == #send:super:numArgs:
		and: [message arguments first == #handleUnhandledError:
		and: [self isKnownException: top top]]
!
dnuContext
	"The doesNotUnderstand: frame of the exception, if it is still on the stack."
	| ctx |
	(kind == #dnu and: [exception notNil]) ifFalse: [^nil].
	ctx := process suspendedContext.
	[ctx notNil] whileTrue: [
		(ctx selector == #doesNotUnderstand: and: [ctx receiver == exception receiver and: [(ctx tempAt: 1) == exception message]])
			ifTrue: [^ctx].
		ctx := ctx sender].
	^nil
!
dnuMessage
	^self dnuContext isNil ifTrue: [nil] ifFalse: [exception message]
!
resend: enter
	"Unwind the doesNotUnderstand: frame and the frames above it, and set its sender up to send the message again. If enter, step into the send."
	| dnu caller message receiver sim sendPc |
	dnu := self dnuContext.
	caller := dnu sender.
	message := exception message.
	receiver := exception receiver.
	sim := self newSimulator.
	sim popTo: caller.
	sim isStopped ifTrue: [^self handleStop: sim].
	caller pop.
	caller push: receiver.
	message arguments do: [:each | caller push: each].
	sendPc := self pcOfSendBefore: caller pc in: caller selector: message selector numArgs: message arguments size.
	sendPc isNil
		ifTrue: [
			"Not a send bytecode (e.g. perform:): send it from the simulator."
			sim resetStop.
			process suspendedContext: (sim send: message selector from: caller numArgs: message arguments size).
			enter ifFalse: [sim completeTo: caller]]
		ifFalse: [
			caller pc: sendPc.
			enter ifTrue: [sim stepInto: caller]].
	sim isStopped ifTrue: [^self handleStop: sim].
	kind := #halt.
	label := 'Resent #', message selector.
	interruptedContext := process suspendedContext.
	self highlightStatementOfTop.
	self announce: #stepped
!
pcOfSendBefore: anInteger in: aContext selector: aSymbol numArgs: n
	"The pc of the instruction just before anInteger in aContext's code, if it sends aSymbol with n arguments."
	| stream previous message sel |
	stream := InstructionStream on: aContext method pc: aContext startpc.
	previous := nil.
	[stream pc < anInteger] whileTrue: [
		previous := stream pc.
		message := stream nextInstruction.
		message selector == #pushClosureNumArgs:numTemps:frameSize:blockSize: ifTrue: [
			stream pc: stream pc + message arguments last]].
	(previous isNil or: [stream pc ~= anInteger]) ifTrue: [^nil].
	message selector == #send:super:numArgs: ifTrue: [sel := message arguments first].
	message selector == #sendSpecial:numArgs: ifTrue: [sel := CompiledMethod specialSelectorAt: message arguments first].
	^(sel == aSymbol and: [message arguments last = n]) ifTrue: [previous] ifFalse: [nil]
! !

!DebugSession methodsFor: 'statements'!
statementMapFor: aContext
	^statementMaps at: aContext method ifAbsentPut: [StatementMap forMethod: aContext method]
!
statementIn: aContext
	"The statement highlighted in aContext, or nil. statementContext nil: the innermost statement at the pc of the interrupted context."
	| chain |
	(statementContext isNil and: [interruptedContext notNil]) ifTrue: [
		statementContext := interruptedContext.
		chain := (self statementMapFor: interruptedContext) chainAt: (self intervalOf: interruptedContext).
		statement := chain isEmpty ifTrue: [nil] ifFalse: [chain last]].
	^aContext == statementContext ifTrue: [statement] ifFalse: [nil]
!
highlightStatementOfTop
	"Highlight the innermost statement at the pc of the interrupted context (computed when asked)."
	statementContext := nil.
	statement := nil
!
highlightStatementFrom: oldTop
	"After a step from oldTop: if it is still on top, highlight exactly its next instruction, else the innermost statement of the new top."
	interruptedContext == oldTop
		ifTrue: [statementContext := oldTop. statement := nil]
		ifFalse: [self highlightStatementOfTop]
!
isMapped: aContext
	"Does the compiler's source map have an entry for aContext's next instruction? (The counter store of an inlined to:do: has none; Over runs through it.)"
	| map pc |
	map := aContext method sourceMap.
	pc := aContext pc.
	(map isNil or: [pc isNil]) ifTrue: [^true].
	1 to: map size by: 3 do: [:i | (map at: i) = pc ifTrue: [^true]].
	^false
! !

!DebugSession methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a DebugSession('; nextPutAll: label asString; nextPut: $)
! !

!DebugSession class methodsFor: 'class initialization'!
initialize
	"Route unhandled errors of all processes through me."
	OpenerProcesses isNil ifTrue: [OpenerProcesses := IdentitySet new].
	Smalltalk unhandledErrorHandler: [:ex | DebugSession handleUnhandledError: ex]
! !

!DebugSession class methodsFor: 'opening'!
openerBlock
	"The one-argument block that shows a new session (the UI's debugger window), or nil when headless."
	^OpenerBlock
!
openerBlock: aBlockOrNil
	OpenerBlock := aBlockOrNil
!
handleUnhandledError: anException
	"The kernel's unhandled-error handler. With an opener installed: suspend the active process and call the opener with a session on it, from a new process; answer nil (resuming the exception) once the process is resumed. Otherwise the kernel default."
	| active session |
	active := Processor activeProcess.
	(OpenerBlock isNil or: [OpenerProcesses includes: active])
		ifTrue: [^Smalltalk defaultUnhandledError: anException].
	session := self basicNew setProcess: active exception: anException.
	self open: session.
	active suspend.
	^nil
!
open: aSession
	"Call the opener with aSession from a new process at the process's priority, once the process is suspended."
	| opener debugged |
	opener := OpenerBlock.
	debugged := aSession process.
	([[debugged isSuspended or: [debugged isTerminated]] whileFalse: [Processor yield].
	  OpenerProcesses add: Processor activeProcess.
	  [debugged isSuspended ifTrue: [
		[aSession prepare] on: Error do: [:e | e return: nil].
		self noteShown: aSession.
		opener value: aSession]]
			ensure: [OpenerProcesses remove: Processor activeProcess ifAbsent: [nil]]] newProcess)
		priority: debugged priority;
		name: 'debugger for ', debugged name;
		resume
!
debugProcess: aProcess
	"Answer a session on aProcess (not the active one), suspending it if it is runnable. A waiting process should be interrupted instead (Process>>interrupt)."
	aProcess isActiveProcess ifTrue: [^self error: 'Cannot debug the active process from itself'].
	aProcess isRunnable ifTrue: [aProcess suspend].
	aProcess isSuspended ifFalse: [^self error: 'The process is not suspended'].
	^self noteShown: (self basicNew setProcess: aProcess exception: nil)
!
noteShown: aSession
	(Shown ifNil: [Shown := IdentitySet new]) add: aSession.
	self process: aSession process changed: #held.
	^aSession
!
isDebugging: aProcess
	"Whether a session handed to the opener (a debugger or notifier window) still holds aProcess suspended."
	Shown isNil ifTrue: [^false].
	Shown copy do: [:each |
		(each process isSuspended and: [each state ~~ #running and: [each state ~~ #terminated]])
			ifFalse: [Shown remove: each ifAbsent: [nil]]].
	^Shown anySatisfy: [:each | each process == aProcess]
!
process: aProcess exception: anException
	"A session on suspended aProcess stopped by anException."
	^self basicNew setProcess: aProcess exception: anException
! !

!DebugSession class methodsFor: 'process listeners'!
subscribe: aKey do: aBlock
	"aBlock value: aProcess value: #held (a session holds it suspended, before a debugger shows it) or #released (proceeded: it runs again; abandoned: it is terminated). The window system starts stand-ins for its own Processes this way. Subscribing again under aKey replaces the block."
	ProcessListeners isNil ifTrue: [ProcessListeners := Dictionary new].
	ProcessListeners at: aKey put: aBlock
!
unsubscribe: aKey
	ProcessListeners isNil ifFalse: [ProcessListeners removeKey: aKey ifAbsent: [nil]]
!
process: aProcess changed: aSymbol
	ProcessListeners isNil ifTrue: [^self].
	ProcessListeners values do: [:each |
		[each value: aProcess value: aSymbol] on: Error do: [:e |
			Transcript show: 'DebugSession process listener: ', e messageText asString; cr.
			e return: nil]]
! !
