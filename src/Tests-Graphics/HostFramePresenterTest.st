GraphicsTestCase subclass: #HostFramePresenterTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

HostFramePresenterTest comment: 'HostFramePresenter showing frames in the window''s SDL surface (windowPresentAddress), as it does where no SDL_GPU device can be made (the Linux appliance under QEMU, docs/linux-appliance.md): a whole frame, damaged rectangles (one clipped by the frame''s edges, one outside it), and the failures: rows shorter than the frame, a window that is closed.'!

!HostFramePresenterTest methodsFor: 'tests'!
testPresentsInTheWindowSurface
	| presenter window address |
	window := GPUPrimitives openWindow: 64 height: 48 title: 'surface fixture' flags: 1.
	address := Machine allocate: 64 * 48 * 4.
	[presenter := HostFramePresenter new.
	 presenter instVarNamed: 'surface' put: true.
	 self assert: presenter usesSurface.
	 presenter presentWindow: window pixels: address width: 64 height: 48.
	 presenter presentWindow: window pixels: address width: 64 height: 48 rects: #(#(0 0 8 8) #(60 40 10 10) #(70 50 4 4)).
	 presenter presentWindow: window pixels: address width: 64 height: 48 rects: #().
	 self assert: (GPUPrimitives primPresentWindow: window address: address width: 64 height: 48 bytesPerRow: 64 x: 0 y: 0 width: 8 height: 8 mode: 3) isNil.
	 GPUPrimitives closeWindow: window.
	 window := nil.
	 self should: [presenter presentWindow: 1000 pixels: address width: 64 height: 48] raise: GPUError]
		ensure: [
			window ifNotNil: [GPUPrimitives closeWindow: window].
			Machine free: address]
! !
