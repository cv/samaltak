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
! !

!AgentInputEditor methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| label font badge |
	super drawSelfOn: aCanvas.
	self images isEmpty ifTrue: [^self].
	label := self images size printString, (self images size = 1
		ifTrue: [' image attached']
		ifFalse: [' images attached']).
	font := self theme font: #small.
	badge := ((self width - (font widthOf: label) - 16 max: 0) @ (self height - 24 max: 0))
		corner: self width @ self height.
	aCanvas fillRect: badge color: self theme paper.
	aCanvas drawString: label in: badge font: font color: self theme ink align: #center
! !
