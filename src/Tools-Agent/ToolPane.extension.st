!ToolPane methodsFor: '*Tools-Agent'!
agentContext
	"What ⌘J binds for my Agent window: nothing, labelled with my window's title."
	^AgentContext new label: self window title; yourself
! !
