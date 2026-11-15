!Debugger methodsFor: '*Tools-Agent'!
agentContext
	"The selected frame: cells run in it, with its receiver as self and its temporaries as variables."
	^AgentContext new frame: self selectedContext; label: 'Debugger: ', self headerTitle; yourself
! !
