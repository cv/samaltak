ToolsTestCase subclass: #GpuToolsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-CUDA'!

GpuToolsTest comment: 'Tests the GPU demos (Tools-CUDA) without a GPU: the World menu''s GPU submenu in Apps (shown where its condition holds), and that each window opens, lays out and names its parts for remote control, saying what is missing where there is no CUDA. GpuToolsGpuTest runs them on the GPU.'!

!GpuToolsTest methodsFor: 'running'!
setUp
	| condition |
	super setUp.
	condition := ToolsMenu conditionOf: #gpu.
	self addCleanup: [ToolsMenu showGroup: #gpu when: condition]
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
! !

!GpuToolsTest methodsFor: 'tests'!
testGpuSubmenuInApps
	| labels |
	ToolsMenu showGroup: #gpu when: [true].
	self assert: self gpuMenu notNil description: 'no GPU submenu in Apps'.
	labels := self labelsOf: self gpuMenu.
	self assert: (labels includes: 'GPU Workspace').
	"the Apps items stay before it"
	self assert: ((self labelsOf: ((ToolsMenu worldMenuAt: nil) itemLabeled: 'Apps') submenu) includes: 'Mandelbrot')
!
testGpuSubmenuHiddenWithoutCuda
	ToolsMenu showGroup: #gpu when: [false].
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
	self assert: ws header notNil.
	self assert: (ws widgetNamed: 'gpu-header') == ws header.
	GpuTools isAvailable ifFalse: [self assert: (ws text includesSubstring: GpuTools unavailableText)].
	self assert: (Tools hasOpener: #gpuWorkspace).
	window close
! !
