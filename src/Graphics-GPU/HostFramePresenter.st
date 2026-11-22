Object subclass: #HostFramePresenter
	instanceVariableNames: 'device frames'
	classVariableNames: ''
	package: 'Graphics-GPU'!

HostFramePresenter comment: 'I show frames that a GPU of the image rendered into memory (BGRA8 rows at an address: an NvComputeGPU''s back buffer, or a SoftwareGPU''s on a host) in the VM''s windows, as FirmwareDisplay shows them on the firmware''s screen: I am such a GPU''s display where the VM has windows (GPUPlatform, --gpu). presentWindow:pixels:width:height: copies the frame into a ByteArray, uploads it into a BGRA8 texture of an SDL_GPU device of my own (GPUPrimitives) and blits that onto the window''s swapchain. The windows and events stay GPUPrimitives'' (GPUPlatform''s display).'!

!HostFramePresenter methodsFor: 'initialization'!
initialize
	frames := Dictionary new
! !

!HostFramePresenter methodsFor: 'windows'!
windowPixelSize: window
	^GPUPrimitives windowPixelSize: window
!
presentWindow: window pixels: address width: w height: h
	| f cmd swap |
	f := self frameFor: window width: w height: h.
	Machine copy: w * h * 4 from: address at: 0 to: (f at: 2) at: 0.
	GPUPrimitives uploadTexture: f first bytes: (f at: 2) x: 0 y: 0 width: w height: h bytesPerRow: w * 4.
	cmd := GPUPrimitives acquireCommandBuffer: device.
	swap := GPUPrimitives acquireSwapchain: cmd window: window.
	swap isNil ifFalse: [
		GPUPrimitives blit: cmd source: f first rect: {0. 0. w. h} destination: swap first rect: {0. 0. swap at: 2. swap at: 3} linear: false].
	GPUPrimitives submit: cmd fence: false
!
windowClosed: window
	"The VM released the window's swapchain; my texture for it goes too."
	(frames removeKey: window ifAbsent: [nil]) ifNotNil: [:f | GPUPrimitives release: f first]
! !

!HostFramePresenter methodsFor: 'private'!
frameFor: window width: w height: h
	"{texture. bytes. width. height} for frames of window of w x h pixels; my device made and the window claimed on first use."
	| f |
	device isNil ifTrue: [device := GPUPrimitives createDevice: false].
	f := frames at: window ifAbsent: [nil].
	(f notNil and: [(f at: 3) = w and: [(f at: 4) = h]]) ifTrue: [^f].
	f isNil
		ifTrue: [GPUPrimitives claim: device window: window]
		ifFalse: [GPUPrimitives release: f first].
	f := {GPUPrimitives createTexture: device width: w height: h format: 3 usage: 1. ByteArray new: w * h * 4. w. h}.
	frames at: window put: f.
	^f
! !
