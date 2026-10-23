GPUResource subclass: #GPUTexture
	instanceVariableNames: 'width height format usage generation'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUTexture comment: 'I am a 2D texture (format #r8, #rgba8 or #bgra8; usage #sampler and/or #colorTarget). Each re-creation of my handle (first use, new session) increments my generation, so whoever keeps CPU-side contents knows when to upload them again. Swapchain textures are transient: they live for one frame and are never re-created.'!

!GPUTexture methodsFor: 'private'!
setDevice: aDevice width: w height: h format: formatSymbol usage: usageSymbols
	self setDevice: aDevice.
	width := w.
	height := h.
	format := formatSymbol.
	usage := usageSymbols.
	generation := 0
!
setTransientHandle: anInteger
	"A texture owned by the platform for this frame (a swapchain image)."
	handle := anInteger.
	session := device session
!
createHandle
	| bits |
	usage isNil ifTrue: [^GPUError new operation: 'swapchain texture'; platformLastError: 'used after its frame'; signal].
	bits := 0.
	(usage includes: #sampler) ifTrue: [bits := bits + 1].
	(usage includes: #colorTarget) ifTrue: [bits := bits + 2].
	^GPUPlatform createTexture: device handle width: width height: height
		format: (GPUDevice textureFormatCode: format) usage: bits
!
handleCreated
	generation := generation + 1
! !

!GPUTexture methodsFor: 'accessing'!
width
	^width
!
height
	^height
!
extent
	^width @ height
!
format
	^format
!
bytesPerPixel
	^GPUDevice bytesPerPixel: format
!
generation
	"Answer a number that changes whenever my contents were lost (new handle). Forces handle creation."
	self handle.
	^generation
! !

!GPUTexture methodsFor: 'transferring'!
upload: bytes
	"Replace all my pixels from bytes (ByteArray or Bitmap, rows top to bottom)."
	self upload: bytes x: 0 y: 0 width: width height: height bytesPerRow: width * self bytesPerPixel
!
upload: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	"Copy a w×h region from bytes (starting at its first byte) to my pixel x@y. Takes effect at the next submit."
	GPUPlatform uploadTexture: self handle bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
!
downloadInto: bytes
	"Read all my pixels back into bytes (a ByteArray or Bitmap of at least width*height*bytesPerPixel bytes). Synchronous; sees only submitted work."
	^self downloadX: 0 y: 0 width: width height: height into: bytes
!
downloadX: x y: y width: w height: h into: bytes
	^GPUPlatform download: self handle x: x y: y width: w height: h into: bytes
!
download
	"Answer all my pixels as a new ByteArray."
	^self downloadInto: (ByteArray new: width * height * self bytesPerPixel)
! !

!GPUTexture methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a GPUTexture('; print: width; nextPut: $x; print: height; space; nextPutAll: format; nextPut: $)
! !
