GPUResource subclass: #GPUBuffer
	instanceVariableNames: 'size'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUBuffer comment: 'I am a GPU vertex buffer of a fixed byte size. Uploads are queued and run before the next submitted command buffer; two uploads to the same range before a submit leave only the last one visible.'!

!GPUBuffer methodsFor: 'private'!
setDevice: aDevice size: byteSize
	self setDevice: aDevice.
	size := byteSize
!
createHandle
	^GPUPlatform createBuffer: device handle usage: 1 size: size
! !

!GPUBuffer methodsFor: 'accessing'!
size
	^size
! !

!GPUBuffer methodsFor: 'uploading'!
upload: bytes count: byteCount offset: dstOffset
	"Copy the first byteCount bytes of bytes (a ByteArray) to my byte offset dstOffset (0-based)."
	GPUPlatform uploadBuffer: self handle bytes: bytes count: byteCount offset: dstOffset
! !
