!SystemMonitor methodsFor: '*Tools-Agent'!
agentContext
	"The samples (SystemMonitorData) as self."
	^super agentContext receiver: data; yourself
! !
