ToolsTestCase subclass: #GpuToolsGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-CUDA'!

GpuToolsGpuTest comment: 'Tests the GPU demos'' windows on the GPU: the GPU Monitor listing an allocation with its CudaMatrix and the product it traced, the Inspector''s heat map of a CudaMatrix, the Spectrum transforming and filtering as the filter is dragged, and the cuOpt window routing a moved stop and solving its program. Needs a GPU (and cuOpt for the cuOpt window), so it does not run by default (runsByDefault): make test-nv runs it.'!

!GpuToolsGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!GpuToolsGpuTest methodsFor: 'running'!
setUp
	| forced |
	super setUp.
	forced := GpuTools forced.
	self addCleanup: [GpuTools forced: forced].
	GpuTools forced: nil.
	GpuTools isAvailable ifFalse: [^self error: 'no CUDA device here']
! !

!GpuToolsGpuTest methodsFor: 'tests'!
testMonitorShowsAllocationsAndCalls
	| window monitor m p |
	window := self open: [GpuMonitor open].
	monitor := window content.
	self assert: CudaTrace isOn.
	m := CudaMatrix uniformRows: 128 cols: 128.
	[p := m * m.
	self assert: (self waitFor: [(monitor allocationList items anySatisfy: [:a | a key = p address])] timeout: 3000).
	self assert: ((self in: window do: [monitor holderOf: p address -> 0]) includesSubstring: 'CudaMatrix float32[128x128]').
	self assert: (self waitFor: [monitor recentList items anySatisfy: [:e | e name = 'cublasSgemm' and: [e deviceMilliseconds notNil]]] timeout: 3000).
	self assert: (monitor callList items anySatisfy: [:c | c first = 'cublasSgemm']).
	self assert: (monitor readout cellAt: 'total') notNil]
		ensure: [m release. p isNil ifFalse: [p release]].
	window close.
	self deny: CudaTrace isOn
!
testInspectorHeatMap
	| m window inspector |
	m := CudaMatrix uniformRows: 300 cols: 200.
	[window := self open: [Tools inspect: m].
	inspector := window content.
	self assert: inspector pixelView notNil.
	self assert: inspector pixelView form width equals: 200.
	self assert: inspector pixelView form height equals: 256.
	self assert: (inspector fieldList items anySatisfy: [:f | f name = 'top left']).
	self assert: ((inspector fieldNamed: 'top left') valueIn: m) size equals: 8.
	window close]
		ensure: [m release]
!
testSpectrumFilters
	| window tool before r |
	window := self open: [SpectrumWindow open].
	tool := window content.
	self settle.
	self assert: tool spectrum notNil.
	self assert: tool spectrumImage form width equals: 256.
	self assert: tool engine equals: #cufft.
	self assert: ((self in: window do: [tool statusBar fullText]) includesSubstring: 'cuFFT 256').
	self in: window do: [tool engine: #cublas].
	self assert: tool spectrum engine equals: #cublas.
	self assert: ((self in: window do: [tool statusBar fullText]) includesSubstring: 'cuBLAS DFT 256').
	self in: window do: [tool engine: #cufft].
	before := tool filteredImage form.
	r := tool spectrumImage.
	self click: (self in: window do: [r remotePointAt: '60']) rounded.
	self assert: (self waitFor: [(tool radius - 60) abs < 3]) description: 'the click did not set the radius'.
	self assert: (self waitFor: [tool filteredImage form ~~ before]).
	self in: window do: [tool size: 128].
	self assert: tool spectrum size equals: 128.
	window close.
	self assert: tool spectrum isNil
!
testCuOptWindowSolves
	| window tool p start |
	GpuTools cuOptAvailable ifFalse: [^self skip: 'no cuOpt here'].
	window := self open: [CuOptWindow open].
	tool := window content.
	self assert: (self waitFor: [tool routing routes notNil] timeout: 10000).
	self assert: tool routing visitsEveryStop.
	self assert: tool routeList items notEmpty.
	p := (self in: window do: [tool map remotePointAt: '1']) rounded.
	start := tool routing stops first.
	self moveTo: p.
	self inject: 2 at: p button: 1 count: 1 modifiers: 0.
	self moveTo: p + (40 @ 30).
	self inject: 3 at: p + (40 @ 30) button: 1 count: 1 modifiers: 0.
	self assert: (self waitFor: [tool routing routes notNil and: [(tool routing stops first dist: start) > 0.01]] timeout: 10000).
	self in: window do: [tool showTab: #program].
	self assert: (self waitFor: [tool lastResult notNil and: [tool lastResult isOptimal]] timeout: 10000).
	self assert: (tool lastResult objective - 36) abs < 1.0e-6.
	self assert: (tool variablesTable items collect: [:v | v at: 2]) equals: #(2.0 6.0).
	window close
! !
