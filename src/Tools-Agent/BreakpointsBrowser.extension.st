!BreakpointsBrowser methodsFor: '*Tools-Agent'!
agentContext
	"The breakpoints and watchpoints listed as self, the selected one as breakpoint."
	^AgentContext new
		label: self window title;
		receiver: list items;
		bind: #breakpoint to: list selection;
		yourself
! !
