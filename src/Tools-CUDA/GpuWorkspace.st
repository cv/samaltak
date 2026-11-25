Workspace subclass: #GpuWorkspace
	instanceVariableNames: 'header'
	classVariableNames: ''
	package: 'Tools-CUDA'!

GpuWorkspace comment: 'I am the GPU Workspace (World menu › Apps › GPU): a Workspace with ready-to-run snippets of NVIDIA''s libraries from Smalltalk (docs/cuda.md): matrix products on cuBLAS, random numbers on cuRAND, solvers on cuSOLVER, transforms on cuFFT, linear programs on cuOpt, and what else this VM binds, each comparison timed on the GPU and in Smalltalk on the CPU (CudaComparison: the times, the speedup, a check of the result). ⌘I on a CudaMatrix shows it in the Inspector: its fields, its first values and a heat map. Above the text, the device and the libraries found.

	GpuWorkspace open'!

!GpuWorkspace methodsFor: 'initialization'!
initialize
	| below |
	super initialize.
	header := PaneHeader title: 'GPU' right: GpuTools summary.
	header name: 'gpu-header'.
	below := self children copy.
	self removeAllChildren.
	self addAll: (Array with: header) , below
!
header
	^header
! !

!GpuWorkspace class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	| ws window |
	ws := self new.
	ws editor text: self snippets.
	window := ws openIn: (Tools placeAt: aPointOrNil extent: 780 @ 600) title: 'GPU Workspace'.
	window do: [
		ws startWatching.
		ws editor focus].
	^window
!
snippets
	"The text: a section a library, those this VM has; without CUDA, why not first."
	^String streamContents: [:s |
		s nextPutAll: '"The GPU from Smalltalk: NVIDIA''s CUDA libraries through generated, checked bindings (docs/cuda.md).
 Put the cursor on a line: ⌘P print it · ⌘I inspect it · ⌘D do it. The GPU Monitor shows the calls they make."
'.
		GpuTools isAvailable ifFalse: [
			s nextPutAll: '
"Not here: '; nextPutAll: GpuTools unavailableText; nextPutAll: '. The snippets need an NVIDIA GPU with CUDA."
'].
		s nextPutAll: self deviceSnippets; nextPutAll: self blasSnippets; nextPutAll: self randSnippets.
		(self has: #CusolverAPI) ifTrue: [s nextPutAll: self solverSnippets].
		(self has: #CufftAPI) ifTrue: [s nextPutAll: self fftSnippets].
		s nextPutAll: self optSnippets; nextPutAll: self cleanupSnippets]
!
deviceSnippets
	^'
Cuda summary
GpuTools libraries
'
!
blasSnippets
	^'
"cuBLAS: a matrix product on the GPU, against the same product as a Smalltalk loop on the CPU (times, speedup, a check)"
CudaComparison sgemm: 1024
CudaComparison sgemm: 4096
CudaComparison gemm: 512 type: #float64

"Matrices live in device memory; ⌘I on a, b or c: their values and a heat map"
a := CudaMatrix uniformRows: 1000 cols: 1000.
b := CudaMatrix uniformRows: 1000 cols: 1000.
c := a * b.
(c at: 1 at: 1) - ((1 to: 1000) inject: 0 into: [:sum :k | sum + ((a at: 1 at: k) * (b at: k at: 1))])
(c rows: 1 to: 3) collect: [:row | row first: 4]
m := CudaMatrix rows: 2 cols: 3 values: #(1 2 3 4 5 6).
(m * (CudaMatrix rows: 3 cols: 2 values: #(1 0 0 1 1 1))) asRows
'
!
randSnippets
	^'
"cuRAND: random numbers made on the device; cuBLAS reduces them there"
CudaComparison uniform: 10000000
r := CudaArray uniform: 1000000 type: #float32.
r norm / 1000000 sqrt    "about 1 / 3 sqrt = 0.577"
CudaComparison norm: 10000000
'
!
has: aClassName
	"Whether the library of the binding class aClassName loads here (or, without CUDA, is bound: its snippets are shown)."
	| c |
	c := Smalltalk at: aClassName ifAbsent: [^false].
	^GpuTools isAvailable not or: [c isAvailable]
!
solverSnippets
	^'
"cuSOLVER: a linear system solved on the GPU (LU), against Gaussian elimination in Smalltalk; factorizations"
CudaComparison solve: 2048
s := CudaMatrix fromRows: #(#(2 1) #(1 3)) type: #float64.
(s solve: (CudaArray withAll: #(3 5) type: #float64)) asArray
s determinant
s inverse asRows
(CudaMatrix uniformRows: 512 cols: 256) singularValues first: 4
'
!
fftSnippets
	^'
"cuFFT: Fourier transforms on the GPU, against a Smalltalk FFT (the Spectrum window shows one)"
CudaComparison fft2d: 2048
(CudaArray withAll: #(1 2 3 4)) fft asArray
f := (CudaMatrix uniformRows: 1024 cols: 1024) fft
'
!
optSnippets
	^'
"cuOpt: linear programs (the cuOpt window edits them, and routes, live)"
CuOpt maximize: #(3 5) subjectTo: #(#(1 0) #(0 2) #(3 2)) atMost: #(4 12 18)
CuOpt minimize: #(2 3) subjectTo: #(#(1 2) #(3 1)) atLeast: #(8 9)
(CuOptRouting example vehicles: 2; solve; yourself) routes
'
!
cleanupSnippets
	^'
"Device memory is freed when an array is collected, or at once:"
{a. b. c. m. r. s. f} do: [:each | each isNil ifFalse: [each release]]
CudaLibraryAPI liveAllocations
CudaBenchmark report    "the numbers of docs/cuda.md, a few seconds"
'
!
initialize
	ToolsMenu register: 'GPU Workspace' description: 'cuBLAS · cuRAND · cuOpt' group: #gpu order: 10 action: [:point | self openAt: point].
	Tools registerOpener: #gpuWorkspace with: [:arg | self open]
! !
