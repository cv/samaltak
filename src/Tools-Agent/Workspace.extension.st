!Workspace methodsFor: '*Tools-Agent'!
agentContext
	"My variables (the same Dictionary: the agent's assignments are mine and mine its), my do-its' receiver and the selected text."
	^super agentContext
		receiver: evaluator receiver;
		bindings: self bindings;
		selection: (editor hasSelection ifTrue: [editor selectedText] ifFalse: [nil]);
		yourself
! !
