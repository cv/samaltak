!Object methodsFor: '*System-Agent'!
pngBytes
	"PNG bytes for the agent to see, or nil."
	^nil
!
pngBytesScaledToFit: maxEdge pixels: maxPixels
	"PNG bytes for the agent to see, at most maxEdge pixels on the longer side and maxPixels in area, or nil (Form scales itself down)."
	^self pngBytes
!
isAgentPicture
	"Whether I am a large picture, of which an AgentConversation keeps only the newest (releasePictures); Forms larger than their agentThumbnail are."
	^false
!
agentThumbnail
	"A much smaller stand-in for me (isAgentPicture) that the agent's transcript can show once its conversation no longer keeps me (AgentConversation>>releasePictures)."
	^nil
! !
