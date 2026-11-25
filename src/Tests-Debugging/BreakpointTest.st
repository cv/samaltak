DebuggingTestCase subclass: #BreakpointTest
	instanceVariableNames: 'transcript listener echo'
	classVariableNames: ''
	package: 'Tests-Debugging'!

BreakpointTest comment: 'Tests of method breakpoints (break, once, log, condition), per-object breakpoints and the registry.'!

!BreakpointTest methodsFor: 'running'!
setUp
	super setUp.
	transcript := OrderedCollection new.
	listener := [:text | transcript add: text].
	echo := Transcript echo.
	Transcript echo: false; addListener: listener
!
tearDown
	Transcript removeListener: listener; echo: echo.
	super tearDown
! !

!BreakpointTest methodsFor: 'tests'!
testInstallAndRemoveRestoresMethod
	| original bp patched |
	original := Integer compiledMethodAt: #gcd:.
	bp := Breakpoint on: Integer selector: #gcd:.
	patched := Integer compiledMethodAt: #gcd:.
	self deny: patched == original.
	self assert: patched sourceCode equals: original sourceCode.
	self assert: (patched sourceIntervalAt: Breakpoint prologueSize) equals: (original sourceIntervalAt: 0).
	self assert: (patched tempNamesAt: Breakpoint prologueSize) equals: (original tempNamesAt: 0).
	self assert: (Breakpoint all includes: bp).
	self assert: (Breakpoint forMethod: patched) == bp.
	"Ignored in this process: the patched method still computes."
	self assert: (Breakpoint ignoreDuring: [48 gcd: 18]) equals: 6.
	bp remove.
	self assert: (Integer compiledMethodAt: #gcd:) == original.
	self deny: (Breakpoint all includes: bp)
!
testBreakOnce
	| session bp process |
	bp := Breakpoint onceOn: Integer selector: #gcd:.
	process := self fork: [Smalltalk at: #DebugBreakOnce put: (48 gcd: 18) + (10 gcd: 4)].
	session := self waitForSession.
	self assert: session breakpoint == bp.
	self assert: bp hits equals: 1.
	self deny: (Breakpoint all includes: bp).
	self assert: (Integer compiledMethodAt: #gcd:) == bp originalMethod.
	session proceed.
	self waitUntilTerminated: process.
	self assertNoSessionWithin: 50.
	self assert: (Smalltalk at: #DebugBreakOnce) equals: 8.
	Smalltalk removeKey: #DebugBreakOnce
!
testDisabledBreakpointDoesNotStop
	| bp process result |
	bp := Breakpoint on: Integer selector: #gcd:.
	bp disable.
	process := self fork: [result := 48 gcd: 18].
	self waitUntilTerminated: process.
	self assert: result equals: 6.
	self assert: sessions isEmpty.
	bp enable.
	self assert: bp isEnabled
!
testLogpoint
	| bp result |
	bp := Breakpoint on: Integer selector: #gcd: log: 'self printString, '' gcd: '', anInteger printString'.
	result := (12 gcd: 8) + (9 gcd: 6).
	self assert: result equals: 7.
	self assert: (transcript includes: '12 gcd: 8').
	self assert: (transcript includes: '9 gcd: 6').
	self assert: bp hits equals: 2.
	self assert: sessions isEmpty
!
testConditionalBreakpoint
	| session bp process result |
	bp := Breakpoint on: Integer selector: #gcd: condition: '[anInteger > 10]'.
	process := self fork: [result := (12 gcd: 8) + (36 gcd: 24)].
	session := self waitForSession.
	self assert: (self temp: 'anInteger' of: session) equals: 24.
	self assert: session interruptedContext receiver equals: 36.
	self assert: bp hits equals: 1.
	session proceed.
	self waitUntilTerminated: process.
	self assert: result equals: 16
!
testConditionAsExpression
	| session process |
	Breakpoint on: Integer selector: #gcd: condition: 'self even and: [anInteger = 3]'.
	process := self fork: [(4 gcd: 2) + (5 gcd: 3) + (6 gcd: 3)].
	session := self waitForSession.
	self assert: session interruptedContext receiver equals: 6.
	session abandon
!
testObjectBreakpoint
	| session bp process p q result |
	p := 3 @ 4.
	q := 5 @ 6.
	bp := Breakpoint onObject: p selector: #x:.
	self assert: p class ~~ Point.
	self assert: p class superclass == Point.
	self assert: p class name equals: #Point.
	self assert: q class == Point.
	process := self fork: [q x: 1. p x: 7. result := p x + q x].
	session := self waitForSession.
	self assert: session kind equals: #breakpoint.
	self assert: session interruptedContext receiver == p.
	self assert: session interruptedContext selector equals: #x:.
	self assert: (self textOf: session) equals: 'x := aNumber'.
	self assert: q x equals: 1.
	self assert: (self temp: 'aNumber' of: session) equals: 7.
	bp remove.
	self assert: p class == Point.
	session proceed.
	self waitUntilTerminated: process.
	self assert: result equals: 8.
	self assert: p equals: 7 @ 4
!
testObjectBreakpointAnyMessage
	| session process p result |
	p := 3 @ 4.
	Breakpoint onObject: p.
	process := self fork: [result := (1 @ 1) + 1. result := p + 1].
	session := self waitForSession.
	self assert: session interruptedContext receiver == p.
	self assert: session interruptedContext selector equals: #+.
	self removeBreakpoints.
	session proceed.
	self waitUntilTerminated: process.
	self assert: result equals: 4 @ 5
!
testObjectBreakpointOnPrimitiveMethod
	| session process array result |
	array := Array new: 3.
	Breakpoint onObject: array selector: #at:put:.
	process := self fork: [array at: 2 put: #two. result := array at: 2].
	session := self waitForSession.
	self assert: (session interruptedContext receiver) == array.
	self assert: session interruptedContext selector equals: #at:put:.
	self removeBreakpoints.
	session proceed.
	self waitUntilTerminated: process.
	self assert: result equals: #two
!
testProcessFilter
	"Filtered-out processes neither stop nor count hits nor consume a break-once."
	| bp logger log session process result |
	bp := Breakpoint onceOn: Integer selector: #gcd:.
	log := Breakpoint on: Integer selector: #lcm: log: '#logged'.
	Breakpoint ignoreProcessesSatisfying: [:p | p name = 'filtered'].
	process := self fork: [result := (48 gcd: 18) + (4 lcm: 6)].
	process name: 'filtered'.
	self waitUntilTerminated: process.
	self assert: result equals: 18.
	self assert: bp hits equals: 0.
	self assert: log hits equals: 0.
	self deny: (transcript includes: 'logged').
	self assert: bp isInstalled.
	self assert: sessions isEmpty.
	process := self fork: [result := 48 gcd: 18].
	session := self waitForSession.
	self assert: session breakpoint == bp.
	self assert: bp hits equals: 1.
	session proceed.
	self waitUntilTerminated: process.
	logger := nil.
	Breakpoint processFilter: [:p | p == logger].
	self deny: (Breakpoint isIgnoring: (logger := Processor activeProcess)) .
	self assert: (Breakpoint isIgnoring: process)
!
testScopeTargetsIgnoredProcesses
	"A breakpoint in user scope skips ignored and filtered-out processes; scoped to a process it acts there (and only there), scoped to all processes everywhere, never inside ignoreDuring:."
	| bp ignored other session result |
	bp := Breakpoint on: Integer selector: #gcd:.
	ignored := self fork: [(Delay forMilliseconds: 50) wait. result := 48 gcd: 18].
	Breakpoint ignoreProcess: ignored.
	self waitUntilTerminated: ignored.
	self assert: result equals: 6.
	self assert: sessions isEmpty.
	ignored := self fork: [(Delay forMilliseconds: 50) wait. result := 48 gcd: 18].
	Breakpoint ignoreProcess: ignored.
	bp inProcess: ignored.
	self assert: bp isTargeted.
	self assert: (bp description includesSubstring: ' in ').
	session := self waitForSession.
	self assert: session process == ignored.
	other := self fork: [result := 12 gcd: 8].
	self waitUntilTerminated: other.
	self assert: result equals: 4.
	session proceed.
	self waitUntilTerminated: ignored.
	Breakpoint unignoreProcess: ignored.
	Breakpoint processFilter: [:p | false].
	bp inAllProcesses.
	self assert: bp description equals: 'Integer>>gcd: (break in all processes)'.
	other := self fork: [result := 12 gcd: 8].
	session := self waitForSession.
	self assert: session process == other.
	session proceed.
	self waitUntilTerminated: other.
	self assert: (Breakpoint ignoreDuring: [9 gcd: 6]) equals: 3.
	self assert: sessions isEmpty.
	bp inUserProcesses.
	self deny: bp isTargeted
!
testConditionBlockTakesTheReceiver
	| session process |
	Breakpoint on: Integer selector: #gcd: condition: '[:receiver :n | receiver = 36 and: [n = 24]]'.
	process := self fork: [(12 gcd: 8) + (36 gcd: 24)].
	session := self waitForSession.
	self assert: session interruptedContext receiver equals: 36.
	session proceed.
	self waitUntilTerminated: process
!
testScopedConditionalBreakpoint
	| bp session process |
	bp := Breakpoint on: Integer selector: #gcd: condition: '[anInteger > 10]' scope: #all.
	self assert: bp scope equals: #all.
	Breakpoint processFilter: [:p | false].
	process := self fork: [(12 gcd: 8) + (36 gcd: 24)].
	session := self waitForSession.
	self assert: session interruptedContext receiver equals: 36.
	self assert: bp hits equals: 1.
	session proceed.
	self waitUntilTerminated: process
!
testAllHits
	| a b |
	a := Breakpoint on: Integer selector: #gcd: log: '1'.
	b := Breakpoint on: Integer selector: #lcm: log: '2'.
	(4 gcd: 2) + (4 lcm: 6).
	self assert: ((Breakpoint allHits select: [:each | self ownBreakpoints includes: each key]) collect: [:each | each value]) asArray equals: #(2 1).
	self assert: ((Breakpoint allHits select: [:each | self ownBreakpoints includes: each key]) collect: [:each | each key]) asArray equals: {a. b}
!
testChangeNotification
	| seen block |
	seen := OrderedCollection new.
	block := [:bp | seen add: bp].
	Breakpoint addListener: block.
	[(Breakpoint on: Integer selector: #gcd:) remove] ensure: [Breakpoint removeListener: block].
	self assert: seen size equals: 2
! !
