!VMSimulator methodsFor: '*Tools-Agent'!
agentContext
	"The simulated VM's output and the selected text."
	^super agentContext
		bind: #output to: output text;
		selection: (output hasSelection ifTrue: [output selectedText]);
		yourself
! !
