ToolsTestCase subclass: #AgentWindowTest
	instanceVariableNames: 'account provider debugged'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

AgentWindowTest comment: 'I test the Agent window in a real World without a network: a ScriptedProvider answers, an AgentTestAccount signs in. ⌘J in a Workspace (its variables shared with the cells, a second ⌘J brings the window back), the Inspector''s and the Debugger''s contexts, the transcript''s views for a turn, Inspect, Stop, and the login card.'!

!AgentWindowTest methodsFor: 'running'!
setUp
	super setUp.
	account := AgentTestAccount new.
	AgentWindow account: account.
	provider := ScriptedProvider new
!
tearDown
	(self windowsOf: AgentWindow) do: [:w | w content conversation stop].
	debugged isNil ifFalse: [debugged terminate].
	AgentWindow account: nil.
	super tearDown
! !

!AgentWindowTest methodsFor: 'support'!
openAgent
	| w |
	w := self open: [AgentWindow openOn: AgentConversation new origin: nil in: (100 @ 60 extent: 720 @ 700)].
	w content conversation provider: provider.
	^w
!
ask: aString in: anAgentWindow
	"Type aString into the ASK editor and press Return, as the user does; wait for the turn and the transcript."
	| view |
	view := anAgentWindow content.
	self in: anAgentWindow do: [view askEditor text: aString; focus].
	self settle.
	self key: #return modifiers: 0.
	self assert: (self waitFor: [view conversation items notEmpty and: [view conversation isBusy not]]) description: 'the turn did not end'.
	self assert: (self waitFor: [anAgentWindow queue isEmpty and: [(self kindsIn: anAgentWindow) size = (self shownItemsIn: view)]]) description: 'the transcript did not follow'
!
shownItemsIn: anAgentWindowView
	^(anAgentWindowView conversation items reject: [:each | each kind == #reasoning]) size
!
kindsIn: anAgentWindow
	^(self in: anAgentWindow do: [anAgentWindow content transcript children collect: [:each | each item kind]]) asArray
!
named: aString in: aWidget
	"The widget named aString in aWidget's tree, as remote control finds it."
	aWidget name = aString ifTrue: [^aWidget].
	aWidget children do: [:each | (self named: aString in: each) ifNotNil: [:found | ^found]].
	^nil
!
frameOf: x
	"Stop in a frame with an argument and a temporary."
	| y |
	y := x + 1.
	Processor activeProcess suspend.
	^y
! !

!AgentWindowTest methodsFor: 'tests'!
testCommandJInAWorkspace
	| ws agent conversation |
	ws := self openWorkspaceWith: 'p := 3 @ 4'.
	self evaluate: 'p := 3 @ 4' in: ws mode: #do.
	self key: $j modifiers: self commandModifier.
	self assert: (self waitFor: [(self windowsOf: AgentWindow) size = 1]) description: '⌘J opened no Agent window'.
	agent := (self windowsOf: AgentWindow) first.
	self assert: (self waitFor: [agent isOpen and: [agent queue isEmpty]]).
	self assert: agent title equals: 'Agent — Workspace'.
	self assert: agent content origin == ws content.
	conversation := agent content conversation.
	self assert: conversation context bindings == ws content bindings.
	self assert: conversation context selection equals: 'p := 3 @ 4'.
	provider reply: {ScriptedProvider code: 'p := p * 2' call: 'c1'}.
	provider reply: {ScriptedProvider message: 'Doubled.'}.
	conversation provider: provider.
	self ask: 'double p' in: agent.
	self assert: (ws content bindings at: #p) value equals: 6 @ 8.
	"A second ⌘J in the Workspace brings the same window back."
	self in: ws do: [ws focus. ws content editor focus].
	self assert: (self waitFor: [world activeWindow == ws]).
	self settle.
	self key: $j modifiers: self commandModifier.
	self assert: (self waitFor: [world activeWindow == agent]) description: 'the Agent window did not come back'.
	self assert: (self windowsOf: AgentWindow) size equals: 1.
	self assert: (ToolsMenu labels includes: 'Agent')
!
testInspectorContext
	| inspector context |
	inspector := self open: [Inspector openOn: 3 @ 4 in: (100 @ 100 extent: 450 @ 290) bindings: nil].
	context := self in: inspector do: [inspector content agentContext].
	self assert: context receiver equals: 3 @ 4.
	self assert: context label equals: 'Inspector: a Point'
!
testDebuggerContext
	| debugger context frame |
	debugged := [self frameOf: 41] newProcess.
	debugged resume.
	self assert: (self waitFor: [debugged isSuspended]).
	debugger := self open: [Debugger openOn: (DebugSession debugProcess: debugged)].
	frame := debugged suspendedContext.
	[frame method selector == #frameOf:] whileFalse: [frame := frame sender].
	context := self in: debugger do: [debugger content selectFrame: frame. debugger content agentContext].
	self assert: context frame == frame.
	self assert: (context label beginsWith: 'Debugger: ').
	self assert: (context evaluate: 'x + y' bindings: Dictionary new) equals: 83.
	self assert: context receiver == self
!
testATurnShowsItsItems
	| agent views shown inspectors |
	agent := self openAgent.
	provider reply: {ScriptedProvider code: 'Form extent: 40 @ 20' call: 'c1'. ScriptedProvider code: '3 + 4' call: 'c2'}.
	provider reply: {ScriptedProvider show: 'o1' call: 'c3'. ScriptedProvider show: 'o2' call: 'c4'}.
	provider reply: {ScriptedProvider code: '3 zork' call: 'c5'}.
	provider reply: #('Se' 'ven.') items: {ScriptedProvider message: 'Seven.'}.
	self ask: 'show me' in: agent.
	self assert: (self kindsIn: agent) equals: #(#user #code #code #show #show #code #assistant).
	views := self in: agent do: [agent content transcript children asArray].
	self assert: (views at: 2) item result equals: 'o1 a Form(40x20)'.
	self assert: (views at: 4) isForm.
	self deny: (views at: 5) isForm.
	self assert: (views at: 5) remoteLabel equals: 'o2 7'.
	self assert: (views at: 6) item failed.
	self assert: (views last remoteLabel) equals: 'Seven.'.
	self assert: ((views collect: [:each | each height]) allSatisfy: [:h | h > 0]).
	"Inspect opens the real Inspector on the shown object."
	shown := views at: 5.
	self in: agent do: [(self named: 'inspect' in: shown) click].
	self assert: (self waitFor: [(self windowsOf: Inspector) notEmpty]) description: 'Inspect opened no Inspector'.
	inspectors := self windowsOf: Inspector.
	self assert: inspectors first content object equals: 7.
	self assert: (self in: agent do: [agent content askEditor text]) equals: ''
!
testStop
	| agent conversation |
	agent := self openAgent.
	conversation := agent content conversation.
	provider block.
	self in: agent do: [agent content askEditor text: 'wait'. agent content send].
	self assert: conversation isBusy.
	self in: agent do: [(self named: 'stop' in: agent content) click].
	self assert: (self waitFor: [conversation isBusy not]).
	self assert: (self waitFor: [(self kindsIn: agent) = #(#user #error)]).
	self assert: conversation items last text equals: 'Stopped.'
!
testSignInFromTheLoginCard
	| agent view card |
	account signOut.
	agent := self openAgent.
	view := agent content.
	card := view loginCard.
	self assert: card isVisible.
	self deny: view transcript owner isVisible.
	self in: agent do: [card signInButton click].
	self assert: (self waitFor: [(self in: agent do: [card code]) = 'TEST-1234']) description: 'no code on the card'.
	account approve.
	self assert: (self waitFor: [self in: agent do: [card isVisible not and: [view transcript owner isVisible]]]) description: 'the transcript did not come back'.
	self assert: account isSignedIn
!
testClosingCancelsTheLogin
	| agent |
	account signOut.
	agent := self openAgent.
	self in: agent do: [agent content loginCard signInButton click].
	self assert: (self waitFor: [account isLoginPending]).
	agent close.
	self assert: (self waitFor: [account isLoginPending not]) description: 'the login was not cancelled'.
	self deny: account isSignedIn
! !
