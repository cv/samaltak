AgentTool subclass: #CodeModeTool
	instanceVariableNames: 'timeout limit'
	classVariableNames: ''
	package: 'System-Agent'!

CodeModeTool comment: 'I am the code-mode tool: the call''s input is Smalltalk source, run as a do-it against the conversation''s AgentContext with the conversation''s objects bound as o1 … oN. It runs in a fresh Process (''agent code-mode'', the priority of a Workspace do-it); the turn waits for it at most timeout seconds (default 60), then terminates it.

The output is the value''s id and printString, e.g. ''o2 an Array(3 4)''; a printString longer than limit (default 4,000 characters) is cut and ends with ''... [cut: <size> characters in all; the next part: o2 printString copyFrom: 4001 to: 8000]'', except a sequenceable collection''s whose elements can share the limit: the longest elements are cut each to what the shorter ones leave, each ending ''... [cut: <size> characters; o2 at: <index>]''; ''syntax error: <message>''; ''error: <class>: <messageText>'' and the top 10 frames of the signaling stack (an unhandled error, halt or breakpoint ends the cell''s Process, no debugger opens); or ''error: terminated after 60 s''.'!

!CodeModeTool methodsFor: 'initialization'!
initialize
	timeout := 60.
	limit := 4000
! !

!CodeModeTool methodsFor: 'accessing'!
name
	^'code-mode'
!
spec
	^Dictionary new
		at: 'type' put: 'custom';
		at: 'name' put: self name;
		at: 'description' put: 'Run Smalltalk code in the live image. The input is raw Smalltalk source (statements or an expression), not JSON. Answers the id of the resulting object (o1, o2, ...) and its printString; later code can use the id as a variable bound to that object.';
		at: 'format' put: (Dictionary new at: 'type' put: 'text'; yourself);
		yourself
!
timeout
	"Seconds a cell may run."
	^timeout
!
timeout: seconds
	timeout := seconds
!
limit
	"The most characters of a printString the output shows."
	^limit ifNil: [10000]
!
limit: characters
	limit := characters
! !

!CodeModeTool methodsFor: 'running'!
run: aCallDictionary in: anAgentConversation
	| item |
	item := AgentItem call: aCallDictionary kind: #code text: (aCallDictionary at: 'input' ifAbsent: ['']).
	anAgentConversation add: item.
	self evaluate: item in: anAgentConversation.
	anAgentConversation changed.
	^item result
!
evaluate: anAgentItem in: anAgentConversation
	"Run anAgentItem's source in a new Process and wait for it; give anAgentItem its value or error and its output. That Process ends with the wait, also when the waiting Process is terminated, wherever it is."
	| done value text parts error process |
	done := Semaphore new.
	[process := [
		[[[value := anAgentConversation context evaluate: anAgentItem text bindings: anAgentConversation objectBindings.
		   text := self printStringOf: value.
		   text size > limit ifTrue: [parts := self partsOf: value]]
			on: SyntaxError do: [:e | error := 'syntax error: ', e messageText asString. e return: nil]]
			on: UnhandledError do: [:e | error := self describeError: e exception. e return: nil]]
				ensure: [done signal]] newProcess.
	 process priority: Processor userSchedulingPriority; name: 'agent code-mode'.
	 process resume.
	 (done waitTimeoutMSecs: (timeout * 1000) rounded)
		ifTrue: [error := 'error: terminated after ', timeout printString, ' s']]
			ensure: [process isNil ifFalse: [process terminate]].
	(error isNil and: [text isNil]) ifTrue: [error := 'error: terminated'].
	error notNil ifTrue: [
		anAgentItem failed: true.
		^anAgentItem output: error].
	anAgentItem object: value; objectId: (anAgentConversation idFor: value).
	anAgentItem output: (self output: text parts: parts id: anAgentItem objectId)
!
printStringOf: anObject
	^[anObject printString] on: Error do: [:e |
		e return: 'a ', anObject class name, ' (printString failed: ', e messageText asString, ')']
!
describeError: anException
	"error: <class>: <messageText>, then the frames from the signaler down to the cell's DoIt, at most 10, indented."
	| ctx count |
	^String new: 400 streamContents: [:s |
		s nextPutAll: 'error: '; nextPutAll: anException class name; nextPutAll: ': '; nextPutAll: anException messageText asString.
		ctx := anException signalerContext.
		count := 0.
		[ctx notNil and: [count < 10 and: [ctx method ~~ (Compiler >> #evaluate:for:)]]] whileTrue: [
			s nextPut: Character lf; nextPutAll: '  '; nextPutAll: ([ctx printString] on: Error do: [:e | e return: '?']).
			ctx := ctx sender.
			count := count + 1]]
!
output: aString id: anId
	"anId and aString, cut to limit characters with a note saying how to read the rest."
	| max rest |
	max := self limit.
	aString size <= max ifTrue: [^anId, ' ', aString].
	rest := max + 1.
	^String new: max + 200 streamContents: [:s |
		s nextPutAll: anId; space; nextPutAll: (aString copyFrom: 1 to: max);
			nextPutAll: '... [cut: '; print: aString size; nextPutAll: ' characters in all; the next part: ';
			nextPutAll: anId; nextPutAll: ' printString copyFrom: '; print: rest; nextPutAll: ' to: ';
			print: (aString size min: rest + max - 1); nextPut: $]]
!
partsOf: anObject
	"How anObject's printString opens and its elements' printStrings, when it is a sequenceable collection (not a String) with few enough elements to share limit; else nil."
	| open |
	((anObject isKindOf: SequenceableCollection) and: [anObject isString not]) ifFalse: [^nil].
	(anObject isEmpty or: [anObject size > (limit // 150)]) ifTrue: [^nil].
	open := (anObject isMemberOf: Array)
		ifTrue: ['#(']
		ifFalse: [(String streamContents: [:s | anObject printNameOn: s]), '('].
	^Array with: open with: (anObject asArray collect: [:each | self printStringOf: each])
!
capFor: sizes within: budget
	"The largest cap with the sizes, each cut to it, adding up to at most budget; nil when all fit."
	| sorted remaining |
	sorted := sizes asSortedCollection asArray.
	remaining := budget.
	sorted doWithIndex: [:size :i | | even |
		even := remaining // (sorted size - i + 1).
		size <= even ifTrue: [remaining := remaining - size] ifFalse: [^even]].
	^nil
!
output: aString parts: partsOrNil id: anId
	"anId and aString; when aString is too long and partsOrNil (partsOf:) are there, the elements are cut each, the shorter ones kept whole, each cut saying how to read it (oN at: i); else aString is cut as a whole (output:id:)."
	| elements cap text |
	(aString size <= limit or: [partsOrNil isNil]) ifTrue: [^self output: aString id: anId].
	elements := partsOrNil at: 2.
	cap := self capFor: (elements collect: [:each | each size]) within: limit - (partsOrNil at: 1) size - elements size - 1.
	(cap isNil or: [cap < 150]) ifTrue: [^self output: aString id: anId].
	cap := cap - 50.
	text := String new: limit streamContents: [:s |
		s nextPutAll: (partsOrNil at: 1).
		elements doWithIndex: [:each :i |
			i > 1 ifTrue: [s space].
			each size <= cap
				ifTrue: [s nextPutAll: each]
				ifFalse: [s nextPutAll: (each copyFrom: 1 to: cap); nextPutAll: '... [cut: '; print: each size; nextPutAll: ' characters; '; nextPutAll: anId; nextPutAll: ' at: '; print: i; nextPut: $]]].
		s nextPut: $)].
	text size > limit ifTrue: [^self output: aString id: anId].
	^anId, ' ', text
! !
