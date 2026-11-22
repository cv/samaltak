AgentError subclass: #AgentImageRefused
	instanceVariableNames: 'parts'
	classVariableNames: ''
	package: 'System-Agent'!

AgentImageRefused comment: 'I am an AgentError for a request the model''s API refused because an image, or the whole request, was too large (HTTP 400 or 413, AgentImage isSizeRefusal:status:). parts are the input_image parts the error names, or every image of the request when it names none: AgentConversation replaces them by placeholders and sends the request once more.'!

!AgentImageRefused methodsFor: 'accessing'!
parts
	^parts ifNil: [#()]
!
parts: aCollection
	parts := aCollection
! !
