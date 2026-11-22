Object subclass: #ScriptedPicture
	instanceVariableNames: 'requests'
	classVariableNames: ''
	package: 'Tests-Agent'!

ScriptedPicture comment: 'I stand in for a Form in AgentImageTest: an incompressible picture. pngBytesScaledToFit:pixels: answers three bytes per pixel allowed, and I record each request (maxEdge -> maxPixels).'!

!ScriptedPicture methodsFor: 'accessing'!
requests
	^requests ifNil: [requests := OrderedCollection new]
!
pngBytesScaledToFit: maxEdge pixels: maxPixels
	self requests add: maxEdge -> maxPixels.
	^ByteArray new: maxPixels * 3
! !
