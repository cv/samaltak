TestCase subclass: #AgentConversationTest
	instanceVariableNames: 'provider conversation frameResult others'
	classVariableNames: ''
	package: 'Tests-Agent'!

AgentConversationTest comment: 'Tests AgentConversation''s turns against a ScriptedProvider: tool calls and what is sent back, the object table, code-mode results and failures, Stop, contexts (receiver, Workspace bindings, a suspended frame), change notification, and where the instructions say source changes go.'!

!AgentConversationTest methodsFor: 'running'!
setUp
	others := self agentProcesses.
	provider := ScriptedProvider new.
	conversation := AgentConversation new provider: provider; yourself
!
tearDown
	conversation stop
! !

!AgentConversationTest methodsFor: 'helpers'!
code: aString call: anId
	^ScriptedProvider code: aString call: anId
!
message: aString
	^ScriptedProvider message: aString
!
run: sourceStrings
	"One turn running each source in a cell of its own, then a message; answer the cells' outputs."
	sourceStrings doWithIndex: [:each :i | provider reply: (Array with: (self code: each call: 'c', i printString))].
	provider reply: (Array with: (self message: 'done')).
	self assert: (conversation ask: 'go'; wait) equals: 'done'.
	^(conversation items select: [:each | each kind == #code]) asArray collect: [:each | each result]
!
showPictures: n
	"Register n ScriptedPictures, each shown in an item; answer the items."
	^(1 to: n) asArray collect: [:i | | picture item |
		picture := ScriptedPicture new.
		item := AgentItem kind: #show text: 'shown'.
		item object: picture; objectId: (conversation idFor: picture).
		conversation add: item]
!
itemsOfKind: aSymbol
	^(conversation items select: [:each | each kind == aSymbol]) asArray
!
frameOf: x
	"Stop in a frame with an argument and a temporary; on resumption, keep the temporary."
	| y |
	y := x + 1.
	Processor activeProcess suspend.
	frameResult := y
! !

!AgentConversationTest methodsFor: 'tests'!
testInstructionsSayWhereChangesGo
	| savedAccount savedFiler filerClass account |
	savedAccount := GitHubAccount default.
	filerClass := Smalltalk at: #SourceFiler ifAbsent: [nil].
	savedFiler := filerClass ifNotNil: [:c | c default].
	account := GitHubAccount new.
	GitHubAccount default: account.
	[filerClass ifNotNil: [:c | c default: (c new sourceDirectory: nil; yourself)].
	self assert: (AgentInstructions sourceState includesSubstring: 'cannot be saved').
	self assert: (AgentInstructions sourceState includesSubstring: 'samaltak-ctl github-config --from-gh').
	account configure: (Dictionary new at: 'repository' put: 'octo/demo'; at: 'token' put: 'x', 'y'; yourself).
	self assert: (AgentInstructions sourceState includesSubstring: 'GitHub, octo/demo').
	self assert: (AgentInstructions sourceState includesSubstring: 'into main').
	self assert: ((AgentInstructions textFor: conversation context) includesSubstring: 'Source: changes go to GitHub, octo/demo').
	self assert: (AgentInstructions text includesSubstring: 'default commit:')]
		ensure: [
			account forgetToken.
			GitHubAccount default: savedAccount.
			filerClass ifNotNil: [:c | c default: savedFiler]]
!
testTurnWithCellsAndShow
	| second third fourth outputs |
	provider reply: (Array with: (self code: '3 + 4
' call: 'c1')).
	provider reply: (Array with: (self code: 'o1 * 2' call: 'c2')).
	provider reply: (Array with: (ScriptedProvider show: 'o2' call: 'c3')).
	provider reply: #('Four' 'teen.') items: (Array with: (self message: 'Fourteen.')).
	self assert: (conversation ask: 'double 3 + 4'; wait) equals: 'Fourteen.'.
	self deny: conversation isBusy.
	self assert: (conversation items collect: [:each | each kind]) asArray equals: #(#user #code #code #show #assistant).
	outputs := (self itemsOfKind: #code) collect: [:each | each result].
	self assert: outputs equals: #('o1 7' 'o2 14').
	self assert: (conversation items at: 4) object equals: 14.
	self assert: (conversation items at: 4) objectId equals: 'o2'.
	self assert: (conversation items at: 4) result equals: 'shown'.
	self assert: provider requests size equals: 4.
	self assert: (provider requests first collect: [:each | each at: 'role']) equals: #('developer' 'user').
	self assert: ((provider requests first first at: 'content') first at: 'text') equals: (AgentInstructions textFor: conversation context).
	self assert: (provider toolSpecs collect: [:each | each at: 'name']) equals: #('code-mode' 'show-object').
	second := provider requests at: 2.
	self assert: second size equals: 4.
	self assert: ((second at: 3) at: 'call_id') equals: 'c1'.
	self assert: ((second at: 4) at: 'type') equals: 'custom_tool_call_output'.
	self assert: ((second at: 4) at: 'call_id') equals: 'c1'.
	self assert: ((second at: 4) at: 'output') equals: 'o1 7'.
	third := provider requests at: 3.
	self assert: third size equals: 6.
	self assert: ((third at: 6) at: 'output') equals: 'o2 14'.
	fourth := provider requests at: 4.
	self assert: fourth size equals: 8.
	self assert: ((fourth at: 7) at: 'type') equals: 'function_call'.
	self assert: ((fourth at: 8) at: 'type') equals: 'function_call_output'.
	self assert: ((fourth at: 8) at: 'output') equals: 'shown'.
	self assert: (conversation usage at: 'total_tokens') equals: 440.
	"The final message goes back in the next request."
	provider reply: (Array with: (self message: 'Bye.')).
	conversation ask: 'thanks'; wait.
	self assert: (provider requests last at: 9) == (conversation items at: 5) wire first.
	self assert: ((provider requests last at: 10) at: 'role') equals: 'user'
!
testObjectIdentity
	| outputs |
	outputs := self run: #('OrderedCollection new' 'o1 add: 3. o1' '3 + 4' 'nil' 'nil').
	self assert: outputs equals: #('o1 an OrderedCollection()' 'o1 an OrderedCollection(3)' 'o2 7' 'o3 nil' 'o3 nil').
	self assert: (conversation objectAt: 'o1') == ((self itemsOfKind: #code) at: 2) object.
	self assert: (conversation objectAt: 'o1') asArray equals: #(3).
	self assert: (conversation idFor: (conversation objectAt: 'o1')) equals: 'o1'.
	self assert: (conversation objectAt: 'o9') isNil.
	self assert: (self run: #('o1 == (o1 add: 4; yourself)')) last equals: 'o4 true'
!
testRuntimeError
	| outputs lines |
	outputs := self run: #('nil foo' 'self halt. 3' '1 / 0' '5').
	lines := (outputs at: 1) lines.
	self assert: lines first equals: 'error: MessageNotUnderstood: Instance of UndefinedObject did not understand #foo'.
	self assert: (lines at: 2) equals: '  UndefinedObject(ProtoObject)>>doesNotUnderstand:'.
	self assert: lines last equals: '  UndefinedObject>>DoIt'.
	self assert: ((outputs at: 2) beginsWith: 'error: Halt').
	self assert: ((outputs at: 3) beginsWith: 'error: ZeroDivide').
	self assert: (outputs at: 4) equals: 'o1 5'.
	self assert: (((self itemsOfKind: #code) collect: [:each | each failed]) asArray) equals: #(true true true false)
!
testSyntaxError
	| outputs |
	outputs := self run: #('3 +' '3 + 4').
	self assert: ((outputs at: 1) beginsWith: 'syntax error: ').
	self assert: (outputs at: 2) equals: 'o1 7'.
	self assert: (self itemsOfKind: #code) first failed
!
testPrintStringFails
	| outputs |
	outputs := self run: #('OrderedCollection basicNew').
	self assert: ((outputs at: 1) beginsWith: 'o1 ').
	self assert: ((outputs at: 1) includesSubstring: 'printString failed')
!
testLongPrintStringIsCut
	| outputs |
	outputs := self run: #('String new: 25000 withAll: $a' 'String new: 9998 withAll: $a').
	self assert: (outputs at: 1) size < 10200.
	self assert: ((outputs at: 1) endsWith: '... [cut: 25002 characters in all; the next part: o1 printString copyFrom: 10001 to: 20000]').
	self assert: (outputs at: 2) size equals: 10003
!
testTimeout
	| outputs |
	(conversation toolNamed: 'code-mode') timeout: 1.
	outputs := self run: #('(Delay forSeconds: 30) wait. 3' '4').
	self assert: outputs equals: #('error: terminated after 1 s' 'o1 4').
	self assert: self cellProcesses isEmpty
!
testShowUnknownObjectAndUnknownTool
	| other |
	other := (self code: '3' call: 'c2') at: 'name' put: 'no-such'; yourself.
	provider reply: (Array with: (ScriptedProvider show: 'o9' call: 'c1')).
	provider reply: (Array with: other).
	provider reply: (Array with: (self message: 'ok')).
	conversation ask: 'show o9'; wait.
	self assert: ((conversation items at: 2) wire last at: 'output') equals: 'error: no object o9'.
	self assert: (conversation items at: 3) result equals: 'error: no such tool'.
	self assert: (provider requests last collect: [:each | each at: 'type']) equals: #('message' 'message' 'function_call' 'function_call_output' 'custom_tool_call' 'custom_tool_call_output')
!
testStopDuringSend
	provider block.
	conversation ask: 'wait forever'.
	self assert: (self waitFor: [provider requests size = 1]).
	conversation stop.
	self deny: conversation isBusy.
	self assert: conversation items last kind equals: #error.
	self assert: conversation wait equals: 'Stopped.'.
	provider reply: (Array with: (self message: 'Back.')).
	self assert: (conversation ask: 'again'; wait) equals: 'Back.'.
	self assert: (provider requests last collect: [:each | each at: 'role' ifAbsent: [nil]]) equals: #('developer' 'user' 'user')
!
testStopDuringCell
	| cell request |
	provider reply: (Array with: (self code: '(Delay forSeconds: 30) wait' call: 'c1')).
	conversation ask: 'sleep'.
	self assert: (self waitFor: [self cellProcesses notEmpty]).
	conversation stop.
	self deny: conversation isBusy.
	self assert: self agentProcesses isEmpty.
	cell := (self itemsOfKind: #code) first.
	self assert: cell failed.
	self assert: cell result equals: 'error: stopped by the user'.
	self assert: cell wire size equals: 2.
	provider reply: (Array with: (self message: 'Back.')).
	self assert: (conversation ask: 'again'; wait) equals: 'Back.'.
	request := provider requests last.
	self assert: (request collect: [:each | each at: 'type']) equals: #('message' 'message' 'custom_tool_call' 'custom_tool_call_output' 'message').
	self assert: ((request at: 4) at: 'output') equals: 'error: stopped by the user'
!
testACellEndsWithTheProcessWaitingForIt
	"Wherever that Process is terminated (Stop terminates the turn's): step a Process through a cell's evaluation until the cell's Process runs, and terminate it there."
	| item session cells left |
	item := AgentItem call: (self code: '(Delay forSeconds: 30) wait' call: 'c1') kind: #code text: '(Delay forSeconds: 30) wait'.
	session := DebugSession debugProcess: (self track: [(conversation toolNamed: 'code-mode') evaluate: item in: conversation] newProcess).
	cells := [self cellProcesses].
	[session interruptedContext selector == #evaluate:in:] whileFalse: [session stepInto].
	[cells value isEmpty] whileTrue: [session stepThrough].
	session stepThrough.
	self deny: cells value first isSuspended description: 'the cell''s Process does not run yet'.
	session terminate.
	left := cells value.
	left do: [:each | each terminate].
	self assert: left isEmpty description: 'the cell''s Process is still there'
!
testProviderError
	provider fail: 'The network is down'.
	self assert: (conversation ask: 'hi'; wait) equals: 'The network is down'.
	self assert: conversation items last kind equals: #error.
	self assert: conversation items last wire isEmpty.
	self deny: conversation isBusy
!
testBusy
	provider block.
	conversation ask: 'one'.
	self should: [conversation ask: 'two'] raise: Error.
	conversation stop
!
testBusyBeforeTheMessageIsThere
	"Whenever another Process looks: step a Process through its ask:, looking after every step."
	| session frame |
	provider block.
	session := DebugSession debugProcess: (self track: [conversation ask: 'hi'] newProcess).
	[session interruptedContext selector == #ask:images:] whileFalse: [session stepInto].
	frame := session interruptedContext.
	[frame isDead] whileFalse: [
		session stepOver: frame.
		self assert: (conversation items isEmpty or: [conversation isBusy]) description: 'the message is there, the conversation not busy'].
	self assert: conversation items size equals: 1.
	session terminate
!
testOnChange
	| texts busy |
	texts := OrderedCollection new.
	busy := OrderedCollection new.
	conversation onChange: [:c |
		texts add: c items last text copy.
		busy add: c isBusy].
	provider reply: #('Hel' 'lo') items: (Array with: (self message: 'Hello')).
	conversation ask: 'hi'; wait.
	self assert: (texts includes: 'Hel').
	self assert: (texts includes: 'Hello').
	self assert: busy first.
	self deny: busy last
!
testOnlyTheNewestPicturesAreKept
	| items kept |
	items := self showPictures: AgentConversation keptPictures + 2.
	kept := (3 to: items size) collect: [:i | (items at: i) object].
	3 to: items size do: [:i |
		self assert: ((items at: i) object isKindOf: ScriptedPicture).
		self assert: (conversation objectAt: 'o', i printString) == (items at: i) object.
		self deny: (conversation isReleased: 'o', i printString)].
	1 to: 2 do: [:i |
		self assert: (items at: i) object equals: 'thumbnail'.
		self assert: (conversation isReleased: 'o', i printString)].
	Smalltalk vm garbageCollect.
	self assert: (conversation objectAt: 'o1') isNil.
	self assert: (conversation objectAt: 'o1' ifAbsent: [#absent]) equals: #absent.
	self assert: ((conversation describeMissing: 'o1') includesSubstring: 'capture it again').
	self assert: (conversation describeMissing: 'o9') equals: 'no object o9'.
	self assert: (conversation objectAt: 'o3') == kept first.
	self assert: (conversation objectBindings at: #o1) value isNil.
	self assert: (conversation idFor: nil) equals: 'o', (items size + 1) printString
!
testAReleasedPictureKeepsItsId
	| picture |
	picture := ScriptedPicture new.
	self assert: (conversation idFor: picture) equals: 'o1'.
	self showPictures: AgentConversation keptPictures.
	self assert: (conversation isReleased: 'o1').
	self assert: (conversation objectAt: 'o1') == picture.
	self assert: (conversation idFor: picture) equals: 'o1'
!
testImagesNoLongerSentAreReleased
	| types |
	(AgentImage maxImages + 2) timesRepeat: [
		conversation add: (AgentItem user: 'shot' images: {AgentImage imagePart: 'data:image/png;base64,AQID'})].
	conversation input.
	types := conversation items asArray collect: [:each | ((each wire first at: 'content') last) at: 'type'].
	self assert: (types first: 2) equals: #('input_text' 'input_text').
	self assert: ((types allButFirst: 2) allSatisfy: [:each | each = 'input_image']).
	self assert: (((conversation items first wire first at: 'content') last) at: 'text') equals: '[image omitted: an older image, no longer sent; show it again to see it]'
!
testShowFormSendsImage
	| message image |
	provider reply: (Array with: (self code: 'Form width: 2 height: 3' call: 'c1')).
	provider reply: (Array with: (ScriptedProvider show: 'o1' call: 'c2')).
	provider reply: (Array with: (self message: 'seen')).
	conversation ask: 'capture'; wait.
	message := provider requests last last.
	self assert: (message at: 'role') equals: 'user'.
	image := (message at: 'content') last.
	self assert: (image at: 'type') equals: 'input_image'.
	self assert: (image at: 'image_url') equals: 'data:image/png;base64,', (Base64 encode: (conversation objectAt: 'o1') pngBytes).
	self assert: ((provider requests last at: 6) at: 'output') equals: 'shown'
!
testInputKeepsInitialInstructions
	| first |
	conversation context: (AgentContext new receiver: 5; label: 'Original'; yourself).
	first := conversation input first.
	conversation context: (AgentContext new receiver: 99; label: 'Changed'; yourself).
	self assert: conversation input first == first.
	self assert: conversation input size equals: 1.
	self assert: conversation items isEmpty
!
testContextTokensUsesLatestRequest
	| c |
	c := AgentConversation new.
	self assert: c contextTokens isNil.
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 100; at: 'total_tokens' put: 120; yourself).
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 150; at: 'total_tokens' put: 180; yourself).
	self assert: c contextTokens = 150
!
testRetryAfterProviderError
	provider fail: 'The network is down'.
	conversation ask: 'hi'; wait.
	self assert: conversation canRetry.
	provider fail: 'Still down'.
	conversation retry; wait.
	self assert: conversation canRetry.
	self assert: (self itemsOfKind: #user) size equals: 1.
	self assert: (self itemsOfKind: #error) size equals: 2
!
testLongElementsAreCutEach
	| outputs |
	outputs := self run: #('Array with: (String new: 25000 withAll: $a) with: ''short'' with: 42' '(1 to: 5000) asArray').
	self assert: (outputs at: 1) size <= 10003.
	self assert: ((outputs at: 1) beginsWith: 'o1 #(''aaa').
	self assert: ((outputs at: 1) endsWith: '... [cut: 25002 characters; o1 at: 1] ''short'' 42)').
	self assert: ((outputs at: 2) endsWith: 'the next part: o2 printString copyFrom: 10001 to: 20000]')
!
testTurnUsageCountsRequestsOfTheTurn
	| c |
	c := AgentConversation new.
	self assert: c turnUsage isNil.
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 100; at: 'output_tokens' put: 20; at: 'input_tokens_details' put: (Dictionary new at: 'cached_tokens' put: 80; yourself); yourself).
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 150; at: 'output_tokens' put: 30; yourself).
	c accumulateUsage: Dictionary new.
	self assert: (c turnUsage at: 'requests') = 3.
	self assert: (c turnUsage at: 'input_tokens') = 250.
	self assert: (c turnUsage at: 'output_tokens') = 50.
	self assert: ((c turnUsage at: 'input_tokens_details') at: 'cached_tokens') = 80.
	self assert: c contextTokens = 150.
	self assert: (c usage at: 'output_tokens') = 50
! !

!AgentConversationTest methodsFor: 'tests - contexts'!
testReceiverAndBindings
	| bindings |
	bindings := Dictionary new.
	bindings at: #x put: #x -> 3.
	conversation context: (AgentContext new receiver: 5; bindings: bindings; label: 'Workspace'; yourself).
	self assert: (self run: #('self + x' 'x := 30' 'y := 400' 'o1 + y')) equals: #('o1 8' 'o2 30' 'o3 400' 'o4 408').
	self assert: (bindings at: #x) value equals: 30.
	self assert: (bindings at: #y) value equals: 400.
	self deny: (bindings includesKey: #o1).
	self assert: (conversation context describe includesSubstring: 'self: 5 (SmallInteger)').
	self assert: (conversation context describe includesSubstring: 'Variables: x y')
!
testFrame
	| process frame |
	process := self fork: [self frameOf: 20].
	self assert: (self waitFor: [process isSuspended]).
	frame := process suspendedContext findContextSuchThat: [:ctx | ctx selector == #frameOf:].
	conversation context: (AgentContext new frame: frame; yourself).
	self assert: conversation context receiver == self.
	self assert: (self run: #('x + y' 'self class name' 'o1 + x' 'y := 5')) equals: #('o1 41' 'o2 #AgentConversationTest' 'o3 61' 'o4 5').
	self assert: (conversation context describe includesSubstring: 'Frame: AgentConversationTest>>frameOf:').
	self assert: (conversation context describe includesSubstring: 'Variables: x y').
	process resume.
	self assert: (self waitFor: [frameResult notNil]).
	self assert: frameResult equals: 5
! !

!AgentConversationTest methodsFor: 'private'!
agentProcesses
	"The Processes of agent turns and cells, except those that were there before the test (another conversation's, the agent's own when it runs me)."
	^Processor allProcesses select: [:p |
		(p name = 'agent code-mode' or: [p name = 'agent turn']) and: [others isNil or: [(others includes: p) not]]]
!
cellProcesses
	"The Processes of cells started during the test."
	^self agentProcesses select: [:p | p name = 'agent code-mode']
! !
