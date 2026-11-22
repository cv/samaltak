Object subclass: #AnthropicProvider
	instanceVariableNames: 'account client cancelled wake finished rawUsage stopReason blocks messageId emitted streamError customTools retries retryDelay caching imageSources'
	classVariableNames: ''
	package: 'System-Agent'!

AnthropicProvider comment: 'I send a conversation to a model behind the Anthropic Messages API (POST baseURL, ''/v1/messages'', streamed), with an ApiKeyAccount''s base URL, model, thinking effort, max_tokens and key: the sibling of CodexProvider, with the same protocol toward AgentConversation.

	provider := AnthropicProvider new account: anApiKeyAccount; yourself.
	provider send: inputItems tools: toolSpecs onText: [:delta | ...] onItem: [:item | ...]   "answers the usage"
	provider cancel   "from another Process"

The conversation speaks the Responses API''s items; I translate. The developer message becomes the system prompt; user messages, assistant text, reasoning items (thinking blocks, echoed back verbatim with their signatures), tool calls (tool_use) and their outputs (tool_result, is_error for an output that starts with error: or syntax error:) become alternating user and assistant messages, the blocks of one response in one assistant message. A custom tool (code-mode) is a tool whose input_schema has one string, input; a function tool keeps its parameters. Thinking is adaptive with the account''s effort (output_config, summarized thinking text), or left to the model when the account has none (models with adaptive thinking refuse thinking disabled); one tool call per response (disable_parallel_tool_use), as CodexProvider asks. With caching (the default) the system prompt and the last block of the last message carry cache_control, so each request reads the previous one''s prefix from the cache.

From the stream (message_start, content_block_start/delta/stop, message_delta, message_stop, ping, error) itemBlock gets, at each block''s end: a message item for text (textBlock got its deltas), a reasoning item for thinking or redacted_thinking, a custom_tool_call or function_call for tool_use; each keeps its Anthropic block under ''anthropic'' and the message id under ''response''. The usage answered is the Responses API''s: input_tokens (cache reads and writes included), output_tokens, total_tokens, input_tokens_details cached_tokens.

AgentError when the account has no key; for an HTTP error (with the body''s message), an error event, a cut-off stream, a response stopped by max_tokens, a refusal or the context window; and ''Cancelled'' after cancel. An HTTP 400 or 413 that says an image or the request is too large is an AgentImageRefused naming the input_image parts of the image blocks it names (messages.N.content.M), else all of them. HTTP 408, 409, 429 and 5xx (529 overloaded) and overloaded, rate-limit and api error events that come before any output are retried, at most retries times, after retry-after or retryDelay ms doubling each time; cancel ends the wait. My connection is kept between sends.'!

!AnthropicProvider methodsFor: 'initialization'!
initialize
	client := HTTPClient new.
	retries := 4.
	retryDelay := 1000.
	caching := true.
	cancelled := false
! !

!AnthropicProvider methodsFor: 'accessing'!
account
	^account ifNil: [account := ApiKeyAccount default]
!
account: anApiKeyAccount
	account := anApiKeyAccount
!
modelName
	^self account model ifNil: ['no model']
!
retries: anInteger
	"How often a refused or overloaded request is tried again."
	retries := anInteger
!
retryDelay: milliseconds
	"The wait before the first retry (doubled for each next one) when the server does not say (retry-after)."
	retryDelay := milliseconds
!
caching: aBoolean
	"Whether requests mark cache breakpoints (cache_control)."
	caching := aBoolean
! !

!AnthropicProvider methodsFor: 'sending'!
send: inputItems tools: toolSpecs onText: textBlock onItem: itemBlock
	"Run one model response: textBlock gets each text delta, itemBlock each completed output item (see my comment). Answer the usage Dictionary or nil. AgentError when it fails."
	| body headers response attempt |
	cancelled := false.
	wake := Semaphore new.
	customTools := (toolSpecs select: [:each | (each at: 'type' ifAbsent: [nil]) = 'custom']) collect: [:each | each at: 'name'].
	body := self bodyFor: inputItems tools: toolSpecs.
	headers := self headers.
	attempt := 0.
	[response := self post: body headers: headers onText: textBlock onItem: itemBlock.
	 (self shouldRetry: response) and: [attempt < retries]] whileTrue: [
		attempt := attempt + 1.
		self pause: (self delayBefore: attempt after: response)].
	response == #retry ifTrue: [^AgentError signal: self serviceName, ': ', (self messageIn: streamError)].
	response isSuccess ifFalse: [^self refuse: response body: body].
	finished ifFalse: [^AgentError signal: 'The response from ', self serviceName, ' ended early'].
	stopReason = 'max_tokens' ifTrue: [^AgentError signal: 'The model stopped at max_tokens (', self account maxTokens printString, ') before it finished'].
	stopReason = 'refusal' ifTrue: [^AgentError signal: 'The model declined to answer'].
	stopReason = 'model_context_window_exceeded' ifTrue: [^AgentError signal: 'The conversation no longer fits the model''s context window'].
	^self usage
!
cancel
	"From another Process: a pending send ends with AgentError ''Cancelled''."
	cancelled := true.
	wake isNil ifFalse: [wake signal].
	client close
! !

!AnthropicProvider methodsFor: 'request'!
bodyFor: inputItems tools: toolSpecs
	"The Messages request for the Responses-API inputItems and toolSpecs."
	| system body |
	imageSources := IdentityDictionary new.
	body := Dictionary new
		at: 'model' put: self account model;
		at: 'max_tokens' put: self account maxTokens;
		at: 'stream' put: true;
		at: 'messages' put: (self messagesFor: inputItems);
		yourself.
	system := self systemIn: inputItems.
	system isEmpty ifFalse: [
		body at: 'system' put: (Array with: (self cached: (Dictionary new at: 'type' put: 'text'; at: 'text' put: system; yourself)))].
	toolSpecs isEmpty ifFalse: [
		body at: 'tools' put: (toolSpecs collect: [:each | self toolFor: each]) asArray.
		body at: 'tool_choice' put: (Dictionary new at: 'type' put: 'auto'; at: 'disable_parallel_tool_use' put: true; yourself)].
	self account thinking isNil ifFalse: [
			body at: 'thinking' put: (Dictionary new at: 'type' put: 'adaptive'; at: 'display' put: 'summarized'; yourself).
			body at: 'output_config' put: (Dictionary new at: 'effort' put: self account thinking; yourself)].
	^body
!
headers
	^Dictionary new
		at: 'x-api-key' put: self account apiKey;
		at: 'anthropic-version' put: '2023-06-01';
		at: 'Accept' put: 'text/event-stream';
		yourself
!
systemIn: inputItems
	"The text of the developer and system messages."
	^String new: 1000 streamContents: [:s |
		inputItems do: [:item |
			((item at: 'type' ifAbsent: [nil]) = 'message' and: [#('developer' 'system') includes: (item at: 'role' ifAbsent: [nil])]) ifTrue: [
				(item at: 'content' ifAbsent: [#()]) do: [:part |
					(part at: 'text' ifAbsent: [nil]) ifNotNil: [:text |
						s position > 0 ifTrue: [s nextPutAll: String lf; nextPutAll: String lf].
						s nextPutAll: text]]]]]
!
messagesFor: inputItems
	"Alternating user and assistant messages; each entry is {role. blocks. response id} while they are built."
	| messages last |
	messages := OrderedCollection new.
	inputItems do: [:item | self add: item to: messages].
	(caching and: [messages notEmpty]) ifTrue: [
		last := (messages last at: 2).
		(self isThinking: last last) ifFalse: [
			last at: last size put: (self cached: last last copy)]].
	^(messages collect: [:each | | blocks |
		blocks := each at: 2.
		each first = 'assistant' ifTrue: [
			"a streamed message joins the conversation before the reasoning that preceded it"
			blocks := (blocks select: [:block | self isThinking: block]), (blocks reject: [:block | self isThinking: block])].
		Dictionary new at: 'role' put: each first; at: 'content' put: blocks asArray; yourself]) asArray
!
add: anItem to: messages
	| type role |
	type := anItem at: 'type' ifAbsent: [nil].
	type = 'message' ifTrue: [
		role := anItem at: 'role' ifAbsent: ['user'].
		role = 'assistant' ifTrue: [^self addAssistant: (self textBlocksOf: anItem) of: anItem to: messages].
		role = 'user' ifTrue: [^self addUser: (self userBlocksOf: anItem) to: messages].
		^self].
	type = 'reasoning' ifTrue: [
		^(anItem at: 'anthropic' ifAbsent: [nil]) ifNotNil: [:block | self addAssistant: (Array with: block) of: anItem to: messages]].
	(AgentItem isCall: anItem) ifTrue: [^self addAssistant: (Array with: (self toolUseOf: anItem)) of: anItem to: messages].
	(type isString and: [type endsWith: '_output']) ifTrue: [^self addUser: (Array with: (self toolResultOf: anItem)) to: messages]
!
addAssistant: blockArray of: anItem to: messages
	"Blocks of one response go to one assistant message, also a call after the result of an earlier call of that response."
	| id last previous |
	blockArray isEmpty ifTrue: [^self].
	id := anItem at: 'response' ifAbsent: [nil].
	last := messages isEmpty ifFalse: [messages last].
	(last notNil and: [last first = 'assistant' and: [(last at: 3) = id]]) ifTrue: [^(last at: 2) addAll: blockArray].
	previous := messages size >= 2 ifTrue: [messages at: messages size - 1].
	(id notNil and: [previous notNil and: [last first = 'user' and: [previous first = 'assistant' and: [(previous at: 3) = id
		and: [(last at: 2) allSatisfy: [:each | (each at: 'type') = 'tool_result']]]]]])
			ifTrue: [^(previous at: 2) addAll: blockArray].
	messages add: (Array with: 'assistant' with: blockArray asOrderedCollection with: id)
!
addUser: blockArray to: messages
	blockArray isEmpty ifTrue: [^self].
	(messages notEmpty and: [messages last first = 'user']) ifTrue: [^(messages last at: 2) addAll: blockArray].
	messages add: (Array with: 'user' with: blockArray asOrderedCollection with: nil)
!
textBlocksOf: anAssistantMessage
	| text |
	(anAssistantMessage at: 'anthropic' ifAbsent: [nil]) ifNotNil: [:block | ^Array with: block].
	text := AgentItem textOf: anAssistantMessage.
	text isEmpty ifTrue: [^#()].
	^Array with: (self textBlock: text)
!
userBlocksOf: aUserMessage
	"input_text parts as text blocks (empty ones dropped: the API refuses them), input_image parts as image blocks."
	| blocks |
	blocks := OrderedCollection new.
	(aUserMessage at: 'content' ifAbsent: [#()]) do: [:part | | type |
		type := part at: 'type' ifAbsent: [nil].
		(type = 'input_text' and: [(part at: 'text' ifAbsent: ['']) notEmpty]) ifTrue: [blocks add: (self textBlock: (part at: 'text'))].
		type = 'input_image' ifTrue: [ | block |
			block := self imageBlock: (part at: 'image_url' ifAbsent: ['']).
			imageSources ifNotNil: [imageSources at: (block at: 'source') put: part].
			blocks add: block]].
	^blocks asArray
!
textBlock: aString
	^Dictionary new at: 'type' put: 'text'; at: 'text' put: aString; yourself
!
imageBlock: aURL
	"A data: URL (data:image/png;base64,...) as a base64 source, any other URL as a url source."
	| comma header source |
	comma := aURL indexOf: $,.
	header := comma = 0 ifTrue: [''] ifFalse: [aURL copyFrom: 1 to: comma - 1].
	source := ((header beginsWith: 'data:') and: [header endsWith: ';base64'])
		ifTrue: [Dictionary new
			at: 'type' put: 'base64';
			at: 'media_type' put: (header copyFrom: 6 to: header size - 7);
			at: 'data' put: (aURL copyFrom: comma + 1 to: aURL size);
			yourself]
		ifFalse: [Dictionary new at: 'type' put: 'url'; at: 'url' put: aURL; yourself].
	^Dictionary new at: 'type' put: 'image'; at: 'source' put: source; yourself
!
toolUseOf: aCall
	"The tool_use block a call came from, or one made from the call."
	| input |
	(aCall at: 'anthropic' ifAbsent: [nil]) ifNotNil: [:block | ^block].
	input := (aCall at: 'type') = 'custom_tool_call'
		ifTrue: [Dictionary new at: 'input' put: (aCall at: 'input' ifAbsent: ['']); yourself]
		ifFalse: [[JSON parse: (aCall at: 'arguments' ifAbsent: ['{}'])] on: Error do: [:e | e return: Dictionary new]].
	^Dictionary new
		at: 'type' put: 'tool_use';
		at: 'id' put: (aCall at: 'call_id');
		at: 'name' put: (aCall at: 'name');
		at: 'input' put: input;
		yourself
!
toolResultOf: anOutput
	| output block |
	output := (anOutput at: 'output' ifAbsent: ['']) asString.
	block := Dictionary new
		at: 'type' put: 'tool_result';
		at: 'tool_use_id' put: (anOutput at: 'call_id');
		at: 'content' put: (output isEmpty ifTrue: ['(no output)'] ifFalse: [output]);
		yourself.
	((output beginsWith: 'error:') or: [output beginsWith: 'syntax error:']) ifTrue: [block at: 'is_error' put: true].
	^block
!
toolFor: aSpec
	"A tool of the Messages API for a Responses-API tool spec."
	| schema |
	schema := (aSpec at: 'type' ifAbsent: [nil]) = 'custom'
		ifTrue: [Dictionary new
			at: 'type' put: 'object';
			at: 'properties' put: (Dictionary new
				at: 'input' put: (Dictionary new at: 'type' put: 'string'; at: 'description' put: 'The tool''s input, as raw text.'; yourself);
				yourself);
			at: 'required' put: #('input');
			yourself]
		ifFalse: [aSpec at: 'parameters' ifAbsent: [Dictionary new at: 'type' put: 'object'; yourself]].
	^Dictionary new
		at: 'name' put: (aSpec at: 'name');
		at: 'description' put: (aSpec at: 'description' ifAbsent: ['']);
		at: 'input_schema' put: schema;
		yourself
!
isThinking: aBlock
	^#('thinking' 'redacted_thinking') includes: (aBlock at: 'type' ifAbsent: [nil])
!
cached: aBlock
	caching ifTrue: [aBlock at: 'cache_control' put: (Dictionary new at: 'type' put: 'ephemeral'; yourself)].
	^aBlock
! !

!AnthropicProvider methodsFor: 'stream'!
post: body headers: headers onText: textBlock onItem: itemBlock
	"The response, or #retry after an error event worth retrying that came before any output."
	| reader |
	finished := false.
	emitted := false.
	rawUsage := Dictionary new.
	stopReason := nil.
	messageId := nil.
	streamError := nil.
	blocks := Dictionary new.
	reader := SSEReader do: [:name :data | self handle: (JSON parse: data) onText: textBlock onItem: itemBlock].
	^[client post: self account baseURL, '/v1/messages' json: body headers: headers do: [:text | reader feed: text]]
		on: Error do: [:e |
			(e isKindOf: HTTPError) ifTrue: [
				AgentError signal: (cancelled ifTrue: ['Cancelled'] ifFalse: ['Lost the connection to ', self serviceName, ': ', (e messageText ifNil: [e class name])])].
			((e isKindOf: AgentError) and: [streamError notNil and: [emitted not and: [cancelled not and: [self isRetryable: streamError]]]])
				ifTrue: [e return: #retry].
			e pass]
!
handle: event onText: textBlock onItem: itemBlock
	| type block message |
	type := event at: 'type' ifAbsent: [nil].
	type = 'content_block_delta' ifTrue: [
		block := blocks at: (event at: 'index') ifAbsent: [^self].
		^self apply: (event at: 'delta') to: block onText: textBlock].
	type = 'content_block_start' ifTrue: [
		block := (event at: 'content_block') copy.
		block at: ' parts' put: (WriteStream on: (String new: 64)).
		^blocks at: (event at: 'index') put: block].
	type = 'content_block_stop' ifTrue: [
		block := blocks removeKey: (event at: 'index') ifAbsent: [^self].
		^(self itemFor: block) ifNotNil: [:item | emitted := true. itemBlock value: item]].
	type = 'message_start' ifTrue: [
		message := event at: 'message' ifAbsent: [Dictionary new].
		messageId := message at: 'id' ifAbsent: [nil].
		^self addUsage: (message at: 'usage' ifAbsent: [nil])].
	type = 'message_delta' ifTrue: [
		stopReason := (event at: 'delta' ifAbsent: [Dictionary new]) at: 'stop_reason' ifAbsent: [stopReason].
		^self addUsage: (event at: 'usage' ifAbsent: [nil])].
	type = 'message_stop' ifTrue: [^finished := true].
	type = 'error' ifTrue: [
		streamError := event at: 'error' ifAbsent: [event].
		^AgentError signal: self serviceName, ': ', (self messageIn: streamError)]
!
apply: aDelta to: aBlock onText: textBlock
	| type text |
	type := aDelta at: 'type' ifAbsent: [nil].
	type = 'text_delta' ifTrue: [
		text := aDelta at: 'text' ifAbsent: [''].
		(aBlock at: ' parts') nextPutAll: text.
		emitted := true.
		^textBlock value: text].
	type = 'thinking_delta' ifTrue: [^(aBlock at: ' parts') nextPutAll: (aDelta at: 'thinking' ifAbsent: [''])].
	type = 'input_json_delta' ifTrue: [^(aBlock at: ' parts') nextPutAll: (aDelta at: 'partial_json' ifAbsent: [''])].
	type = 'signature_delta' ifTrue: [^aBlock at: 'signature' put: (aBlock at: 'signature' ifAbsent: ['']), (aDelta at: 'signature' ifAbsent: [''])]
!
itemFor: aBlock
	"The Responses-API output item for a finished content block, or nil (an empty text, a kind of block I do not know)."
	| type parts block item input |
	type := aBlock at: 'type' ifAbsent: [nil].
	parts := (aBlock removeKey: ' parts') contents.
	type = 'text' ifTrue: [
		parts isEmpty ifTrue: [^nil].
		block := self textBlock: parts.
		item := Dictionary new at: 'type' put: 'message'; at: 'role' put: 'assistant'; yourself.
		item at: 'content' put: (Array with: (Dictionary new at: 'type' put: 'output_text'; at: 'text' put: parts; yourself))].
	type = 'thinking' ifTrue: [
		block := aBlock.
		block at: 'thinking' put: (block at: 'thinking' ifAbsent: ['']), parts.
		item := Dictionary new
			at: 'type' put: 'reasoning';
			at: 'summary' put: (Array with: (Dictionary new at: 'type' put: 'summary_text'; at: 'text' put: (block at: 'thinking'); yourself));
			yourself].
	type = 'redacted_thinking' ifTrue: [
		block := aBlock.
		item := Dictionary new at: 'type' put: 'reasoning'; at: 'summary' put: #(); yourself].
	type = 'tool_use' ifTrue: [
		input := parts isEmpty ifTrue: [aBlock at: 'input' ifAbsent: [Dictionary new]] ifFalse: [JSON parse: parts].
		block := Dictionary new at: 'type' put: 'tool_use'; at: 'id' put: (aBlock at: 'id'); at: 'name' put: (aBlock at: 'name'); at: 'input' put: input; yourself.
		item := Dictionary new at: 'call_id' put: (aBlock at: 'id'); at: 'name' put: (aBlock at: 'name'); yourself.
		(customTools includes: (aBlock at: 'name'))
			ifTrue: [
				item at: 'type' put: 'custom_tool_call'.
				item at: 'input' put: (((input isKindOf: Dictionary) and: [(input at: 'input' ifAbsent: [nil]) isString])
					ifTrue: [input at: 'input']
					ifFalse: [JSON render: input])]
			ifFalse: [
				item at: 'type' put: 'function_call'.
				item at: 'arguments' put: (JSON render: input)]].
	item isNil ifTrue: [^nil].
	item at: 'anthropic' put: block.
	messageId isNil ifFalse: [item at: 'response' put: messageId].
	^item
!
addUsage: aDictionaryOrNil
	"message_start has the input and cache counts, message_delta the output so far."
	aDictionaryOrNil isNil ifTrue: [^self].
	aDictionaryOrNil keysAndValuesDo: [:key :value | value isNumber ifTrue: [rawUsage at: key put: value]]
!
usage
	"The last response's usage, as the Responses API counts it."
	| read input output |
	rawUsage isEmpty ifTrue: [^nil].
	read := rawUsage at: 'cache_read_input_tokens' ifAbsent: [0].
	input := (rawUsage at: 'input_tokens' ifAbsent: [0]) + read + (rawUsage at: 'cache_creation_input_tokens' ifAbsent: [0]).
	output := rawUsage at: 'output_tokens' ifAbsent: [0].
	^Dictionary new
		at: 'input_tokens' put: input;
		at: 'output_tokens' put: output;
		at: 'total_tokens' put: input + output;
		at: 'input_tokens_details' put: (Dictionary new at: 'cached_tokens' put: read; yourself);
		yourself
! !

!AnthropicProvider methodsFor: 'errors'!
shouldRetry: aResponse
	cancelled ifTrue: [^false].
	aResponse == #retry ifTrue: [^true].
	^(#(408 409 429) includes: aResponse status) or: [aResponse status >= 500]
!
isRetryable: anErrorDictionary
	^(anErrorDictionary isKindOf: Dictionary)
		and: [#('overloaded_error' 'rate_limit_error' 'api_error') includes: (anErrorDictionary at: 'type' ifAbsent: [nil])]
!
delayBefore: attempt after: aResponse
	"Milliseconds: what retry-after says (at most a minute), else retryDelay doubling with each attempt."
	| after seconds |
	after := aResponse == #retry ifFalse: [aResponse headerAt: 'retry-after'].
	after isNil ifFalse: [
		seconds := [after asNumber] on: Error do: [:e | e return: nil].
		seconds isNumber ifTrue: [^((seconds * 1000) rounded min: 60000) max: 0]].
	^retryDelay * (1 bitShift: attempt - 1)
!
pause: milliseconds
	"Wait before a retry; cancel ends the wait with AgentError."
	milliseconds > 0 ifTrue: [wake waitTimeoutMSecs: milliseconds].
	cancelled ifTrue: [AgentError signal: 'Cancelled']
!
refuse: aResponse body: aBody
	"Signal why aResponse is not a stream: AgentImageRefused when an image or the request is too large, else AgentError."
	| text indices block parts |
	text := [aResponse string] on: Error do: [:e | e return: ''].
	(AgentImage isSizeRefusal: text status: aResponse status) ifFalse: [^AgentError signal: (self refusal: aResponse)].
	parts := imageSources values asArray.
	indices := AgentImage indicesIn: text after: 'messages.'.
	indices notNil ifTrue: [
		block := [(((aBody at: 'messages') at: indices first + 1) at: 'content') at: indices last + 1] on: Error do: [:e | e return: nil].
		(block isKindOf: Dictionary) ifTrue: [
			(imageSources at: (block at: 'source' ifAbsent: [nil]) ifAbsent: [nil]) ifNotNil: [:part | parts := Array with: part]]].
	^(AgentImageRefused new parts: parts) signal: (self refusal: aResponse)
!
refusal: aResponse
	"For the user: why aResponse is not a stream."
	| text |
	text := self serviceName, ' refused the request: ', (self describe: aResponse).
	(#(401 403) includes: aResponse status) ifTrue: [
		text := text, '. Set the key again: on the host, run samaltak-ctl agent-config --from-pi'].
	^text
!
describe: aResponse
	"HTTP status: the body's error message."
	| json message |
	json := [aResponse json] on: Error do: [:e | e return: nil].
	(json isKindOf: Dictionary) ifTrue: [message := self messageIn: (json at: 'error' ifAbsent: [json])].
	(message isString and: [message ~= 'unknown error']) ifFalse: [message := aResponse string trimBoth].
	message size > 300 ifTrue: [message := (message copyFrom: 1 to: 300), '...'].
	^'HTTP ', aResponse status printString, (message isEmpty ifTrue: [''] ifFalse: [': ', message])
!
messageIn: anErrorDictionary
	(anErrorDictionary isKindOf: Dictionary) ifFalse: [^'unknown error'].
	^(anErrorDictionary at: 'message' ifAbsent: [nil]) ifNil: [(anErrorDictionary at: 'type' ifAbsent: [nil]) ifNil: ['unknown error']]
!
serviceName
	^self account providerName ifNil: [(self account baseURL ifNil: ['the model''s server'])]
! !
