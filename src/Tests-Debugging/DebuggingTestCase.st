TestCase subclass: #DebuggingTestCase
	instanceVariableNames: 'sessions arrived savedOpener breakpoints watchpoints'
	classVariableNames: ''
	package: 'Tests-Debugging'!

DebuggingTestCase comment: 'I install a DebugSession opener that queues the sessions, fork the code under test in its own processes and clean up breakpoints, watchpoints and processes afterwards: only the breakpoints and watchpoints the test set (removeBreakpoints), not the image''s own; the breakpoints'' process filter is nil during the test and set back after it.'!

!DebuggingTestCase methodsFor: 'running'!
setUp
	sessions := OrderedCollection new.
	arrived := Semaphore new.
	savedOpener := DebugSession openerBlock.
	DebugSession openerBlock: [:session | sessions add: session. arrived signal].
	breakpoints := Breakpoint all.
	watchpoints := Watchpoint all.
	self replace: #processFilter of: Breakpoint with: nil
!
tearDown
	DebugSession openerBlock: savedOpener.
	self terminateForkedProcesses.
	self removeBreakpoints
!
ownBreakpoints
	"The breakpoints this test set, oldest first (Breakpoint all less those the image had)."
	^Breakpoint all reject: [:each | breakpoints includes: each]
!
ownWatchpoints
	"The watchpoints this test set."
	^Watchpoint all reject: [:each | watchpoints includes: each]
!
removeBreakpoints
	"Remove the breakpoints and watchpoints this test set; those the image had before it stay."
	self ownBreakpoints do: [:each | each remove].
	self ownWatchpoints do: [:each | each unwatch]
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
