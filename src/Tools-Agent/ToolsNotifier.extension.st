!ToolsNotifier methodsFor: '*Tools-Agent'!
agentContext
	"The selected frame, as in the Debugger (cells run in it), with the session and its exception as variables."
	^super agentContext
		frame: (stack selection ifNil: [session interruptedContext]);
		bind: #session to: session;
		bind: #exception to: session exception;
		yourself
! !
