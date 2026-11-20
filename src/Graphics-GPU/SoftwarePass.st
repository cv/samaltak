Object subclass: #SoftwarePass
	instanceVariableNames: 'command target targetHandle pipeline buffer bufferHandle offset texture textureHandle state'
	classVariableNames: ''
	package: 'Graphics-GPU'!

SoftwarePass comment: 'A render pass of a SoftwareGPU: its command buffer (a handle), its target, the bound pipeline, vertex buffer (slot 0) and texture (slot 0) with their handles (a released one is not drawn with), and the raster state SoftwareRaster draws with, kept up to date as they are bound (the target, the blend, the scissor, the viewport, the texture and its sampler; the uniforms come from the command buffer at each draw).'!

!SoftwarePass methodsFor: 'initialization'!
setCommand: aHandle target: aTexture handle: anInteger
	command := aHandle.
	target := aTexture.
	targetHandle := anInteger.
	offset := 0.
	state := {aTexture address. aTexture width. aTexture height. aTexture format. 0.
		0. 0. aTexture width. aTexture height.
		0.0. 0.0. aTexture width asFloat. aTexture height asFloat.
		0.0. 0.0. 0.0. 0.0.
		0. 0. 0. 1. false. false}
! !

!SoftwarePass methodsFor: 'accessing'!
kind
	^#pass
!
device
	"Passes end with their command buffer."
	^nil
!
command
	^command
!
target
	^target
!
targetHandle
	^targetHandle
!
pipeline
	^pipeline
!
pipeline: aPipeline
	pipeline := aPipeline.
	state at: 5 put: aPipeline extra
!
buffer
	^buffer
!
bufferHandle
	^bufferHandle
!
offset
	^offset
!
buffer: aBuffer handle: anInteger offset: byteOffset
	buffer := aBuffer.
	bufferHandle := anInteger.
	offset := byteOffset
!
texture
	^texture
!
textureHandle
	^textureHandle
!
texture: aTexture handle: anInteger sampler: linearAndRepeat
	texture := aTexture.
	textureHandle := anInteger.
	state
		at: 18 put: aTexture address;
		at: 19 put: aTexture width;
		at: 20 put: aTexture height;
		at: 21 put: aTexture format;
		at: 22 put: linearAndRepeat first;
		at: 23 put: linearAndRepeat last
!
scissorX: x y: y width: w height: h
	state at: 6 put: x; at: 7 put: y; at: 8 put: w; at: 9 put: h
!
viewportX: x y: y width: w height: h
	state at: 10 put: x asFloat; at: 11 put: y asFloat; at: 12 put: w asFloat; at: 13 put: h asFloat
!
stateWith: uniforms texture: aBoolean
	"The raster state for a draw with the vertex uniforms (four floats), with the bound texture or without."
	state replaceFrom: 14 to: 17 with: uniforms startingAt: 1.
	state at: 18 put: (aBoolean ifTrue: [texture address] ifFalse: [0]).
	^state
! !

!SoftwarePass class methodsFor: 'instance creation'!
command: aHandle target: aTexture handle: anInteger
	^self new setCommand: aHandle target: aTexture handle: anInteger
! !
