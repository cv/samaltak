ToolPane subclass: #AccountsPanel
	instanceVariableNames: 'keyAccount gitHubAccount fields order thinking keyField tokenField keyHeader gitHubHeader keyMessage gitHubMessage seen'
	classVariableNames: ''
	package: 'Tools-Agent'!

AccountsPanel comment: 'I am the Accounts window (World menu › Settings › "Accounts", the Agent window''s key card; docs/agent.md, docs/github.md): the image''s accounts configured from the World itself, for a machine with no host to run samaltak-ctl agent-config --from-pi or github-config --from-gh (bare-metal UEFI).

Model API key (an ApiKeyAccount, ApiKeyAccount default): provider, base URL, model, thinking, max tokens and context window, and whether a key is set; a key typed or pasted (⌘V or Paste) into a SecretField, shown as bullets. Save applies the settings and the key (configure:, so a bad setting changes nothing and says why), Forget key signs out (the settings stay). GitHub (a GitHubAccount, GitHubAccount default): repository, base branch, branch prefix, whether a token is set, a token field, Save and Forget token.

I never show or keep a key: the field hands it to the account and lets go; the account holds it in memory only and drops it before every snapshot (as when samaltak-ctl sends it). What I show follows the accounts when they change elsewhere (a samaltak-ctl request): I compare their configurations once a second.

	AccountsPanel open.   "on the default accounts, or the one already open"
	AccountsPanel openOn: anApiKeyAccount gitHub: aGitHubAccount in: aRectangle

Remote names: provider base-url model thinking max-tokens context-window api-key paste-key save-key forget-key key-message; repository base-branch branch-prefix token paste-token save-github forget-token github-message.'!

!AccountsPanel methodsFor: 'initialization'!
setKeyAccount: anApiKeyAccount gitHubAccount: aGitHubAccount
	keyAccount := anApiKeyAccount.
	gitHubAccount := aGitHubAccount.
	fields := Dictionary new.
	order := OrderedCollection new.
	thinking := (ToggleGroup options: #('off' 'low' 'medium' 'high' 'xhigh' 'max') selected: 1) name: 'thinking'; yourself.
	keyField := SecretField new name: 'api-key'; onAccept: [self saveKey]; yourself.
	tokenField := SecretField new name: 'token'; onAccept: [self saveGitHub]; yourself.
	keyHeader := PaneHeader title: 'Model API key'.
	gitHubHeader := PaneHeader title: 'GitHub'.
	keyMessage := Label text: '' font: #uiItalic.
	keyMessage name: 'key-message'; color: #ink3.
	gitHubMessage := Label text: '' font: #uiItalic.
	gitHubMessage name: 'github-message'; color: #ink3.
	self addAll: {
		keyHeader.
		self spacer.
		self row: 'Provider' with: (self field: 'provider' accept: [self saveKey]).
		self row: 'Base URL' with: (self field: 'base-url' accept: [self saveKey]).
		self row: 'Model' with: (self field: 'model' accept: [self saveKey]).
		self row: 'Thinking' with: thinking.
		self row: 'Max tokens' with: (self field: 'max-tokens' accept: [self saveKey]).
		self row: 'Context window' with: (self field: 'context-window' accept: [self saveKey]).
		self row: 'API key' with: (self secretRow: keyField paste: 'paste-key').
		self buttonsSave: 'save-key' action: [self saveKey] forget: 'forget-key' label: 'Forget key' action: [self forgetKey] message: keyMessage.
		gitHubHeader.
		self spacer.
		self row: 'Repository' with: (self field: 'repository' accept: [self saveGitHub]).
		self row: 'Base branch' with: (self field: 'base-branch' accept: [self saveGitHub]).
		self row: 'Branch prefix' with: (self field: 'branch-prefix' accept: [self saveGitHub]).
		self row: 'Token' with: (self secretRow: tokenField paste: 'paste-token').
		self buttonsSave: 'save-github' action: [self saveGitHub] forget: 'forget-token' label: 'Forget token' action: [self forgetToken] message: gitHubMessage.
		(PaneHeader title: '') fixed: 1; yourself.
		(Label text: 'Kept in memory only: set them again after Save image or a restart.' font: #uiItalic)
			color: #ink3; padding: (16 @ 0 corner: 16 @ 0); fixed: 26; yourself.
		Widget new}.
	self refresh
!
spacer
	^Widget new fixed: 6; yourself
!
field: aName accept: aBlock
	"A framed one-line editor named aName; Return runs aBlock, Tab and Shift-Tab move between the fields."
	| editor |
	editor := TextEditor new name: aName; title: aName; highlighting: false; font: #ui; yourself.
	editor onKey: [:event | self fieldKey: event in: editor accept: aBlock].
	fields at: aName put: editor.
	order add: editor.
	^self framed: editor
!
framed: aWidget
	^(Row with: {aWidget}) background: #ink; padding: 1; yourself
!
row: aString with: aWidget
	^(Row with: {(Label text: aString font: #ui) fixed: 118; yourself. aWidget})
		fixed: self fieldHeight + 6; padding: (16 @ 2 corner: 16 @ 2); yourself
!
fieldHeight
	"A framed one-line editor's height: its line and padding (no scroll bar), and the frame."
	^((self fontFor: #ui) lineHeight + (2 * (self theme metric: #editorPaddingY)) + 3) ceiling
!
secretRow: aSecretField paste: aName
	order add: aSecretField.
	^(Row with: {aSecretField. (Button label: 'Paste' action: [aSecretField paste. aSecretField focus]) name: aName; fixed: 64; yourself})
		spacing: 8; yourself
!
buttonsSave: saveName action: saveBlock forget: forgetName label: forgetLabel action: forgetBlock message: aLabel
	^(Row with: {
		Widget new fixed: 118; yourself.
		(Button label: 'Save' action: saveBlock) name: saveName; beDefault; sizeToContent; yourself.
		(Button label: forgetLabel action: forgetBlock) name: forgetName; sizeToContent; yourself.
		aLabel})
			spacing: 8; fixed: 34; padding: (16 @ 6 corner: 16 @ 4); yourself
!
minimumWindowExtent
	^480 @ 560
! !

!AccountsPanel methodsFor: 'accessing'!
keyAccount
	^keyAccount
!
gitHubAccount
	^gitHubAccount
!
fieldNamed: aName
	^fields at: aName
!
keyField
	^keyField
!
tokenField
	^tokenField
!
thinking
	^thinking
!
keyMessage
	^keyMessage text
!
gitHubMessage
	^gitHubMessage text
! !

!AccountsPanel methodsFor: 'showing'!
refresh
	"Show the accounts' settings in the fields, and whether each has its key."
	(fields at: 'provider') text: (keyAccount providerName ifNil: ['']).
	(fields at: 'base-url') text: (keyAccount baseURL ifNil: ['https://api.anthropic.com']).
	(fields at: 'model') text: (keyAccount model ifNil: ['']).
	thinking selection: (keyAccount thinking ifNil: ['off']).
	(fields at: 'max-tokens') text: keyAccount maxTokens printString.
	(fields at: 'context-window') text: (keyAccount contextWindow ifNil: [''] ifNotNil: [:n | n printString]).
	(fields at: 'repository') text: (gitHubAccount repository ifNil: ['']).
	(fields at: 'base-branch') text: gitHubAccount baseBranch.
	(fields at: 'branch-prefix') text: gitHubAccount branchPrefix.
	self refreshStatus
!
refreshStatus
	| api |
	api := keyAccount configuration.
	keyHeader rightText: (keyAccount isConfigured
		ifTrue: [(api at: 'hasKey') ifTrue: ['key set'] ifFalse: ['no key']]
		ifFalse: ['not configured', ((api at: 'hasKey') ifTrue: [' · key set'] ifFalse: [''])]).
	keyField placeholder: ((api at: 'hasKey')
		ifTrue: ['a key is set: paste another to replace it']
		ifFalse: ['type or paste the key']).
	gitHubHeader rightText: (gitHubAccount hasToken ifTrue: ['token set'] ifFalse: ['no token']).
	tokenField placeholder: (gitHubAccount hasToken
		ifTrue: ['a token is set: paste another to replace it']
		ifFalse: ['type or paste the token']).
	seen := Array with: api with: gitHubAccount configuration
!
followAccounts
	"The accounts changed elsewhere (a samaltak-ctl request): show them."
	(seen notNil and: [(seen at: 1) = keyAccount configuration and: [(seen at: 2) = gitHubAccount configuration]]) ifTrue: [^self].
	self refresh
! !

!AccountsPanel methodsFor: 'actions'!
saveKey
	"Apply the settings, and the key when one was typed or pasted; a bad setting changes nothing."
	| settings |
	settings := [self keySettings] on: AgentError do: [:e | ^self keyMessage: e messageText].
	keyField hasSecret ifTrue: [settings at: 'apiKey' put: keyField secret].
	[keyAccount configure: settings] on: AgentError do: [:e | ^self keyMessage: e messageText].
	(settings includesKey: 'apiKey') ifTrue: [keyField release].
	self refresh.
	self keyMessage: (keyAccount isSignedIn ifTrue: ['Saved; the agent can use it now.'] ifFalse: ['Saved; there is no key yet.'])
!
keySettings
	"The ApiKeyAccount settings in the fields (configure:'s names)."
	| d provider maxTokens window |
	d := Dictionary new.
	provider := (fields at: 'provider') text trimBoth.
	d at: 'provider' put: (provider isEmpty ifTrue: [nil] ifFalse: [provider]).
	d at: 'baseUrl' put: (fields at: 'base-url') text trimBoth.
	d at: 'model' put: (fields at: 'model') text trimBoth.
	d at: 'thinking' put: (thinking selection ifNil: ['off']).
	maxTokens := self integerIn: 'max-tokens' named: 'Max tokens'.
	maxTokens isNil ifTrue: [^AgentError signal: 'Max tokens must be a positive integer'].
	d at: 'maxTokens' put: maxTokens.
	window := self integerIn: 'context-window' named: 'The context window'.
	d at: 'contextWindow' put: window.
	^d
!
integerIn: aFieldName named: aString
	"The positive integer in a field, nil when it is empty; AgentError when it is something else."
	| text n |
	text := (fields at: aFieldName) text trimBoth.
	text isEmpty ifTrue: [^nil].
	n := (text allSatisfy: [:c | c isDigit]) ifTrue: [Number readFrom: text ifFail: [nil]].
	(n isInteger and: [n > 0]) ifFalse: [^AgentError signal: aString, ' must be a positive integer'].
	^n
!
forgetKey
	keyField clear.
	keyAccount signOut.
	self refreshStatus.
	self keyMessage: 'The key is forgotten; the settings stay.'
!
saveGitHub
	"Apply the repository, the branches and the token when one was typed or pasted; a bad setting changes nothing."
	| settings |
	settings := Dictionary new.
	settings
		at: 'repository' put: (fields at: 'repository') text trimBoth;
		at: 'baseBranch' put: (fields at: 'base-branch') text trimBoth;
		at: 'branchPrefix' put: (fields at: 'branch-prefix') text trimBoth.
	tokenField hasSecret ifTrue: [settings at: 'token' put: tokenField secret].
	[gitHubAccount configure: settings] on: Error do: [:e | ^self gitHubMessage: e messageText].
	(settings includesKey: 'token') ifTrue: [tokenField release].
	self refresh.
	self gitHubMessage: (gitHubAccount isConfigured ifTrue: ['Saved; changes can go to GitHub now.'] ifFalse: ['Saved; there is no token yet.'])
!
forgetToken
	tokenField clear.
	gitHubAccount forgetToken.
	self refreshStatus.
	self gitHubMessage: 'The token is forgotten; the repository stays.'
!
keyMessage: aString
	keyMessage text: aString
!
gitHubMessage: aString
	gitHubMessage text: aString
! !

!AccountsPanel methodsFor: 'events'!
fieldKey: anEvent in: anEditor accept: aBlock
	| i |
	(anEvent key == #return or: [anEvent key == #enter]) ifTrue: [aBlock value. ^true].
	anEvent key == #tab ifFalse: [^false].
	i := order indexOf: anEditor.
	i := anEvent modifiers shift ifTrue: [i - 1] ifFalse: [i + 1].
	i < 1 ifTrue: [i := order size].
	i > order size ifTrue: [i := 1].
	(order at: i) focus.
	^true
!
keyDown: anEvent
	"Tab in a secret field moves on, as in the other fields."
	| i focus |
	(anEvent key == #tab and: [self window notNil]) ifTrue: [
		focus := self window keyboardFocus.
		i := order indexOf: focus.
		i > 0 ifTrue: [
			i := anEvent modifiers shift ifTrue: [i - 1] ifFalse: [i + 1].
			i < 1 ifTrue: [i := order size].
			i > order size ifTrue: [i := 1].
			(order at: i) focus.
			^true]].
	^super keyDown: anEvent
!
windowClosed
	keyField clear.
	tokenField clear
! !

!AccountsPanel class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	"On the default accounts; the window already open comes to the front."
	^self openOn: ApiKeyAccount default gitHub: GitHubAccount default in: (Tools placeAt: aPointOrNil extent: self extent)
!
openNear: aWindow keyAccount: anApiKeyAccount
	^self openOn: anApiKeyAccount gitHub: GitHubAccount default in: (Tools placeNear: aWindow extent: self extent)
!
openOn: anApiKeyAccount gitHub: aGitHubAccount in: aRectangle
	| existing view window |
	existing := (Tools windowsOf: self) detect: [:each | each content keyAccount == anApiKeyAccount and: [each content gitHubAccount == aGitHubAccount]] ifNone: [nil].
	existing isNil ifFalse: [existing focus. ^existing].
	view := self new setKeyAccount: anApiKeyAccount gitHubAccount: aGitHubAccount.
	window := view openIn: aRectangle title: 'Accounts'.
	window do: [
		view every: 1000 do: [view followAccounts].
		view keyField focus].
	^window
!
extent
	^560 @ 640
!
initialize
	Tools registerOpener: #accounts with: [:tool | self open].
	ToolsMenu register: 'Accounts' description: 'API key · GitHub token' group: #settings order: 66 action: [:point | self openAt: point]
! !
