AgentTool subclass: #ShowObjectTool
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Agent'!

ShowObjectTool comment: 'I am the show-object tool: the call''s arguments are {"id": "o2"}; I add a #show item for that object to the conversation and answer ''shown'', or an #error item and ''error: no object o9''.'!

!ShowObjectTool methodsFor: 'accessing'!
name
	^'show-object'
!
spec
	^Dictionary new
		at: 'type' put: 'function';
		at: 'name' put: self name;
		at: 'description' put: 'Show an object to the user in the transcript.';
		at: 'strict' put: false;
		at: 'parameters' put: (Dictionary new
			at: 'type' put: 'object';
			at: 'properties' put: (Dictionary new
				at: 'id' put: (Dictionary new at: 'type' put: 'string'; at: 'description' put: 'Object id, e.g. o2'; yourself);
				yourself);
			at: 'required' put: #('id');
			at: 'additionalProperties' put: false;
			yourself);
		yourself
! !

!ShowObjectTool methodsFor: 'running'!
run: aCallDictionary in: anAgentConversation
	| id item found object |
	id := (self idIn: aCallDictionary) ifNil: [''].
	found := true.
	object := anAgentConversation objectAt: id ifAbsent: [found := false].
	found
		ifTrue: [
			item := AgentItem call: aCallDictionary kind: #show text: id.
			item object: object; objectId: id; output: 'shown']
		ifFalse: [
			item := AgentItem call: aCallDictionary kind: #error text: 'no object ', id.
			item failed: true; output: 'error: no object ', id].
	anAgentConversation add: item.
	^item result
!
idIn: aCallDictionary
	"The id argument, or nil."
	| arguments |
	arguments := [JSON parse: (aCallDictionary at: 'arguments' ifAbsent: ['{}'])] on: Error do: [:e | e return: nil].
	^(arguments isDictionary and: [(arguments at: 'id' ifAbsent: [nil]) isString])
		ifTrue: [arguments at: 'id']
		ifFalse: [nil]
! !
