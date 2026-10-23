Object subclass: #BlockClosure
	instanceVariableNames: 'outerContext startpc numArgs numTemps frameSize'
	classVariableNames: ''
	package: 'Kernel-Methods'!

BlockClosure comment: 'I am a block: code inside a method plus the context that created me (outerContext), through which I reach the variables of enclosing scopes. My code starts at startpc in my home method''s bytecodes. When evaluated, the VM activates a Context with my numArgs arguments and numTemps temporaries. My field order is fixed by the VM.

The exception and unwinding protocol (on:do:, ensure:, ifCurtailed:) is implemented with marker primitives: the VM never runs them, but Smalltalk finds their contexts on the stack by the primitive number of their method (onDoMarker for on:do:, ensureMarker for ensure:/ifCurtailed:).'!

!BlockClosure methodsFor: 'accessing'!
outerContext
	^outerContext
!
startpc
	^startpc
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
method
	^outerContext method
!
receiver
	^outerContext receiver
!
home
	^outerContext home
!
numArgsError: n
	^self error: 'This block takes ', numArgs printString, ' argument(s), but was evaluated with ', n printString
! !

!BlockClosure methodsFor: 'private'!
outerContext: aContext startpc: pc numArgs: nArgs numTemps: nTemps frameSize: size
	outerContext := aContext.
	startpc := pc.
	numArgs := nArgs.
	numTemps := nTemps.
	frameSize := size
! !

!BlockClosure methodsFor: 'testing'!
isBlock
	^true
! !

!BlockClosure methodsFor: 'evaluating'!
value
	<primitive: 'closureValue'>
	^self numArgsError: 0
!
value: arg
	<primitive: 'closureValue'>
	^self numArgsError: 1
!
value: arg1 value: arg2
	<primitive: 'closureValue'>
	^self numArgsError: 2
!
value: arg1 value: arg2 value: arg3
	<primitive: 'closureValue'>
	^self numArgsError: 3
!
value: arg1 value: arg2 value: arg3 value: arg4
	<primitive: 'closureValue'>
	^self numArgsError: 4
!
valueWithArguments: anArray
	<primitive: 'closureValueWithArguments'>
	anArray isArray ifFalse: [^self error: 'valueWithArguments: needs an Array'].
	^self numArgsError: anArray size
!
valueNoContextSwitch
	^self value
!
cull: arg
	^numArgs = 0 ifTrue: [self value] ifFalse: [self value: arg]
!
cull: arg1 cull: arg2
	numArgs < 2 ifTrue: [^self cull: arg1].
	^self value: arg1 value: arg2
!
cull: arg1 cull: arg2 cull: arg3
	numArgs < 3 ifTrue: [^self cull: arg1 cull: arg2].
	^self value: arg1 value: arg2 value: arg3
!
cull: arg1 cull: arg2 cull: arg3 cull: arg4
	numArgs < 4 ifTrue: [^self cull: arg1 cull: arg2 cull: arg3].
	^self value: arg1 value: arg2 value: arg3 value: arg4
!
valueWithPossibleArgs: anArray
	| args |
	args := Array new: numArgs.
	1 to: (numArgs min: anArray size) do: [:i | args at: i put: (anArray at: i)].
	^self valueWithArguments: args
! !

!BlockClosure methodsFor: 'controlling'!
whileTrue: aBlock
	"Evaluate aBlock as long as the receiver evaluates to true. Inlined by the compiler for literal blocks."
	[self value] whileTrue: [aBlock value].
	^nil
!
whileFalse: aBlock
	[self value] whileFalse: [aBlock value].
	^nil
!
whileTrue
	[self value] whileTrue.
	^nil
!
whileFalse
	[self value] whileFalse.
	^nil
!
repeat
	"Evaluate the receiver forever (until a non-local return leaves it)."
	[true] whileTrue: [self value]
!
repeatWithIndex: aBlock
	| i |
	i := 0.
	[true] whileTrue: [aBlock value: (i := i + 1)]
! !

!BlockClosure methodsFor: 'exceptions'!
on: exceptionClassOrSet do: handlerBlock
	"Evaluate the receiver; if an exception matching exceptionClassOrSet is signaled meanwhile, evaluate handlerBlock with it. Context>>handleSignal: reads my arguments and handlerActive by position."
	<primitive: 'onDoMarker'>
	| handlerActive |
	handlerActive := true.
	^self value
!
on: class1 do: block1 on: class2 do: block2
	^[self on: class1 do: block1] on: class2 do: block2
!
ensure: aBlock
	"Evaluate the receiver, then aBlock, even if the receiver is left by a non-local return, an exception or process termination. Unwinding code reads aBlock and complete by position."
	<primitive: 'ensureMarker'>
	| complete returnValue |
	returnValue := self valueNoContextSwitch.
	complete isNil ifTrue: [
		complete := true.
		aBlock value].
	^returnValue
!
ifCurtailed: aBlock
	"Evaluate the receiver; evaluate aBlock only if the receiver did not complete normally."
	<primitive: 'ensureMarker'>
	| complete result |
	result := self valueNoContextSwitch.
	complete := true.
	^result
!
ifError: errorHandlerBlock
	"Evaluate the receiver; on Error evaluate errorHandlerBlock with the message text and the receiver of the error."
	^self on: Error do: [:ex |
		errorHandlerBlock cull: ex messageText cull: ex receiver]
! !

!BlockClosure methodsFor: 'scheduling'!
newProcess
	"Answer a suspended Process that will evaluate the receiver at the active priority."
	^Process
		forContext: [self value. Processor terminateActive] asContext
		priority: Processor activePriority
!
newProcessWith: anArray
	^Process
		forContext: [self valueWithArguments: anArray. Processor terminateActive] asContext
		priority: Processor activePriority
!
fork
	"Create and schedule a Process evaluating the receiver at the active priority."
	^self newProcess resume
!
forkAt: priority
	^self newProcess priority: priority; resume
!
forkNamed: aString
	^self newProcess name: aString; resume
!
forkAt: priority named: aString
	^self newProcess priority: priority; name: aString; resume
!
valueWithin: milliseconds onTimeout: timeoutBlock
	"Evaluate the receiver; if it takes longer than milliseconds, abandon it and answer timeoutBlock value."
	| process semaphore result done timedOut |
	semaphore := Semaphore new.
	done := false.
	process := [result := self value. done := true. semaphore signal] newProcess.
	process priority: Processor activePriority.
	process resume.
	timedOut := semaphore waitTimeoutMSecs: milliseconds.
	(timedOut and: [done not]) ifTrue: [
		process terminate.
		^timeoutBlock value].
	^result
! !

!BlockClosure methodsFor: 'private'!
asContext
	"Answer a Context that will evaluate the receiver when resumed; its sender is nil."
	^self asContextWithSender: nil
!
asContextWithSender: aContext
	| ctx |
	ctx := Context basicNew: frameSize + VMConstants ctxSlack.
	ctx
		setSender: aContext
		receiver: outerContext receiver
		method: outerContext method
		closure: self
		startpc: startpc.
	ctx stackp: numArgs + numTemps.
	^ctx
! !

!BlockClosure methodsFor: 'timing'!
timeToRun
	"Answer the milliseconds it takes to evaluate the receiver."
	^Time millisecondsToRun: self
!
bench
	"Answer a String with how often the receiver runs per second."
	| count start elapsed |
	count := 0.
	start := Time millisecondClockValue.
	[(elapsed := Time millisecondClockValue - start) < 1000] whileTrue: [self value. count := count + 1].
	^(count * 1000 // elapsed) printString, ' per second'
! !

!BlockClosure methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '[] in '.
	outerContext isNil
		ifTrue: [aStream nextPutAll: 'nil']
		ifFalse: [outerContext method printOn: aStream]
! !
