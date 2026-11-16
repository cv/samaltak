ToolPane subclass: #AgentWindow
	instanceVariableNames: 'conversation origin account transcript pane card askEditor sendButton stopButton status signOutButton updateQueued login'
	classVariableNames: 'Account'
	package: 'Tools-Agent'!

AgentWindow comment: 'I am the Agent window (docs/agent.md, prototypes/5-agent/6-chosen.html): a view of an AgentConversation. ⌘J in a tool (Tools open: #agent with: aTool) opens me on a conversation with the tool''s agentContext, or brings back the one already open for that tool. Top to bottom: the context strip (what the tool bound), the transcript (AgentTranscript in a ScrollPane, following the end), the ASK editor (Return sends, Shift-Return is a new line) with Send and Stop, and the status bar (model, account, tokens of the last response, working…) with Sign out. Signed out, the login card (AgentLoginCard) replaces the transcript; the device login runs in a Process of its own.

The conversation notifies me in its turn''s Process; I redraw in my window''s Process, at most one update queued at a time. The account and the provider block on the network: I call them from other Processes only. Closing me stops a running turn and cancels a pending login.

	AgentWindow openFor: aWorkspace
	AgentWindow account: anAccountDouble   "tests; nil: OpenAIAccount default"

Remote names: transcript (items user-3, code-4, show-5 with its inspect button …), login (sign-in url code copy message), ask, send, stop, status, sign-out.'!

!AgentWindow methodsFor: 'initialization'!
setConversation: anAgentConversation origin: aToolOrNil account: anAccount
	conversation := anAgentConversation.
	origin := aToolOrNil.
	account := anAccount.
	transcript := AgentTranscript new conversation: conversation; name: 'transcript'; yourself.
	pane := ScrollPane new content: transcript; yourself.
	card := AgentLoginCard new name: 'login'; yourself.
	card signInButton action: [self signIn].
	askEditor := AgentInputEditor new name: 'ask'; title: 'ask'; highlighting: false; font: #ui; yourself.
	askEditor onKey: [:event | self askKey: event].
	sendButton := (Button label: 'Send' action: [self send]) name: 'send'; beDefault; fixed: 26; yourself.
	stopButton := (Button label: 'Stop' action: [self stop]) name: 'stop'; fixed: 22; yourself.
	status := StatusBar new name: 'status'; flex: 1; yourself.
	signOutButton := (AgentSignOutButton label: 'Sign out' action: [self signOut]) name: 'sign-out'; font: #small; sizeToContent; yourself.
	self addAll: {
		self contextStrip.
		PaneHeader title: 'Conversation'.
		pane.
		card.
		(PaneHeader title: '') fixed: 1; yourself.
		(Row with: {askEditor. (Column with: {sendButton. stopButton. Widget new}) spacing: 6; fixed: 92; padding: (0 @ 8 corner: 10 @ 8); yourself})
			fixed: 72; yourself.
		(Row with: {status. signOutButton}) fixed: (self theme metric: #statusBarHeight); yourself}.
	conversation onChange: [:c | self conversationChanged] for: self
!
contextStrip
	"A header with the context's label above the lines of its description."
	| lines |
	lines := (conversation context describe lines reject: [:each | each isEmpty]) asArray.
	lines size > 4 ifTrue: [lines := (lines first: 4) copyWith: '…'].
	^(Column with: (Array with: (PaneHeader title: 'Context' right: conversation context label)),
		(lines collect: [:each | (Label text: each font: #code12) padding: (8 @ 0 corner: 8 @ 0); fixed: 18; yourself]))
		background: #accentSoft;
		fixed: 20 + (lines size * 18) + 4;
		name: 'context';
		yourself
!
minimumWindowExtent
	^420 @ 360
! !

!AgentWindow methodsFor: 'accessing'!
conversation
	^conversation
!
origin
	"The tool whose ⌘J opened me, or nil."
	^origin
!
account
	^account
!
transcript
	^transcript
!
loginCard
	^card
!
askEditor
	^askEditor
! !

!AgentWindow methodsFor: 'updating'!
conversationChanged
	"Any Process: update in my window's Process, once for all changes until then."
	updateQueued == true ifTrue: [^self].
	updateQueued := true.
	self inWindowDo: [updateQueued := false. self update]
!
update
	| signedIn atEnd busy tokens |
	signedIn := account isSignedIn.
	busy := conversation isBusy.
	pane visible: signedIn.
	card visible: signedIn not.
	atEnd := pane scrollOffset + pane scrollVisible >= (pane scrollTotal - 20).
	transcript sync.
	pane layout.
	atEnd ifTrue: [pane scrollOffset: pane scrollTotal].
	sendButton enabled: (signedIn and: [busy not]).
	stopButton enabled: busy.
	signOutButton visible: signedIn.
	tokens := conversation contextTokens.
	status clear.
	status add: conversation provider modelName style: #strong.
	status add: '│' style: #muted.
	status add: (signedIn ifTrue: [account email ifNil: ['signed in']] ifFalse: ['signed out']).
	tokens isNil ifFalse: [status add: '│' style: #muted. status add: tokens printString, ' tokens' style: #plain].
	(self cacheUsageText: conversation usage) ifNotNil: [:text | status add: '│' style: #muted. status add: text style: #plain].
	busy ifTrue: [status addRight: 'working…' style: #pillBusy]
!
cacheUsageText: usage
	"Show cumulative input cache reuse once the latest context exceeds 10k tokens."
	| input details cached percent |
	usage isNil ifTrue: [^nil].
	(usage at: 'context_tokens' ifAbsent: [0]) > 10000 ifFalse: [^nil].
	input := usage at: 'input_tokens' ifAbsent: [^nil].
	input > 0 ifFalse: [^nil].
	details := usage at: 'input_tokens_details' ifAbsent: [^nil].
	details isNil ifTrue: [^nil].
	cached := details at: 'cached_tokens' ifAbsent: [^nil].
	percent := (cached * 100 / input) rounded.
	^percent printString, '% cached'



! !

!AgentWindow methodsFor: 'actions'!
askKey: anEvent
	"Return sends, Shift-Return is a new line."
	((anEvent key == #return or: [anEvent key == #enter]) and: [anEvent modifiers shift not and: [anEvent modifiers commandKey not]])
		ifFalse: [^false].
	self send.
	^true
!
send
	| text attachments |
	text := askEditor text trimBoth.
	attachments := (askEditor respondsTo: #images)
		ifTrue: [askEditor images asArray]
		ifFalse: [#()].
	((text isEmpty and: [attachments isEmpty]) or: [conversation isBusy or: [account isSignedIn not]]) ifTrue: [^self].
	conversation ask: text images: attachments.
	askEditor text: ''.
	(askEditor respondsTo: #clearImages) ifTrue: [askEditor clearImages].
	pane scrollOffset: pane scrollTotal
!
stop
	conversation isBusy ifTrue: [[conversation stop] forkAt: Processor userSchedulingPriority named: 'agent stop']
!
signOut
	account signOut.
	self update
!
signIn
	(login notNil and: [login isTerminated not]) ifTrue: [^self].
	card showMessage: 'Asking for a code…'.
	login := [self runLogin] forkAt: Processor userSchedulingPriority named: 'agent sign-in'
!
runLogin
	"In the sign-in Process: the device login, showing its code, until it is approved, expires, fails or is cancelled."
	| ok |
	ok := [account startLogin.
		self inWindowDo: [card showURL: account loginURL code: account loginCode].
		account finishLogin]
			on: Error do: [:e | e return: e messageText asString].
	self inWindowDo: [
		card showButton: (ok == true ifTrue: [nil] ifFalse: [ok == false ifTrue: ['The code expired or the sign-in was cancelled.'] ifFalse: [ok]]).
		self update]
!
focusOrigin
	(origin notNil and: [origin window notNil]) ifTrue: [origin window focus]
! !

!AgentWindow class methodsFor: 'accessing'!
account
	"The account new windows use: OpenAIAccount default unless a test set another."
	^Account ifNil: [OpenAIAccount default]
!
account: anAccountOrNil
	Account := anAccountOrNil
! !

!AgentWindow class methodsFor: 'opening'!
openOn: anAgentConversation origin: aToolOrNil in: aRectangle
	| view window |
	view := self new setConversation: anAgentConversation origin: aToolOrNil account: self account.
	window := view openIn: aRectangle title: 'Agent — ', anAgentConversation context label.
	window do: [view update. view askEditor focus].
	^window
!
openFor: aTool
	^self openFor: aTool context: aTool
!
openFor: aToolOrNil context: aContext
	"⌘J opens the Agent for a tool on aContext's agentContext, bringing it back if already open."
	| existing |
	existing := aToolOrNil isNil ifFalse: [(Tools windowsOf: self) detect: [:each | each content origin == aToolOrNil] ifNone: [nil]].
	existing isNil ifFalse: [existing focus. ^existing].
	^self openOn: (AgentConversation on: aContext agentContext) origin: aToolOrNil in: (Tools placeNear: aContext window extent: 720 @ 640)
!
initialize
	Tools registerOpener: #agent with: [:tool | self openFor: tool].
	ToolsMenu register: 'Agent' description: '⌘J in a tool' order: 65 action: [:point |
		self openOn: (AgentConversation on: (AgentContext new label: 'Desktop'; yourself)) origin: nil in: (Tools placeAt: point extent: 720 @ 640)]
! !

!AgentWindow methodsFor: 'context'!
agentContext
	"Expose this agent and its conversation to a second agent."
	^AgentContext new
		label: self window title;
		receiver: self;
		bind: #conversation to: conversation;
		yourself
! !

!AgentWindow methodsFor: 'events'!
windowClosed
	(login notNil and: [login isTerminated not]) ifTrue: [account cancelLogin].
	conversation onChange: nil for: self.
	self stop
! !
