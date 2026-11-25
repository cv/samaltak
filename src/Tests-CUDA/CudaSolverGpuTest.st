TestCase subclass: #CudaSolverGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CudaSolverGpuTest comment: 'Tests CudaMatrix''s cuSOLVER factorizations on the GPU against small CPU references in Smalltalk (products, Gaussian elimination, the cyclic Jacobi eigenvalue method), in float64 and float32 to their tolerances: lu (P A = L U, solve:, inverse, determinant), cholesky, qr, svd (tall and wide), symmetricEigen, and devInfo''s failures as CudaSolverErrors. Needs a GPU and the CUDA toolkit''s libraries: make test-nv runs it. Each test releases what it allocates.'!

!CudaSolverGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!CudaSolverGpuTest class methodsFor: 'references'!
product: a with: b
	"Row-major Arrays of rows: a b, in Smalltalk."
	^a collect: [:row | (1 to: b first size) collect: [:j | | s | s := 0.0. row doWithIndex: [:v :k | s := s + (v * ((b at: k) at: j))]. s]]
!
transpose: a
	^(1 to: a first size) collect: [:j | a collect: [:row | row at: j]]
!
solve: a with: b
	"x with a x = b by Gaussian elimination with partial pivoting; answers x and the determinant."
	| n m x det |
	n := a size.
	m := (1 to: n) collect: [:i | ((a at: i) collect: [:v | v asFloat]) copyWith: (b at: i) asFloat].
	det := 1.0.
	1 to: n do: [:k | | p |
		p := k.
		k + 1 to: n do: [:i | ((m at: i) at: k) abs > ((m at: p) at: k) abs ifTrue: [p := i]].
		p = k ifFalse: [m swap: p with: k. det := det negated].
		det := det * ((m at: k) at: k).
		k + 1 to: n do: [:i | | f |
			f := ((m at: i) at: k) / ((m at: k) at: k).
			k to: n + 1 do: [:j | (m at: i) at: j put: ((m at: i) at: j) - (f * ((m at: k) at: j))]]].
	x := Array new: n.
	n to: 1 by: -1 do: [:i | | s |
		s := (m at: i) at: n + 1.
		i + 1 to: n do: [:j | s := s - (((m at: i) at: j) * (x at: j))].
		x at: i put: s / ((m at: i) at: i)].
	^{x. det}
!
jacobiEigenvalues: a
	"The eigenvalues of the symmetric a, increasing (cyclic Jacobi rotations)."
	| n m |
	n := a size.
	m := a collect: [:row | row collect: [:v | v asFloat]].
	1 to: 50 do: [:sweep | | off |
		off := 0.0.
		1 to: n do: [:p | p + 1 to: n do: [:q | off := off + ((m at: p) at: q) squared]].
		off < 1.0e-30 ifFalse: [
			1 to: n do: [:p | p + 1 to: n do: [:q | | apq theta t c s |
				apq := (m at: p) at: q.
				apq = 0.0 ifFalse: [
					theta := (((m at: q) at: q) - ((m at: p) at: p)) / (2.0 * apq).
					t := theta = 0.0
						ifTrue: [1.0]
						ifFalse: [theta sign asFloat / (theta abs + (theta squared + 1.0) sqrt)].
					c := 1.0 / (t squared + 1.0) sqrt.
					s := t * c.
					1 to: n do: [:k | | akp akq |
						akp := (m at: k) at: p. akq := (m at: k) at: q.
						(m at: k) at: p put: (c * akp) - (s * akq).
						(m at: k) at: q put: (s * akp) + (c * akq)].
					1 to: n do: [:k | | apk aqk |
						apk := (m at: p) at: k. aqk := (m at: q) at: k.
						(m at: p) at: k put: (c * apk) - (s * aqk).
						(m at: q) at: k put: (s * apk) + (c * aqk)]]]]]].
	^((1 to: n) collect: [:i | (m at: i) at: i]) asSortedCollection asArray
! !

!CudaSolverGpuTest methodsFor: 'running'!
setUp
	Cuda isAvailable ifFalse: [^self error: 'no CUDA here (libcudart from the CUDA toolkit, and a GPU): CudaSolverGpuTest needs them'].
	CusolverAPI isAvailable ifFalse: [^self error: 'no cuSOLVER here (libcusolver from the CUDA toolkit)']
! !

!CudaSolverGpuTest methodsFor: 'helpers'!
tolerance: type
	^type == #float64 ifTrue: [1.0e-9] ifFalse: [2.0e-3]
!
assert: a closeTo: b tolerance: eps
	"Arrays of numbers or of rows, elementwise, relative to the largest magnitude."
	| x y scale |
	x := (a first isKindOf: Array) ifTrue: [a inject: #() into: [:all :row | all , row]] ifFalse: [a].
	y := (b first isKindOf: Array) ifTrue: [b inject: #() into: [:all :row | all , row]] ifFalse: [b].
	self assert: x size equals: y size.
	scale := y inject: 1.0 into: [:m :v | m max: v abs].
	x with: y do: [:u :v | self assert: (u - v) abs <= (eps * scale) description: u printString , ' is not ' , v printString]
!
randomRows: r cols: c type: type
	"A well-conditioned random matrix: uniform values, the diagonal made dominant if square."
	| m rows |
	m := CudaMatrix uniformRows: r cols: c type: type.
	rows := [m asRows] ensure: [m release].
	r = c ifTrue: [1 to: r do: [:i | (rows at: i) at: i put: ((rows at: i) at: i) + r]].
	^rows
!
identity: n
	^(1 to: n) collect: [:i | (1 to: n) collect: [:j | i = j ifTrue: [1.0] ifFalse: [0.0]]]
! !

!CudaSolverGpuTest methodsFor: 'tests'!
testLUAgainstSmalltalk
	#(#float64 #float32) do: [:type | | rows a lu b x ref l u perm pa eps |
		eps := self tolerance: type.
		rows := (self randomRows: 12 cols: 12 type: type) collect: [:row | row collect: [:v | v - 0.5]].
		a := CudaMatrix fromRows: rows type: type.
		lu := a lu.
		b := CudaArray withAll: ((1 to: 12) collect: [:i | i asFloat / 3]) type: type.
		[ref := self class solve: rows with: b asArray.
		self deny: lu isSingular.
		x := lu solve: b.
		self assert: x asArray closeTo: ref first tolerance: eps * 10.
		x release.
		self assert: (lu determinant - ref last) abs <= (ref last abs * eps * 10).
		self assert: (lu logAbsDeterminant - ref last abs ln) abs <= (eps * 10).
		l := lu l. u := lu u.
		perm := lu permutation.
		pa := perm collect: [:i | rows at: i].
		self assert: (self class product: l asRows with: u asRows) closeTo: pa tolerance: eps.
		self assert: ((1 to: 12) allSatisfy: [:i | (l at: i at: i) = 1.0 and: [(i + 1 to: 12) allSatisfy: [:j | (l at: i at: j) = 0.0 and: [(u at: j at: i) = 0.0]]]]).
		l release. u release]
			ensure: [a release. lu release. b release]]
!
testSolveMatrixAndInverse
	#(#float64 #float32) do: [:type | | rows a bRows b x inv eps |
		eps := self tolerance: type.
		rows := self randomRows: 8 cols: 8 type: type.
		bRows := self randomRows: 8 cols: 3 type: type.
		a := CudaMatrix fromRows: rows type: type.
		b := CudaMatrix fromRows: bRows type: type.
		[x := a solve: b.
		self assert: x rows equals: 8.
		self assert: x cols equals: 3.
		self assert: (self class product: rows with: x asRows) closeTo: bRows tolerance: eps * 10.
		inv := a inverse.
		self assert: (self class product: rows with: inv asRows) closeTo: (self identity: 8) tolerance: eps * 10.
		x release. inv release]
			ensure: [a release. b release]]
!
testDeterminant
	| a |
	a := CudaMatrix fromRows: #(#(2 0 1) #(1 3 2) #(1 1 2)) type: #float64.
	[self assert: (a determinant - 6.0) abs < 1.0e-12] ensure: [a release].
	a := CudaMatrix fromRows: #(#(0 1) #(1 0)) type: #float32.
	[self assert: a determinant equals: -1.0] ensure: [a release]
!
testSingularMatrix
	| a lu b e |
	a := CudaMatrix fromRows: #(#(1 2 3) #(2 4 6) #(1 0 1)) type: #float64.
	b := CudaArray withAll: #(1 2 3) type: #float64.
	lu := a lu.
	[self assert: lu isSingular.
	self assert: lu determinant equals: 0.0.
	e := [lu solve: b. nil] on: CudaSingularMatrix do: [:x | x].
	self assert: e notNil.
	self assert: e devInfo > 0.
	self assert: ('cusolverDnXgetrf: the matrix is singular: U(*) is exactly zero (devInfo *)' match: e messageText).
	self should: [a inverse] raise: CudaSingularMatrix.
	self should: [a solve: b] raise: CudaSolverError]
		ensure: [a release. b release. lu release]
!
testCholesky
	| a |
	#(#float64 #float32) do: [:type | | m rows l lRows |
		m := self randomRows: 6 cols: 6 type: type.
		rows := self class product: m with: (self class transpose: m).
		a := CudaMatrix fromRows: rows type: type.
		[l := a cholesky.
		lRows := l asRows.
		self assert: ((1 to: 6) allSatisfy: [:i | (i + 1 to: 6) allSatisfy: [:j | ((lRows at: i) at: j) = 0.0]]).
		self assert: (self class product: lRows with: (self class transpose: lRows)) closeTo: rows tolerance: (self tolerance: type).
		l release]
			ensure: [a release]].
	a := CudaMatrix fromRows: #(#(1 2) #(2 1)) type: #float64.
	[| e |
	e := [a cholesky. nil] on: CudaNotPositiveDefinite do: [:x | x].
	self assert: e devInfo equals: 2.
	self assert: ('*leading minor of order 2*' match: e messageText)]
		ensure: [a release]
!
testQR
	#(#float64 #float32) do: [:type | | rows a d q r eps |
		eps := self tolerance: type.
		rows := self randomRows: 9 cols: 5 type: type.
		a := CudaMatrix fromRows: rows type: type.
		[d := a qr.
		q := d q asRows. r := d r asRows.
		self assert: d q rows equals: 9.
		self assert: d r rows equals: 5.
		self assert: ((1 to: 5) allSatisfy: [:i | (1 to: i - 1) allSatisfy: [:j | ((r at: i) at: j) = 0.0]]).
		self assert: (self class product: q with: r) closeTo: rows tolerance: eps.
		self assert: (self class product: (self class transpose: q) with: q) closeTo: (self identity: 5) tolerance: eps.
		d release]
			ensure: [a release]]
!
testSVD
	#(#float64 #float32) do: [:type | #(#(7 4) #(4 7) #(5 5)) do: [:shape | | rows a d u s vt k usv eps ref sv |
		eps := self tolerance: type.
		rows := self randomRows: shape first cols: shape last type: type.
		k := shape first min: shape last.
		a := CudaMatrix fromRows: rows type: type.
		[d := a svd.
		u := d u asRows. s := d s asArray. vt := d vt asRows.
		self assert: d u rows equals: shape first. self assert: d u cols equals: k.
		self assert: d vt rows equals: k. self assert: d vt cols equals: shape last.
		self assert: s size equals: k.
		self assert: s equals: (s asSortedCollection: [:x :y | x >= y]) asArray.
		usv := self class product: (u collect: [:row | row withIndexCollect: [:v :i | v * (s at: i)]]) with: vt.
		self assert: usv closeTo: rows tolerance: eps.
		self assert: (self class product: (self class transpose: u) with: u) closeTo: (self identity: k) tolerance: eps.
		self assert: (self class product: vt with: (self class transpose: vt)) closeTo: (self identity: k) tolerance: eps.
		"The squares of the singular values are the eigenvalues of A^T A (or A A^T)."
		ref := (self class jacobiEigenvalues: (shape first >= shape last
			ifTrue: [self class product: (self class transpose: rows) with: rows]
			ifFalse: [self class product: rows with: (self class transpose: rows)])) reverse.
		self assert: (s collect: [:v | v squared]) closeTo: ref tolerance: eps * 10.
		sv := a singularValues.
		self assert: sv asArray closeTo: s tolerance: eps.
		sv release.
		d release]
			ensure: [a release]]]
!
testSymmetricEigen
	#(#float64 #float32) do: [:type | | m rows a d values vectors eps |
		eps := self tolerance: type.
		m := self randomRows: 6 cols: 6 type: type.
		rows := (1 to: 6) collect: [:i | (1 to: 6) collect: [:j | ((m at: i) at: j) + ((m at: j) at: i)]].
		a := CudaMatrix fromRows: rows type: type.
		[d := a symmetricEigen.
		values := d values asArray. vectors := d vectors asRows.
		self assert: values closeTo: (self class jacobiEigenvalues: rows) tolerance: eps * 10.
		"A V = V diag(values)"
		self assert: (self class product: rows with: vectors)
			closeTo: (vectors collect: [:row | row withIndexCollect: [:v :i | v * (values at: i)]]) tolerance: eps * 10.
		self assert: (self class product: (self class transpose: vectors) with: vectors) closeTo: (self identity: 6) tolerance: eps.
		d release]
			ensure: [a release]]
!
testTransposeAndIdentity
	| a t id |
	a := CudaMatrix fromRows: #(#(1 2 3) #(4 5 6)) type: #float64.
	t := a transposed.
	id := CudaMatrix identity: 3 type: #float32.
	[self assert: t asRows equals: #(#(1.0 4.0) #(2.0 5.0) #(3.0 6.0)).
	self assert: id asRows equals: (self identity: 3)]
		ensure: [a release. t release. id release]
!
testRefusals
	| a |
	a := CudaMatrix fromRows: #(#(1 2 3) #(4 5 6)) type: #float64.
	[self should: [a lu] raise: Error.
	self should: [a qr] raise: Error.
	self should: [a cholesky] raise: Error]
		ensure: [a release]
! !
