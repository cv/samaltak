TestCase subclass: #ApiKeyAccountTest
	instanceVariableNames: 'account previous'
	classVariableNames: ''
	package: 'Tests-Agent'!

ApiKeyAccountTest comment: 'Tests ApiKeyAccount: the agent-config control command (configure, answer without the key, refuse bad settings, clear), the default base URL, that the key is never printed and is forgotten at shutdown, and that conversations pick AnthropicProvider once an account is configured. The image''s account is swapped for a fresh one during each test and put back after it. That no snapshot holds a key is checked from the host, through samaltak-ctl agent-config (tests/tools/agent_config_test.sh).'!

!ApiKeyAccountTest methodsFor: 'running'!
setUp
	previous := ApiKeyAccount default.
	account := ApiKeyAccount new.
	ApiKeyAccount default: account
!
tearDown
	account forgetKey.
	ApiKeyAccount default: previous
!
agentConfig: aDictionary
	"The agent-config command's response, as the control connection would send it."
	^RemoteControl dispatch: (RemoteRequest on: (aDictionary copy at: 'cmd' put: 'agent-config'; yourself))
!
settings
	^JSON parse: '{"provider":"test","baseUrl":"https://models.example/","model":"claude-test","thinking":"high","maxTokens":2000}'
!
newKey
	"A key made at run time, so that no literal in the image holds it."
	| random |
	random := Random new.
	^String new: 40 streamContents: [:s |
		s nextPutAll: 'sk-'.
		37 timesRepeat: [s nextPut: ('0123456789abcdefghijklmnopqrstuvwxyz' at: (random nextInt: 36))]]
! !

!ApiKeyAccountTest methodsFor: 'tests'!
testAgentConfigCommand
	| key response |
	key := self newKey.
	response := self agentConfig: (self settings at: 'apiKey' put: key; yourself).
	self assert: (response at: 'ok').
	self assert: (response at: 'hasKey').
	self assert: (response at: 'provider') equals: 'test'.
	self assert: (response at: 'baseUrl') equals: 'https://models.example'.
	self assert: (response at: 'model') equals: 'claude-test'.
	self assert: (response at: 'thinking') equals: 'high'.
	self assert: (response at: 'maxTokens') equals: 2000.
	self deny: ((JSON render: response) includesSubstring: key).
	self assert: account isSignedIn.
	self assert: account apiKey equals: key.
	self assert: account statusLabel equals: 'test'.
	self deny: (account printString includesSubstring: key).
	self assert: account printString equals: 'an ApiKeyAccount (claude-test at test)'.
	response := self agentConfig: Dictionary new.
	self assert: (response at: 'hasKey').
	response := self agentConfig: (Dictionary new at: 'thinking' put: 'off'; yourself).
	self assert: (response at: 'thinking') isNil.
	self assert: account isSignedIn.
	response := self agentConfig: (Dictionary new at: 'clear' put: true; yourself).
	self deny: (response at: 'hasKey').
	self assert: (response at: 'model') isNil.
	self deny: account isConfigured.
	self assert: (key allSatisfy: [:each | each = $*])
!
testAgentConfigRefusesBadSettings
	| response |
	response := self agentConfig: (self settings at: 'baseUrl' put: 'ftp://x'; yourself).
	self deny: (response at: 'ok').
	self assert: ((response at: 'error') includesSubstring: 'http(s) URL').
	response := self agentConfig: (self settings at: 'thinking' put: 'lots'; yourself).
	self deny: (response at: 'ok').
	response := self agentConfig: (self settings at: 'apiKey' put: ''; yourself).
	self deny: (response at: 'ok').
	self deny: account isSignedIn.
	self deny: account isConfigured
!
testNoKey
	self deny: account isConfigured.
	self assert: account baseURL equals: 'https://api.anthropic.com'.
	self should: [account apiKey] raise: AgentError.
	account configure: (self settings removeKey: 'baseUrl'; yourself).
	self assert: account baseURL equals: 'https://api.anthropic.com'.
	account configure: self settings.
	self assert: account isConfigured.
	self deny: account isSignedIn.
	self assert: account statusLabel equals: 'test (no key)'.
	self assert: account printString equals: 'an ApiKeyAccount (claude-test at test, no key)'
!
testSignOutKeepsTheConfiguration
	| changes |
	changes := 0.
	account onChange: [:a | changes := changes + 1] for: self.
	account configure: (self settings at: 'apiKey' put: self newKey; yourself).
	account signOut.
	self assert: account isConfigured.
	self deny: account isSignedIn.
	self assert: changes equals: 3.
	account onChange: nil for: self.
	account apiKey: self newKey.
	self assert: changes equals: 3
!
testShutDownForgetsEveryKey
	| other key |
	"ApiKeyAccount shutDown: forgets the key of every account, the image's own too: only in the image make test runs."
	(Smalltalk vm arguments includes: '--test') ifFalse: [^self].
	key := self newKey.
	account configure: (self settings at: 'apiKey' put: key; yourself).
	other := ApiKeyAccount new apiKey: self newKey; yourself.
	ApiKeyAccount shutDown: false.
	self deny: account isSignedIn.
	self assert: account isConfigured.
	self should: [other apiKey] raise: AgentError.
	self assert: (key allSatisfy: [:each | each = $*])
!
testConversationsPickTheProvider
	self assert: (AgentConversation new provider isKindOf: CodexProvider).
	account configure: self settings.
	self assert: (AgentConversation new provider isKindOf: AnthropicProvider).
	self assert: AgentConversation new provider account == account.
	self assert: AgentConversation new provider modelName equals: 'claude-test'
!
testContextWindow
	| response |
	response := self agentConfig: self settings.
	self assert: (response at: 'contextWindow') isNil.
	response := self agentConfig: (self settings at: 'contextWindow' put: 1000000; yourself).
	self assert: (response at: 'contextWindow') equals: 1000000.
	self assert: account contextWindow equals: 1000000.
	response := self agentConfig: (Dictionary new at: 'thinking' put: 'low'; yourself).
	self assert: (response at: 'contextWindow') equals: 1000000.
	response := self agentConfig: (Dictionary new at: 'model' put: 'claude-other'; yourself).
	self assert: (response at: 'contextWindow') isNil.
	response := self agentConfig: (Dictionary new at: 'contextWindow' put: 0; yourself).
	self deny: (response at: 'ok').
	self assert: account contextWindow isNil.
	self assert: account model equals: 'claude-other'.
	response := self agentConfig: (Dictionary new at: 'clear' put: true; yourself).
	self assert: (response at: 'contextWindow') isNil.
	self assert: account baseURL equals: 'https://api.anthropic.com'
! !
