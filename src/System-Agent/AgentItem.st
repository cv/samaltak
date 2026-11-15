Object subclass: #AgentItem
	instanceVariableNames: 'kind text result object objectId failed wire'
	classVariableNames: ''
	package: 'System-Agent'!

AgentItem comment: 'I am one entry of an AgentConversation''s transcript. kind is #user #assistant #reasoning #code #show or #error. text is the message (an assistant''s grows while it streams), a cell''s source or the error; result the output of a tool call as the model sees it; object and objectId a cell''s value or the shown object; failed whether a cell ended in an error.

wire is what I contribute to the next request (Responses-API Dictionaries): a message, a reasoning item, or a tool call followed by its output. It is empty for what the model must not see (a message still streaming, a Stop).'!

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
! !
