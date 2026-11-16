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
		at: 'description' put: 'Show an object in the transcript. Forms are also sent as PNG images to the agent. Capture with World current screenshot, World current screenshot: aRectangle (logical desktop coordinates), or aWindow screenshot. Captures use the last submitted frame; windows include visible occlusion.';
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
	| id item found object bytes image message |
	id := (self idIn: aCallDictionary) ifNil: [''].
	found := true.
	object := anAgentConversation objectAt: id ifAbsent: [found := false].
	found
		ifTrue: [
			item := AgentItem call: aCallDictionary kind: #show text: id.
			item object: object; objectId: id; output: 'shown'.
			bytes := object pngBytes.
			bytes ifNotNil: [
				image := Dictionary new
					at: 'type' put: 'input_image';
					at: 'image_url' put: 'data:image/png;base64,', (Base64 encode: bytes);
					yourself.
				message := AgentItem user: 'Image shown from object ', id images: (Array with: image)]]
		ifFalse: [
			item := AgentItem call: aCallDictionary kind: #error text: 'no object ', id.
			item failed: true; output: 'error: no object ', id].
	anAgentConversation add: item.
	message ifNotNil: [anAgentConversation add: message].
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
