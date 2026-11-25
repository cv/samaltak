ToolsTestCase subclass: #GpuToolsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-CUDA'!

GpuToolsTest comment: 'Tests the GPU demos (Tools-CUDA) without the GPU (GpuTools forced: false, also where there is one): the World menu''s GPU submenu in Apps (shown where its condition holds), and that each window opens, lays out, names its parts for remote control and says that CUDA is missing. GpuToolsGpuTest runs them on the GPU (make test-nv).'!

!GpuToolsTest methodsFor: 'running'!
setUp
	| condition forced |
	super setUp.
	condition := ToolsMenu conditionOf: #gpu.
	forced := GpuTools forced.
	self addCleanup: [ToolsMenu showGroup: #gpu when: condition. GpuTools forced: forced].
	GpuTools forced: false
! !

!GpuToolsTest methodsFor: 'support'!
labelsOf: aMenu
	^(aMenu allItems select: [:i | i isItem]) collect: [:i | i label]
!
gpuMenu
	| apps gpu |
	apps := (ToolsMenu worldMenuAt: nil) itemLabeled: 'Apps'.
	apps isNil ifTrue: [^nil].
	gpu := apps submenu itemLabeled: 'GPU'.
	^gpu isNil ifTrue: [nil] ifFalse: [gpu submenu]
!
statusOf: aWindow
	^self in: aWindow do: [aWindow content statusBar fullText]
! !

!GpuToolsTest methodsFor: 'tests'!
testGpuSubmenuInApps
	| labels |
	ToolsMenu showGroup: #gpu when: [true].
	self assert: self gpuMenu notNil description: 'no GPU submenu in Apps'.
	labels := self labelsOf: self gpuMenu.
	self assert: labels asArray equals: #('GPU Workspace' 'cuOpt' 'GPU Monitor' 'Spectrum').
	self assert: ((self labelsOf: ((ToolsMenu worldMenuAt: nil) itemLabeled: 'Apps') submenu) includes: 'Mandelbrot').
	#(#gpuWorkspace #cuopt #gpuMonitor #spectrum) do: [:each | self assert: (Tools hasOpener: each)]
!
testGpuSubmenuHiddenWithoutCuda
	ToolsMenu showGroup: #gpu when: [GpuTools isAvailable].
	self assert: self gpuMenu isNil.
	ToolsMenu showGroup: #gpu when: [self error: 'a broken condition hides the group'].
	self assert: self gpuMenu isNil
!
testWorkspaceOpensWithSnippets
	| window ws |
	window := self open: [GpuWorkspace open].
	ws := window content.
	self assert: window title equals: 'GPU Workspace'.
	self assert: (ws text includesSubstring: 'CudaComparison sgemm: 1024').
	self assert: (ws text includesSubstring: 'CuOpt maximize:').
	self assert: (ws text includesSubstring: GpuTools unavailableText).
	self assert: (ws widgetNamed: 'gpu-header') == ws header.
	window close
!
testMonitorLayout
	| window monitor |
	window := self open: [GpuMonitor open].
	monitor := window content.
	self settle.
	#('device' 'values' 'busy-chart' 'allocations' 'calls' 'recent' 'status' 'clear' 'gc') do: [:name |
		self assert: (monitor widgetNamed: name) notNil description: name].
	self assert: (monitor readout cellAt: 'cuda') notNil.
	self assert: ((self statusOf: window) includesSubstring: 'NVIDIA GPU').
	self deny: CudaTrace isOn.
	self assert: (Tools open: #gpuMonitor) == window.
	window close
!
testCuOptWindowLayout
	| window tool |
	window := self open: [CuOptWindow open].
	tool := window content.
	self settle.
	self assert: tool tab equals: #routing.
	self assert: (tool map remoteState includes: 'stops=10').
	self assert: ((self statusOf: window) includesSubstring: 'no cuOpt').
	self in: window do: [tool showTab: #program].
	self assert: tool tab equals: #program.
	self assert: (tool editor text includesSubstring: 'maximize 3 chairs').
	self assert: tool program variables equals: #('chairs' 'tables').
	self assert: tool variablesTable items size equals: 2.
	self assert: tool constraintsTable items size equals: 3.
	self in: window do: [tool editor text: 'maximize 3 x +'. tool solveProgram].
	self assert: ((self statusOf: window) includesSubstring: 'line 1').
	window close
!
testCuOptMapEditsTheRouting
	| window tool map p |
	window := self open: [CuOptWindow open].
	tool := window content.
	self settle.
	map := tool map.
	p := (self in: window do: [map remotePointAt: '1']) rounded.
	self click: p.
	"a click on a stop starts a drag, not a new stop"
	self settle.
	self assert: tool routing stops size equals: 10.
	self click: (self in: window do: [map localToScreen: map plot center + (3 @ 37)]) rounded.
	self assert: (self waitFor: [tool routing stops size = 11]) description: 'the click did not add a stop'.
	self moveTo: p.
	self inject: 2 at: p button: 1 count: 1 modifiers: 1.
	self inject: 3 at: p button: 1 count: 1 modifiers: 1.
	self assert: (self waitFor: [tool routing stops size = 10]) description: 'shift-click did not remove the stop'.
	window close
!
testSpectrumLayout
	| window tool |
	window := self open: [SpectrumWindow open].
	tool := window content.
	self settle.
	self assert: tool pictureImage form width equals: 256.
	self assert: tool spectrumImage form isNil.
	self assert: ((self statusOf: window) includesSubstring: 'no CUDA').
	self assert: (tool pictureImage remoteState includes: 'size=256x256').
	self assert: ((SpectrumWindow picture: #zone size: 32) allSatisfy: [:v | v between: 0 and: 1]).
	self assert: ((SpectrumWindow picture: #letters size: 64) anySatisfy: [:v | v > 0.5]).
	window close
! !
