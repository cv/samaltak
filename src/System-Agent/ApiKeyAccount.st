Object subclass: #ApiKeyAccount
	instanceVariableNames: 'providerName baseURL model thinking maxTokens apiKey changeBlocks contextWindow'
	classVariableNames: 'Default'
	package: 'System-Agent'!

ApiKeyAccount comment: 'I am an API-key account for a model behind the Anthropic Messages API, which AnthropicProvider talks to: the provider''s name (a label, e.g. ''nvidia-internal''), the base URL (requests go to baseURL, ''/v1/messages''), the model id, the thinking effort (''low'' ''medium'' ''high'' ''xhigh'' ''max''; nil turns thinking off), the max_tokens of a response, the model''s context window in tokens (nil when unknown; another model forgets it), and the API key.

The key lives in memory only: I never print it, and it is forgotten before every snapshot and quit (I am on the shutdown list), so no image file contains it; the rest of my configuration is saved with the image. After Save image or Rebuild & reboot the key is set again. The host sends it over the control connection with samaltak-ctl agent-config --from-pi (docs/agent.md), which is the agent-config command I register with RemoteControl:

	{"cmd": "agent-config", "provider": "nvidia-internal", "baseUrl": "https://inference-api.nvidia.com", "model": "azure/anthropic/claude-opus-5-5", "thinking": "high", "maxTokens": 128000, "contextWindow": 200000, "apiKey": "..."}
	{"cmd": "agent-config"}   "the configuration"
	{"cmd": "agent-config", "clear": true}   "forget it all"
each answering the configuration (configuration: provider, baseUrl, model, thinking, maxTokens, contextWindow, hasKey; never the key).

	account := ApiKeyAccount default.
	account isConfigured.   "a base URL and a model: new conversations use an AnthropicProvider"
	account isSignedIn.   "and a key"
	account onChange: [:anAccount | ...] for: anOwner   "after every change; nil unsubscribes anOwner"'!

!ApiKeyAccount methodsFor: 'initialization'!
initialize
	maxTokens := 32000
! !

!ApiKeyAccount methodsFor: 'accessing'!
providerName
	^providerName
!
baseURL
	^baseURL
!
model
	^model
!
thinking
	"The thinking effort, or nil for no thinking."
	^thinking
!
maxTokens
	^maxTokens
!
apiKey
	"The key. AgentError when there is none."
	apiKey isNil ifTrue: [^AgentError signal: 'No API key: on the host, run samaltak-ctl agent-config --from-pi'].
	^apiKey
!
isConfigured
	^baseURL notNil and: [model notNil]
!
isSignedIn
	^self isConfigured and: [apiKey notNil]
!
statusLabel
	"What the Agent window's status bar shows of me."
	^(providerName ifNil: [baseURL ifNil: ['not configured']]), (apiKey isNil ifTrue: [' (no key)'] ifFalse: [''])
!
configuration
	"My settings, without the key."
	^Dictionary new
		at: 'provider' put: providerName;
		at: 'baseUrl' put: baseURL;
		at: 'model' put: model;
		at: 'thinking' put: thinking;
		at: 'maxTokens' put: maxTokens;
		at: 'contextWindow' put: contextWindow;
		at: 'hasKey' put: apiKey notNil;
		yourself
!
contextWindow
	"The model's context window in tokens, nil when not told."
	^contextWindow
!
contextWindow: anIntegerOrNil
	(anIntegerOrNil isNil or: [anIntegerOrNil isInteger and: [anIntegerOrNil > 0]])
		ifFalse: [^AgentError signal: 'contextWindow must be a positive integer'].
	contextWindow := anIntegerOrNil.
	self changed
! !

!ApiKeyAccount methodsFor: 'configuring'!
providerName: aString baseURL: aURLString model: aModelId thinking: anEffortOrNil maxTokens: anInteger
	(aURLString isString and: [(aURLString beginsWith: 'https://') or: [aURLString beginsWith: 'http://']])
		ifFalse: [^AgentError signal: 'The base URL must be an http(s) URL'].
	(aModelId isString and: [aModelId notEmpty]) ifFalse: [^AgentError signal: 'No model'].
	(anEffortOrNil isNil or: [#('low' 'medium' 'high' 'xhigh' 'max') includes: anEffortOrNil])
		ifFalse: [^AgentError signal: 'Thinking must be low, medium, high, xhigh, max or off'].
	(anInteger isInteger and: [anInteger > 0]) ifFalse: [^AgentError signal: 'maxTokens must be a positive integer'].
	providerName := aString.
	baseURL := (aURLString endsWith: '/') ifTrue: [aURLString allButLast] ifFalse: [aURLString].
	model := aModelId.
	thinking := anEffortOrNil.
	maxTokens := anInteger.
	self changed
!
apiKey: aString
	"Hold aString as the key (in memory only)."
	(aString isString and: [aString notEmpty]) ifFalse: [^AgentError signal: 'The API key is empty'].
	self forgetKey.
	apiKey := aString.
	self changed
!
configure: aDictionary
	"Apply an agent-config request's settings (JSON names: provider baseUrl model thinking maxTokens contextWindow apiKey); a missing setting keeps its value, but another model forgets the context window; thinking 'off' turns thinking off."
	| effort newModel window previous |
	effort := aDictionary at: 'thinking' ifAbsent: [thinking].
	effort = 'off' ifTrue: [effort := nil].
	newModel := aDictionary at: 'model' ifAbsent: [model].
	window := aDictionary at: 'contextWindow' ifAbsent: [newModel = model ifTrue: [contextWindow]].
	(window isNil or: [window isInteger and: [window > 0]])
		ifFalse: [^AgentError signal: 'contextWindow must be a positive integer'].
	previous := contextWindow.
	contextWindow := window.
	[self
		providerName: (aDictionary at: 'provider' ifAbsent: [providerName])
		baseURL: (aDictionary at: 'baseUrl' ifAbsent: [baseURL])
		model: newModel
		thinking: effort
		maxTokens: (aDictionary at: 'maxTokens' ifAbsent: [maxTokens])]
			ifCurtailed: [contextWindow := previous].
	(aDictionary includesKey: 'apiKey') ifTrue: [self apiKey: (aDictionary at: 'apiKey')]
!
signOut
	"Forget the key; the configuration stays."
	self forgetKey.
	self changed
!
forget
	"Forget the key and the configuration."
	self forgetKey.
	providerName := baseURL := model := thinking := contextWindow := nil.
	maxTokens := 32000.
	self changed
!
forgetKey
	"Drop the key, overwriting its characters first so no copy that shares it survives."
	| key |
	key := apiKey.
	apiKey := nil.
	key isString ifTrue: [[1 to: key size do: [:i | key at: i put: $*]] on: Error do: [:e | e return: nil]]
! !

!ApiKeyAccount methodsFor: 'notification'!
onChange: aBlock for: anOwner
	"Evaluate aBlock with me after every change; nil removes anOwner's subscription."
	changeBlocks isNil ifTrue: [changeBlocks := IdentityDictionary new].
	aBlock isNil
		ifTrue: [changeBlocks removeKey: anOwner ifAbsent: []]
		ifFalse: [changeBlocks at: anOwner put: aBlock]
!
changed
	changeBlocks isNil ifFalse: [changeBlocks values do: [:each | each value: self]]
! !

!ApiKeyAccount methodsFor: 'printing'!
printOn: aStream
	"Never the key."
	aStream nextPutAll: 'an ApiKeyAccount'.
	self isConfigured ifFalse: [^aStream nextPutAll: ' (not configured)'].
	aStream nextPutAll: ' ('; nextPutAll: model; nextPutAll: ' at '; nextPutAll: (providerName ifNil: [baseURL]).
	apiKey isNil ifTrue: [aStream nextPutAll: ', no key'].
	aStream nextPut: $)
! !

!ApiKeyAccount class methodsFor: 'accessing'!
default
	"The image's account."
	^Default ifNil: [Default := self new]
!
default: anAccountOrNil
	"Make anAccountOrNil the image's account (tests); nil: a new one next time."
	Default := anAccountOrNil
!
reset
	Default isNil ifFalse: [Default forgetKey].
	Default := nil
! !

!ApiKeyAccount class methodsFor: 'class initialization'!
initialize
	Smalltalk addToShutDownList: self.
	RemoteControl registerCommand: 'agent-config' handler: [:request | self agentConfig: request]
! !

!ApiKeyAccount class methodsFor: 'system startup'!
shutDown: quitting
	"Before a snapshot or quit: no account keeps its key."
	self allInstancesDo: [:each | each forgetKey]
! !

!ApiKeyAccount class methodsFor: 'remote control'!
agentConfig: aRemoteRequest
	"The agent-config command: configure the default account (see my comment) and answer its configuration."
	| arguments |
	arguments := aRemoteRequest arguments.
	(arguments at: 'clear' ifAbsent: [false]) == true
		ifTrue: [self default forget]
		ifFalse: [
			(arguments keys anySatisfy: [:each | #('provider' 'baseUrl' 'model' 'thinking' 'maxTokens' 'contextWindow' 'apiKey') includes: each])
				ifTrue: [[self default configure: arguments] on: AgentError do: [:e | RemoteError signal: e messageText]]].
	^self default configuration
! !
