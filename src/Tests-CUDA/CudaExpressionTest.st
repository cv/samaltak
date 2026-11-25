TestCase subclass: #CudaExpressionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaExpressionTest comment: 'Tests CudaExpression without a GPU, on stand-in operands (CudaExpressionTestOperand): shapes broadcasting as numpy''s and refused where they do not, the result types, the kernel signature (one per shape of expression: not the sizes or the numbers), the CUDA C++ written for maps and reductions, and printString. CudaFusionGpuTest runs the kernels.'!

!CudaExpressionTest methodsFor: 'helpers'!
f32: aShape
	^CudaExpression array: (CudaExpressionTestOperand type: #float32 shape: aShape)
!
f64: aShape
	^CudaExpression array: (CudaExpressionTestOperand type: #float64 shape: aShape)
!
op: aSymbol with: anArray
	^CudaExpression op: aSymbol args: anArray
! !

!CudaExpressionTest methodsFor: 'tests'!
testBroadcastShapes
	self assert: (CudaExpression broadcast: #(3 4) with: #(4)) equals: #(3 4).
	self assert: (CudaExpression broadcast: #(4) with: #(3 4)) equals: #(3 4).
	self assert: (CudaExpression broadcast: #(3 4) with: #(3 1)) equals: #(3 4).
	self assert: (CudaExpression broadcast: #(3 1) with: #(1 4)) equals: #(3 4).
	self assert: (CudaExpression broadcast: #(5) with: #()) equals: #(5).
	self assert: (CudaExpression broadcast: #(5) with: #(1)) equals: #(5).
	self should: [CudaExpression broadcast: #(5) with: #(4)] raise: Error.
	self should: [CudaExpression broadcast: #(3 4) with: #(3)] raise: Error.
	self should: [self op: #+ with: {self f32: #(3 4). self f32: #(4 3)}] raise: Error
!
testIndices
	self assert: (CudaExpression indexFor: #(3 4) in: #(3 4)) equals: 'i'.
	self assert: (CudaExpression indexFor: #(4) in: #(3 4)) equals: 'i % cols'.
	self assert: (CudaExpression indexFor: #(1 4) in: #(3 4)) equals: 'i % cols'.
	self assert: (CudaExpression indexFor: #(3 1) in: #(3 4)) equals: 'i / cols'.
	self assert: (CudaExpression indexFor: #(1) in: #(7)) equals: '0'
!
testTypes
	self assert: (self op: #+ with: {self f32: #(4). CudaExpression scalar: 2}) type equals: #float32.
	self assert: (self op: #* with: {self f32: #(4). self f64: #(4)}) type equals: #float64.
	self assert: (self op: #lt with: {self f32: #(4). CudaExpression scalar: 0.5}) type equals: #float32.
	self assert: (self op: #where with: {self f64: #(4). self f32: #(4). CudaExpression scalar: 0}) type equals: #float32.
	self should: [self op: #sqrt with: {self f32: #(4). self f32: #(4)}] raise: Error.
	self should: [self op: #frobnicate with: {self f32: #(4)}] raise: Error
!
testSignatureIsTheShapeOfTheExpression
	"Sizes and numbers are arguments: a * 2 + b of any length shares a kernel with a * 3 + b; broadcasting, types, operations and which operands are the same array do not."
	| a b sig |
	a := self f32: #(1000).
	b := self f32: #(1000).
	sig := [:x :y :s | (self op: #+ with: {self op: #* with: {x. CudaExpression scalar: s}. y}) signature: nil].
	self assert: (sig value: a value: b value: 2) equals: (sig value: (self f32: #(7)) value: (self f32: #(7)) value: 3).
	self deny: (sig value: a value: b value: 2) = (sig value: a value: a value: 2).
	self deny: (sig value: a value: b value: 2) = (sig value: a value: (self f64: #(1000)) value: 2).
	self deny: (sig value: a value: b value: 2) = ((self op: #- with: {self op: #* with: {a. CudaExpression scalar: 2}. b}) signature: nil).
	self deny: ((self op: #+ with: {self f32: #(3 4). self f32: #(4)}) signature: nil) = ((self op: #+ with: {self f32: #(3 4). self f32: #(3 4)}) signature: nil).
	self deny: (sig value: a value: b value: 2) = ((self op: #+ with: {self op: #* with: {a. CudaExpression scalar: 2}. b}) signature: #sum)
!
testSource
	| e src |
	e := self op: #max with: {self op: #sqrt with: {self op: #+ with: {self f32: #(3 4). self f32: #(4)}}. CudaExpression scalar: 0.25}.
	src := e cudaSource: nil.
	self assert: (src includesSubstring: 'extern "C" __global__ void samaltak_fused(float *out, const float *a0, const float *a1, double s0, long long n, long long cols)').
	self assert: (src includesSubstring: 'const float v1 = a1[i % cols];').
	self assert: (src includesSubstring: 'sqrtf(').
	self assert: (src includesSubstring: 'fmaxf(').
	self assert: (src includesSubstring: 'out[i] = (float)(').
	src := e cudaSource: #max.
	self assert: (src includesSubstring: 'double *out').
	self assert: (src includesSubstring: 'acc = fmax(acc, (double)(').
	self assert: (src includesSubstring: 'out[blockIdx.x] = part[0];').
	src := (self op: #where with: {self op: #gt with: {self f64: #(5). CudaExpression scalar: 0}. self f64: #(5). CudaExpression scalar: 0}) cudaSource: nil.
	self assert: (src includesSubstring: ' > ').
	self assert: (src includesSubstring: ' !!= 0 ? ').
	self assert: (src includesSubstring: 'double s1')
!
testPrintString
	| e |
	e := self op: #sqrt with: {self op: #+ with: {self op: #* with: {self f32: #(10). CudaExpression scalar: 2}. self f32: #(10)}}.
	self assert: e printString equals: '((float32[10] * 2) + float32[10]) sqrt'.
	self assert: (self op: #min with: {self f64: #(2 3). CudaExpression scalar: 1}) printString equals: '(float64[2x3] min: 1)'.
	self assert: e nodeCount equals: 6.
	self assert: e arrays size equals: 2.
	self assert: e scalars equals: #(2).
	self deny: e isTooLarge
! !
