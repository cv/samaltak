TestCase subclass: #DebuggingTestCase
	instanceVariableNames: 'sessions arrived savedOpener'
	classVariableNames: ''
	package: 'Tests-Debugging'!

DebuggingTestCase comment: 'I install a DebugSession opener that queues the sessions, fork the code under test in its own processes and clean up breakpoints, watchpoints and processes afterwards.'!

!DebuggingTestCase methodsFor: 'running'!
setUp
	sessions := OrderedCollection new.
	arrived := Semaphore new.
	savedOpener := DebugSession openerBlock.
	DebugSession openerBlock: [:session | sessions add: session. arrived signal]
!
tearDown
	DebugSession openerBlock: savedOpener.
	self terminateForkedProcesses.
	Breakpoint removeAll.
	Watchpoint removeAll
! !

!DebuggingTestCase methodsFor: 'helpers'!
fork: aBlock
	^self fork: aBlock named: 'debugged by ', self printString at: Processor activePriority
!
waitForSession
	(arrived waitTimeoutMSecs: 5000) ifTrue: [self fail: 'No debugger session opened'].
	^sessions removeFirst
!
assertNoSessionWithin: milliseconds
	self assert: (arrived waitTimeoutMSecs: milliseconds) description: 'A debugger session opened unexpectedly'
!
waitUntilTerminated: aProcess
	self assert: (self waitFor: [aProcess isTerminated]) description: 'The process did not finish'
!
textOf: aSession
	^aSession selectedSourceOf: aSession interruptedContext
!
temp: aString of: aSession
	^(aSession interruptedContext tempsAndValues detect: [:a | a key = aString]) value
! !

!DebuggingTestCase class methodsFor: 'testing'!
isAbstract
	^self == DebuggingTestCase
! !
