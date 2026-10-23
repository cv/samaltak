Object subclass: #Surface
	instanceVariableNames: 'width height scale device texture'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

Surface comment: 'I am an offscreen render target: an RGBA8 GPU texture of width × height device pixels holding premultiplied pixels, for scale device pixels per point. Renderers draw into me; Canvas>>image:in: draws me (layers, compositing); readback answers my pixels as a Form.'!

!Surface methodsFor: 'initialization'!
setWidth: w height: h scale: aNumber device: aDevice
	width := w.
	height := h.
	scale := aNumber.
	device := aDevice.
	texture := aDevice textureWidth: w height: h format: #rgba8 usage: #(#sampler #colorTarget)
! !

!Surface methodsFor: 'accessing'!
width
	^width
!
height
	^height
!
pixelExtent
	^width @ height
!
extent
	"Size in points."
	^(width / scale) @ (height / scale)
!
scale
	^scale
!
texture
	^texture
!
device
	^device
! !

!Surface methodsFor: 'rendering'!
textureOn: aDevice
	^texture
!
isLinearFiltered
	^true
!
render: aDisplayList clear: aColorOrNil
	Renderer default render: aDisplayList on: self clear: aColorOrNil
! !

!Surface methodsFor: 'reading back'!
readback
	"Answer my pixels as a Form (waits for submitted GPU work)."
	| form |
	form := Form width: width height: height.
	texture downloadInto: form bits.
	^form
!
readbackBytes
	^texture download
!
readbackBytesInto: aByteArray
	"Read my pixels (RGBA8) back into aByteArray (width * height * 4 bytes) and answer it: no allocation, for readbacks every frame."
	texture downloadInto: aByteArray.
	^aByteArray
! !

!Surface methodsFor: 'releasing'!
release
	texture release
! !

!Surface class methodsFor: 'instance creation'!
width: w height: h
	^self width: w height: h scale: Font deviceScale
!
width: w height: h scale: aNumber
	^self new setWidth: w height: h scale: aNumber device: GPUDevice default
!
extent: aPoint scale: aNumber
	"A surface of aPoint points."
	^self width: (aPoint x * aNumber) ceiling height: (aPoint y * aNumber) ceiling scale: aNumber
! !
