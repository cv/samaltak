DebuggingTestCase subclass: #WatchpointTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Debugging'!

WatchpointTest comment: 'Tests of watchpoints: a forked process storing into a watched field stops; proceeding performs the store.'!

!WatchpointTest methodsFor: 'running'!
tearDown
	Breakpoint processFilter: nil.
	super tearDown
! !

!WatchpointTest methodsFor: 'tests'!
testProcessFilter
	| p wp mover |
	p := 3 @ 4.
	wp := Watchpoint on: p instVarNamed: #x.
	Breakpoint processFilter: [:process | false].
	mover := self fork: [p x: 5].
	self waitUntilTerminated: mover.
	self assert: p x equals: 5.
	self assert: wp hits equals: 0.
	self assert: p isReadOnlyObject.
	self assert: sessions isEmpty
!
testWatchpointUnwatchProceed
	| session p wp mover |
	p := 3 @ 4.
	wp := Watchpoint on: p instVarNamed: #x.
	self assert: p isReadOnlyObject.
	mover := self fork: [p x: p x + 1].
	session := self waitForSession.
	self assert: session kind equals: #watchpoint.
	self assert: session label equals: 'watchpoint on #x'.
	self assert: session watchpoint == wp.
	"The stack starts at the refused store's signal: ModificationForbidden(Exception)>>signal, Point(Object)>>attemptToAssign:withIndex:, Point>>x:"
	self assert: session interruptedContext selector equals: #signal.
	self assert: session interruptedContext receiver == session exception modification.
	self assert: session interruptedContext == session process suspendedContext.
	self assert: session interruptedContext sender selector equals: #attemptToAssign:withIndex:.
	self assert: session interruptedContext sender sender selector equals: #x:.
	self assert: session interruptedContext sender sender receiver == p.
	self assert: (session selectedSourceOf: session interruptedContext sender sender) equals: 'x := aNumber'.
	self assert: session fullStack size equals: session stack size.
	self assert: (session exception modification isKindOf: ModificationForbidden).
	self assert: p x equals: 3.
	wp unwatch.
	self deny: p isReadOnlyObject.
	session proceed.
	self waitUntilTerminated: mover.
	self assert: p equals: 4 @ 4.
	self assert: wp hits equals: 1
!
testProceedWhileWatchedStoresAndKeepsWatching
	| session p mover |
	p := 3 @ 4.
	Watchpoint on: p instVarNamed: #x.
	mover := self fork: [p x: 10. p x: 20].
	session := self waitForSession.
	session proceed.
	session := self waitForSession.
	self assert: p x equals: 10.
	self assert: p isReadOnlyObject.
	session proceed.
	self waitUntilTerminated: mover.
	self assert: p x equals: 20.
	self assert: p isReadOnlyObject
!
testOtherFieldsAreStoredSilently
	| p mover |
	p := 3 @ 4.
	Watchpoint on: p instVarNamed: #x.
	mover := self fork: [p y: 10].
	self waitUntilTerminated: mover.
	self assert: p equals: 3 @ 10.
	self assert: p isReadOnlyObject.
	self assert: sessions isEmpty
!
testSteppingOverTheStore
	| session p mover |
	p := 3 @ 4.
	Watchpoint on: p instVarNamed: #x.
	mover := self fork: [p x: 5. p y: 6].
	session := self waitForSession.
	"Stepping on from the refused store performs it: the signal answers the stored value."
	session stepOver: session interruptedContext sender sender.
	self assert: p x equals: 5.
	self assert: session interruptedContext selector ~~ #signal.
	session proceed.
	self waitUntilTerminated: mover.
	self assert: p equals: 5 @ 6
!
testAnyWriteWatchpoint
	| session array mover |
	array := Array new: 2.
	Watchpoint on: array.
	mover := self fork: [array at: 1 put: #a].
	session := self waitForSession.
	self assert: session label equals: 'watchpoint on any write'.
	Watchpoint removeAll.
	session proceed.
	self waitUntilTerminated: mover.
	self assert: (array at: 1) equals: #a
!
testWatchpointIsNotAnError
	"Error handlers of the program do not see watchpoints."
	| session p mover |
	p := 3 @ 4.
	Watchpoint on: p instVarNamed: #x.
	mover := self fork: [[p x: 9] on: Error do: [:e | #caught]].
	session := self waitForSession.
	self assert: session kind equals: #watchpoint.
	session proceed.
	self waitUntilTerminated: mover.
	self assert: p x equals: 9
!
testNonWatchedImmutabilityErrorsStayErrors
	| session literal mover |
	literal := #(1 2 3).
	self assert: literal isReadOnlyObject.
	self assert: ([literal at: 1 put: 9] on: ModificationForbidden do: [:e | e return: #caught]) equals: #caught.
	mover := self fork: [literal at: 1 put: 9].
	session := self waitForSession.
	self assert: session kind equals: #error.
	self assert: (session exception isKindOf: ModificationForbidden).
	session abandon.
	self assert: (literal at: 1) equals: 1
!
testUnwatchRestoresReadOnlyState
	| literal wp |
	literal := #(1 2 3).
	wp := Watchpoint on: literal.
	wp unwatch.
	self assert: literal isReadOnlyObject.
	self assert: Watchpoint all isEmpty
! !
