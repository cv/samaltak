Object subclass: #CudaExpression
	instanceVariableNames: 'op args value shape type'
	classVariableNames: 'Fusing Launches LastFailure'
	package: 'System-CUDA'!

CudaExpression comment: 'I am an element-wise expression over CudaArrays and numbers, not computed yet: what a pending CudaArray holds (CudaArray pending:). CudaArray''s + - * / (with numbers and arrays), min: max: raisedTo:, negated abs sqrt squared reciprocal exp ln log sin cos tanh, the comparisons < <= > >= eq: ne: (masks: 1.0 where true, else 0.0) and where:else: (a mask choosing between two operands) answer a pending array whose expression is mine folded into its operands'' (a pending operand''s expression is taken in, not computed). Its values are computed when first needed (its address: printString, asArray, a cuBLAS or cuFFT operand) or asked for (realize, value), by one kernel for the whole tree: the CUDA C++ I write, compiled by NVRTC once per shape of expression (my signature: the types, each array''s broadcasting, the operations; not the sizes or the numbers, which are arguments) and kept (Cuda fusedKernel:source:, its cubin by its source''s SHA-256 in Cuda compiler, an NvRtcCache), then one launch. sum, max, min and mean reduce in the same kernel (each block''s partial result in float64, the last step on the host). Shapes broadcast as numpy''s: a number, a one-element array, a row (an array of the columns'' count, or a 1 x n matrix) or a column (n x 1) against a matrix. float32 with float64 is float64. Where no kernel can be made (no NVRTC; a compile error: lastFailure) each operation runs by itself, by a kernel of its own or by cuBLAS (+ and - of arrays, * and / by a number). A pending array whose operand is about to change or be freed (anything that asks for the operand''s address but my kernels, release) computes its values first. fusing: false computes every operation at once, one kernel each (as without fusion); launches counts the kernels and cuBLAS calls run for expressions.

	| a b c |
	a := CudaArray uniform: 1000000 type: #float32. b := CudaArray uniform: 1000000 type: #float32.
	c := (a * 2 + b) sqrt - 1.        "pending: nothing ran yet"
	c realize.                         "one kernel"
	((a - b) abs max: 0.25) sum.        "one kernel, a Float"
	(a > b) where: a else: b            "the larger of each pair"'!

!CudaExpression class methodsFor: 'instance creation'!
array: aCudaArray
	"An operand: the values of aCudaArray (anything with a type and an elementShape)."
	^self new setOp: #array args: #() value: aCudaArray shape: aCudaArray elementShape type: aCudaArray type
!
scalar: aNumber
	^self new setOp: #scalar args: #() value: aNumber shape: #() type: nil
!
on: anObject
	"An operand: a CudaExpression, a CudaArray (its pending expression, or itself) or a real number."
	(anObject isKindOf: CudaExpression) ifTrue: [^anObject].
	(anObject isKindOf: CudaArray) ifTrue: [^anObject asExpression].
	(anObject isNumber and: [(anObject isKindOf: Complex) not]) ifTrue: [^self scalar: anObject].
	^self error: 'an element-wise operand is a CudaArray or a real number, not ' , anObject printString
!
op: aSymbol args: anArray
	"The operation aSymbol on the expressions anArray: an error if their shapes do not broadcast."
	(self arity: aSymbol) = anArray size ifFalse: [^self error: aSymbol , ' takes ' , (self arity: aSymbol) printString , ' operands'].
	^self new setOp: aSymbol args: anArray asArray value: nil
		shape: (anArray inject: #() into: [:s :each | self broadcast: s with: each shape])
		type: (self typeOf: aSymbol args: anArray)
! !

!CudaExpression class methodsFor: 'operations'!
unaryOperations
	^#(#negated #abs #sqrt #squared #reciprocal #exp #ln #log #sin #cos #tanh)
!
binaryOperations
	^#(#+ #- #* #/ #min #max #pow #lt #le #gt #ge #eq #ne)
!
comparisons
	"The comparisons, as C++ writes them."
	^#(#lt '<' #le '<=' #gt '>' #ge '>=' #eq '==' #ne '!!=')
!
reductions
	^#(#sum #max #min #mean)
!
at: aSymbol in: pairs
	"The value after aSymbol in pairs (#(key value ...): keys at odd indices, so a value that equals a key, as 'log' does #log, is not taken for one), or nil."
	1 to: pairs size - 1 by: 2 do: [:i | (pairs at: i) == aSymbol ifTrue: [^pairs at: i + 1]].
	^nil
!
arity: aSymbol
	(self unaryOperations includes: aSymbol) ifTrue: [^1].
	(self binaryOperations includes: aSymbol) ifTrue: [^2].
	aSymbol == #where ifTrue: [^3].
	^self error: 'no element-wise operation ' , aSymbol printString
!
selectorFor: aSymbol
	"How Smalltalk writes the operation (printString)."
	| i |
	i := #(#min #max #pow #lt #le #gt #ge #eq #ne) indexOf: aSymbol.
	i = 0 ifTrue: [^aSymbol].
	^#('min:' 'max:' 'raisedTo:' '<' '<=' '>' '>=' 'eq:' 'ne:') at: i
! !

!CudaExpression class methodsFor: 'evaluating'!
apply: aSymbol to: operands
	"The pending array (CudaArray pending:) of the element-wise operation aSymbol on operands (CudaArrays, pending or not, and numbers), taking in a pending operand's expression. A tree past isTooLarge computes its pending operands first. Not fusing: computed at once."
	| e |
	e := self op: aSymbol args: (operands collect: [:each | self on: each]).
	e isTooLarge ifTrue: [
		operands do: [:each | ((each isKindOf: CudaArray) and: [each isPending]) ifTrue: [each realize]].
		e := self op: aSymbol args: (operands collect: [:each | self on: each])].
	self isFusing ifFalse: [^(CudaArray pending: e) realize].
	^CudaArray pending: e
!
reduce: aSymbol of: anObject
	"The sum, max, min or mean of anObject's values (a CudaArray: a pending one's expression reduced in its kernel, never stored): a Float."
	^(self on: anObject) reduce: aSymbol
! !

!CudaExpression class methodsFor: 'shapes'!
countOf: aShape
	^aShape inject: 1 into: [:a :b | a * b]
!
broadcast: a with: b
	"The shape of an operation on operands of the shapes a and b (#() a number, {n} an array, {rows. cols} a matrix), as numpy broadcasts: equal shapes, a number or one value, a row (n or 1 x n) or a column (n x 1) against a matrix."
	| ra ca rb cb |
	a isEmpty ifTrue: [^b].
	b isEmpty ifTrue: [^a].
	a = b ifTrue: [^a].
	(self countOf: a) = 1 ifTrue: [^b].
	(self countOf: b) = 1 ifTrue: [^a].
	(a size = 2 or: [b size = 2]) ifTrue: [
		ra := a size = 2 ifTrue: [a first] ifFalse: [1].
		ca := a last.
		rb := b size = 2 ifTrue: [b first] ifFalse: [1].
		cb := b last.
		((ra = rb or: [ra = 1 or: [rb = 1]]) and: [ca = cb or: [ca = 1 or: [cb = 1]]])
			ifTrue: [^Array with: (ra max: rb) with: (ca max: cb)]].
	^self error: 'shapes do not broadcast: ' , (self shapeString: a) , ' and ' , (self shapeString: b)
!
shapeString: aShape
	aShape isEmpty ifTrue: [^'a number'].
	aShape size = 1 ifTrue: [^'[' , aShape first printString , ']'].
	^'[' , aShape first printString , 'x' , aShape last printString , ']'
!
indexFor: leafShape in: outShape
	"The C++ index of an operand of leafShape at the output's element i (cols: the output's columns)."
	leafShape = outShape ifTrue: [^'i'].
	(self countOf: leafShape) = 1 ifTrue: [^'0'].
	outShape size = 2 ifTrue: [
		(leafShape last = outShape last and: [leafShape size = 1 or: [leafShape first = 1]]) ifTrue: [^'i % cols'].
		(leafShape size = 2 and: [leafShape last = 1 and: [leafShape first = outShape first]]) ifTrue: [^'i / cols']].
	(self countOf: leafShape) = (self countOf: outShape) ifTrue: [^'i'].
	^self error: 'shapes do not broadcast: ' , (self shapeString: leafShape) , ' into ' , (self shapeString: outShape)
!
typeOf: aSymbol args: anArray
	"float64 if an array operand is (a where:'s mask aside), else float32."
	| types |
	types := ((aSymbol == #where ifTrue: [anArray allButFirst] ifFalse: [anArray]) collect: [:each | each type]) reject: [:t | t isNil].
	types isEmpty ifTrue: [types := (anArray collect: [:each | each type]) reject: [:t | t isNil]].
	(types includes: #float64) ifTrue: [^#float64].
	types isEmpty ifTrue: [^#float64].
	^#float32
!
cType: aType
	^aType == #float32 ifTrue: ['float'] ifFalse: ['double']
! !

!CudaExpression class methodsFor: 'settings'!
isFusing
	^Fusing ~~ false
!
fusing: aBoolean
	"false: each element-wise operation runs at once, a kernel each (to compare, or to find a fault)."
	Fusing := aBoolean
!
fusing: aBoolean during: aBlock
	| was |
	was := Fusing.
	Fusing := aBoolean.
	^aBlock ensure: [Fusing := was]
!
launches
	"The kernels (and cuBLAS calls) run for expressions so far."
	^Launches ifNil: [0]
!
countLaunches: n
	Launches := self launches + n
!
lastFailure
	"NVRTC's log of the last fused kernel that did not compile, or nil."
	^LastFailure
!
noteFailure: aString
	LastFailure := aString
! !

!CudaExpression class methodsFor: 'writing'!
sourceFor: expr type: aType arrays: arrayTypes indices: indices scalars: nScalars reduction: reduction
	"The kernel samaltak_fused: a grid-stride loop over the n output elements; each array operand loaded once at its index, the expression expr, stored as aType or (reduction: #sum, #max, #min) combined into a float64 partial result a block."
	| t combine |
	t := self cType: aType.
	combine := [:a :b | reduction == #sum ifTrue: [a , ' + ' , b] ifFalse: [(reduction == #max ifTrue: ['fmax('] ifFalse: ['fmin(']) , a , ', ' , b , ')']].
	^String streamContents: [:s |
		s nextPutAll: 'extern "C" __global__ void samaltak_fused('; nextPutAll: (reduction isNil ifTrue: [t] ifFalse: ['double']); nextPutAll: ' *out'.
		arrayTypes doWithIndex: [:each :k | s nextPutAll: ', const '; nextPutAll: (self cType: each); nextPutAll: ' *a'; print: k - 1].
		0 to: nScalars - 1 do: [:k | s nextPutAll: ', double s'; print: k].
		s nextPutAll: ', long long n, long long cols)'; lf; nextPut: ${; lf.
		reduction notNil ifTrue: [
			s tab; nextPutAll: '__shared__ double part[256];'; lf; tab; nextPutAll: 'double acc = '.
			s nextPutAll: (reduction == #sum ifTrue: ['0.0'] ifFalse: [reduction == #max
				ifTrue: ['-__longlong_as_double(0x7ff0000000000000LL)'] ifFalse: ['__longlong_as_double(0x7ff0000000000000LL)']]).
			s nextPut: $;; lf].
		s tab; nextPutAll: 'for (long long i = blockIdx.x * (long long)blockDim.x + threadIdx.x; i < n; i += (long long)gridDim.x * blockDim.x) {'; lf.
		arrayTypes doWithIndex: [:each :k |
			s tab; tab; nextPutAll: 'const '; nextPutAll: (self cType: each); nextPutAll: ' v'; print: k - 1; nextPutAll: ' = a'; print: k - 1;
				nextPut: $[; nextPutAll: (indices at: k); nextPutAll: '];'; lf].
		reduction isNil
			ifTrue: [s tab; tab; nextPutAll: 'out[i] = ('; nextPutAll: t; nextPutAll: ')('; nextPutAll: expr; nextPutAll: ');'; lf]
			ifFalse: [s tab; tab; nextPutAll: 'acc = '; nextPutAll: (combine value: 'acc' value: '(double)(' , expr , ')'); nextPut: $;; lf].
		s tab; nextPut: $}; lf.
		reduction notNil ifTrue: [
			s tab; nextPutAll: 'part[threadIdx.x] = acc;'; lf; tab; nextPutAll: '__syncthreads();'; lf.
			s tab; nextPutAll: 'for (int k = blockDim.x / 2; k > 0; k >>= 1) {'; lf.
			s tab; tab; nextPutAll: 'if (threadIdx.x < k) part[threadIdx.x] = '; nextPutAll: (combine value: 'part[threadIdx.x]' value: 'part[threadIdx.x + k]'); nextPut: $;; lf.
			s tab; tab; nextPutAll: '__syncthreads();'; lf; tab; nextPut: $}; lf.
			s tab; nextPutAll: 'if (threadIdx.x == 0) out[blockIdx.x] = part[0];'; lf].
		s nextPut: $}; lf]
! !

!CudaExpression methodsFor: 'initializing'!
setOp: aSymbol args: anArray value: anObject shape: aShape type: aType
	op := aSymbol.
	args := anArray.
	value := anObject.
	shape := aShape.
	type := aType
! !

!CudaExpression methodsFor: 'accessing'!
op
	^op
!
args
	^args
!
value
	"An operand's CudaArray or number."
	^value
!
shape
	"#() for a number, {n} for an array, {rows. cols} for a matrix."
	^shape
!
type
	"#float32 or #float64 (nil for a number)."
	^type
!
count
	^self class countOf: shape
!
isLeaf
	^op == #array or: [op == #scalar]
!
arrays
	"The CudaArrays I read, each once, in the order I meet them."
	| all |
	all := OrderedCollection new.
	self addArraysTo: all.
	^all asArray
!
addArraysTo: all
	op == #array ifTrue: [
		(all anySatisfy: [:each | each == value]) ifFalse: [all add: value].
		^self].
	args do: [:each | each addArraysTo: all]
!
scalars
	"The numbers, in the order I meet them."
	| all |
	all := OrderedCollection new.
	self addScalarsTo: all.
	^all asArray
!
addScalarsTo: all
	op == #scalar ifTrue: [^all add: value].
	args do: [:each | each addScalarsTo: all]
!
nodeCount
	^args inject: 1 into: [:n :each | n + each nodeCount]
!
isTooLarge
	"Past 16 arrays or 64 operations a kernel gets unwieldy: its pending operands are computed first."
	^self nodeCount > 64 or: [self arrays size > 16]
! !

!CudaExpression methodsFor: 'writing'!
cudaString
	"My value at element i in C++: array operand k is v<k> (loaded once), number k is s<k> (a double argument)."
	^String streamContents: [:s | self cudaOn: s arrays: self arrays counter: (Array with: 0)]
!
cudaOn: s arrays: arrays counter: counter
	| t f cmp x names |
	op == #array ifTrue: [^s nextPut: $v; print: (arrays findFirst: [:each | each == value]) - 1].
	op == #scalar ifTrue: [
		counter at: 1 put: (counter at: 1) + 1.
		^s nextPut: $s; print: (counter at: 1) - 1].
	t := self class cType: type.
	x := [:i | s nextPutAll: '(('; nextPutAll: t; nextPutAll: ')('. (args at: i) cudaOn: s arrays: arrays counter: counter. s nextPutAll: '))'].
	f := [:name | s nextPutAll: name; nextPutAll: (type == #float32 ifTrue: ['f('] ifFalse: ['(']).
		1 to: args size do: [:i | i > 1 ifTrue: [s nextPutAll: ', ']. x value: i].
		s nextPut: $)].
	(#(#+ #- #* #/) includes: op) ifTrue: [s nextPut: $(. x value: 1. s space; nextPutAll: op; space. x value: 2. ^s nextPut: $)].
	cmp := self class at: op in: self class comparisons.
	cmp notNil ifTrue: [
		s nextPutAll: '(('. x value: 1. s space; nextPutAll: cmp; space. x value: 2.
		^s nextPutAll: ') ? ('; nextPutAll: t; nextPutAll: ')1 : ('; nextPutAll: t; nextPutAll: ')0)'].
	op == #where ifTrue: [
		s nextPutAll: '(('. (args at: 1) cudaOn: s arrays: arrays counter: counter. s nextPutAll: ') !!= 0 ? '.
		x value: 2. s nextPutAll: ' : '. x value: 3.
		^s nextPut: $)].
	op == #negated ifTrue: [s nextPutAll: '(-'. x value: 1. ^s nextPut: $)].
	op == #squared ifTrue: [s nextPut: $(. x value: 1. s nextPutAll: ' * '. x value: 1. ^s nextPut: $)].
	op == #reciprocal ifTrue: [s nextPutAll: '(('; nextPutAll: t; nextPutAll: ')1 / '. x value: 1. ^s nextPut: $)].
	names := #(#abs 'fabs' #sqrt 'sqrt' #exp 'exp' #ln 'log' #log 'log10' #sin 'sin' #cos 'cos' #tanh 'tanh' #min 'fmin' #max 'fmax' #pow 'pow').
	^f value: (self class at: op in: names)
!
kernelParts: reduction
	"{signature. arrays. scalars. expr. indices}: my kernel's key (the output's type, the reduction, each array's type and index, my C++) and what launching it takes."
	| arrays expr indices signature |
	arrays := self arrays.
	expr := String streamContents: [:s | self cudaOn: s arrays: arrays counter: (Array with: 0)].
	indices := arrays collect: [:each | self class indexFor: each elementShape in: shape].
	signature := String streamContents: [:s |
		s nextPutAll: type; space; nextPutAll: (reduction ifNil: ['map']).
		arrays with: indices do: [:a :i | s space; nextPutAll: a type; nextPut: $[; nextPutAll: i; nextPut: $]].
		s nextPutAll: ': '; nextPutAll: expr].
	^Array with: signature with: arrays with: self scalars with: expr with: indices
!
signature: reduction
	^(self kernelParts: reduction) first
!
cudaSource: reduction
	"My kernel's CUDA C++ (reduction nil: my values stored; #sum, #max, #min: reduced)."
	| parts |
	parts := self kernelParts: reduction.
	^self class sourceFor: (parts at: 4) type: type arrays: ((parts at: 2) collect: [:a | a type]) indices: (parts at: 5) scalars: (parts at: 3) size reduction: reduction
! !

!CudaExpression methodsFor: 'evaluating'!
newArray
	"New device memory for my values."
	shape size = 2 ifTrue: [^CudaMatrix rows: shape first cols: shape last type: type].
	^CudaArray new: self count type: type
!
evaluateInto: target
	"Compute my values into target (a CudaArray of my count and type): one fused kernel, or if none can be made each operation by itself. Answer target."
	(self launchInto: target reduction: nil) notNil ifTrue: [^target].
	^self evaluateStepwiseInto: target
!
launchInto: target reduction: reduction
	"Queue my fused kernel writing target (my values; for a reduction each block's partial result, float64): answer the blocks launched, nil if there is no kernel."
	| parts kernel n cols blocks params |
	parts := self kernelParts: reduction.
	kernel := Cuda default fusedKernel: parts first source: [
		self class sourceFor: (parts at: 4) type: type arrays: ((parts at: 2) collect: [:a | a type]) indices: (parts at: 5) scalars: (parts at: 3) size reduction: reduction].
	kernel isNil ifTrue: [^nil].
	n := self count.
	n = 0 ifTrue: [^0].
	cols := shape size = 2 ifTrue: [shape last max: 1] ifFalse: [1].
	blocks := n + 255 // 256 min: (reduction isNil ifTrue: [16r7FFFFFFF] ifFalse: [4096]).
	params := OrderedCollection new.
	params add: target readAddress.
	(parts at: 2) do: [:a | params add: a readAddress].
	(parts at: 3) do: [:v | params add: v asFloat].
	params add: n; add: cols.
	CudaTrace operation: 'fused kernel' detail: [self printString , (reduction ifNil: [''] ifNotNil: [' ' , reduction])] during: [
		Cuda compute launch: kernel grid: blocks block: 256 arguments: params asArray].
	self class countLaunches: 1.
	^blocks
!
evaluateStepwiseInto: target
	"Each operation by itself: my operands computed first (into arrays of their own), then me, by a kernel of my own or by cuBLAS."
	| temps operands one |
	temps := OrderedCollection new.
	[operands := args collect: [:each |
		each isLeaf
			ifTrue: [each]
			ifFalse: [| t | t := each newArray. temps add: t. each evaluateStepwiseInto: t. self class array: t]].
	one := self class op: op args: operands.
	(one launchInto: target reduction: nil) isNil ifTrue: [one evaluateWithCublasInto: target]]
		ensure: [temps do: [:t | t release]].
	^target
!
evaluateWithCublasInto: target
	"What cuBLAS does without a kernel: + and - of two arrays of my shape and type (a copy, then axpy), * and / by a number, negated (a copy, then scal)."
	| x y |
	x := args first.
	y := args size > 1 ifTrue: [args at: 2] ifFalse: [nil].
	((op == #+ or: [op == #-]) and: [x op == #array and: [y op == #array and: [x shape = shape and: [y shape = shape and: [x type = type and: [y type = type]]]]]]) ifTrue: [
		self copy: x value into: target.
		target accumulate: y value times: (op == #+ ifTrue: [1] ifFalse: [-1]).
		self class countLaunches: 2.
		^target].
	((op == #* or: [op == #/]) and: [y notNil and: [(x op == #array and: [y op == #scalar]) or: [op == #* and: [x op == #scalar and: [y op == #array]]]]]) ifTrue: [| a s |
		x op == #array ifTrue: [a := x. s := y value] ifFalse: [a := y. s := x value].
		(a shape = shape and: [a type = type]) ifTrue: [
			self copy: a value into: target.
			target scale: (op == #* ifTrue: [s] ifFalse: [1 / s]).
			self class countLaunches: 2.
			^target]].
	(op == #negated and: [x op == #array and: [x type = type]]) ifTrue: [
		self copy: x value into: target.
		target scale: -1.
		self class countLaunches: 2.
		^target].
	^self error: 'element-wise ' , (self class selectorFor: op) , ' needs a kernel, and none could be made: ' ,
		(NvRtc isAvailable ifTrue: [(self class lastFailure ifNil: ['NVRTC failed']) lines first] ifFalse: ['no NVRTC here (the CUDA toolkit''s libnvrtc)'])
!
copy: anArray into: target
	anArray size = 0 ifTrue: [^self].
	CudaRuntimeAPI cudaMemcpyDtoD: target readAddress src: anArray readAddress count: anArray byteSize
!
reduce: aSymbol
	"The sum, max, min or mean of my values, a Float: one kernel computing and reducing them (each block's partial result in float64, the last step here); without a kernel, my values copied here."
	| n kind scratch blocks partials r |
	(self class reductions includes: aSymbol) ifFalse: [^self error: 'reductions are ' , self class reductions printString].
	n := self count.
	n = 0 ifTrue: [aSymbol == #sum ifTrue: [^0.0]. ^self error: 'the ' , aSymbol , ' of no values'].
	kind := aSymbol == #mean ifTrue: [#sum] ifFalse: [aSymbol].
	scratch := Cuda default reductionScratch.
	[blocks := self launchInto: scratch reduction: kind.
	blocks notNil ifTrue: [partials := scratch copyFrom: 1 count: blocks]]
		ensure: [Cuda default returnScratch: scratch].
	partials isNil ifTrue: [partials := self hostValues].
	r := kind == #sum
		ifTrue: [partials inject: 0.0 into: [:a :b | a + b]]
		ifFalse: [kind == #max
			ifTrue: [partials inject: partials first asFloat into: [:a :b | a max: b]]
			ifFalse: [partials inject: partials first asFloat into: [:a :b | a min: b]]].
	aSymbol == #mean ifTrue: [r := r / n].
	^r
!
hostValues
	"My values, copied here (computed into an array of their own first)."
	| t |
	op == #array ifTrue: [^value asArray].
	t := self newArray.
	^[self evaluateStepwiseInto: t. t asArray] ensure: [t release]
! !

!CudaExpression methodsFor: 'printing'!
printOn: aStream
	"As Smalltalk would write me: ((float32[1000] * 2) + float32[1000]) sqrt."
	op == #array ifTrue: [^aStream nextPutAll: type; nextPutAll: (self class shapeString: shape)].
	op == #scalar ifTrue: [^aStream print: value].
	args size = 1 ifTrue: [^aStream print: args first; space; nextPutAll: op].
	op == #where ifTrue: [^aStream nextPut: $(; print: args first; nextPutAll: ' where: '; print: (args at: 2); nextPutAll: ' else: '; print: (args at: 3); nextPut: $)].
	aStream nextPut: $(; print: args first; space; nextPutAll: (self class selectorFor: op); space; print: (args at: 2); nextPut: $)
! !
