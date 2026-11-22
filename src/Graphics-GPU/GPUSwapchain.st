GPUResource subclass: #GPUSwapchain
	instanceVariableNames: 'window'
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUSwapchain comment: 'I am the swapchain of one HostWindow (the device claims the window on first use). My textures are write-only: render offscreen and blit (see GPUCommandBuffer>>blit:to:). Present at most 60 Hz (vm/platform/README.md).'!

!GPUSwapchain methodsFor: 'private'!
setDevice: aDevice window: aHostWindow
	self setDevice: aDevice.
	window := aHostWindow
!
createHandle
	GPUPlatform claim: device handle window: window handle.
	^window handle
! !

!GPUSwapchain methodsFor: 'accessing'!
window
	^window
!
format
	^GPUDevice textureFormatFromCode: (GPUPlatform swapchainFormat: device handle window: self handle)
!
keepsContents
	"Whether my texture keeps the last frame presented, so that a frame may blit and present only its damage (GPUCommandBuffer>>presentDamage:): a software GPU's back buffer, not SDL_GPU's swapchain."
	^GPUPlatform swapchainKeepsContents: device handle window: self handle
! !

!GPUSwapchain methodsFor: 'releasing'!
release
	"The claim ends when the window closes."
	handle := nil
!
registerForFinalization
	"My handle is my window's; it is not released."
! !
