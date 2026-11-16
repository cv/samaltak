ToolTextEditor subclass: #AgentInputEditor
	instanceVariableNames: 'images'
	classVariableNames: ''
	package: 'Tools-Agent'!

AgentInputEditor comment: 'I am the agent composer. I keep pasted images until the message is sent.'!

!AgentInputEditor methodsFor: 'editing'!
attach: bytes mime: mime
	images ifNil: [images := OrderedCollection new].
	images add: (Dictionary new
		at: 'type' put: 'input_image';
		at: 'image_url' put: 'data:', mime, ';base64,', (Base64 encode: bytes);
		yourself).
	self title: 'ask (', images size printString, ' images)'.
	self invalidate
!
clearImages
	images := nil.
	self title: 'ask'.
	self invalidate
!
paste
	readOnly ifTrue: [^self].
	#('image/png' 'image/jpeg' 'image/gif' 'image/webp') do: [:mime |
		| bytes |
		bytes := GPUPlatform clipboardData: mime.
		(bytes notNil and: [bytes notEmpty]) ifTrue: [
			self attach: bytes mime: mime.
			^self]].
	super paste
! !

!AgentInputEditor methodsFor: 'accessing'!
images
	^images ifNil: [#()]
!
attachmentLabel
	^self images size printString, (self images size = 1
		ifTrue: [' image attached']
		ifFalse: [' images attached']), '  × Remove'
! !

!AgentInputEditor methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| badge |
	super drawSelfOn: aCanvas.
	self images isEmpty ifTrue: [^self].
	badge := self attachmentBounds.
	aCanvas fillRect: badge color: self theme paper.
	aCanvas drawString: self attachmentLabel in: badge
		font: (self theme font: #small) color: self theme ink align: #center
! !

!AgentInputEditor methodsFor: 'geometry'!
attachmentBounds
	| label font |
	label := self attachmentLabel.
	font := self theme font: #small.
	^((self width - (font widthOf: label) - 16 max: 0) @ (self height - 24 max: 0))
		corner: self width @ self height
! !

!AgentInputEditor methodsFor: 'events'!
mouseDown: anEvent
	(anEvent button = 1 and: [self images notEmpty and: [
		self attachmentBounds containsPoint: (self localEventPosition: anEvent)]]) ifTrue: [
			self clearImages.
			^true].
	^super mouseDown: anEvent
! !
