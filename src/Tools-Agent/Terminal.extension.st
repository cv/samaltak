!Terminal methodsFor: '*Tools-Agent'!
agentContext
	"Me as terminal (terminal view send: 'ls', (String with: Character cr) types into my program), the screen's text and the selected text."
	^super agentContext
		bind: #terminal to: self;
		bind: #text to: view screen text;
		selection: (view selection isNil ifFalse: [view selectedText]);
		yourself
! !
