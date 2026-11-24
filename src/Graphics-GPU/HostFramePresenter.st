Object subclass: #HostFramePresenter
	instanceVariableNames: 'device frames surface'
	classVariableNames: ''
	package: 'Graphics-GPU'!

HostFramePresenter comment: 'I show frames that a GPU of the image rendered into memory (BGRA8 rows at an address: an NvComputeGPU''s back buffer, or a SoftwareGPU''s on a host) in the VM''s windows, as FirmwareDisplay shows them on the firmware''s screen: I am such a GPU''s display where the VM has windows (GPUPlatform, --gpu). presentWindow:pixels:width:height: uploads the frame from its address into a BGRA8 texture of an SDL_GPU device of my own (GPUPrimitives) and blits that onto the window''s swapchain. Where no SDL_GPU device can be made (no Vulkan driver that shows on this display: lavapipe on KMS/DRM, as in the Linux appliance under QEMU, docs/linux-appliance.md), or SAMALTAK_PRESENT=surface asks for it, I copy the frame''s damaged rectangles into the window''s SDL surface instead (windowPresentAddress) and show it. The windows and events stay GPUPrimitives'' (GPUPlatform''s display).'!

!HostFramePresenter methodsFor: 'initialization'!
initialize
	frames := Dictionary new
! !

!HostFramePresenter methodsFor: 'windows'!
windowPixelSize: window
	^GPUPrimitives windowPixelSize: window
!
presentWindow: window pixels: address width: w height: h
	^self presentWindow: window pixels: address width: w height: h rects: nil
!
usesSurface
	"Whether I show frames in the windows' SDL surfaces rather than through an SDL_GPU device: decided on the first frame."
	surface isNil ifTrue: [
		surface := (Smalltalk vm getenv: 'SAMALTAK_PRESENT') = 'surface'
			or: [device isNil and: [[device := GPUPrimitives createDevice: false. false] on: GPUError do: [:e | e return: true]]]].
	^surface
!
presentSurface: window pixels: address width: w height: h rects: scissorsOrNil
	"Copy the rectangles scissorsOrNil ({x. y. width. height}; nil: the whole frame) into window's surface, then show their bounds once (SDL's surface on KMS/DRM is drawn by a renderer: a frame per show)."
	| rects s t x0 y0 x1 y1 |
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	scissorsOrNil isNil ifTrue: [
		GPUPrimitives presentWindow: window address: address width: w height: h x: 0 y: 0 width: w height: h mode: 3.
		^s isNil ifFalse: [s add: #'host.surface' since: t bytes: w * h * 4]].
	rects := scissorsOrNil.
	rects isEmpty ifTrue: [^self].
	x0 := y0 := SmallInteger maxVal.
	x1 := y1 := SmallInteger minVal.
	rects do: [:r |
		GPUPrimitives presentWindow: window address: address width: w height: h
			x: (r at: 1) y: (r at: 2) width: (r at: 3) height: (r at: 4) mode: 1.
		x0 := x0 min: (r at: 1).
		y0 := y0 min: (r at: 2).
		x1 := x1 max: (r at: 1) + (r at: 3).
		y1 := y1 max: (r at: 2) + (r at: 4)].
	GPUPrimitives presentWindow: window address: address width: w height: h x: x0 y: y0 width: x1 - x0 height: y1 - y0 mode: 2.
	s isNil ifFalse: [s add: #'host.surface' since: t bytes: 0]
!
presentWindow: window pixels: address width: w height: h rects: scissorsOrNil
	"Upload the frame (only the rectangles scissorsOrNil, {x. y. width. height}, into the texture that holds the last one) and blit the texture onto the window."
	| f cmd swap s t bytes rects |
	self usesSurface ifTrue: [^self presentSurface: window pixels: address width: w height: h rects: scissorsOrNil].
	s := StageTimes current.
	s isNil ifFalse: [t := Time microsecondClockValue].
	rects := scissorsOrNil.
	f := frames at: window ifAbsent: [nil].
	(f notNil and: [(f at: 3) = w and: [(f at: 4) = h]]) ifFalse: [
		f := self frameFor: window width: w height: h.
		rects := nil].
	rects isNil
		ifTrue: [
			GPUPrimitives uploadTexture: f first bytes: address x: 0 y: 0 width: w height: h bytesPerRow: w * 4.
			bytes := w * h * 4]
		ifFalse: [
			bytes := 0.
			rects do: [:r | | x y rw rh |
				x := (r at: 1) max: 0.
				y := (r at: 2) max: 0.
				rw := ((r at: 1) + (r at: 3) min: w) - x.
				rh := ((r at: 2) + (r at: 4) min: h) - y.
				(rw > 0 and: [rh > 0]) ifTrue: [
					GPUPrimitives uploadTexture: f first bytes: address + ((y * w + x) * 4) x: x y: y width: rw height: rh bytesPerRow: w * 4.
					bytes := bytes + (rw * rh * 4)]]].
	s isNil ifFalse: [t := s add: #'host.upload' since: t bytes: bytes].
	rects isNil ifFalse: [self check: f first pixels: address width: w height: h].
	cmd := GPUPrimitives acquireCommandBuffer: device.
	swap := GPUPrimitives acquireSwapchain: cmd window: window.
	swap isNil ifFalse: [
		GPUPrimitives blit: cmd source: f first rect: {0. 0. w. h} destination: swap first rect: {0. 0. swap at: 2. swap at: 3} linear: false].
	GPUPrimitives submit: cmd fence: false.
	s isNil ifFalse: [s add: #'host.blit' since: t bytes: 0]
!
windowClosed: window
	"The VM released the window's swapchain; my texture for it goes too."
	(frames removeKey: window ifAbsent: [nil]) ifNotNil: [:f | GPUPrimitives release: f first]
! !

!HostFramePresenter methodsFor: 'private'!
check: texture pixels: address width: w height: h
	"While a DamageCheck runs (UI-Windows): the texture that took only the damaged rectangles must hold the whole frame."
	| check frame shown |
	check := (Smalltalk at: #DamageCheck ifAbsent: [nil]) ifNotNil: [:c | c current].
	check isNil ifTrue: [^self].
	frame := ByteArray new: w * h * 4.
	SoftwareRaster copy: frame stride: w * 4 from: address stride: w * 4 width: w height: h bytesPerPixel: 4 mode: 1.
	shown := ByteArray new: w * h * 4.
	GPUPrimitives download: texture x: 0 y: 0 width: w height: h into: shown.
	check notePresent: 'the host texture' same: (frame compareBytes: shown) = 0
!
frameFor: window width: w height: h
	"{texture. nil. width. height} for frames of window of w x h pixels; my device made and the window claimed on first use."
	| f |
	device isNil ifTrue: [device := GPUPrimitives createDevice: false].
	f := frames at: window ifAbsent: [nil].
	(f notNil and: [(f at: 3) = w and: [(f at: 4) = h]]) ifTrue: [^f].
	f isNil
		ifTrue: [GPUPrimitives claim: device window: window]
		ifFalse: [GPUPrimitives release: f first].
	f := {GPUPrimitives createTexture: device width: w height: h format: 3 usage: 1. nil. w. h}.
	frames at: window put: f.
	^f
! !
