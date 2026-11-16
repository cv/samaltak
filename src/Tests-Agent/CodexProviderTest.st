TestCase subclass: #CodexProviderTest
	instanceVariableNames: 'server provider account replies texts items'
	classVariableNames: ''
	package: 'Tests-Agent'!

CodexProviderTest comment: 'Tests CodexProvider against an HTTPTestServer standing in for the backend and the auth server, replaying streams recorded from gpt-6.1-sol (trimmed to the events used, ids and metadata removed), served in small chunks: text deltas, items and usage, error events, HTTP errors, a 401 answered by a refresh and a retry, cancelling.'!

!CodexProviderTest methodsFor: 'running'!
setUp
	replies := Dictionary new.
	server := HTTPTestServer on: [:request | | queue |
		queue := replies at: request path ifAbsent: [nil].
		queue isNil
			ifTrue: [HTTPTestServer response: 404 body: '{}']
			ifFalse: [
				(queue size > 1 ifTrue: [queue removeFirst] ifFalse: [queue first]) value: request]].
	account := OpenAIAccount new issuer: server url.
	account tokens: (Dictionary new
		at: 'id_token' put: self idToken;
		at: 'access_token' put: self accessToken;
		at: 'refresh_token' put: 'r1';
		yourself).
	provider := CodexProvider new baseURL: server url, '/codex'; account: account; yourself.
	texts := OrderedCollection new.
	items := OrderedCollection new
!
tearDown
	provider cancel.
	server stop
!
reply: path with: blocks
	"Each block answers the response to a request."
	replies at: path put: blocks asOrderedCollection
!
stream: aString
	"A block answering aString as a chunked event stream, in pieces of 50 bytes (split inside characters too)."
	^[:request | | bytes |
		bytes := aString utf8Encoded.
		HTTPTestServer chunked: 200 pieces: ((1 to: bytes size by: 50) collect: [:i | bytes copyFrom: i to: (i + 49 min: bytes size)])]
!
send
	^provider
		send: {self userMessage: 'What is 3 + 4?'}
		tools: {self toolSpec}
		onText: [:t | texts add: t]
		onItem: [:i | items add: i]
!
userMessage: aString
	^JSON parse: '{"type":"message","role":"user","content":[{"type":"input_text","text":', (JSON quote: aString), '}]}'
!
toolSpec
	^JSON parse: '{"type":"custom","name":"code-mode","description":"Run Smalltalk code.","format":{"type":"text"}}'
! !

!CodexProviderTest methodsFor: 'fixtures'!
idToken
	"account acct-1"
	^'eyJhbGciOiJub25lIn0.eyJlbWFpbCI6ImFkYUBleGFtcGxlLmNvbSIsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LTEiLCJjaGF0Z3B0X3BsYW5fdHlwZSI6InBybyJ9fQ.x'
!
accessToken
	"exp 2100"
	^'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDAsIm4iOjF9.x'
!
accessToken2
	^'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDAsIm4iOjJ9.x'
!
textStream
	"A final answer."
	^'event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"status":"in_progress","model":"gpt-6.1-sol"}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":2,"output_index":0,"item":{"type":"message","id":"msg_1","role":"assistant","status":"in_progress","content":[],"phase":"final_answer"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":4,"item_id":"msg_1","output_index":0,"content_index":0,"delta":"3"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":5,"item_id":"msg_1","output_index":0,"content_index":0,"delta":" +"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":6,"item_id":"msg_1","output_index":0,"content_index":0,"delta":" 4 = 7"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":7,"item_id":"msg_1","output_index":0,"content_index":0,"delta":" — é."}

event: response.output_text.done
data: {"type":"response.output_text.done","sequence_number":13,"item_id":"msg_1","output_index":0,"content_index":0,"text":"3 + 4 = 7 — é."}

event: response.output_item.done
data: {"type":"response.output_item.done","sequence_number":15,"output_index":0,"item":{"type":"message","id":"msg_1","role":"assistant","status":"completed","content":[{"type":"output_text","text":"3 + 4 = 7 — é.","annotations":[]}],"phase":"final_answer"}}

event: response.completed
data: {"type":"response.completed","sequence_number":16,"response":{"status":"completed","model":"gpt-6.1-sol","usage":{"input_tokens":351,"input_tokens_details":{"cached_tokens":0},"output_tokens":12,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":363}}}

'
!
toolCallStream
	"A code-mode call and a show-object call."
	^'event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"status":"in_progress","model":"gpt-6.1-sol"}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":2,"output_index":0,"item":{"type":"custom_tool_call","id":"ctc_1","call_id":"call_1","name":"code-mode","input":"","status":"in_progress"}}

event: response.custom_tool_call_input.delta
data: {"type":"response.custom_tool_call_input.delta","sequence_number":3,"item_id":"ctc_1","output_index":0,"delta":"3 + 4\n"}

event: response.output_item.done
data: {"type":"response.output_item.done","sequence_number":9,"output_index":0,"item":{"type":"custom_tool_call","id":"ctc_1","call_id":"call_1","name":"code-mode","input":"3 + 4\n","status":"completed"}}

event: response.output_item.done
data: {"type":"response.output_item.done","sequence_number":10,"output_index":1,"item":{"type":"function_call","id":"fc_1","call_id":"call_2","name":"show-object","arguments":"{\"id\":\"o1\"}","status":"completed"}}

event: response.completed
data: {"type":"response.completed","sequence_number":11,"response":{"status":"completed","model":"gpt-6.1-sol","usage":{"input_tokens":289,"output_tokens":16,"total_tokens":305}}}

'
!
errorStream
	^'event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"status":"in_progress"}}

event: error
data: {"type":"error","sequence_number":1,"code":"server_error","message":"The server had an error"}

'
!
failedStream
	^'event: response.failed
data: {"type":"response.failed","sequence_number":1,"response":{"status":"failed","error":{"code":"rate_limit_exceeded","message":"Slow down"}}}

'
!
truncatedStream
	^'event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":4,"delta":"3"}

'
! !

!CodexProviderTest methodsFor: 'tests'!
testDecodesAStream
	| usage request body |
	self reply: '/codex/responses' with: {self stream: self textStream}.
	usage := self send.
	self assert: (usage at: 'input_tokens') equals: 351.
	self assert: (usage at: 'total_tokens') equals: 363.
	self assert: texts asArray equals: {'3'. ' +'. ' 4 = 7'. ' ', (String with: (Character value: 16r2014)), ' ', (String with: (Character value: 233)), '.'}.
	self assert: items size equals: 1.
	self assert: (items first at: 'type') equals: 'message'.
	self assert: (((items first at: 'content') first) at: 'text') equals: (texts inject: '' into: [:a :b | a, b]).
	request := server requests first.
	self assert: request method equals: 'POST'.
	self assert: (request headerAt: 'authorization') equals: 'Bearer ', self accessToken.
	self assert: (request headerAt: 'chatgpt-account-id') equals: 'acct-1'.
	self assert: (request headerAt: 'accept') equals: 'text/event-stream'.
	self assert: (request headerAt: 'originator') equals: 'codex_cli_rs'.
	self assert: (request headerAt: 'version') equals: '1.0.0'.
	self assert: (request headerAt: 'session-id') size equals: 36.
	self assert: (request headerAt: 'accept-encoding') isNil.
	body := request json.
	self assert: (body at: 'model') equals: 'gpt-6.1-sol'.
	self assert: (body at: 'stream').
	self deny: (body at: 'store').
	self assert: (body at: 'input') equals: {self userMessage: 'What is 3 + 4?'}.
	self assert: (body at: 'tools') equals: {self toolSpec}.
	self assert: (body at: 'tool_choice') equals: 'auto'.
	self deny: (body at: 'parallel_tool_calls').
	self assert: ((body at: 'reasoning') at: 'effort') equals: 'low'.
	self assert: (body at: 'include') equals: #('reasoning.encrypted_content')
!
testToolCallItems
	self reply: '/codex/responses' with: {self stream: self toolCallStream}.
	self assert: (self send at: 'output_tokens') equals: 16.
	self assert: texts isEmpty.
	self assert: (items collect: [:i | i at: 'type']) asArray equals: #('custom_tool_call' 'function_call').
	self assert: (items first at: 'input') equals: '3 + 4', String lf.
	self assert: (items first at: 'call_id') equals: 'call_1'.
	self assert: (items last at: 'arguments') equals: '{"id":"o1"}'
!
testKeepsTheConnection
	self reply: '/codex/responses' with: {self stream: self textStream}.
	self send.
	self send.
	self assert: server connectionCount equals: 1
!
testErrorEvent
	self reply: '/codex/responses' with: {self stream: self errorStream}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'The server had an error')].
	self reply: '/codex/responses' with: {self stream: self failedStream}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'Slow down')]
!
testStreamCutOff
	self reply: '/codex/responses' with: {self stream: self truncatedStream}.
	self should: [self send] raise: AgentError
!
testHTTPError
	self reply: '/codex/responses' with: {[:r | HTTPTestServer response: 400 body: '{"detail":"The model is not supported.","error":{"type":"invalid_request_error","code":"x","message":"m"}}']}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: '400: The model is not supported.')]
!
testRefreshAfter401
	| responses |
	self reply: '/codex/responses' with: {
		[:r | HTTPTestServer response: 401 body: '{"detail":"Unauthorized"}'].
		self stream: self textStream}.
	self reply: '/oauth/token' with: {[:r | HTTPTestServer response: 200 body: '{"access_token":"', self accessToken2, '","refresh_token":"r2"}']}.
	self assert: (self send at: 'output_tokens') equals: 12.
	responses := server requests select: [:r | r path = '/codex/responses'].
	self assert: responses size equals: 2.
	self assert: (responses last headerAt: 'authorization') equals: 'Bearer ', self accessToken2.
	self assert: ((server requests detect: [:r | r path = '/oauth/token']) json at: 'refresh_reason') equals: 'unauthorized_recovery'
!
testRefusedRefreshSignsOut
	self reply: '/codex/responses' with: {[:r | HTTPTestServer response: 401 body: '{"detail":"Unauthorized"}']}.
	self reply: '/oauth/token' with: {[:r | HTTPTestServer response: 401 body: '{"error":{"code":"refresh_token_expired"}}']}.
	self should: [self send] raise: AgentError.
	self deny: account isSignedIn.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'Not signed in')]
!
testCancel
	| outcome |
	self reply: '/codex/responses' with: {[:request | | part |
		"the events up to the first delta, then nothing"
		part := self textStream copyFrom: 1 to: (self textStream indexOfSubCollection: '"delta":" +"').
		request socket sendAll: ('HTTP/1.1 200 OK', String crlf, 'Transfer-Encoding: chunked', String crlf, String crlf,
			(part size printString: 16), String crlf, part, String crlf) asByteArray.
		nil]}.
	self fork: [outcome := [self send. #completed] on: AgentError do: [:e | e return: e messageText]].
	self assert: (self waitFor: [texts notEmpty]).
	provider cancel.
	self assert: (self waitFor: [outcome notNil]).
	self assert: outcome equals: 'Cancelled'
!
testStablePromptCacheKey
	| first second other |
	first := provider bodyFor: {self userMessage: 'First'} tools: {self toolSpec}.
	second := provider bodyFor: {self userMessage: 'Next'} tools: {self toolSpec}.
	self assert: (first at: 'prompt_cache_key') equals: (provider headers at: 'session-id').
	self assert: (second at: 'prompt_cache_key') equals: (first at: 'prompt_cache_key').
	other := CodexProvider new bodyFor: #() tools: #().
	self deny: (other at: 'prompt_cache_key') = (first at: 'prompt_cache_key')
! !
