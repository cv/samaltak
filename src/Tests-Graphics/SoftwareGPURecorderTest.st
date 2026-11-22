TestCase subclass: #SoftwareGPURecorderTest
	instanceVariableNames: 'path'
	classVariableNames: ''
	package: 'Tests-Graphics'!

SoftwareGPURecorderTest comment: 'SoftwareGPURecorder records what a Renderer frame gives a SoftwareGPU (as DisplayWindow does: render into a Surface, blit it to the swapchain, submit) and the pixels it produced, in the format its comment states; recordsIn: reads it back. tests/nv replays such records on the CUDA raster kernels.'!

!SoftwareGPURecorderTest methodsFor: 'running'!
setUp
	path := '/tmp/samaltak-nvrec-' , Time utcMicroseconds printString , '.nvrec'
!
tearDown
	File deleteIfExists: path
! !

!SoftwareGPURecorderTest methodsFor: 'tests'!
testRecordsAFrame
	| rec old device canvas renderer surface window swapchain cmd swap records ops draw pass present px |
	rec := SoftwareGPURecorder width: 6 height: 4 path: path.
	old := rec install.
	[device := GPUDevice new.
	canvas := Canvas extent: 6 @ 4 scale: 1.
	canvas fillRect: (1 @ 1 extent: 3 @ 2) color: Color blue.
	renderer := Renderer on: device.
	surface := Surface new setWidth: 6 height: 4 scale: 1 device: device.
	window := HostWindow width: 6 height: 4 title: 'test' flags: 1.
	swapchain := device swapchainFor: window.
	cmd := device commandBuffer.
	renderer render: canvas displayList into: surface texture clear: Color white commandBuffer: cmd.
	swap := cmd acquireSwapchainTexture: swapchain.
	cmd blit: surface texture to: swap.
	cmd submit]
		ensure: [
			GPUPlatform display: old first device: old last.
			rec stop].
	self assert: rec frames equals: 1.
	records := SoftwareGPURecorder recordsIn: (FileStream readOnlyFileNamed: path do: [:s | s binary; upToEnd]).
	ops := records collect: [:r | r first].
	#(1 2 5 6 7 8 9 10 11 12) do: [:op | self assert: (ops includes: op)].
	self assert: (ops indexOf: 8) < (ops indexOf: 10).
	self assert: (ops indexOf: 12) < (ops indexOf: 11).
	draw := records detect: [:r | r first = 8].
	self assert: draw second size equals: 21.
	self assert: (draw second at: 2) equals: 2.
	self assert: (draw second at: 21) equals: 6.
	pass := records detect: [:r | r first = 10].
	self assert: (pass second copyFrom: 2 to: 4) equals: #(6 4 2).
	px := pass third.
	self assert: (px uint32At: 1) equals: 16rFFFFFFFF.
	self deny: (px uint32At: 6 + 1 * 4 + 1) = 16rFFFFFFFF.
	present := records detect: [:r | r first = 11].
	self assert: present second equals: #(1 6 4).
	self assert: present third size equals: 96.
	self assert: ((1 to: 96 by: 4) collect: [:i | present third uint32At: i]) equals: ((1 to: 96 by: 4) collect: [:i | | v |
		v := px uint32At: i.
		(v bitAnd: 16rFF00FF00) + ((v bitAnd: 16rFF) bitShift: 16) + ((v bitShift: -16) bitAnd: 16rFF)])
! !
