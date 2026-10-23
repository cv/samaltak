TestCase subclass: #SimulatorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Debugging'!

SimulatorTest comment: 'I check that the Simulator executes bytecodes exactly like the VM: results and side effects of the SimulatorTestSubject examples, run directly and simulated; and a whole Process stepped to its end, then resumed.'!

!SimulatorTest methodsFor: 'tests'!
testEquivalence
	"Every example gives the same result and the same side effects simulated as in the VM."
	SimulatorTestSubject exampleSelectors do: [:sel | | real simulated realSubject simSubject |
		realSubject := SimulatorTestSubject new.
		simSubject := SimulatorTestSubject new.
		real := realSubject perform: sel.
		simulated := Simulator evaluate: [simSubject perform: sel].
		self assert: simulated printString equals: real printString.
		self assert: simSubject log printString equals: realSubject log printString]
!
testExamplesHaveExpectedValues
	| subject |
	subject := SimulatorTestSubject new.
	self assert: (Simulator evaluate: [subject exampleNonLocalReturnThroughEnsure]) equals: 20.
	self assert: subject log asArray equals: #(1 2).
	self assert: (Simulator evaluate: [SimulatorTestSubject new exampleMustBeBoolean]) equals: 1.
	self assert: (Simulator evaluate: [SimulatorTestSubject new exampleCannotReturn]) equals: #cannot.
	self assert: (Simulator evaluate: [SimulatorTestSubject new exampleDnuResumed]) equals: 11.
	self assert: (Simulator evaluate: [SimulatorTestSubject new exampleAttemptToAssign]) equals: 5.
	self assert: (Simulator evaluate: [SimulatorTestSubject new exampleNestedNonLocalReturn]) equals: 2 @ 5
!
testUnhandledErrorStopsTheSimulation
	| sim |
	sim := Simulator new.
	self should: [sim runSimulated: [1 / 0]] raise: Error.
	self assert: sim stopReason equals: #error.
	self assert: (sim stopException isKindOf: ZeroDivide)
!
testWholeProcessSteppedThenResumed
	"Step a fresh process through its whole computation; it stops when it would terminate (suspend itself)."
	| result process sim subject |
	subject := SimulatorTestSubject new.
	process := [result := subject exampleNonLocalReturnThroughEnsure + subject exampleRecursion] newProcess.
	sim := process simulator.
	[sim isStopped] whileFalse: [sim stepProcess].
	self assert: sim stopReason equals: #blocked.
	self assert: result equals: 630.
	self assert: subject log asArray equals: #(1 2).
	"Process>>terminate ran (simulated) up to suspending itself."
	self assert: process isTerminated
!
testProcessResumesAfterPartialSimulation
	"Simulate part of a computation, then let the VM finish it from the same contexts."
	| result process sim |
	process := self track: [result := (1 to: 10) inject: 0 into: [:a :b | a + b]] newProcess.
	sim := process simulator.
	50 timesRepeat: [sim stepProcess].
	self deny: sim isStopped.
	process resume.
	self assert: (self waitFor: [process isTerminated]).
	self assert: result equals: 55
!
testContextStep
	| ctx next |
	ctx := [3 + 4] asContext.
	next := ctx step.
	self assert: next == ctx.
	self assert: ctx top equals: 3
!
testTryPrimitive
	| add |
	add := Smalltalk vm primitiveNumberFor: 'intAdd'.
	self assert: (thisContext tryPrimitive: add receiver: 3 args: #(4)) equals: 7.
	self assert: (thisContext tryPrimitive: add receiver: 3 args: #(nil)) == #primitiveFailed
!
testInstructionStream
	| stream messages |
	stream := InstructionStream on: (Integer >> #gcd:).
	messages := OrderedCollection new.
	[stream atEnd] whileFalse: [messages add: stream nextInstruction].
	self assert: messages first selector equals: #pushReceiver.
	self assert: (messages at: 2) arguments equals: #(#abs false 0).
	self assert: messages last selector equals: #methodReturnTop.
	stream := InstructionStream on: (Integer >> #gcd:) pc: 1.
	self assert: stream willSend.
	self deny: stream willReturn
! !
