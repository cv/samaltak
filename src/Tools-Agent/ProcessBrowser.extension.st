!ProcessBrowser methodsFor: '*Tools-Agent'!
agentContext
	"The selected Process as self and its selected frame as context, as objects: the Process may be running, so cells do not run in the frame."
	^super agentContext
		receiver: table selection;
		bind: #context to: stack selection;
		yourself
! !
