Object subclass: #AgentItem
	instanceVariableNames: 'kind text result object objectId failed wire original edit key'
	classVariableNames: ''
	package: 'System-Agent'!

AgentItem comment: 'I am one entry of an AgentConversation''s transcript. kind is #user #assistant #reasoning #code #tests #show #error, #note (a working note the agent keeps, key its key, object its text or nil when removed) or #notice (the conversation''s own, e.g. how full the context is). text is the message (an assistant''s grows while it streams), a cell''s source or the error; result the output of a tool call as the model sees it; object and objectId a cell''s value or the shown object; failed whether a cell ended in an error.

wire is what I contribute to the next request (Responses-API Dictionaries): a message, a reasoning item, or a tool call followed by its output. It is empty for what the model must not see (a message still streaming, a Stop).

The agent edits its context by replacing my wire (replaceWire:edit:, AgentConversation elide:reason: and summarize:to:as:): original is the wire before the first edit, edit says what replaced it (''elided'', ''summary of 4–9'', ''summarized'', ''superseded'', ''dropped''). text, result and object stay: the window shows the original, the model the edit.'!

!AgentItem methodsFor: 'initialization'!
initialize
	text := ''.
	failed := false.
	wire := #()
! !

!AgentItem methodsFor: 'accessing'!
kind
	^kind
!
kind: aSymbol
	kind := aSymbol
!
text
	^text
!
text: aString
	text := aString
!
result
	^result
!
object
	^object
!
object: anObject
	object := anObject
!
objectId
	^objectId
!
objectId: aString
	objectId := aString
!
failed
	^failed
!
failed: aBoolean
	failed := aBoolean
!
wire
	^wire
!
wire: anArray
	wire := anArray
! !

!AgentItem methodsFor: 'images'!
mapImages: aBlock
	"Replace each input_image part of my wire's messages (and of my original's) by what aBlock answers for it; answer whether any changed."
	| changed |
	changed := self mapImages: aBlock in: wire.
	(original notNil and: [original ~~ wire]) ifTrue: [self mapImages: aBlock in: original].
	^changed
!
mapImages: aBlock in: aWire
	| changed |
	changed := false.
	aWire do: [:each | | content mapped |
		content := (each isKindOf: Dictionary) ifTrue: [each at: 'content' ifAbsent: [nil]].
		(content isKindOf: Array) ifTrue: [
			mapped := content collect: [:part | (AgentImage isImage: part) ifTrue: [aBlock value: part] ifFalse: [part]].
			(1 to: content size) do: [:i |
				(mapped at: i) == (content at: i) ifFalse: [
					each at: 'content' put: mapped.
					changed := true]]]].
	^changed
! !

!AgentItem methodsFor: 'tool calls'!
call
	"The tool call I stand for, or nil."
	^(wire notEmpty and: [self class isCall: wire first]) ifTrue: [wire first] ifFalse: [nil]
!
isOpen
	"A tool call without its output yet."
	^self call notNil and: [wire size = 1]
!
output: aString
	"Answer my tool call with aString."
	| call |
	call := self call.
	result := aString.
	wire := Array
		with: call
		with: (Dictionary new
			at: 'type' put: (call at: 'type'), '_output';
			at: 'call_id' put: (call at: 'call_id');
			at: 'output' put: aString;
			yourself)
! !

!AgentItem methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an AgentItem('; print: kind; space; nextPutAll: (text printStringLimitedTo: 40); nextPut: $)
! !

!AgentItem class methodsFor: 'instance creation'!
kind: aSymbol text: aString
	^self new kind: aSymbol; text: aString; yourself
!
user: aString
	^(self kind: #user text: aString) wire: (Array with: (self message: 'user' text: aString)); yourself
!
call: aCallDictionary kind: aSymbol text: aString
	"An item for a tool call, open until it gets its output:."
	^(self kind: aSymbol text: aString) wire: (Array with: aCallDictionary); yourself
!
user: aString images: images
	| item message content |
	item := self user: aString.
	images isEmpty ifTrue: [^item].
	message := item wire first.
	content := (message at: 'content') asOrderedCollection.
	content addAll: images.
	message at: 'content' put: content asArray.
	item text: aString, (aString isEmpty ifTrue: [''] ifFalse: [String lf]), (images size = 1 ifTrue: ['[attached image]'] ifFalse: ['[', images size printString, ' attached images]']).
	^item
! !

!AgentItem class methodsFor: 'wire'!
message: aRole text: aString
	"An input message: role developer or user."
	^Dictionary new
		at: 'type' put: 'message';
		at: 'role' put: aRole;
		at: 'content' put: (Array with: (Dictionary new at: 'type' put: 'input_text'; at: 'text' put: aString; yourself));
		yourself
!
isCall: aDictionary
	^#('function_call' 'custom_tool_call') includes: (aDictionary at: 'type' ifAbsent: [nil])
!
textOf: aMessageDictionary
	"The text of an output message: its output_text parts, joined."
	^String new: 100 streamContents: [:s |
		(aMessageDictionary at: 'content' ifAbsent: [#()]) do: [:part |
			(part at: 'type' ifAbsent: [nil]) = 'output_text' ifTrue: [s nextPutAll: (part at: 'text' ifAbsent: [''])]]]
!
assistant: aString
	"An assistant message of the input, as the model wrote it."
	^Dictionary new
		at: 'type' put: 'message';
		at: 'role' put: 'assistant';
		at: 'content' put: (Array with: (Dictionary new at: 'type' put: 'output_text'; at: 'text' put: aString; yourself));
		yourself
! !

!AgentItem methodsFor: 'context'!
original
	"My wire before it was edited."
	^original ifNil: [wire]
!
edit
	"What replaced my wire (a short String), or nil."
	^edit
!
edit: aString
	edit := aString
!
isEdited
	^edit notNil
!
replaceWire: anArray edit: aString
	"Send anArray instead of my wire from now on, keeping the original."
	original isNil ifTrue: [original := wire].
	wire := anArray.
	edit := aString
!
restore
	"Send my original wire again."
	original isNil ifFalse: [wire := original].
	original := nil.
	edit := nil
!
key
	"A note's key."
	^key
!
key: aString
	key := aString
!
tokens
	"An estimate of the tokens my wire takes in a request."
	^self class tokensIn: wire
!
preview
	"One line: the start of my text, and of my result."
	| line |
	line := result isNil ifTrue: [text] ifFalse: [text, ' → ', result].
	line := line collect: [:ch | (ch = Character cr or: [ch = Character lf or: [ch = Character tab]]) ifTrue: [Character space] ifFalse: [ch]].
	^line size > 100 ifTrue: [(line first: 100), '…'] ifFalse: [line]
! !

!AgentItem class methodsFor: 'context'!
tokensIn: aWire
	"An estimate of the tokens aWire's items take: four characters of their JSON a token, an image 1,600."
	| characters images |
	characters := 0.
	images := AgentImage imagesIn: aWire.
	aWire do: [:each | characters := characters + (JSON render: each) size].
	images do: [:each | characters := characters - (each at: 'image_url' ifAbsent: ['']) size].
	^(characters max: 0) // 4 + (images size * 1600)
! !
