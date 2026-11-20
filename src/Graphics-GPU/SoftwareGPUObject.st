Object subclass: #SoftwareGPUObject
	instanceVariableNames: 'kind device address width height format size command extra owned'
	classVariableNames: ''
	package: 'Graphics-GPU'!

SoftwareGPUObject comment: 'An object of a SoftwareGPU, behind a handle: kind #device, #shader (format: its stage), #pipeline (format: the target''s; extra: the blend), #texture or #swapchain (address, width, height, format; a swapchain texture''s command buffer and window, extra), #sampler (extra: {linear. repeat}), #buffer (address, size), #commandBuffer (extra: the vertex uniforms; size: the µs its work took; owned: its passes and swapchain textures, handle -> object), #fence (size: those µs), or a window''s #claim (device; address, width, height: its back buffer).'!

!SoftwareGPUObject methodsFor: 'accessing'!
kind
	^kind
!
kind: aSymbol
	kind := aSymbol
!
device
	^device
!
device: aHandle
	device := aHandle
!
address
	^address
!
address: anInteger
	address := anInteger
!
width
	^width
!
width: anInteger
	width := anInteger
!
height
	^height
!
height: anInteger
	height := anInteger
!
format
	^format
!
format: anInteger
	format := anInteger
!
size
	^size
!
size: anInteger
	size := anInteger
!
command
	^command
!
command: aHandle
	command := aHandle
!
extra
	^extra
!
extra: anObject
	extra := anObject
!
owned
	^owned
!
owned: aCollection
	owned := aCollection
!
surface
	"For SoftwareRaster: {address. width. height. format}."
	^{address. width. height. format}
! !

!SoftwareGPUObject class methodsFor: 'instance creation'!
kind: aSymbol
	^self new kind: aSymbol
! !
