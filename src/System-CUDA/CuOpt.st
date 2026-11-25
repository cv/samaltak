Object subclass: #CuOpt
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-CUDA'!

CuOpt comment: 'I am NVIDIA cuOpt''s linear programming solver (libcuopt_mathopt, its C API cuopt_c.h, through CuOptAPI): I solve a linear program given as Smalltalk Arrays on the GPU and answer a CuOptResult. cuOpt is not in the CUDA toolkit: install its wheel (libcuopt-cu13, pip or uv, from pypi.nvidia.com) and name its lib64 in SAMALTAK_CUDA_LIBS (docs/cuda.md). The solve blocks the VM for its duration (tenths of a second for a small problem).

	CuOpt maximize: #(3 5) subjectTo: #(#(1 0) #(0 2) #(3 2)) atMost: #(4 12 18)    "objective 36 at (2 6)"'!

!CuOpt class methodsFor: 'testing'!
isAvailable
	^CuOptAPI isAvailable
!
version
	^(CuOptAPI cuOptGetVersion inject: '' into: [:s :v | s isEmpty ifTrue: [v printString] ifFalse: [s , '.' , v printString]])
! !

!CuOpt class methodsFor: 'solving'!
maximize: objective subjectTo: rows atMost: rhs
	"Maximize objective . x subject to rows x <= rhs and x >= 0."
	^self solve: objective sense: #maximize rows: rows senses: (String new: rhs size withAll: $L) rhs: rhs
		lower: (Array new: objective size withAll: 0.0) upper: (Array new: objective size withAll: Float infinity)
!
minimize: objective subjectTo: rows atLeast: rhs
	"Minimize objective . x subject to rows x >= rhs and x >= 0."
	^self solve: objective sense: #minimize rows: rows senses: (String new: rhs size withAll: $G) rhs: rhs
		lower: (Array new: objective size withAll: 0.0) upper: (Array new: objective size withAll: Float infinity)
!
solve: objective sense: aSymbol rows: rows senses: aString rhs: rhs lower: lower upper: upper
	"Optimize (aSymbol #minimize or #maximize) objective . x subject to, for each row i, (rows at: i) . x <= = >= (rhs at: i) as (aString at: i) is $L $E $G, and lower <= x <= upper (Float infinity for none). rows are dense; cuOpt gets them as CSR."
	| n offsets columns values problem settings solution x result |
	n := objective size.
	offsets := OrderedCollection with: 0.
	columns := OrderedCollection new.
	values := OrderedCollection new.
	rows do: [:row |
		row size = n ifFalse: [^self error: 'a row has ' , row size printString , ' coefficients, not ' , n printString].
		row doWithIndex: [:v :j | v = 0 ifFalse: [columns add: j - 1. values add: v]].
		offsets add: columns size].
	problem := CuOptAPI cuOptCreateProblem: rows size numVariables: n objectiveSense: (aSymbol == #maximize ifTrue: [-1] ifFalse: [1]) objectiveOffset: 0.0
		objectiveCoefficients: (self doubles: objective) constraintMatrixRowOffsets: (self ints: offsets) constraintMatrixColumnIndices: (self ints: columns)
		constraintMatrixCoefficentValues: (self doubles: values) constraintSense: aString asByteArray rhs: (self doubles: rhs)
		lowerBounds: (self doubles: lower) upperBounds: (self doubles: upper) variableTypes: (ByteArray new: n withAll: $C value).
	[settings := CuOptAPI cuOptCreateSolverSettings.
	[CuOptAPI cuOptSetParameter: settings parameterName: 'log_to_console' parameterValue: 'false'] on: CudaError do: [:e | nil].
	solution := CuOptAPI cuOptSolve: problem settings: settings.
	x := ByteArray new: n * 8.
	[CuOptAPI cuOptGetPrimalSolution: solution solutionValues: x] on: CudaError do: [:e | x := nil].
	result := CuOptResult new
		setStatus: (CuOptAPI cuOptGetTerminationStatus: solution)
		objective: (CuOptAPI cuOptGetObjectiveValue: solution)
		values: (x ifNotNil: [(1 to: n) collect: [:i | x float64At: i - 1 * 8 + 1]])
		seconds: (CuOptAPI cuOptGetSolveTime: solution)]
		ensure: [
			solution ifNotNil: [CuOptAPI cuOptDestroySolution: solution].
			settings ifNotNil: [CuOptAPI cuOptDestroySolverSettings: settings].
			CuOptAPI cuOptDestroyProblem: problem].
	^result
!
doubles: aCollection
	| bytes |
	bytes := ByteArray new: aCollection size * 8.
	aCollection doWithIndex: [:v :i | bytes float64At: i - 1 * 8 + 1 put: v asFloat].
	^bytes
!
ints: aCollection
	| bytes |
	bytes := ByteArray new: aCollection size * 4.
	aCollection doWithIndex: [:v :i | bytes uint32At: i - 1 * 4 + 1 put: (v bitAnd: 16rFFFFFFFF)].
	^bytes
! !
