ToolsTestCase subclass: #WorkspaceTest
	instanceVariableNames: 'window'
	classVariableNames: ''
	package: 'Tests-Tools'!

WorkspaceTest comment: 'I test the Workspace: print it inserts the result as a #result mark, do-its run in a Process named ''Workspace doIt'' while the window stays responsive, variables persist, syntax errors are marked inline, inspect it opens an Inspector, ⌘P typed for real works, and the Transcript shows what any Process writes.'!

!WorkspaceTest methodsFor: 'running'!
setUp
	super setUp.
	window := self openWorkspaceWith: '3 + 4
(3 + 4
x := 6 * 7
x + 1
(Delay forMilliseconds: 400) wait. Processor activeProcess name
{3/4. 3@4}
'
! !

!WorkspaceTest methodsFor: 'tests'!
testPrintItInsertsTheResult
	| ws |
	ws := self evaluate: '3 + 4' in: window mode: #print.
	self assert: (self markTexts: #result in: ws editor) asArray equals: #('7').
	self assert: (ws editor text beginsWith: '3 + 4 7')
!
testCommandPTypedForReal
	| ws |
	ws := window content.
	self in: window do: [ws editor focus. ws editor selectFrom: 1 to: 5].
	self settle.
	self key: $p modifiers: self commandModifier.
	self assert: (self waitFor: [(ws editor marksStyled: #result) notEmpty]) description: 'no result after ⌘P'.
	self assert: (self markTexts: #result in: ws editor) asArray equals: #('7')
!
testDoItRunsInItsOwnProcess
	| ws marks |
	ws := window content.
	self in: window do: [
		| i |
		i := ws editor text indexOfSubCollection: '(Delay'.
		ws editor selectFrom: i to: (ws editor text indexOf: Character lf startingAt: i) - 1.
		ws editor printIt].
	self assert: (self waitFor: [ws evaluator running notEmpty]).
	self assert: ws evaluator running first name equals: 'Workspace doIt'.
	"The window's own Process is free meanwhile."
	self assert: (self in: window do: [Processor activeProcess]) == window process.
	self assert: (self waitFor: [window isBusy]) description: 'no busy indicator while the do-it runs'.
	self assert: (self waitFor: [(ws editor marksStyled: #result) notEmpty] timeout: 3000).
	marks := self markTexts: #result in: ws editor.
	self assert: marks first equals: '''Workspace doIt'''.
	self assert: (self waitFor: [window isBusy not])
!
testVariablesPersist
	| ws |
	ws := self evaluate: 'x := 6 * 7' in: window mode: #do.
	self assert: (ws bindings at: #x) value equals: 42.
	self evaluate: 'x + 1' in: window mode: #print.
	self assert: (self markTexts: #result in: ws editor) asArray equals: #('43')
!
testSyntaxErrorIsMarkedInline
	| ws errors |
	ws := window content.
	self in: window do: [
		ws editor selectFrom: 7 to: 12.
		ws editor printIt].
	errors := self markTexts: #error in: ws editor.
	self assert: errors size equals: 1.
	self assert: (errors first includesSubstring: 'expected').
	self assert: ws evaluator running isEmpty
!
testInspectItOpensAnInspector
	| inspector |
	self evaluate: '{3/4. 3@4}' in: window mode: #inspect.
	self assert: (self waitFor: [(self windowsOf: Inspector) notEmpty]).
	inspector := (self windowsOf: Inspector) first.
	self assert: inspector title equals: 'Inspector: an Array'.
	self assert: inspector content object equals: {3/4. 3@4}
!
testTranscriptShowsOutputOfAnyProcess
	| tw done |
	tw := self open: [TranscriptView openIn: (700 @ 100 extent: 500 @ 200)].
	done := Semaphore new.
	self fork: [Transcript show: 'from another process'; cr. done signal] at: 30.
	done wait.
	self assert: (self waitFor: [tw content text includesSubstring: 'from another process'])
! !
