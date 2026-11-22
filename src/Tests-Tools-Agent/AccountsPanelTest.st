ToolsTestCase subclass: #AccountsPanelTest
	instanceVariableNames: 'keyAccount gitHub server'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

AccountsPanelTest comment: 'I test the Accounts window (AccountsPanel) in a real World, on accounts of my own put in place of the image''s defaults (replace:of:with:): a key pasted (⌘V, the Paste button) or typed configures the ApiKeyAccount with the settings in the fields, and an AnthropicProvider sends it; bad settings change nothing and say why; the key and the GitHub token never show in any printString, displayString or the windows'' remote text; Forget drops and overwrites them; the Agent window''s key card opens me, and after the key is saved the agent answers (a ScriptedProvider); the panel follows changes made elsewhere; SecretField by itself.'!

!AccountsPanelTest methodsFor: 'running'!
setUp
	| saved |
	super setUp.
	keyAccount := self replace: #default of: ApiKeyAccount with: ApiKeyAccount new.
	gitHub := self replace: #default of: GitHubAccount with: GitHubAccount new.
	saved := AgentWindow accountSetting.
	self addCleanup: [AgentWindow account: saved].
	self addCleanup: [keyAccount forgetKey. gitHub forgetToken]
!
tearDown
	(self windowsOf: AgentWindow) do: [:w | w content conversation stop].
	server isNil ifFalse: [server stop].
	super tearDown
! !

!AccountsPanelTest methodsFor: 'support'!
newKey
	"A key no method holds as a literal (so finding it anywhere means it leaked)."
	^(String new: 3 withAll: $k), '-test-panel-', '7f3a9c21e5'
!
newToken
	^'ghp', '_', 'TestPanelToken0123456789'
!
openPanel
	| window |
	window := self open: [AccountsPanel open].
	self settle.
	^window
!
click: aName in: aWindow
	self in: aWindow do: [(aWindow content widgetNamed: aName) click]
!
fill: aDictionary in: aWindow
	"Set the panel's fields (remote names to text) as typing would leave them."
	self in: aWindow do: [aDictionary keysAndValuesDo: [:name :text |
		name = 'thinking'
			ifTrue: [aWindow content thinking selection: text]
			ifFalse: [(aWindow content fieldNamed: name) text: text]]]
!
pasteKey: aString in: aWindow
	"Put aString on the clipboard, focus the key field and press ⌘V."
	self in: aWindow do: [aWindow content keyField focus].
	world clipboard: aString.
	self settle.
	self key: $v modifiers: self commandModifier.
	self assert: (self waitFor: [self in: aWindow do: [aWindow content keyField hasSecret]]) description: '⌘V pasted nothing'
!
settingsFor: aURL
	^Dictionary new
		at: 'provider' put: 'test';
		at: 'base-url' put: aURL;
		at: 'model' put: 'claude-test';
		at: 'thinking' put: 'high';
		at: 'max-tokens' put: '1000';
		at: 'context-window' put: '200000';
		yourself
!
shownText
	"Everything the World shows or prints: the remote snapshot's text (labels, state, editors' text), and every widget's, window's and account's printString and displayString."
	^String new: 10000 streamContents: [:s |
		s nextPutAll: (RemoteSnapshot new setRoot: world refTable: RemoteRefTable new) allText.
		world windows do: [:w |
			s nextPutAll: w printString; nextPutAll: w displayString; nextPutAll: w title.
			self in: w do: [w content allWidgetsDo: [:each | s nextPutAll: each printString; nextPutAll: each displayString]]].
		{keyAccount. gitHub. keyAccount configuration. gitHub configuration} do: [:each |
			s nextPutAll: each printString; nextPutAll: each displayString].
		s nextPutAll: keyAccount statusLabel]
!
assertNotShown: aString
	| text |
	text := self shownText.
	self assert: text size > 500.
	self deny: (text includesSubstring: aString) description: 'the secret is shown'.
	self deny: (text includesSubstring: (aString copyFrom: 4 to: aString size - 3)) description: 'part of the secret is shown'
! !

!AccountsPanelTest methodsFor: 'tests'!
testTheWorldMenuOpensThePanelOnTheDefaultAccounts
	| window |
	self assert: (ToolsMenu labels includes: 'Accounts').
	window := self openPanel.
	self assert: window title equals: 'Accounts'.
	self assert: window content keyAccount == keyAccount.
	self assert: window content gitHubAccount == gitHub.
	self assert: (self in: window do: [window keyboardFocus]) == window content keyField.
	self assert: (self in: window do: [(window content widgetNamed: 'base-url') text]) equals: 'https://api.anthropic.com'.
	self assert: (self in: window do: [(window content widgetNamed: 'base-branch') text]) equals: 'main'.
	self assert: AccountsPanel open == window.
	self assert: (self windowsOf: AccountsPanel) size equals: 1
!
testPastingAKeyConfiguresTheAccount
	| window view key provider |
	server := HTTPTestServer on: [:request | HTTPTestServer response: 400 body: '{"type":"error","error":{"type":"invalid_request_error","message":"no"}}'].
	key := self newKey.
	window := self openPanel.
	view := window content.
	self fill: (self settingsFor: server url) in: window.
	self pasteKey: key in: window.
	self deny: (world clipboard includesSubstring: key) description: 'the key stayed on the clipboard'.
	self deny: keyAccount isConfigured.
	self click: 'save-key' in: window.
	self assert: keyAccount isSignedIn.
	self assert: keyAccount apiKey equals: key.
	self assert: keyAccount providerName equals: 'test'.
	self assert: keyAccount baseURL equals: server url.
	self assert: keyAccount model equals: 'claude-test'.
	self assert: keyAccount thinking equals: 'high'.
	self assert: keyAccount maxTokens equals: 1000.
	self assert: keyAccount contextWindow equals: 200000.
	self deny: (self in: window do: [view keyField hasSecret]).
	self assert: (self in: window do: [view keyMessage]) equals: 'Saved; the agent can use it now.'.
	self assert: ((self in: window do: [(view widgetNamed: 'api-key') remoteState]) includes: #empty).
	"The agent's provider sends it."
	provider := AnthropicProvider new account: keyAccount; retries: 0; yourself.
	self should: [provider send: #() tools: #() onText: [:t | ] onItem: [:i | ]] raise: AgentError.
	provider cancel.
	self assert: (server requests first headerAt: 'x-api-key') equals: key
!
testTypingAKey
	| window view key |
	keyAccount providerName: 'test' baseURL: 'https://models.example' model: 'claude-test' thinking: nil maxTokens: 1000.
	window := self openPanel.
	view := window content.
	self assert: (self in: window do: [view thinking selection]) equals: 'off'.
	self type: 'sk-typed-7c41e9b2X'.
	self assert: (self waitFor: [(self in: window do: [view keyField secret]) = 'sk-typed-7c41e9b2X']) description: 'typing went elsewhere'.
	self key: #backspace modifiers: 0.
	self key: #return modifiers: 0.
	self assert: (self waitFor: [keyAccount isSignedIn]) description: 'Return did not save the key'.
	key := keyAccount apiKey.
	self assert: key equals: 'sk-typed-7c41e9b2'.
	self assert: keyAccount thinking isNil.
	self assertNotShown: key
!
testTheKeyIsNeverShown
	| window agent key token |
	key := self newKey.
	token := self newToken.
	window := self openPanel.
	self fill: (self settingsFor: 'https://models.example') in: window.
	self pasteKey: key in: window.
	self assertNotShown: key.
	self click: 'save-key' in: window.
	self assert: keyAccount isSignedIn.
	self assertNotShown: key.
	self fill: (Dictionary new at: 'repository' put: 'cv/samaltak'; yourself) in: window.
	world clipboard: token.
	self click: 'paste-token' in: window.
	self assert: (self in: window do: [window content tokenField hasSecret]).
	self assertNotShown: token.
	self click: 'save-github' in: window.
	self assert: gitHub isConfigured.
	self assertNotShown: token.
	"Nor in the Agent window that uses the key."
	AgentWindow account: keyAccount.
	agent := self open: [AgentWindow openOn: (AgentConversation new provider: ScriptedProvider new; yourself) origin: nil in: (100 @ 60 extent: 720 @ 600)].
	self settle.
	self assertNotShown: key.
	self assertNotShown: token
!
testForgetClearsTheKeyAndTheToken
	| window view stored storedToken |
	window := self openPanel.
	view := window content.
	self fill: (self settingsFor: 'https://models.example') in: window.
	self pasteKey: self newKey in: window.
	self click: 'save-key' in: window.
	stored := keyAccount apiKey.
	self assert: ((self in: window do: [view keyAccount configuration at: 'hasKey'])).
	self click: 'forget-key' in: window.
	self deny: keyAccount isSignedIn.
	self assert: keyAccount isConfigured.
	self assert: (stored allSatisfy: [:c | c = $*]) description: 'the key was not overwritten'.
	self assert: (self in: window do: [view keyMessage]) equals: 'The key is forgotten; the settings stay.'.
	self fill: (Dictionary new at: 'repository' put: 'cv/samaltak'; yourself) in: window.
	world clipboard: self newToken.
	self click: 'paste-token' in: window.
	self click: 'save-github' in: window.
	storedToken := gitHub token.
	self click: 'forget-token' in: window.
	self deny: gitHub hasToken.
	self assert: gitHub repository equals: 'cv/samaltak'.
	self assert: (storedToken allSatisfy: [:c | c = $*]) description: 'the token was not overwritten'.
	"A key typed but not saved goes too."
	self pasteKey: self newKey in: window.
	self click: 'forget-key' in: window.
	self deny: (self in: window do: [view keyField hasSecret])
!
testBadSettingsChangeNothing
	| window view |
	window := self openPanel.
	view := window content.
	self fill: ((self settingsFor: 'ftp://models.example') at: 'max-tokens' put: 'many'; yourself) in: window.
	self pasteKey: self newKey in: window.
	self click: 'save-key' in: window.
	self assert: (self in: window do: [view keyMessage]) equals: 'Max tokens must be a positive integer'.
	self fill: (Dictionary new at: 'max-tokens' put: '1000'; yourself) in: window.
	self click: 'save-key' in: window.
	self assert: (self in: window do: [view keyMessage]) equals: 'The base URL must be an http(s) URL'.
	self deny: keyAccount isConfigured.
	self should: [keyAccount apiKey] raise: AgentError.
	self assert: (self in: window do: [view keyField hasSecret]) description: 'the key typed was lost'.
	self fill: (Dictionary new at: 'base-url' put: 'https://models.example'; yourself) in: window.
	self click: 'save-key' in: window.
	self assert: keyAccount isSignedIn.
	"GitHub: a bad repository keeps the account as it was."
	self fill: (Dictionary new at: 'repository' put: 'no-slash'; yourself) in: window.
	world clipboard: self newToken.
	self click: 'paste-token' in: window.
	self click: 'save-github' in: window.
	self assert: (self in: window do: [view gitHubMessage]) equals: 'The repository must be owner/name'.
	self deny: gitHub hasToken.
	self assert: gitHub repository isNil.
	self assert: (self in: window do: [view tokenField hasSecret])
!
testTheKeyCardOpensAccountsAndTheAgentAnswers
	| agent view card panel provider conversation |
	keyAccount providerName: 'test' baseURL: 'https://models.example' model: 'claude-test' thinking: 'high' maxTokens: 1000.
	AgentWindow account: keyAccount.
	provider := ScriptedProvider new.
	agent := self open: [AgentWindow openOn: (AgentConversation new provider: provider; yourself) origin: nil in: (100 @ 60 extent: 720 @ 600)].
	view := agent content.
	card := view loginCard.
	conversation := view conversation.
	self assert: (self waitFor: [self in: agent do: [card isVisible and: [card isShowingKeyHelp]]]) description: 'no key help'.
	self assert: (self in: agent do: [card accountsButton isVisible]).
	self assert: ((self in: agent do: [(view widgetNamed: 'url') text]) includesSubstring: 'samaltak-ctl agent-config').
	self assert: (self in: agent do: [card accountsButton label]) equals: 'Accounts…'.
	self in: agent do: [card accountsButton click].
	self assert: (self waitFor: [(self windowsOf: AccountsPanel) size = 1]) description: 'no Accounts window'.
	panel := (self windowsOf: AccountsPanel) first.
	self assert: (self waitFor: [panel isOpen]).
	self assert: panel content keyAccount == keyAccount.
	self assert: (self in: panel do: [(panel content fieldNamed: 'model') text]) equals: 'claude-test'.
	world clipboard: self newKey.
	self click: 'paste-key' in: panel.
	self click: 'save-key' in: panel.
	self assert: keyAccount isSignedIn.
	self assert: (self waitFor: [self in: agent do: [card isVisible not and: [view transcript owner isVisible]]]) description: 'the key did not show the transcript'.
	provider reply: {ScriptedProvider message: 'Hello.'}.
	self in: agent do: [view askEditor text: 'hi'. view send].
	self assert: (self waitFor: [conversation isBusy not and: [conversation items notEmpty and: [conversation items last kind == #assistant]]]) description: 'the agent did not answer'.
	self assert: conversation items last text equals: 'Hello.'
!
testTheChatGPTCardOffersAnApiKey
	| account agent card |
	account := AgentTestAccount new.
	account signOut.
	AgentWindow account: account.
	agent := self open: [AgentWindow openOn: (AgentConversation new provider: ScriptedProvider new; yourself) origin: nil in: (100 @ 60 extent: 720 @ 600)].
	card := agent content loginCard.
	self assert: (self waitFor: [self in: agent do: [card isVisible and: [card apiKeyButton isVisible]]]).
	self deny: (self in: agent do: [card accountsButton isVisible]).
	self in: agent do: [card apiKeyButton click].
	self assert: (self waitFor: [(self windowsOf: AccountsPanel) size = 1]) description: 'no Accounts window'.
	self assert: (self windowsOf: AccountsPanel) first content keyAccount == keyAccount
!
testThePanelFollowsTheAccounts
	| window view |
	window := self openPanel.
	view := window content.
	keyAccount configure: (Dictionary new at: 'provider' put: 'host'; at: 'baseUrl' put: 'https://models.example'; at: 'model' put: 'claude-host'; at: 'apiKey' put: self newKey; yourself).
	gitHub configure: (Dictionary new at: 'repository' put: 'cv/samaltak'; yourself).
	self assert: (self waitFor: [(self in: window do: [(view fieldNamed: 'model') text]) = 'claude-host'] timeout: 5000) description: 'the panel did not follow'.
	self assert: (self in: window do: [(view fieldNamed: 'repository') text]) equals: 'cv/samaltak'.
	self assert: (self in: window do: [(view widgetNamed: 'model') isKindOf: TextEditor]).
	self assert: ((self in: window do: [view keyField placeholder]) beginsWith: 'a key is set')
! !

!AccountsPanelTest methodsFor: 'tests - secret field'!
testSecretField
	| field first second |
	field := SecretField new placeholder: 'the key'; yourself.
	field append: 'sk-a'.
	first := field secret.
	field append: 'bc'.
	self assert: field secret equals: 'sk-abc'.
	self assert: (first allSatisfy: [:c | c = $*]) description: 'an edit left the string before it'.
	second := field secret.
	field deleteLast.
	self assert: field secret equals: 'sk-ab'.
	self assert: (second allSatisfy: [:c | c = $*]).
	self assert: field printString equals: 'a SecretField (filled)'.
	self assert: field remoteLabel equals: 'the key'.
	self assert: (field remoteState includes: #filled).
	self deny: (field respondsTo: #remoteText).
	first := field secret.
	field release.
	self deny: field hasSecret.
	self assert: first equals: 'sk-ab'.
	field append: 'sk-xyz'.
	first := field secret.
	field clear.
	self deny: field hasSecret.
	self assert: (first allSatisfy: [:c | c = $*]).
	self assert: field printString equals: 'a SecretField (empty)'.
	self assert: (Smalltalk shutDownList includes: #SecretField) description: 'fields are not cleared before a snapshot'
! !
