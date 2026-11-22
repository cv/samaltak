Object subclass: #AgentTool
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Agent'!

AgentTool comment: 'I am a tool the model can call in an AgentConversation. Subclasses give my name, my Responses-API spec, and run a call: add their AgentItem to the conversation, give it the call''s output: and answer that output. A new tool is a subclass, listed in AgentTool class>>all.'!

!AgentTool methodsFor: 'accessing'!
name
	^self subclassResponsibility
!
spec
	"The tool's entry in the request's tools (a Dictionary)."
	^self subclassResponsibility
! !

!AgentTool methodsFor: 'running'!
run: aCallDictionary in: anAgentConversation
	"Run the tool call, add my item for it to anAgentConversation and answer the output text sent to the model."
	^self subclassResponsibility
! !

!AgentTool class methodsFor: 'instances'!
all
	"A fresh instance of every tool (a conversation owns its tools)."
	^Array with: CodeModeTool new with: ShowObjectTool new with: RunTestsTool new
! !
