!VMRebuilder methodsFor: '*Tools-Agent'!
agentContext
	"The build's output and the selected text."
	^super agentContext
		bind: #output to: output text;
		selection: (output hasSelection ifTrue: [output selectedText]);
		yourself
! !
