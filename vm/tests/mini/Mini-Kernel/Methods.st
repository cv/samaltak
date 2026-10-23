Object variableSubclass: #Context
	instanceVariableNames: 'sender pc stackp method closureOrNil receiver'
	classVariableNames: ''
	package: 'Mini-Kernel'!

Object subclass: #BlockClosure
	instanceVariableNames: 'outerContext startpc numArgs numTemps frameSize'
	classVariableNames: ''
	package: 'Mini-Kernel'!

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
receiver
	^receiver
!
closure
	^closureOrNil
!
home
	closureOrNil == nil ifTrue: [^self].
	^closureOrNil outerContext home
!
tempAt: i
	^self basicAt: i
!
tempAt: i put: v
	^self basicAt: i put: v
!
isDead
	^pc == nil
!
privSender: aContext
	sender := aContext
!
kill
	pc := nil.
	sender := nil
!
setSender: s pc: p stackp: sp method: m closure: c receiver: r
	sender := s.
	pc := p.
	stackp := sp.
	method := m.
	closureOrNil := c.
	receiver := r
!
printString
	^(closureOrNil == nil ifTrue: [''] ifFalse: ['[] in ']) , method printString
! !

!Context methodsFor: 'unwinding'!
return: value
	"Return value from me to my sender, abandoning the contexts above me."
	| ctx next |
	ctx := thisContext sender.
	[ctx == self] whileFalse: [next := ctx sender. ctx kill. ctx := next].
	thisContext privSender: sender.
	self kill.
	^value
!
cannotReturn: value
	('cannotReturn: ' , value printString) displayNl.
	^self return: value
!
aboutToReturn: result through: firstUnwind
	| home |
	home := self home.
	self unwindTo: home.
	^home return: result
!
unwindTo: aContext
	| ctx |
	ctx := self.
	[ctx == aContext or: [ctx == nil]] whileFalse: [
		ctx method primitive = 198 ifTrue: [ctx runUnwindBlock].
		ctx := ctx sender]
!
runUnwindBlock
	(self tempAt: 2) == nil ifTrue: [
		self tempAt: 2 put: true.
		(self tempAt: 1) value]
! !

!BlockClosure methodsFor: 'evaluating'!
outerContext
	^outerContext
!
numArgs
	^numArgs
!
value
	<primitive: 'closureValue'>
	^self error: 'wrong argument count'
!
value: a
	<primitive: 'closureValue'>
	^self error: 'wrong argument count'
!
value: a value: b
	<primitive: 'closureValue'>
	^self error: 'wrong argument count'
!
value: a value: b value: c
	<primitive: 'closureValue'>
	^self error: 'wrong argument count'
!
value: a value: b value: c value: d
	<primitive: 'closureValue'>
	^self error: 'wrong argument count'
!
valueWithArguments: anArray
	<primitive: 'closureValueWithArguments'>
	^self error: 'wrong argument count'
!
ensure: aBlock
	| complete result |
	<primitive: 198>
	result := self value.
	complete == nil ifTrue: [complete := true. aBlock value].
	^result
!
whileTrue: aBlock
	^[self value] whileTrue: [aBlock value]
!
repeat
	[self value] repeat
!
asContext
	| ctx |
	ctx := Context basicNew: frameSize + 2.
	ctx setSender: nil pc: startpc stackp: numArgs + numTemps method: outerContext method closure: self receiver: outerContext receiver.
	^ctx
!
newProcess
	^Process new
		setContext: [self value. Processor terminateActive] asContext
		priority: Processor activeProcess priority
!
fork
	^self newProcess resume
!
forkAt: priority
	^(self newProcess) priority: priority; resume; yourself
! !

!Context methodsFor: 'simulation'!
tryPrimitive: index receiver: r args: anArray
	<primitive: 'tryPrimitiveWithArgs'>
	^self error: 'tryPrimitive failed'
! !
