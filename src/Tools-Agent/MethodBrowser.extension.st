!MethodBrowser methodsFor: '*Tools-Agent'!
agentContext
	"The listed methods, the selected one and the selected text."
	^super agentContext
		bind: #methods to: list items;
		bind: #method to: list selection;
		selection: (code hasSelection ifTrue: [code selectedText]);
		yourself
! !
