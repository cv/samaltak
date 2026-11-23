TestCase subclass: #TestIsolationTest
	instanceVariableNames: 'conversation point breakpoint watchpoint'
	classVariableNames: ''
	package: 'Tests-Agent'!

TestIsolationTest comment: 'Tests that tests leave a live image as they found it (TestCase''s comment), as they must now that the agent runs them in the image it lives in (its run-tests tool). testLiveImageSurvivesTheTests makes this image look like that one: an ApiKeyAccount and a GitHubAccount holding a key and a token as the defaults, a SourceFiler default on a source directory, an open AgentConversation, a breakpoint, a watchpoint and a process filter of its own; it marks the image live (TestCase runsInThrowawayImage: false), runs the test classes that use or replace that state, and checks that every piece is still there and unchanged, that the tests which cannot help changing the whole image were skipped, that no global was left behind, and that the AgentConversations the tests made are garbage once they ran although the TestResult is kept. testLiveWorldSurvivesTheUITests does the same for the window system (its classes looked up by name: this package comes before it): a running World with a window of its own as World current, the UI tests run (their own Worlds, nested Worlds stopped out of order, AppWorlds, applications, the debugger and the tools), and World current, that World, its windows and compositor are unchanged and no World or Compositor of the tests survives a garbage collection. testStoppedRunStopsItsTest: a run that is stopped (the run-tests tool''s timeout) stops the test it runs, which tears down, instead of leaving it running on into the next run. The other tests check TestCase''s cleanups on TestIsolationFixture.'!

!TestIsolationTest methodsFor: 'running'!
timeLimitMilliseconds
	"The UI tests take minutes on a software GPU (lavapipe)."
	^testSelector == #testLiveWorldSurvivesTheUITests ifTrue: [600000] ifFalse: [240000]
!
tearDown
	breakpoint isNil ifFalse: [breakpoint remove].
	watchpoint isNil ifFalse: [watchpoint unwatch]
! !

!TestIsolationTest methodsFor: 'support'!
classNames
	"The test classes that use or replace the image's accounts, SourceFiler default, conversations, breakpoints, TLS settings, remote control and mount table (those not in this image are left out)."
	^#('ApiKeyAccountTest' 'GitHubAccountTest' 'OpenAIAccountTest' 'AnthropicProviderTest' 'CodexProviderTest' 'AgentConversationTest' 'GitHubClientTest' 'SourceFilerGitHubTest' 'SourceDirectoryStoreTest' 'BreakpointTest' 'WatchpointTest' 'DebugSessionTest' 'RemoteControlTest' 'MountTableTest' 'SecureRandomTest' 'TLSSocketSmalltalkTest')
!
testClasses
	^((self classNames collect: [:each | Smalltalk at: each asSymbol ifAbsent: [nil]]) reject: [:each | each isNil]) asArray
!
liveConversations
	"The AgentConversations that survive a garbage collection."
	Smalltalk vm garbageCollect.
	^AgentConversation allInstances size
!
pauseProfiler
	"Stop the system profiler during the test, and start it again after if it ran: its frame table keeps every sampled CompiledMethod, a code-mode cell's too, and with it the cell's bindings (thisConversation), so what survives would depend on what it sampled."
	| profiler |
	profiler := Profiler default.
	profiler isRunning ifFalse: [^self].
	profiler stop.
	self addCleanup: [profiler start]
!
neverCalled
	"Where this test's own breakpoint is."
	^self
!
newSecret: aPrefix
	"A fake key made at run time."
	| random |
	random := Random new.
	^String new: 40 streamContents: [:s |
		s nextPutAll: aPrefix.
		30 timesRepeat: [s nextPut: ('0123456789abcdefghijklmnopqrstuvwxyz' at: (random nextInt: 36))]]
!
commandsOf: aRegistryState
	"Command name -> handler, of RemoteControl registryState."
	| commands |
	commands := Dictionary new.
	(aRegistryState at: 1) keysAndValuesDo: [:name :handler | commands at: name put: handler].
	^commands
! !

!TestIsolationTest methodsFor: 'window system'!
uiClassNames
	"Test classes that open Worlds of their own and make them current: a World per test (UIWindowsTestCase, ToolsTestCase), nested Worlds stopped out of order (WorldCurrentTest), AppWorlds, applications, the debugger's windows, a theme's World, the profiler's (those not in this image are left out)."
	^#('WorldCurrentTest' 'AppWorldTest' 'ApplicationTest' 'OmarchyThemeTest' 'DebuggerUITest' 'ProfilerViewTest' 'WorkspaceTest')
!
uiTestClasses
	^((self uiClassNames collect: [:each | Smalltalk at: each asSymbol ifAbsent: [nil]]) reject: [:each | each isNil]) asArray
!
uiSamples
	"Of the two classes that take most of the UI tests' time (DebuggerUITest a minute, ProfilerViewTest 40 s on lavapipe, each test a World of its own opened and stopped as in the others), the tests that reach into the live World's machinery: a breakpoint on every Window's redraw (the live window's too), in the Compositor and on the window manager with stand-ins, notifiers and debuggers on window Processes, the Breakpoints window, a method created from the debugger; the profiler's live updates, process filter and remote names. The other classes run in full."
	^Dictionary new
		at: #DebuggerUITest put: #(#testBreakpointHaltsOnlyOneWindowsProcess #testBreakpointInTheCompositorWithAStandIn #testWatchpointStopsTheWindowManagerWithAStandIn #testNotifierDebugOpensDebuggerAndCloseAbandons #testErrorNotifierAbandon #testBreakpointsWindow #testDoesNotUnderstandCreateAcceptProceed);
		at: #ProfilerViewTest put: #(#testLiveUpdatesMarkAndPause #testProcessFilter #testRemoteNames);
		yourself
!
uiTestCases
	"Every test of the UI classes but DebuggerUITest's and ProfilerViewTest's, of which uiSamples."
	| samples |
	samples := self uiSamples.
	^self uiTestClasses inject: OrderedCollection new into: [:all :class |
		all addAll: ((samples at: class name asSymbol ifAbsent: [nil])
			ifNil: [class suite]
			ifNotNil: [:selectors | selectors collect: [:each | self assert: (class includesSelector: each). class selector: each]]).
		all]
!
survivorsOf: aClass
	"aClass's instances that survive a garbage collection, once the Processes of closed windows ended."
	(Delay forMilliseconds: 300) wait.
	Smalltalk vm garbageCollect.
	^aClass allInstances size
! !

!TestIsolationTest methodsFor: 'tests'!
testLiveWorldSurvivesTheUITests
	| world live window compositor worlds compositors result compositorClass cases |
	world := Smalltalk at: #World ifAbsent: [^self].
	compositorClass := Smalltalk at: #Compositor.
	self keep: #current of: world.
	live := world openHidden: 800 @ 600.
	self addCleanup: [live stop].
	window := (Smalltalk at: #Window) new title: 'live'; content: (Smalltalk at: #View) new; bounds: (40 @ 60 extent: 300 @ 200); yourself.
	window openIn: live.
	self assert: (live waitUntilSettled: 5000).
	compositor := live compositor.
	self pauseProfiler.
	worlds := self survivorsOf: world.
	compositors := self survivorsOf: compositorClass.
	self replace: #runsInThrowawayImage of: TestCase with: false.
	result := TestResult new.
	cases := self uiTestCases.
	cases do: [:each | result runCase: each].
	self assert: result hasPassed description: [String new: 200 streamContents: [:s |
		s nextPutAll: 'UI tests failed in a live image:'.
		(result failures, result errors) do: [:each | s space; print: each key; nextPutAll: ': '; nextPutAll: (each value ifNil: ['']) asString]]].
	self assert: world current identicalTo: live.
	self assert: live isRunning.
	self assert: live windows asArray equals: (Array with: window).
	self assert: window isOpen.
	self assert: live compositor identicalTo: compositor.
	self assert: (compositorClass running includes: compositor).
	"What the stopped Worlds' Processes still do (the close animations' end) takes a moment."
	self assert: (self waitFor: [(self survivorsOf: world) <= worlds] timeout: 10000)
		description: [((self survivorsOf: world) - worlds) printString, ' Worlds of the UI tests survive them'].
	self assert: (self waitFor: [(self survivorsOf: compositorClass) <= compositors] timeout: 10000)
		description: [((self survivorsOf: compositorClass) - compositors) printString, ' Compositors of the UI tests survive them'].
	self assert: result runCount equals: cases size.
	self assert: cases size > 30
!
testStoppedRunStopsItsTest
	| result runner |
	TestIsolationFixture log: OrderedCollection new.
	result := TestResult new.
	runner := self fork: [result runCase: (TestIsolationFixture selector: #testWaits)] named: 'stopped run' at: Processor userSchedulingPriority.
	self assert: (self waitFor: [TestIsolationFixture log includes: #started]).
	runner terminate.
	self assert: (TestIsolationFixture log includes: #tearDown).
	self deny: ((Process allInstances select: [:p | p isTerminated not and: [p name = 'TestIsolationFixture>>#testWaits']]) notEmpty)
!
testLiveImageSurvivesTheTests
	| key token keyAccount gitHub filerClass filer directory filerStore files openAI signedIn filter useSmalltalkTLS roots mountTable registry globals before result skipped expected commands after |
	key := self newSecret: 'sk-live-'.
	token := self newSecret: 'ghp_live'.
	keyAccount := self replace: #default of: ApiKeyAccount with: ApiKeyAccount new.
	keyAccount configure: (Dictionary new at: 'provider' put: 'live'; at: 'baseUrl' put: 'https://models.example'; at: 'model' put: 'claude-live'; at: 'apiKey' put: key; yourself).
	gitHub := self replace: #default of: GitHubAccount with: GitHubAccount new.
	gitHub configure: (Dictionary new at: 'repository' put: 'octo/live'; at: 'token' put: token; yourself).
	directory := self scratchDirectory.
	File writeText: 'live' to: directory / 'packages.txt'.
	filerClass := Smalltalk at: #SourceFiler ifAbsent: [nil].
	filerClass isNil ifFalse: [
		filer := self replace: #default of: filerClass with: (filerClass new sourceDirectory: directory; yourself).
		filerStore := filer gitHubStore].
	conversation := AgentConversation new provider: ScriptedProvider new; yourself.
	conversation add: (AgentItem user: 'the live conversation').
	point := 3 @ 4.
	breakpoint := Breakpoint on: TestIsolationTest selector: #neverCalled.
	watchpoint := Watchpoint on: point instVarNamed: 'x'.
	filter := [:process | true].
	self replace: #processFilter of: Breakpoint with: filter.
	openAI := OpenAIAccount default.
	signedIn := openAI isSignedIn.
	useSmalltalkTLS := TLSSocket useSmalltalkTLS.
	roots := TLSSocket trustStoreSetting.
	mountTable := File mountTable.
	registry := RemoteControl registryState.
	commands := self commandsOf: registry.
	globals := Smalltalk keys asSet.
	files := Directory entries: directory.
	self pauseProfiler.
	before := self liveConversations.
	self replace: #runsInThrowawayImage of: TestCase with: false.
	result := TestResult new.
	result runClasses: self testClasses.
	self assert: result hasPassed description: [String new: 200 streamContents: [:s |
		s nextPutAll: 'tests failed in a live image:'.
		(result failures, result errors) do: [:each | s space; print: each key; nextPutAll: ': '; nextPutAll: (each value ifNil: ['']) asString]]].
	skipped := (result skipped collect: [:each | each printString]) asSet.
	expected := #('ApiKeyAccountTest>>#testKeyIsNotSnapshotted' 'ApiKeyAccountTest>>#testShutDownForgetsEveryKey' 'GitHubAccountTest>>#testShutDownForgetsEveryToken' 'GitHubAccountTest>>#testTokenIsNotSnapshotted') asSet.
	self assert: skipped equals: expected.
	self assert: ApiKeyAccount default identicalTo: keyAccount.
	self assert: keyAccount isSignedIn.
	self assert: keyAccount apiKey equals: key.
	self assert: keyAccount model equals: 'claude-live'.
	self assert: keyAccount baseURL equals: 'https://models.example'.
	self assert: GitHubAccount default identicalTo: gitHub.
	self assert: gitHub isConfigured.
	self assert: gitHub token equals: token.
	self assert: gitHub repository equals: 'octo/live'.
	filerClass isNil ifFalse: [
		self assert: filerClass default identicalTo: filer.
		self assert: filer sourceDirectory equals: directory.
		self assert: filer gitHubStore identicalTo: filerStore].
	self assert: (Directory entries: directory) asSet equals: files asSet.
	self assert: (File readText: directory / 'packages.txt') equals: 'live'.
	self assert: conversation items size equals: 1.
	self deny: conversation isBusy.
	self assert: (Breakpoint all includes: breakpoint).
	self assert: (Watchpoint all includes: watchpoint).
	self assert: Breakpoint processFilter identicalTo: filter.
	self assert: OpenAIAccount default identicalTo: openAI.
	self assert: openAI isSignedIn equals: signedIn.
	self assert: TLSSocket useSmalltalkTLS equals: useSmalltalkTLS.
	self assert: TLSSocket trustStoreSetting identicalTo: roots.
	self assert: File mountTable identicalTo: mountTable.
	after := RemoteControl registryState.
	self assert: (after at: 3) identicalTo: (registry at: 3).
	self assert: (self commandsOf: after) keys asSet equals: commands keys asSet.
	commands keysAndValuesDo: [:name :handler | self assert: ((self commandsOf: after) at: name) identicalTo: handler].
	self assert: (Smalltalk keys asSet reject: [:each | globals includes: each]) isEmpty
		description: [String new: 100 streamContents: [:s | s nextPutAll: 'globals left behind:'. (Smalltalk keys asSet reject: [:each | globals includes: each]) do: [:each | s space; nextPutAll: each]]].
	self assert: self liveConversations <= before
		description: [(self liveConversations - before) printString, ' AgentConversations of the tests survive them'].
	self assert: result runCount > 100
!
testCleanupsRunWhenATestFails
	| result |
	TestIsolationFixture value: #live.
	result := (TestIsolationFixture selector: #testReplacesAndFails) run.
	self assert: result failures size equals: 1.
	self assert: TestIsolationFixture value equals: #live.
	self assert: TestIsolationFixture log asArray equals: #(#tearDown #second #first).
	self assert: (result failures first key instVarNamed: 'held') isNil
!
testCleanupsRunWhenOneFails
	| result |
	TestIsolationFixture value: #live.
	result := (TestIsolationFixture selector: #testCleanupFails) run.
	self assert: result errors size equals: 1.
	self assert: TestIsolationFixture value equals: #live
!
testThrowawayImage
	self replace: #runsInThrowawayImage of: TestCase with: false.
	self deny: TestCase runsInThrowawayImage.
	self assert: ((TestIsolationFixture selector: #testNeedsThrowaway) run skipped size) equals: 1.
	TestCase runsInThrowawayImage: true.
	self assert: ((TestIsolationFixture selector: #testNeedsThrowaway) run passed size) equals: 1.
	TestCase runsInThrowawayImage: nil.
	self assert: TestCase runsInThrowawayImage equals: (Smalltalk vm arguments includes: '--test')
! !
