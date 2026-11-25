TestCase subclass: #CuOptGpuTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-CUDA'!

CuOptGpuTest comment: 'Tests CuOpt: linear programs solved on the GPU by NVIDIA cuOpt (libcuopt_mathopt, from its wheel; SAMALTAK_CUDA_LIBS names its lib64). Not by default (runsByDefault); make test-nv runs it where cuOpt is installed (CUOPT_LIB).'!

!CuOptGpuTest class methodsFor: 'testing'!
runsByDefault
	^false
! !

!CuOptGpuTest methodsFor: 'running'!
setUp
	CuOpt isAvailable ifFalse: [^self error: 'no cuOpt here (SAMALTAK_CUDA_LIBS: the libcuopt-cu13 wheel''s libcuopt_mathopt/lib64)']
! !

!CuOptGpuTest methodsFor: 'tests'!
testMaximize
	| r |
	r := CuOpt maximize: #(3 5) subjectTo: #(#(1 0) #(0 2) #(3 2)) atMost: #(4 12 18).
	self assert: r isOptimal.
	self assert: r statusName equals: 'OPTIMAL'.
	self assert: (r objective - 36) abs < 1.0e-6.
	self assert: ((r values first - 2) abs < 1.0e-6 and: [(r values last - 6) abs < 1.0e-6])
!
testMinimize
	"The diet problem's shape: minimize cost with at least the nutrients."
	| r |
	r := CuOpt minimize: #(2 3) subjectTo: #(#(1 2) #(3 1)) atLeast: #(8 9).
	self assert: r isOptimal.
	self assert: (r objective - 13) abs < 1.0e-6.
	self assert: ((r values first - 2) abs < 1.0e-6 and: [(r values last - 3) abs < 1.0e-6])
!
testInfeasible
	| r |
	r := CuOpt solve: #(1 1) sense: #minimize rows: #(#(1 1) #(1 1)) senses: 'LG' rhs: #(1 2)
		lower: #(0 0) upper: {Float infinity. Float infinity}.
	self deny: r isOptimal.
	self assert: r values isNil
!
testBadMatrixRefused
	"Column indices are checked before cuOpt sees them."
	| e |
	e := [CuOptAPI cuOptCreateProblem: 1 numVariables: 1 objectiveSense: 1 objectiveOffset: 0.0
		objectiveCoefficients: (CuOpt doubles: #(1)) constraintMatrixRowOffsets: (CuOpt ints: #(0 1)) constraintMatrixColumnIndices: (CuOpt ints: #(5))
		constraintMatrixCoefficentValues: (CuOpt doubles: #(1)) constraintSense: 'L' asByteArray rhs: (CuOpt doubles: #(1))
		lowerBounds: (CuOpt doubles: #(0)) upperBounds: (CuOpt doubles: #(1)) variableTypes: 'C' asByteArray. nil]
			on: CudaArgumentError do: [:err | err].
	self assert: e notNil.
	self assert: e code equals: -7
! !
