TestCase subclass: #AnthropicProviderTest
	instanceVariableNames: 'server provider account replies texts items'
	classVariableNames: ''
	package: 'Tests-Agent'!

AnthropicProviderTest comment: 'Tests AnthropicProvider against an HTTPTestServer standing in for an Anthropic Messages endpoint, replaying streams recorded from azure/anthropic/claude-opus-5-5 at inference-api.nvidia.com (trimmed: fewer deltas, short ids, signatures cut, metadata removed), served in small chunks: text, thinking with its signature, a tool_use round trip through an AgentConversation, thinking echoed back verbatim, error events, HTTP errors (bodies recorded), retries after 429 and 529, a cut-off stream, max_tokens, Stop while streaming and while waiting to retry.'!

!AnthropicProviderTest methodsFor: 'running'!
setUp
	replies := OrderedCollection new.
	server := HTTPTestServer on: [:request |
		request path = '/v1/messages'
			ifFalse: [HTTPTestServer response: 404 body: '{}']
			ifTrue: [(replies size > 1 ifTrue: [replies removeFirst] ifFalse: [replies first]) value: request]].
	account := ApiKeyAccount new.
	account providerName: 'test' baseURL: server url model: 'claude-test' thinking: 'high' maxTokens: 1000.
	account apiKey: self key copy.
	provider := AnthropicProvider new account: account; retryDelay: 1; yourself.
	texts := OrderedCollection new.
	items := OrderedCollection new
!
tearDown
	provider cancel.
	server stop.
	account forgetKey
!
reply: blocks
	"Each block answers the response to the next request; the last one answers all further ones."
	replies := blocks asOrderedCollection
!
stream: aString
	"A block answering aString as a chunked event stream, in pieces of 50 bytes (split inside characters too)."
	^[:request | | bytes |
		bytes := aString utf8Encoded.
		HTTPTestServer chunked: 200 pieces: ((1 to: bytes size by: 50) collect: [:i | bytes copyFrom: i to: (i + 49 min: bytes size)])]
!
status: anInteger body: aString
	^[:request | HTTPTestServer response: anInteger body: aString]
!
send
	^self send: {self userMessage: 'What is 7 times 6?'}
!
send: inputItems
	^provider
		send: inputItems
		tools: {self codeModeSpec. self showObjectSpec}
		onText: [:t | texts add: t]
		onItem: [:i | items add: i]
!
userMessage: aString
	^JSON parse: '{"type":"message","role":"user","content":[{"type":"input_text","text":', (JSON quote: aString), '}]}'
!
codeModeSpec
	^CodeModeTool new spec
!
showObjectSpec
	^ShowObjectTool new spec
!
requests
	^(server requests select: [:each | each path = '/v1/messages']) asArray
!
key
	^'sk-test-0123456789abcdef'
! !

!AnthropicProviderTest methodsFor: 'fixtures'!
signature
	^'CAQSmgYKEAgUGAI4AUIIdGhpbmtpbmcSDDphe5Tm53CGDmUOkhoMHxX07NOFdpYsuDtDIjCu6sQl4ukxNYAY'
!
thinkingStream
	"Adaptive thinking (summarized) with its signature, then the answer."
	^'event: message_start
data: {"type":"message_start","message":{"model":"azure/anthropic/claude-opus-5-5","id":"msg_2","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":408,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}   }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"I''m confirming 7"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"×"}          }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"6 is 42."}  }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"', self signature, '"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0 }

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Times 6,"}             }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" that''s 42 — é."}     }

event: content_block_stop
data: {"type":"content_block_stop","index":1   }

event: message_delta
data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": null}, "usage": {"input_tokens": 408, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 62, "output_tokens_details": {"thinking_tokens": 50}}}

event: message_stop
data: {"type":"message_stop"           }

'
!
textStream
	"A short answer without thinking."
	^'event: message_start
data: {"type":"message_start","message":{"id":"msg_5","type":"message","role":"assistant","content":[],"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":400,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Touché: 3 + "}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"4 = 7."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":9}}

event: message_stop
data: {"type":"message_stop"}

'
!
toolStream
	"A code-mode call (tool_use, its input streamed as JSON)."
	^'event: message_start
data: {"type":"message_start","message":{"model":"azure/anthropic/claude-opus-5-5","id":"msg_3","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":4,"cache_creation_input_tokens":585,"cache_read_input_tokens":0,"output_tokens":17}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01Y3yqWQZJiPEszbYhJmwGav","name":"code-mode","input":{},"caller":{"type":"direct"}}       }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}              }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"input"}             }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\": \"100"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":" factor"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ial printStrin"}        }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"g size\"}"}          }

event: content_block_stop
data: {"type":"content_block_stop","index":0               }

event: message_delta
data: {"type": "message_delta", "delta": {"stop_reason": "tool_use", "stop_sequence": null}, "usage": {"input_tokens": 4, "cache_creation_input_tokens": 585, "cache_read_input_tokens": 0, "output_tokens": 53}}

event: message_stop
data: {"type":"message_stop"               }

'
!
resultStream
	"The answer after the code-mode call''s result."
	^'event: message_start
data: {"type":"message_start","message":{"model":"azure/anthropic/claude-opus-5-5","id":"msg_4","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":66,"cache_read_input_tokens":585,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}        }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I ran `"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"100 factorial printString size"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"` in the image: 100!! has 158 digits."}        }

event: content_block_stop
data: {"type":"content_block_stop","index":0      }

event: message_delta
data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": null}, "usage": {"input_tokens": 2, "cache_creation_input_tokens": 66, "cache_read_input_tokens": 585, "output_tokens": 38}}

event: message_stop
data: {"type":"message_stop"         }

'
!
showStream
	"A show-object call: a function tool."
	^'event: message_start
data: {"type":"message_start","message":{"id":"msg_6","type":"message","role":"assistant","content":[],"usage":{"input_tokens":20,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_2","name":"show-object","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"id\": \"o1\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":20}}

event: message_stop
data: {"type":"message_stop"}

'
!
errorStream
	^'event: message_start
data: {"type":"message_start","message":{"id":"msg_7","type":"message","role":"assistant","content":[],"usage":{"input_tokens":20,"output_tokens":1}}}

event: error
data: {"type":"error","error":{"type":"invalid_request_error","message":"messages: text content blocks must be non-empty"}}

'
!
overloadedStream
	^'event: message_start
data: {"type":"message_start","message":{"id":"msg_8","type":"message","role":"assistant","content":[],"usage":{"input_tokens":20,"output_tokens":1}}}

event: ping
data: {"type": "ping"}

event: error
data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}

'
!
truncatedStream
	^'event: message_start
data: {"type":"message_start","message":{"id":"msg_9","type":"message","role":"assistant","content":[],"usage":{"input_tokens":20,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Touché"}}

'
!
maxTokensStream
	^'event: message_start
data: {"type":"message_start","message":{"id":"msg_10","type":"message","role":"assistant","content":[],"usage":{"input_tokens":20,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Touché"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":1000}}

event: message_stop
data: {"type":"message_stop"}

'
!
badRequestBody
	"Recorded (cut): the gateway passes on the model''s refusal of thinking disabled."
	^'{"type":"error","error":{"type":"invalid_request_error","message":"litellm.BadRequestError: thinking.type.disabled is not supported for this model."},"request_id":"a851b51b-0a92-4785-9229-cfa7a13010e5"}'
!
forbiddenBody
	"Recorded: an unknown model."
	^'{"error":{"message":"The requested model ''no/such-model'' is not available for this API key, or the model name is invalid. Check the models available to you and try again.","type":"key_model_access_denied","param":"model","code":"403"}}'
!
overloadedBody
	^'{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
! !

!AnthropicProviderTest methodsFor: 'tests'!
testThinkingAndText
	| usage request body thinking message |
	self reply: {self stream: self thinkingStream}.
	usage := self send.
	self assert: (usage at: 'input_tokens') equals: 408.
	self assert: (usage at: 'output_tokens') equals: 62.
	self assert: (usage at: 'total_tokens') equals: 470.
	self assert: ((usage at: 'input_tokens_details') at: 'cached_tokens') equals: 0.
	self assert: texts asArray equals: {'Times 6,'. ' that''s 42 ', (String with: (Character value: 16r2014)), ' ', (String with: (Character value: 233)), '.'}.
	self assert: (items collect: [:each | each at: 'type']) asArray equals: #('reasoning' 'message').
	thinking := items first at: 'anthropic'.
	self assert: (thinking at: 'type') equals: 'thinking'.
	self assert: (thinking at: 'thinking') equals: 'I''m confirming 7', (String with: (Character value: 16rD7)), '6 is 42.'.
	self assert: (thinking at: 'signature') equals: self signature.
	self assert: (items first at: 'response') equals: 'msg_2'.
	message := items last.
	self assert: (message at: 'role') equals: 'assistant'.
	self assert: (AgentItem textOf: message) equals: (texts inject: '' into: [:a :b | a, b]).
	request := self requests first.
	self assert: request method equals: 'POST'.
	self assert: (request headerAt: 'x-api-key') equals: self key.
	self assert: (request headerAt: 'anthropic-version') equals: '2023-06-01'.
	self assert: (request headerAt: 'accept') equals: 'text/event-stream'.
	self assert: (request headerAt: 'authorization') isNil.
	body := request json.
	self assert: (body at: 'model') equals: 'claude-test'.
	self assert: (body at: 'max_tokens') equals: 1000.
	self assert: (body at: 'stream').
	self assert: (body at: 'thinking') equals: (JSON parse: '{"type":"adaptive","display":"summarized"}').
	self assert: (body at: 'output_config') equals: (JSON parse: '{"effort":"high"}').
	self assert: (body at: 'tool_choice') equals: (JSON parse: '{"type":"auto","disable_parallel_tool_use":true}').
	self assert: (body at: 'messages') equals: (JSON parse: '[{"role":"user","content":[{"type":"text","text":"What is 7 times 6?","cache_control":{"type":"ephemeral"}}]}]').
	self deny: (body includesKey: 'system')
!
testTools
	| tools |
	self reply: {self stream: self textStream}.
	self send.
	tools := self requests first json at: 'tools'.
	self assert: (tools collect: [:each | each at: 'name']) equals: #('code-mode' 'show-object').
	self assert: ((tools first at: 'input_schema') at: 'required') equals: #('input').
	self assert: (((tools first at: 'input_schema') at: 'properties') at: 'input') size equals: 2.
	self assert: (tools first at: 'description') equals: (self codeModeSpec at: 'description').
	self assert: (tools last at: 'input_schema') equals: (self showObjectSpec at: 'parameters')
!
testThinkingOff
	| body |
	account providerName: 'test' baseURL: server url model: 'claude-test' thinking: nil maxTokens: 1000.
	self reply: {self stream: self textStream}.
	self send.
	body := self requests first json.
	self deny: (body includesKey: 'thinking').
	self deny: (body includesKey: 'output_config')
!
testCachedTokens
	| usage |
	self reply: {self stream: self textStream}.
	usage := self send.
	self assert: (usage at: 'input_tokens') equals: 412.
	self assert: ((usage at: 'input_tokens_details') at: 'cached_tokens') equals: 400.
	self assert: (usage at: 'output_tokens') equals: 9
!
testToolUse
	| call |
	self reply: {self stream: self toolStream}.
	self assert: (self send at: 'input_tokens') equals: 589.
	self assert: texts isEmpty.
	self assert: items size equals: 1.
	call := items first.
	self assert: (call at: 'type') equals: 'custom_tool_call'.
	self assert: (call at: 'call_id') equals: 'toolu_01Y3yqWQZJiPEszbYhJmwGav'.
	self assert: (call at: 'name') equals: 'code-mode'.
	self assert: (call at: 'input') equals: '100 factorial printString size'.
	self assert: (call at: 'anthropic') equals: (JSON parse: '{"type":"tool_use","id":"toolu_01Y3yqWQZJiPEszbYhJmwGav","name":"code-mode","input":{"input":"100 factorial printString size"}}')
!
testFunctionToolUse
	self reply: {self stream: self showStream}.
	self send.
	self assert: (items first at: 'type') equals: 'function_call'.
	self assert: (items first at: 'call_id') equals: 'toolu_2'.
	self assert: (JSON parse: (items first at: 'arguments')) equals: (JSON parse: '{"id":"o1"}')
!
testToolRoundTripThroughAConversation
	| conversation first second |
	self reply: {self stream: self toolStream. self stream: self resultStream}.
	conversation := AgentConversation new provider: provider; yourself.
	self assert: (conversation ask: 'How many digits has 100 factorial?'; wait) equals: 'I ran `100 factorial printString size` in the image: 100!! has 158 digits.'.
	self assert: (conversation items collect: [:each | each kind]) asArray equals: #(#user #code #assistant).
	self assert: (conversation items at: 2) result equals: 'o1 158'.
	self assert: self requests size equals: 2.
	first := self requests first json.
	self assert: (first at: 'system') equals: {Dictionary new
		at: 'type' put: 'text';
		at: 'text' put: (AgentInstructions textFor: conversation context);
		at: 'cache_control' put: (Dictionary new at: 'type' put: 'ephemeral'; yourself);
		yourself}.
	self assert: ((first at: 'tools') collect: [:each | each at: 'name']) equals: #('code-mode' 'show-object').
	second := self requests last json.
	self assert: (second at: 'system') equals: (first at: 'system').
	self assert: (second at: 'messages') equals: (JSON parse: '[
		{"role":"user","content":[{"type":"text","text":"How many digits has 100 factorial?"}]},
		{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01Y3yqWQZJiPEszbYhJmwGav","name":"code-mode","input":{"input":"100 factorial printString size"}}]},
		{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01Y3yqWQZJiPEszbYhJmwGav","content":"o1 158","cache_control":{"type":"ephemeral"}}]}]').
	self assert: (conversation usage at: 'input_tokens') equals: 589 + 653
!
testThinkingIsEchoedVerbatim
	| conversation messages assistant |
	self reply: {self stream: self thinkingStream. self stream: self textStream}.
	conversation := AgentConversation new provider: provider; yourself.
	conversation ask: 'And times 6?'; wait.
	self assert: (conversation ask: 'And 3 + 4?'; wait) equals: 'Touché: 3 + 4 = 7.'.
	messages := self requests last json at: 'messages'.
	self assert: (messages collect: [:each | each at: 'role']) equals: #('user' 'assistant' 'user').
	assistant := (messages at: 2) at: 'content'.
	self assert: assistant equals: (JSON parse: '[{"type":"thinking","thinking":"I''m confirming 7×6 is 42.","signature":"', self signature, '"},{"type":"text","text":"Times 6, that''s 42 — é."}]').
	self assert: (messages last at: 'content') equals: (JSON parse: '[{"type":"text","text":"And 3 + 4?","cache_control":{"type":"ephemeral"}}]')
!
testShowObjectResultAndImage
	| messages input |
	input := {self userMessage: 'show it'.
		JSON parse: '{"type":"function_call","call_id":"toolu_2","name":"show-object","arguments":"{\"id\":\"o1\"}"}'.
		JSON parse: '{"type":"function_call_output","call_id":"toolu_2","output":"shown"}'.
		(AgentItem user: 'Image shown from object o1' images: {JSON parse: '{"type":"input_image","image_url":"data:image/png;base64,AQID"}'}) wire first.
		JSON parse: '{"type":"function_call_output","call_id":"x","output":"error: no object o9"}'}.
	messages := (provider caching: false; bodyFor: input tools: #()) at: 'messages'.
	self assert: messages equals: (JSON parse: '[
		{"role":"user","content":[{"type":"text","text":"show it"}]},
		{"role":"assistant","content":[{"type":"tool_use","id":"toolu_2","name":"show-object","input":{"id":"o1"}}]},
		{"role":"user","content":[
			{"type":"tool_result","tool_use_id":"toolu_2","content":"shown"},
			{"type":"text","text":"Image shown from object o1"},
			{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AQID"}},
			{"type":"tool_result","tool_use_id":"x","content":"error: no object o9","is_error":true}]}]')
!
testErrorEvent
	self reply: {self stream: self errorStream}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'text content blocks must be non-empty')].
	self assert: self requests size equals: 1
!
testOverloadedEventIsRetried
	self reply: {self stream: self overloadedStream. self stream: self textStream}.
	self send.
	self assert: self requests size equals: 2.
	self assert: texts asArray equals: {'Touch', (String with: (Character value: 233)), ': 3 + '. '4 = 7.'}
!
testHTTPError
	self reply: {self status: 400 body: self badRequestBody}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'test refused the request: HTTP 400: litellm.BadRequestError: thinking.type.disabled is not supported')].
	self reply: {self status: 403 body: self forbiddenBody}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'HTTP 403: The requested model ''no/such-model'' is not available').
		self assert: (e messageText includesSubstring: 'samaltak-ctl agent-config')].
	self assert: self requests size equals: 2
!
testRetriesAfter429And529
	self reply: {
		[:r | HTTPTestServer response: 429 headers: 'retry-after: 0', String crlf body: '{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}'].
		self status: 529 body: self overloadedBody.
		self stream: self textStream}.
	self assert: (self send at: 'output_tokens') equals: 9.
	self assert: self requests size equals: 3
!
testGivesUpAfterTheRetries
	provider retries: 2.
	self reply: {self status: 529 body: self overloadedBody}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'HTTP 529: Overloaded')].
	self assert: self requests size equals: 3
!
testStreamCutOff
	self reply: {self stream: self truncatedStream}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'ended early')]
!
testMaxTokens
	self reply: {self stream: self maxTokensStream}.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'max_tokens (1000)')]
!
testNoKey
	account signOut.
	self should: [self send] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: 'samaltak-ctl agent-config --from-pi')].
	self assert: self requests isEmpty
!
testKeepsTheConnection
	self reply: {self stream: self textStream}.
	self send.
	self send.
	self assert: server connectionCount equals: 1
!
testCancel
	| outcome |
	self reply: {[:request | | part |
		"the events up to the first text delta, then nothing"
		part := (self textStream copyFrom: 1 to: (self textStream indexOfSubCollection: '4 = 7')) utf8Encoded.
		request socket sendAll: ('HTTP/1.1 200 OK', String crlf, 'Transfer-Encoding: chunked', String crlf, String crlf,
			(part size printString: 16), String crlf) asByteArray, part, String crlf asByteArray.
		nil]}.
	self fork: [outcome := [self send. #completed] on: AgentError do: [:e | e return: e messageText]].
	self assert: (self waitFor: [texts notEmpty]).
	provider cancel.
	self assert: (self waitFor: [outcome notNil]).
	self assert: outcome equals: 'Cancelled'
!
testCancelWhileWaitingToRetry
	| outcome |
	provider retryDelay: 60000.
	self reply: {self status: 529 body: self overloadedBody}.
	self fork: [outcome := [self send. #completed] on: AgentError do: [:e | e return: e messageText]].
	self assert: (self waitFor: [self requests notEmpty]).
	provider cancel.
	self assert: (self waitFor: [outcome notNil]).
	self assert: outcome equals: 'Cancelled'.
	self assert: self requests size equals: 1
! !
