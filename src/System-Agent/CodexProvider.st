Object subclass: #CodexProvider
	instanceVariableNames: 'account baseURL effort sessionId client cancelled finished usage requestDiagnostics previousRequestJSON'
	classVariableNames: ''
	package: 'System-Agent'!

CodexProvider comment: 'I send a conversation to OpenAI''s model through the ChatGPT backend the Codex CLI uses (presenting myself as it), signed in with an OpenAIAccount: one streamed Responses-API request per send:tools:onText:onItem:, decoded from its server-sent events. The only class that knows this backend; a provider for another backend implements the same protocol.

	provider := CodexProvider new.
	provider send: {aMessageItem} tools: #() onText: [:delta | ...] onItem: [:item | ...]   "answers the usage"

Items and tool specs are the Responses API''s, as JSON parses them (Dictionaries with String keys). My connection is kept between sends; cancel closes it from another Process.'!

!CodexProvider methodsFor: 'initialization'!
initialize
	baseURL := 'https://chatgpt.com/backend-api/codex'.
	effort := 'low'.
	sessionId := self class newSessionId.
	client := HTTPClient new
! !

!CodexProvider methodsFor: 'accessing'!
account
	^account ifNil: [account := OpenAIAccount default]
!
account: anOpenAIAccount
	account := anOpenAIAccount
!
baseURL
	^baseURL
!
baseURL: aURLString
	baseURL := aURLString
!
effort
	^effort
!
effort: aString
	"The reasoning effort: 'low', 'medium', 'high'."
	effort := aString
!
modelName
	^'gpt-6.1-sol'
! !

!CodexProvider methodsFor: 'sending'!
send: inputItems tools: toolSpecs onText: textBlock onItem: itemBlock
	"Run one model response: textBlock gets each output-text delta, itemBlock each completed output item (message, reasoning, function_call, custom_tool_call: the Dictionary as received). Answer the usage Dictionary (input_tokens, output_tokens, total_tokens, ...) or nil. AgentError when signed out, refused, failed, cancelled or cut off."
	| body response |
	cancelled := false.
	body := self bodyFor: inputItems tools: toolSpecs.
	response := self post: body onText: textBlock onItem: itemBlock.
	response status = 401 ifTrue: [
		self account refresh.
		response := self post: body onText: textBlock onItem: itemBlock].
	response isSuccess ifFalse: [^AgentError signal: 'ChatGPT refused the request: ', (OpenAIAccount describe: response)].
	finished ifFalse: [^AgentError signal: 'The response from ChatGPT ended early'].
	^usage
!
cancel
	"From another Process: a pending send ends with AgentError."
	cancelled := true.
	client close
! !

!CodexProvider methodsFor: 'private'!
bodyFor: inputItems tools: toolSpecs
	^Dictionary new
		at: 'model' put: self modelName;
		at: 'stream' put: true;
		at: 'store' put: false;
		at: 'input' put: inputItems asArray;
		at: 'tools' put: toolSpecs asArray;
		at: 'tool_choice' put: 'auto';
		at: 'parallel_tool_calls' put: false;
		at: 'reasoning' put: (Dictionary new at: 'effort' put: effort; yourself);
		at: 'include' put: #('reasoning.encrypted_content');
		yourself
!
headers
	| headers id |
	headers := Dictionary new
		at: 'Accept' put: 'text/event-stream';
		at: 'Authorization' put: 'Bearer ', self account accessToken;
		at: 'originator' put: 'codex_cli_rs';
		at: 'version' put: '1.0.0';
		at: 'session-id' put: sessionId;
		at: 'User-Agent' put: 'codex_cli_rs/1.0.0';
		yourself.
	id := self account accountId.
	id isNil ifFalse: [headers at: 'chatgpt-account-id' put: id].
	^headers
!
post: body onText: textBlock onItem: itemBlock
	| reader diagnostic response |
	finished := false.
	usage := nil.
	diagnostic := self observeRequest: body.
	reader := SSEReader do: [:name :data | self handle: (JSON parse: data) onText: textBlock onItem: itemBlock].
	[
		response := client post: baseURL, '/responses' json: body headers: self headers do: [:text | reader feed: text].
		diagnostic at: 'http_status' put: response status.
		diagnostic at: 'state' put: (finished ifTrue: ['completed'] ifFalse: ['incomplete']).
		usage ifNotNil: [
			diagnostic at: 'input_tokens' put: (usage at: 'input_tokens' ifAbsent: [0]).
			diagnostic at: 'cached_tokens' put: ((usage at: 'input_tokens_details' ifAbsent: [Dictionary new]) at: 'cached_tokens' ifAbsent: [0])].
		^response
	] on: Error do: [:e |
		diagnostic at: 'state' put: 'error'.
		diagnostic at: 'error_class' put: e class name.
		(e isKindOf: HTTPError) ifTrue: [
			AgentError signal: (cancelled ifTrue: ['Cancelled'] ifFalse: ['Lost the connection to ChatGPT: ', e messageText])].
		e pass]
!
handle: event onText: textBlock onItem: itemBlock
	| type response |
	type := event at: 'type' ifAbsent: [nil].
	type = 'response.output_text.delta' ifTrue: [^textBlock value: (event at: 'delta')].
	type = 'response.output_item.done' ifTrue: [^itemBlock value: (event at: 'item')].
	response := event at: 'response' ifAbsent: [nil].
	type = 'response.completed' ifTrue: [
		finished := true.
		^usage := response at: 'usage' ifAbsent: [nil]].
	type = 'response.failed' ifTrue: [
		^AgentError signal: 'ChatGPT failed: ', (self messageIn: (response at: 'error' ifAbsent: [nil]))].
	type = 'response.incomplete' ifTrue: [
		^AgentError signal: 'ChatGPT stopped: ', (((response at: 'incomplete_details' ifAbsent: [nil]) ifNil: [Dictionary new]) at: 'reason' ifAbsent: ['incomplete'])].
	type = 'error' ifTrue: [
		^AgentError signal: 'ChatGPT: ', (self messageIn: ((event includesKey: 'message') ifTrue: [event] ifFalse: [event at: 'error' ifAbsent: [nil]]))]
!
messageIn: anErrorDictionary
	(anErrorDictionary isKindOf: Dictionary) ifFalse: [^'unknown error'].
	^(anErrorDictionary at: 'message' ifAbsent: [nil]) ifNil: [(anErrorDictionary at: 'code' ifAbsent: [nil]) ifNil: ['unknown error']]
! !

!CodexProvider class methodsFor: 'private'!
newSessionId
	"A random (version 4) UUID."
	| random hex |
	random := Random seed: Time utcMicroseconds.
	hex := String new: 32 streamContents: [:s |
		32 timesRepeat: [s nextPut: (Character digitValue: (random nextInt: 16) - 1) asLowercase]].
	^(hex copyFrom: 1 to: 8), '-', (hex copyFrom: 9 to: 12), '-4', (hex copyFrom: 14 to: 16), '-',
		(String with: ('89ab' at: (random nextInt: 4))), (hex copyFrom: 18 to: 20), '-', (hex copyFrom: 21 to: 32)
! !

!CodexProvider methodsFor: 'diagnostics'!
requestDiagnostics
	"Recent request summaries; no credentials or prompt text."
	^requestDiagnostics ifNil: [#()] ifNotNil: [requestDiagnostics asArray]
!
observeRequest: body
	"Compare serialized input items and settings with the preceding attempt."
	| current settings inputs oldInputs common entry |
	requestDiagnostics ifNil: [requestDiagnostics := OrderedCollection new].
	inputs := (body at: 'input') collect: [:each | JSON render: each].
	settings := body copy.
	settings removeKey: 'input'.
	current := Array with: (JSON render: settings) with: inputs.
	common := 0.
	previousRequestJSON ifNotNil: [
		oldInputs := previousRequestJSON second.
		[common < (oldInputs size min: inputs size)
			and: [(oldInputs at: common + 1) = (inputs at: common + 1)]]
			whileTrue: [common := common + 1]].
	entry := Dictionary new
		at: 'prompt_cache_key' put: (body at: 'prompt_cache_key' ifAbsent: [nil]);
		at: 'input_items' put: inputs size;
		at: 'matching_prefix_items' put: common;
		at: 'previous_input_items' put: (previousRequestJSON ifNil: [0] ifNotNil: [previousRequestJSON second size]);
		at: 'previous_input_is_prefix' put: (previousRequestJSON notNil and: [common = previousRequestJSON second size]);
		at: 'settings_unchanged' put: (previousRequestJSON notNil and: [current first = previousRequestJSON first]);
		at: 'state' put: 'sending';
		yourself.
	previousRequestJSON := current.
	requestDiagnostics add: entry.
	[requestDiagnostics size > 100] whileTrue: [requestDiagnostics removeFirst].
	^entry
! !
