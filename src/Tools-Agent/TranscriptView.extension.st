!TranscriptView methodsFor: '*Tools-Agent'!
agentContext
	"The Transcript's text and the selected text."
	^super agentContext
		bind: #text to: editor text;
		selection: (editor hasSelection ifTrue: [editor selectedText]);
		yourself
! !
