Object subclass: #ScriptedProvider
	instanceVariableNames: 'script requests toolSpecs cancelled'
	classVariableNames: ''
	package: 'Tests-Agent'!

ScriptedProvider comment: 'I am a provider for AgentConversation tests: each send:tools:onText:onItem: replays the next response of my script (text deltas, then completed output items), fails with an AgentError, or blocks until cancel. I keep the input of every request.'!

!ScriptedProvider methodsFor: 'initialization'!
initialize
	script := OrderedCollection new.
	requests := OrderedCollection new
! !

!ScriptedProvider methodsFor: 'scripting'!
reply: deltas items: anArray
	script add: (Array with: deltas with: anArray)
!
reply: anArray
	self reply: #() items: anArray
!
fail: aString
	script add: aString
!
block
	"The next send waits until cancel, then fails."
	script add: #block
! !

!ScriptedProvider methodsFor: 'accessing'!
requests
	^requests
!
toolSpecs
	^toolSpecs
!
modelName
	^'scripted'
! !

!ScriptedProvider methodsFor: 'provider'!
send: inputItems tools: toolSpecArray onText: textBlock onItem: itemBlock
	| step |
	requests add: inputItems.
	toolSpecs := toolSpecArray.
	script isEmpty ifTrue: [^AgentError signal: 'The script has no more responses'].
	step := script removeFirst.
	step == #block ifTrue: [
		cancelled := Semaphore new.
		cancelled wait.
		^AgentError signal: 'Cancelled'].
	step isString ifTrue: [^AgentError signal: step].
	step first do: [:each | textBlock value: each].
	step last do: [:each | itemBlock value: each].
	^Dictionary new at: 'input_tokens' put: 100; at: 'output_tokens' put: 10; at: 'total_tokens' put: 110; yourself
!
cancel
	cancelled ifNotNil: [:semaphore | semaphore signal]
! !

!ScriptedProvider class methodsFor: 'output items'!
code: aString call: anId
	^Dictionary new
		at: 'type' put: 'custom_tool_call';
		at: 'id' put: 'ctc_', anId;
		at: 'call_id' put: anId;
		at: 'name' put: 'code-mode';
		at: 'input' put: aString;
		at: 'status' put: 'completed';
		yourself
!
show: anObjectId call: anId
	^Dictionary new
		at: 'type' put: 'function_call';
		at: 'id' put: 'fc_', anId;
		at: 'call_id' put: anId;
		at: 'name' put: 'show-object';
		at: 'arguments' put: (JSON render: (Dictionary new at: 'id' put: anObjectId; yourself));
		at: 'status' put: 'completed';
		yourself
!
message: aString
	^Dictionary new
		at: 'type' put: 'message';
		at: 'role' put: 'assistant';
		at: 'content' put: (Array with: (Dictionary new at: 'type' put: 'output_text'; at: 'text' put: aString; yourself));
		yourself
! !
